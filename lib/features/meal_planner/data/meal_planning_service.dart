import 'dart:async';
import 'package:opennutritracker/core/utils/env.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';
import '../domain/planner.dart';
import '../domain/planning_task_prompts.dart';

class PlanningCredentials {
  static const prefix = 'meal-planner-v1-';
  Future<Json> read() async {
    final storage = SecureAppStorageProvider.secureAppStorage;
    final values = await Future.wait([
      for (final field in ['url', 'key', 'model', 'consent'])
        storage.read(key: '$prefix$field'),
    ]);
    final url = values[0] ?? 'https://api.deepseek.com';
    final storedKey = values[1];
    return {
      'base_url': url,
      'model': values[2] ?? 'deepseek-flash',
      'key':
          storedKey ??
          (url == 'https://api.deepseek.com' ? Env.plannerApiKey : ''),
      'consented_url': values[3] ?? '',
    };
  }

  static Uri endpoint(String base) {
    final uri = Uri.tryParse(base.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const PlanRejected('HTTPS Base URL required');
    }
    return Uri.parse(
      '${base.trim().replaceAll(RegExp(r'/+$'), '')}/chat/completions',
    );
  }

  Future<void> save(String url, String model, String? key) async {
    endpoint(url);
    if (model.trim().isEmpty) throw const PlanRejected('Model is required');
    final storage = SecureAppStorageProvider.secureAppStorage;
    final previousUrl =
        await storage.read(key: '${prefix}url') ?? 'https://api.deepseek.com';
    if (previousUrl != url.trim() && key == null) {
      await storage.delete(key: '${prefix}key');
    }
    await storage.write(key: '${prefix}url', value: url.trim());
    await storage.write(key: '${prefix}model', value: model.trim());
    if (key != null) {
      await storage.write(key: '${prefix}key', value: key.trim());
    }
  }

  Future<void> consent(String url) => SecureAppStorageProvider.secureAppStorage
      .write(key: '${prefix}consent', value: url);
}

class MealPlanningService {
  final PlanningCredentials credentials;
  final http.Client Function() clientFactory;
  http.Client? _active;
  bool _cancelled = false;
  MealPlanningService(this.credentials, {http.Client Function()? clientFactory})
    : clientFactory = clientFactory ?? http.Client.new;
  void cancel() {
    _cancelled = true;
    _active?.close();
  }

  Future<String> _request(Json settings, List<Json> messages) async {
    if (_cancelled) throw const PlanRejected('Cancelled');
    final client = clientFactory();
    _active = client;
    try {
      final request =
          http.Request(
              'POST',
              PlanningCredentials.endpoint(settings['base_url']),
            )
            ..followRedirects = false
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${settings['key']}',
            })
            ..body = jsonEncode({
              'model': settings['model'],
              'messages': messages,
              // Keep reasoning for constrained planning, with bounded effort.
              // Vendor-specific options must not leak to compatible providers.
              if (PlanningCredentials.endpoint(settings['base_url']).origin ==
                      'https://api.deepseek.com' &&
                  settings['model'] == 'deepseek-flash')
                'reasoning_effort': 'low',
              'max_tokens': 6000,
              'response_format': {'type': 'json_object'},
            });
      final response = await (() async {
        final streamed = await client.send(request);
        final bytes = <int>[];
        await for (final chunk in streamed.stream) {
          if (bytes.length + chunk.length > 250000) {
            throw const PlanRejected('Response too large');
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(bytes, streamed.statusCode);
      })().timeout(const Duration(seconds: 60));
      if (_cancelled) throw const PlanRejected('Cancelled');
      if (response.statusCode != 200) {
        throw PlanRejected('HTTP ${response.statusCode}');
      }
      if (response.bodyBytes.length > 250000) {
        throw const PlanRejected('Response too large');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final choice = data['choices'][0];
      if (choice['finish_reason'] != 'stop') {
        throw const PlanRejected('Incomplete response');
      }
      final content = choice['message']['content'];
      if (content is! String || content.trim().isEmpty) {
        throw const PlanRejected('Empty response');
      }
      return content;
    } on TimeoutException {
      throw const PlanRejected('Request timeout');
    } on PlanRejected {
      rethrow;
    } catch (_) {
      throw const PlanRejected('Network or response format error');
    } finally {
      client.close();
      _active = null;
    }
  }

  Future<void> probe() async {
    _cancelled = false;
    final settings = await credentials.read();
    if ((settings['key'] as String).isEmpty) {
      throw const PlanRejected('API Key required');
    }
    final result = await _request(settings, [
      {'role': 'user', 'content': 'Return JSON: {"ok":true}'},
    ]);
    if (jsonDecode(result)['ok'] != true) {
      throw const PlanRejected('Invalid probe response');
    }
  }

  Future<Json> generate(
    PlanRules rules,
    String start,
    Json input, {
    bool mock = false,
    Map<String, Json> preservedMeals = const {},
  }) async {
    _cancelled = false;
    final settings = await credentials.read();
    if (mock || (settings['key'] as String).isEmpty) {
      return {
        'plan': rules.fallback(start),
        'source': mock ? 'mock' : 'fallback',
        'model': 'local',
        'notice': mock ? 'mock' : 'no-key',
      };
    }
    if (settings['consented_url'] != settings['base_url']) {
      throw const PlanRejected('Third-party disclosure consent required');
    }
    final template = rules.fallback(start);
    final example = <String, dynamic>{
      'schema_version': 1,
      'period_start': start,
      'days': [template['days'][0]],
    };
    final mode = input['mode'] is String
        ? input['mode'] as String : 'initial';
    final systemPrompt = planningSystemPromptForMode(mode);
    final messages = <Json>[
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': jsonEncode({
          ...input,
          'constraints': {
            ...Map<String, dynamic>.from(input['constraints'] ?? {}),
            'target_kcal': rules.targetKcal,
            'energy_min_kcal': rules.minimumKcal,
            'energy_max_kcal': rules.maximumKcal,
            'planning_aim_kcal': rules.planningKcal,
            'minimum_protein_g': rules.minimumProtein,
            'maximum_protein_g': 150,
            'sodium_mg_max': 2000,
            'cooking_oil_g_max': 30,
            'food_group_minimum_g': {
              'vegetable': 400,
              'fruit': 200,
              'grain': 100,
              'dairy': 200,
            },
          },
          'example': example,
          'historical_locked_meals': preservedMeals,
          'allowed_recipes': rules.catalog.recipes.values
              .where((r) => rules.allowed(r['id']))
              .map(
                (r) => {
                  ...r,
                  'nutrition_per_portion': rules.catalog.nutrition(r['id'], 1),
                },
              )
              .toList(),
        }),
      },
    ];
    var failure = 'generation-failed';
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_cancelled) throw const PlanRejected('Cancelled');
      try {
        final raw = await _request(settings, messages);
        final plan = jsonDecode(raw) as Json;
        rules.validate(plan, start, preservedMeals: preservedMeals);
        return {
          'plan': plan,
          'source': 'ai',
          'model': settings['model'],
          'notice': '',
        };
      } on PlanRejected catch (e) {
        failure = e.reason;
        if (_cancelled) rethrow;
        if (failure.startsWith('HTTP') ||
            failure.contains('timeout') ||
            failure.contains('Network')) {
          break;
        }
      } catch (_) {
        failure = 'Invalid JSON or schema';
      }
      messages.add({
        'role': 'user',
        'content':
            planningRepairPrompt(failure),
      });
    }
    if (_cancelled) throw const PlanRejected('Cancelled');
    return {
      'plan': rules.fallback(start),
      'source': 'fallback',
      'model': 'local',
      'notice': failure,
    };
  }
}

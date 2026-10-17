import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/utils/env.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'planner_test.dart' show MemoryCredentials;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlanRules rules;
  setUp(() {
    rules = PlanRules(
      FoodCatalog(
        jsonDecode(File('assets/meal_planner/catalog.json').readAsStringSync())
            as Json,
      ),
      targetKcal: 2337,
      minimumProtein: 80,
    );
  });
  test(
    'bounded DeepSeek reasoning leaves compatible providers untouched',
    () async {
      for (final base in [
        'https://api.deepseek.com',
        'https://example.invalid',
        'https://api.deepseek.com.evil.invalid',
        'https://api.deepseek.com:8443',
      ]) {
        final credentials = MemoryCredentials()..settings['base_url'] = base;
        final service = MealPlanningService(
          credentials,
          clientFactory: () => MockClient((request) async {
            final body = jsonDecode(request.body) as Map;
            if (base == 'https://api.deepseek.com') {
              expect(body['reasoning_effort'], 'low');
            } else {
              expect(body.containsKey('reasoning_effort'), false);
            }
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'finish_reason': 'stop',
                    'message': {'content': '{"ok":true}'},
                  },
                ],
              }),
              200,
            );
          }),
        );
        await service.probe();
      }
    },
  );
  test(
    'timeouts and transport failures stop retrying and publish only validated fallback',
    () async {
      for (final failure in [
        TimeoutException('simulated'),
        const SocketException('simulated'),
      ]) {
        var calls = 0;
        final service = MealPlanningService(
          MemoryCredentials(),
          clientFactory: () => MockClient((_) async {
            calls++;
            throw failure;
          }),
        );
        final result = await service.generate(rules, '2026-10-16', {});
        expect(calls, 1);
        expect(result['source'], 'fallback');
        rules.validate(result['plan'], '2026-10-16');
      }
    },
  );
  test(
    'cancellation rejects result and does not turn into a saved fallback',
    () async {
      final started = Completer<void>();
      final reply = Completer<http.Response>();
      final service = MealPlanningService(
        MemoryCredentials(),
        clientFactory: () => MockClient((_) async {
          started.complete();
          return reply.future;
        }),
      );
      final result = service.generate(rules, '2026-10-16', {});
      await started.future;
      service.cancel();
      reply.complete(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content': jsonEncode(rules.fallback('2026-10-16')),
                },
              },
            ],
          }),
          200,
        ),
      );
      await expectLater(result, throwsA(isA<PlanRejected>()));
    },
  );
  test('redirects and oversized responses are refused', () async {
    for (final response in [
      http.Response('', 307, headers: {'location': 'https://other.invalid'}),
      http.Response('x' * 250001, 200),
    ]) {
      final service = MealPlanningService(
        MemoryCredentials(),
        clientFactory: () => MockClient((request) async {
          expect(request.followRedirects, false);
          return response;
        }),
      );
      final result = await service.generate(rules, '2026-10-16', {});
      expect(result['source'], 'fallback');
      rules.validate(result['plan'], '2026-10-16');
    }
  });
  test(
    'private default stays with DeepSeek; clear and changed endpoints persist without exposing the key',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final credentials = PlanningCredentials();
      expect(
        ((await credentials.read())['key'] as String).isNotEmpty,
        Env.plannerApiKey.isNotEmpty,
      );
      await credentials.save('https://example.invalid/v1', 'test-model', null);
      expect(
        ((await PlanningCredentials().read())['key'] as String).isEmpty,
        true,
      );
      await credentials.save('https://api.deepseek.com', 'deepseek-flash', '');
      expect(
        ((await PlanningCredentials().read())['key'] as String).isEmpty,
        true,
      );
      await credentials.consent('https://api.deepseek.com');
      expect(
        (await PlanningCredentials().read())['consented_url'],
        'https://api.deepseek.com',
      );
    },
  );
}

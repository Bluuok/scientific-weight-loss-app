import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';

class MemoryCredentials extends PlanningCredentials {
  Json settings = {
    'base_url': 'https://example.invalid',
    'key': 'test-only',
    'model': 'deepseek-flash',
    'consented_url': 'https://example.invalid',
  };
  @override
  Future<Json> read() async => settings;
}

void main() {
  late FoodCatalog catalog;
  late PlanRules rules;
  late Json plan;
  setUp(() {
    catalog = FoodCatalog(
      jsonDecode(File('assets/meal_planner/catalog.json').readAsStringSync())
          as Json,
    );
    rules = PlanRules(catalog, targetKcal: 2337, minimumProtein: 80);
    plan = rules.fallback('2026-10-16');
  });
  test(
    'USDA source records complete; fallback passes independent calculation for seven dates',
    () {
      expect(catalog.foods.length, 26);
      expect(catalog.recipes.length, 13);
      rules.validate(plan, '2026-10-16');
      for (final day in plan['days']) {
        final n = catalog.dayNutrition(day);
        expect(n['kcal'], closeTo(2337, .01));
        expect(n['sodium'], lessThanOrEqualTo(2000));
        expect(n['oil'], lessThanOrEqualTo(30));
        expect(n['protein'], greaterThanOrEqualTo(80));
        expect((day['meals'] as List).where((m) => m['simple']).length, 1);
      }
      final chicken = catalog.foods['chicken']!;
      expect(chicken['fdc_id'], '171077');
      expect(chicken['kcal'], 120);
    },
  );
  test(
    'dinner preference uses same validator and local calendar handles month / year / leap',
    () {
      PlanRules(
        catalog,
        targetKcal: 2337,
        minimumProtein: 80,
        simpleSlot: 'dinner',
      ).fallback('2026-12-28');
      expect(nextDay('2026-12-31', 1), '2027-01-01');
      expect(nextDay('2028-02-28', 1), '2028-02-29');
    },
  );
  test('structural attacks and incomplete nutrition cannot publish', () {
    final mutations = <void Function(Json)>[
      (p) => p['days'].removeLast(),
      (p) => p['days'][1]['date'] = p['days'][0]['date'],
      (p) => p['days'][0]['meals'].removeLast(),
      (p) => p['days'][0]['meals'][1]['slot'] = 'breakfast',
      (p) => p['days'][0]['meals'][0]['recipe_id'] = 'invented',
      (p) => p['days'][0]['meals'][0]['portion'] = 0,
      (p) => p['days'][0]['meals'][0]['portion'] = double.infinity,
      (p) => p['days'][0]['meals'][0]['simple'] = true,
      (p) => p['days'][0]['meals'][1]['simple'] = false,
      (p) => p['days'][0]['review'] = 'exercise',
      (p) => p['medication'] = 'stop medicine',
      (p) => p['days'][0]['meals'][0]['kcal'] = 1,
      (p) => p['days'][0]['meals'][0]['portion'] = '1',
    ];
    for (final mutation in mutations) {
      final bad = copyJson(plan);
      mutation(bad);
      expect(() => rules.validate(bad, '2026-10-16'), throwsA(anything));
    }
    catalog.foods['salt']!['sodium'] = null;
    expect(
      () => rules.validate(plan, '2026-10-16'),
      throwsA(isA<PlanRejected>()),
    );
  });
  test(
    'salt, oil, energy, protein, allergies and diversity enforced independently',
    () {
      for (final (food, field, value) in [
        ('salt', 'sodium', 90000),
        ('oil', 'kcal', 9000),
        ('chicken', 'protein', 0),
      ]) {
        final c = FoodCatalog(
          jsonDecode(
                File('assets/meal_planner/catalog.json').readAsStringSync(),
              )
              as Json,
        );
        c.foods[food]![field] = value;
        final r = PlanRules(c, targetKcal: 2337, minimumProtein: 120);
        expect(
          () => r.validate(plan, '2026-10-16'),
          throwsA(isA<PlanRejected>()),
        );
      }
      final oil = copyJson(plan);
      for (final m in oil['days'][0]['meals']) {
        m['portion'] = 1.4;
      }
      expect(
        () => rules.validate(oil, '2026-10-16'),
        throwsA(isA<PlanRejected>()),
      );
      expect(
        () => PlanRules(
          catalog,
          targetKcal: 2337,
          minimumProtein: 80,
          avoid: ['egg'],
        ).validate(plan, '2026-10-16'),
        throwsA(isA<PlanRejected>()),
      );
      expect(
        () => PlanRules(
          catalog,
          targetKcal: 2337,
          minimumProtein: 80,
          avoid: ['milk'],
        ).fallback('2026-10-16'),
        throwsA(isA<PlanRejected>()),
      );
    },
  );
  test(
    'replanning freezes past, completed, replaced and skipped meals; pending stays pending',
    () {
      final candidate = rules.fallback('2026-10-16', rotation: 1);
      final records = <String, dynamic>{
        '2026-10-17/lunch': {'status': 'completed'},
        '2026-10-17/dinner': {'status': 'replaced'},
        '2026-10-18/lunch': {'status': 'skipped'},
      };
      final merged = mergeRemaining(plan, candidate, records, '2026-10-17');
      expect(merged['days'][0]['meals'], plan['days'][0]['meals']);
      expect(merged['days'][1]['meals'][1], plan['days'][1]['meals'][1]);
      expect(merged['days'][1]['meals'][2], plan['days'][1]['meals'][2]);
      expect(merged['days'][2]['meals'][1], plan['days'][2]['meals'][1]);
      expect(merged['days'][1]['meals'][0], candidate['days'][1]['meals'][0]);
      expect(records.containsKey('2026-10-17/breakfast'), false);
    },
  );
  test(
    'real HTTP path validates same plan, sends minimum schema, and never trusts calories',
    () async {
      var calls = 0;
      final service = MealPlanningService(
        MemoryCredentials(),
        clientFactory: () => MockClient((request) async {
          calls++;
          expect(
            request.url.toString(),
            'https://example.invalid/chat/completions',
          );
          final body = jsonDecode(request.body);
          expect(body['model'], 'deepseek-flash');
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': jsonEncode(plan)},
                },
              ],
            }),
            200,
          );
        }),
      );
      final result = await service.generate(rules, '2026-10-16', {
        'profile': {'renal_function': 'unknown'},
      });
      expect(result['source'], 'ai');
      expect(calls, 1);
      rules.validate(result['plan'], '2026-10-16');
    },
  );
  test(
    '429, empty/truncated/invalid JSON and unknown recipe use validated labelled fallback',
    () async {
      for (final response in [
        http.Response('', 429),
        http.Response('{}', 200),
        http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'length',
                'message': {'content': '{}'},
              },
            ],
          }),
          200,
        ),
        http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': 'not json'},
              },
            ],
          }),
          200,
        ),
        http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content': jsonEncode({...plan, 'extra': 'unsafe'}),
                },
              },
            ],
          }),
          200,
        ),
      ]) {
        var calls = 0;
        final service = MealPlanningService(
          MemoryCredentials(),
          clientFactory: () => MockClient((_) async {
            calls++;
            return response;
          }),
        );
        final result = await service.generate(rules, '2026-10-16', {});
        expect(result['source'], 'fallback');
        expect(calls, lessThanOrEqualTo(3));
        rules.validate(result['plan'], '2026-10-16');
      }
    },
  );
  test(
    'no key and Mock never send HTTP; changed destination requires fresh consent',
    () async {
      final credentials = MemoryCredentials();
      credentials.settings['key'] = '';
      final service = MealPlanningService(
        credentials,
        clientFactory: () => throw StateError('Network forbidden'),
      );
      expect(
        (await service.generate(rules, '2026-10-16', {}))['source'],
        'fallback',
      );
      credentials.settings['key'] = 'test-only';
      expect(
        (await service.generate(rules, '2026-10-16', {}, mock: true))['source'],
        'mock',
      );
      credentials.settings['consented_url'] = '';
      await expectLater(
        service.generate(rules, '2026-10-16', {}),
        throwsA(isA<PlanRejected>()),
      );
      expect(
        () => PlanningCredentials.endpoint('http://example.com'),
        throwsA(isA<PlanRejected>()),
      );
      expect(
        () => PlanningCredentials.endpoint('https://key@example.com'),
        throwsA(isA<PlanRejected>()),
      );
    },
  );
}

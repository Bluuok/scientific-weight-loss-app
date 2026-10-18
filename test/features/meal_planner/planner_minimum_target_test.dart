import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'planner_test.dart' show MemoryCredentials;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FoodCatalog catalog;
  setUp(() async {
    catalog = FoodCatalog(
      jsonDecode(
            await rootBundle.loadString('assets/meal_planner/catalog.json'),
          )
          as Json,
    );
  });
  test(
    'minimum energy template stays within strict limits for both simple slots',
    () {
      for (final slot in ['lunch', 'dinner']) {
        final rules = PlanRules(
          catalog,
          targetKcal: 1800,
          minimumProtein: 64,
          simpleSlot: slot,
        );
        final plan = rules.fallback('2026-10-18');
        rules.validate(plan, '2026-10-18');
        for (final day in plan['days']) {
          expect(
            catalog.dayNutrition(day)['kcal'],
            inInclusiveRange(1800, 1980),
          );
        }
        final tooLow = copyJson(plan);
        for (final meal in tooLow['days'][0]['meals']) {
          meal['portion'] *= .93;
        }
        expect(
          () => rules.validate(tooLow, '2026-10-18'),
          throwsA(isA<PlanRejected>()),
        );
      }
    },
  );
  test(
    'API receives full energy boundaries and calculated repair feedback',
    () async {
      final rules = PlanRules(
        catalog,
        targetKcal: 1800,
        minimumProtein: 64,
        simpleSlot: 'dinner',
      );
      final valid = rules.fallback('2026-10-18');
      final invalid = copyJson(valid);
      for (final meal in invalid['days'][0]['meals']) {
        meal['portion'] *= .93;
      }
      var calls = 0;
      final requests = <List>[];
      final service = MealPlanningService(
        MemoryCredentials(),
        clientFactory: () => MockClient((request) async {
          final messages = jsonDecode(request.body)['messages'] as List;
          requests.add(messages);
          final response = calls++ == 0 ? invalid : valid;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': jsonEncode(response)},
                },
              ],
            }),
            200,
          );
        }),
      );
      final result = await service.generate(rules, '2026-10-18', {});
      expect(result['source'], 'ai');
      expect(calls, 2);
      final constraints = jsonDecode(
        requests.first[1]['content'],
      )['constraints'];
      expect(constraints['energy_min_kcal'], closeTo(1800, 1e-8));
      expect(constraints['energy_max_kcal'], closeTo(1980, 1e-8));
      expect(constraints['planning_aim_kcal'], closeTo(1890, 1e-8));
      expect(requests.last.last['content'], contains('2026-10-18 has'));
      expect(requests.last.last['content'], contains('1800.00 to 1980.00'));
    },
  );
}

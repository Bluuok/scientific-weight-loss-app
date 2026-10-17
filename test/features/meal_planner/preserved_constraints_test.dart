import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';

void main() {
  test(
    'history exemptions require exact old meals and retain portion/nutrition checks',
    () {
      final catalog = FoodCatalog(
        jsonDecode(File('assets/meal_planner/catalog.json').readAsStringSync())
            as Json,
      );
      final oldRules = PlanRules(catalog, targetKcal: 2337, minimumProtein: 80);
      final newRules = PlanRules(
        catalog,
        targetKcal: 2337,
        minimumProtein: 80,
        avoid: ['beef'],
      );
      final old = oldRules.fallback('2026-10-16');
      final candidate = newRules.fallback('2026-10-16');
      final preserved = preservedPlanMeals(old, {}, '2026-10-20');
      final merged = mergeRemaining(old, candidate, {}, '2026-10-20');
      newRules.validate(merged, '2026-10-16', preservedMeals: preserved);
      final beef = (old['days'] as List)
          .expand<dynamic>((d) => d['meals'] as List)
          .firstWhere((m) => !catalog.allowed(m['recipe_id'], ['beef']));
      final changed = copyJson(merged);
      final changedMeal = (changed['days'] as List)
          .expand<dynamic>((d) => d['meals'] as List)
          .firstWhere((m) => m['recipe_id'] == beef['recipe_id']);
      changedMeal['portion'] += .01;
      expect(
        () =>
            newRules.validate(changed, '2026-10-16', preservedMeals: preserved),
        throwsA(isA<PlanRejected>()),
      );
      final oversized = copyJson(merged);
      oversized['days'][0]['meals'][0]['portion'] = 2.0;
      final forged = Map<String, Json>.from(preserved);
      forged['2026-10-16/breakfast'] = Map<String, dynamic>.from(
        oversized['days'][0]['meals'][0],
      );
      expect(
        () =>
            newRules.validate(oversized, '2026-10-16', preservedMeals: forged),
        throwsA(isA<PlanRejected>()),
      );
    },
  );
}

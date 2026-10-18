import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/domain/recipe_steps.dart';
import 'package:opennutritracker/features/meal_planner/domain/weight_loss_eligibility.dart';
import 'planner_persistence_test.dart' show TestUser;

void main() {
  final catalog = FoodCatalog(
    jsonDecode(File('assets/meal_planner/catalog.json').readAsStringSync()),
  );
  test(
    'older male protein boundary yields seven safe days including egg rotation',
    () {
      for (final target in [1800.0, 2000.0, 2337.0]) {
        for (final slot in ['lunch', 'dinner']) {
          final rules = PlanRules(
            catalog,
            targetKcal: target,
            minimumProtein: target == 2337 ? 100 : 80,
            simpleSlot: slot,
          );
          final plan = rules.fallback('2026-10-18');
          rules.validate(plan, '2026-10-18');
          for (final day in plan['days']) {
            expect(
              catalog.dayNutrition(day)['protein'],
              greaterThanOrEqualTo(rules.minimumProtein),
            );
          }
        }
      }
    },
  );
  test(
    'oil and salt instructions scale with portions and do not round salt to whole grams',
    () {
      final instructions = RecipeSteps.instructions(catalog, 's1', .825);
      expect(instructions, contains('8.25克'));
      expect(instructions, contains('0.82克'));
      expect(instructions, contains('123.8克'));
      expect(instructions, contains('牛肉糜'));
      expect(instructions, contains('72℃'));
      expect(instructions, contains('不是每道菜再加一份'));
      final breakfast = RecipeSteps.instructions(catalog, 'b0', 1);
      expect(breakfast, contains('烹调油 0.00克、食盐 0.00克'));
      expect(breakfast, contains('碾碎'));
      for (final recipe in catalog.recipes.keys) {
        expect(RecipeSteps.instructions(catalog, recipe, 1), isNotEmpty);
      }
    },
  );
  test(
    'older overweight male is not automatically put on a reducing diet',
    () async {
      // 82 / 1.78² = BMI 25.9, below the adult obesity threshold.
      expect(
        weightLossIssue(await TestUser(weight: 82).getUserData()),
        isNotNull,
      );
    },
  );
}

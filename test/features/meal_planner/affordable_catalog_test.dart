import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/domain/recipe_steps.dart';

void main() {
  final catalog = FoodCatalog(
    jsonDecode(File('assets/meal_planner/catalog.json').readAsStringSync())
        as Json,
  );

  test('all 28 meals use traced ingredients and finite, local nutrition', () {
    expect(catalog.foods.length, 26);
    expect(catalog.recipes.length, 28);
    for (final recipe in catalog.recipes.values) {
      expect(['everyday', 'occasional'], contains(recipe['budget_tier']));
      for (final ingredient in (recipe['ingredients'] as Map).entries) {
        final food = catalog.foods[ingredient.key];
        expect(food, isNotNull, reason: recipe['id'] as String);
        expect(food!['source_url'], isNotNull);
        expect(food['state'], isNotNull);
        expect((ingredient.value as num) > 0, true);
      }
      final nutrition = catalog.nutrition(recipe['id'] as String, 1);
      for (final value in nutrition.values) {
        expect((value as num).isFinite, isTrue);
        expect(value, greaterThanOrEqualTo(0));
      }
    }
  });

  test('fallback remains validated across two simple slots and budgets', () {
    for (final budget in ['normal', 'economy']) {
      for (final slot in ['lunch', 'dinner']) {
        for (final target in [1800.0, 2000.0, 2337.0]) {
          final rules = PlanRules(
            catalog,
            targetKcal: target,
            minimumProtein: target == 2337 ? 100 : 80,
            simpleSlot: slot,
            budget: budget,
          );
          final plan = rules.fallback('2026-10-18');
          rules.validate(plan, '2026-10-18');
          for (final day in plan['days']) {
            final n = catalog.dayNutrition(Map<String, dynamic>.from(day));
            expect(n['kcal'], inInclusiveRange(rules.minimumKcal, rules.maximumKcal));
            expect(n['protein'], greaterThanOrEqualTo(rules.minimumProtein));
            expect(n['sodium'], lessThanOrEqualTo(2000));
            expect(n['oil'], lessThanOrEqualTo(30));
          }
          if (budget == 'economy') {
            for (final day in plan['days']) {
              for (final meal in day['meals']) {
                expect(
                  catalog.recipes[meal['recipe_id']]!['budget_tier'],
                  'everyday',
                );
              }
            }
          }
        }
      }
    }
  });

  test('home-style flavor tips never change computed oil or salt amounts', () {
    final advice = RecipeSteps.instructions(catalog, 's7', 1);
    expect(advice, contains('家常口感建议'));
    expect(advice, contains('毛豆仁'));
    expect(advice, contains('烹调油 10.00克、食盐 1.00克'));
    expect(advice, contains('仅使用清单中已有食材'));
    final n = catalog.nutrition('s7', 1);
    expect(n['oil'], 10);
    expect(n['sodium'], lessThan(2000));
  });
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/domain/grocery_budget.dart';

void main() {
  final catalog = FoodCatalog(
    jsonDecode(File('assets/meal_planner/catalog.json').readAsStringSync())
        as Json,
  );
  test('seven-day list multiplies every ingredient by planned portion', () {
    final rules = PlanRules(catalog, targetKcal: 2337, minimumProtein: 100);
    final plan = rules.fallback('2026-10-19');
    final result = GroceryBudget.calculate(catalog, plan, {});
    final items = List<Json>.from(result['items']);
    expect(items, isNotEmpty);
    final expected = <String, double>{};
    for (final day in plan['days']) {
      for (final meal in day['meals']) {
        final recipe = catalog.recipes[meal['recipe_id']]!;
        for (final ingredient in (recipe['ingredients'] as Map).entries) {
          expected[ingredient.key as String] =
              (expected[ingredient.key] ?? 0) +
              ingredient.value * meal['portion'];
        }
      }
    }
    for (final item in items) {
      expect(item['grams'], closeTo(expected[item['food_id']]!, 1e-6));
      expect(item['estimated_yuan'], isNull);
    }
    expect(result['full_estimate_yuan'], isNull);
    expect(result['unpriced_items'], expected.length);
  });

  test('unknown or malformed prices do not generate misleading totals', () {
    final rules = PlanRules(catalog, targetKcal: 2337, minimumProtein: 100);
    final plan = rules.fallback('2026-10-19');
    final none = GroceryBudget.calculate(catalog, plan, {'rice': 0});
    expect(none['priced_items'], 0);
    expect(none['full_estimate_yuan'], isNull);
    final partial = GroceryBudget.calculate(catalog, plan, {
      'rice': 8.0,
      'chicken': 22.0,
      'egg': 'cheap',
    });
    expect(partial['priced_items'], 2);
    expect(partial['unpriced_items'], greaterThan(0));
    expect(partial['partial_known_yuan'], greaterThan(0));
    expect(partial['full_estimate_yuan'], isNull);
    final all = GroceryBudget.calculate(catalog, plan, {
      for (final id in (none['items'] as List).map((item) => item['food_id']))
        id as String: 10.0,
    });
    expect(all['unpriced_items'], 0);
    expect(all['full_estimate_yuan'], closeTo(all['partial_known_yuan'], 0.001));
  });
}

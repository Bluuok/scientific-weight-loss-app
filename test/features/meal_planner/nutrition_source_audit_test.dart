import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/domain/nutrition_source_audit.dart';

void main() {
  FoodCatalog load() => FoodCatalog(
    jsonDecode(File('assets/meal_planner/catalog.json').readAsStringSync())
        as Json,
  );
  test('all bundled foods and 28 recipes have traceable identity', () {
    final catalog = load();
    NutritionSourceAudit.validate(catalog);
    final report = NutritionSourceAudit.coverage(catalog);
    expect(report['food_count'], 26);
    expect(report['recipe_count'], 28);
    expect(report['clinical_completeness'], false);
    for (final value in (report['additional_nutrients'] as Map).values) {
      expect(value['foods_with_data'], lessThanOrEqualTo(26));
    }
  });
  test('unknown micronutrients never become zero-valued claims', () {
    final catalog = load();
    final food = catalog.foods['tofu']!;
    expect(food.containsKey('potassium'), false);
    expect((NutritionSourceAudit.coverage(catalog)['additional_nutrients']
        as Map)['potassium']['foods_with_data'], 0);
    food['potassium'] = '0';
    expect(
      () => NutritionSourceAudit.validate(catalog),
      throwsA(isA<PlanRejected>()),
    );
  });
  test('invalid provenance, duplicate IDs and broken ingredients fail', () {
    for (final mutation in <void Function(FoodCatalog)>[
      (c) => c.foods['egg']!['source_url'] = 'https://example.org/x',
      (c) => c.foods['egg']!['fdc_id'] = c.foods['milk']!['fdc_id'],
      (c) => c.foods['egg']!['protein'] = null,
      (c) => (c.recipes['b0']!['ingredients'] as Map)['fake'] = 80,
    ]) {
      final catalog = load();
      mutation(catalog);
      expect(
        () => NutritionSourceAudit.validate(catalog),
        throwsA(isA<PlanRejected>()),
      );
    }
  });
}

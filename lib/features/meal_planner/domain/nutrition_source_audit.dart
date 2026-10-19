import 'planner.dart';

/// A source-level integrity gate, not a nutritional-completeness certificate.
/// No Chinese food composition values are bundled without redistribution rights.
class NutritionSourceAudit {
  static const coreNutrients = <String>[
    'kcal', 'protein', 'sodium', 'carbs', 'fat', 'fiber',
  ];
  static const optionalNutrients = <String>[
    'potassium', 'calcium', 'saturated_fat', 'magnesium', 'phosphorus',
  ];

  static void validate(FoodCatalog catalog) {
    if (catalog.foods.isEmpty || catalog.recipes.isEmpty) {
      throw const PlanRejected('Nutrition catalogue must not be empty');
    }
    final ids = <String>{};
    for (final entry in catalog.foods.entries) {
      final id = entry.key;
      final food = entry.value;
      if (id.isEmpty || food['id'] != id ||
          food['name'] is! String || (food['name'] as String).trim().isEmpty ||
          food['group'] is! String || food['state'] is! String ||
          (food['state'] as String).isEmpty ||
          food['fdc_id'] is! String ||
          !RegExp(r'^\d+$').hasMatch(food['fdc_id'] as String) ||
          !ids.add(food['fdc_id'] as String)) {
        throw PlanRejected('Nutrition food identity invalid: $id');
      }
      final uri = Uri.tryParse(food['source_url']?.toString() ?? '');
      if (uri == null || uri.scheme != 'https' ||
          uri.host != 'fdc.nal.usda.gov' ||
          !uri.path.contains('/food-details/')) {
        throw PlanRejected('Unverified nutrition source: $id');
      }
      for (final key in coreNutrients) {
        final value = food[key];
        if (value is! num || !value.isFinite || value < 0) {
          throw PlanRejected('Missing or invalid $key for $id');
        }
      }
      // Missing is distinct from numeric zero. Never infer micronutrients.
      for (final key in optionalNutrients) {
        final value = food[key];
        if (value != null && (value is! num || !value.isFinite || value < 0)) {
          throw PlanRejected('Invalid optional nutrient $key for $id');
        }
      }
    }
    for (final recipe in catalog.recipes.values) {
      final ingredients = recipe['ingredients'];
      if (recipe['id'] is! String ||
          recipe['name'] is! String ||
          ingredients is! Map || ingredients.isEmpty) {
        throw const PlanRejected('Recipe identity or ingredients missing');
      }
      for (final entry in ingredients.entries) {
        if (!catalog.foods.containsKey(entry.key) ||
            entry.value is! num ||
            !(entry.value as num).isFinite ||
            entry.value <= 0) {
          throw PlanRejected('Unverifiable ingredient in ${recipe['id']}');
        }
      }
    }
  }

  static Json coverage(FoodCatalog catalog) => {
    'food_count': catalog.foods.length,
    'recipe_count': catalog.recipes.length,
    'source': 'USDA FoodData Central SR Legacy 2018 / CC0',
    'known_nutrients': coreNutrients,
    'additional_nutrients': {
      for (final name in optionalNutrients)
        name: {
          'foods_with_data': catalog.foods.values.where(
            (food) => food[name] is num,
          ).length,
          'foods_total': catalog.foods.length,
        },
    },
    'clinical_completeness': false,
    'caution': 'Unknown potassium, calcium, saturated fat and other values '
        'are not zero and cannot be called nutritionally adequate.',
  };
}

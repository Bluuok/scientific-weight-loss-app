import 'dart:convert';

typedef Json = Map<String, dynamic>;

String localDay(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String nextDay(String day, int offset) {
  final d = DateTime.parse(day);
  return localDay(DateTime(d.year, d.month, d.day + offset));
}

Json copyJson(Json value) => jsonDecode(jsonEncode(value)) as Json;

class PlanRejected implements Exception {
  final String reason;
  const PlanRejected(this.reason);
  @override
  String toString() => reason;
}

class FoodCatalog {
  final Map<String, Json> foods;
  final Map<String, Json> recipes;
  FoodCatalog(Json data)
    : foods = {
        for (final f in data['foods'])
          f['id'] as String: Map<String, dynamic>.from(f),
      },
      recipes = {
        for (final r in data['recipes'])
          r['id'] as String: Map<String, dynamic>.from(r),
      };

  Json nutrition(String recipeId, double portion) {
    final recipe = recipes[recipeId];
    if (recipe == null) throw const PlanRejected('Unknown recipe ID');
    final sum = <String, dynamic>{
      'kcal': 0.0,
      'protein': 0.0,
      'sodium': 0.0,
      'oil': 0.0,
      'carbs': 0.0,
      'fat': 0.0,
      'fiber': 0.0,
    };
    for (final entry in (recipe['ingredients'] as Map).entries) {
      final food = foods[entry.key];
      if (food == null || food['source_url'] == null || food['state'] == null) {
        throw const PlanRejected('Missing food provenance');
      }
      final grams = (entry.value as num).toDouble() * portion;
      for (final key in [
        'kcal',
        'protein',
        'sodium',
        'carbs',
        'fat',
        'fiber',
      ]) {
        final value = food[key];
        if (value is! num || !value.isFinite || value < 0) {
          throw const PlanRejected('Missing or invalid nutrition');
        }
        sum[key] = (sum[key] as double) + value * grams / 100;
      }
      if (food['group'] == 'oil') sum['oil'] = (sum['oil'] as double) + grams;
    }
    return sum;
  }

  bool allowed(String recipeId, List<String> avoid) {
    final recipe = recipes[recipeId];
    if (recipe == null) return false;
    return !(recipe['ingredients'] as Map).keys.any(avoid.contains);
  }

  String? primaryProtein(String recipeId) {
    final ingredients = recipes[recipeId]?['ingredients'] as Map?;
    if (ingredients == null) return null;
    for (final id in ['chicken', 'beef', 'fish', 'tofu', 'egg']) {
      if (ingredients.containsKey(id)) return id;
    }
    return null;
  }

  Json dayNutrition(Json day) {
    final sum = <String, dynamic>{
      'kcal': 0.0,
      'protein': 0.0,
      'sodium': 0.0,
      'oil': 0.0,
      'carbs': 0.0,
      'fat': 0.0,
      'fiber': 0.0,
    };
    for (final meal in day['meals']) {
      final n = nutrition(
        meal['recipe_id'],
        (meal['portion'] as num).toDouble(),
      );
      for (final key in sum.keys.toList()) {
        sum[key] += n[key];
      }
    }
    return sum;
  }
}

/// Conservative engineering boundaries; these are reference checks, not a prescription.
class PlanRules {
  static const version = 'cn2022-dash-reference-v2';
  final FoodCatalog catalog;
  final double targetKcal;
  final double minimumProtein;
  final List<String> avoid;
  final String simpleSlot;
  PlanRules(
    this.catalog, {
    required this.targetKcal,
    required this.minimumProtein,
    this.avoid = const [],
    this.simpleSlot = 'lunch',
  });

  double get minimumKcal => targetKcal * .9 < 1800 ? 1800 : targetKcal * .9;
  double get maximumKcal => targetKcal * 1.1;
  double get planningKcal => (minimumKcal + maximumKcal) / 2;

  void _keys(Json object, Set<String> required) {
    if (object.keys.toSet().difference(required).isNotEmpty ||
        required.difference(object.keys.toSet()).isNotEmpty) {
      throw const PlanRejected('Unexpected or missing schema fields');
    }
  }

  void validate(
    Json plan,
    String start, {
    Map<String, Json> preservedMeals = const {},
  }) {
    if (!targetKcal.isFinite ||
        targetKcal < 1800 ||
        targetKcal > 3200 ||
        !minimumProtein.isFinite ||
        minimumProtein < 60 ||
        minimumProtein > 120) {
      throw const PlanRejected('Profile needs individual assessment');
    }
    _keys(plan, {'schema_version', 'period_start', 'days'});
    if (plan['schema_version'] != 1 ||
        plan['period_start'] != start ||
        plan['days'] is! List ||
        (plan['days'] as List).length != 7) {
      throw const PlanRejected('Require seven consecutive dates');
    }
    final weeklyRecipes = <String>{};
    final weeklyProteins = <String>{};
    final availableProteins = catalog.recipes.values
        .where((r) => r['simple'] == true && catalog.allowed(r['id'], avoid))
        .map((r) => catalog.primaryProtein(r['id']))
        .whereType<String>()
        .toSet();
    String? previousProtein;
    var proteinRun = 0;
    for (var i = 0; i < 7; i++) {
      final day = Map<String, dynamic>.from(plan['days'][i]);
      _keys(day, {'date', 'meals', 'review'});
      if (day['date'] != nextDay(start, i) ||
          day['review'] != 'daily_review' ||
          day['meals'] is! List ||
          (day['meals'] as List).length != 3) {
        throw const PlanRejected('Invalid date, meals or daily review');
      }
      var simple = 0;
      final slots = <String>{};
      final foodIds = <String>{};
      final groups = <String, double>{};
      for (final raw in day['meals']) {
        final meal = Map<String, dynamic>.from(raw);
        _keys(meal, {'slot', 'recipe_id', 'portion', 'simple'});
        if (!['breakfast', 'lunch', 'dinner'].contains(meal['slot']) ||
            meal['slot'] != ['breakfast', 'lunch', 'dinner'][slots.length] ||
            !slots.add(meal['slot']) ||
            meal['simple'] is! bool) {
          throw const PlanRejected('Invalid or duplicate meal slot');
        }
        final portion = meal['portion'];
        if (portion is! num ||
            !portion.isFinite ||
            portion < .65 ||
            portion > 1.4) {
          throw const PlanRejected('Portion must be 0.65–1.4');
        }
        final original = preservedMeals["${day['date']}/${meal['slot']}"];
        final preserved =
            original != null &&
            [
              'slot',
              'recipe_id',
              'portion',
              'simple',
            ].every((key) => original[key] == meal[key]);
        if (meal['recipe_id'] is! String ||
            !catalog.recipes.containsKey(meal['recipe_id']) ||
            (!preserved && !catalog.allowed(meal['recipe_id'], avoid))) {
          throw const PlanRejected('Unknown recipe or excluded ingredient');
        }
        final recipe = catalog.recipes[meal['recipe_id']]!;
        if (!(recipe['slots'] as List).contains(meal['slot'])) {
          throw const PlanRejected('Recipe does not fit meal slot');
        }
        if (meal['simple']) {
          simple++;
          final protein = catalog.primaryProtein(meal['recipe_id']);
          if (protein != null) {
            weeklyProteins.add(protein);
            proteinRun = protein == previousProtein ? proteinRun + 1 : 1;
            previousProtein = protein;
            if (availableProteins.length >= 2 && proteinRun > 2) {
              throw const PlanRejected(
                'Rotate simple-meal protein; no three consecutive days with the same source',
              );
            }
          }
          if (recipe['simple'] != true || meal['slot'] != simpleSlot) {
            throw const PlanRejected(
              'Simple meal must use a verified recipe and preferred slot',
            );
          }
        }
        weeklyRecipes.add(meal['recipe_id']);
        for (final entry in (recipe['ingredients'] as Map).entries) {
          final group = catalog.foods[entry.key]!['group'] as String;
          groups[group] = (groups[group] ?? 0) + (entry.value as num) * portion;
          foodIds.add(entry.key as String);
        }
      }
      if (simple != 1) {
        throw const PlanRejected('Exactly one simple meal per day');
      }
      _validateDayNutrition(day, groups, foodIds);
    }
    final requiredProteins = availableProteins.length < 3
        ? availableProteins.length
        : 3;
    if (weeklyProteins.length < requiredProteins) {
      throw const PlanRejected('Insufficient weekly main-protein rotation');
    }
    if (weeklyRecipes.length < 6) {
      throw const PlanRejected('Weekly recipe diversity insufficient');
    }
  }

  void _validateDayNutrition(
    Json day,
    Map<String, double> groups,
    Set<String> foodIds,
  ) {
    final n = catalog.dayNutrition(day);
    if (n['kcal'] < minimumKcal || n['kcal'] > maximumKcal) {
      throw PlanRejected(
        'Daily energy outside conservative target: ${day['date']} has '
        '${(n['kcal'] as num).toStringAsFixed(2)} kcal; required '
        '${minimumKcal.toStringAsFixed(2)} to ${maximumKcal.toStringAsFixed(2)} kcal. '
        'Aim near ${planningKcal.toStringAsFixed(2)} kcal and recalculate all portions.',
      );
    }
    if (n['protein'] < minimumProtein ||
        n['protein'] > 150 ||
        n['sodium'] > 2000 ||
        n['oil'] > 30) {
      throw const PlanRejected('Protein, sodium or cooking oil outside limits');
    }
    if (foodIds.length < 9 ||
        (groups['vegetable'] ?? 0) < 400 ||
        (groups['fruit'] ?? 0) < 200 ||
        (groups['grain'] ?? 0) < 100 ||
        (groups['dairy'] ?? 0) < 200) {
      throw const PlanRejected('Insufficient food-group diversity');
    }
  }

  Json fallback(String start, {int rotation = 0}) {
    List<Json> choices(String slot, bool simple) => catalog.recipes.values
        .where(
          (r) =>
              (r['slots'] as List).contains(slot) &&
              r['simple'] == simple &&
              allowed(r['id']),
        )
        .toList();
    final days = <Json>[];
    for (var i = 0; i < 7; i++) {
      final meals = <Json>[];
      for (final slot in ['breakfast', 'lunch', 'dinner']) {
        final simple = slot == simpleSlot;
        final options = choices(slot, simple);
        if (options.isEmpty) {
          throw const PlanRejected(
            'No safe local template for these exclusions',
          );
        }
        meals.add({
          'slot': slot,
          'recipe_id': options[(i + rotation) % options.length]['id'],
          'portion': 1.0,
          'simple': simple,
        });
      }
      final day = <String, dynamic>{
        'date': nextDay(start, i),
        'meals': meals,
        'review': 'daily_review',
      };
      final fullSlot = simpleSlot == 'lunch' ? 'dinner' : 'lunch';
      final fullIndex = fullSlot == 'lunch' ? 1 : 2;
      final options = choices(fullSlot, false);
      var feasible = false;
      for (var attempt = 0; attempt < options.length; attempt++) {
        meals[fullIndex]['recipe_id'] =
            options[(i + rotation + attempt) % options.length]['id'];
        for (final meal in meals) {
          meal['portion'] = 1.0;
        }
        final templateKcal = targetKcal <= 1800 ? 1800.001 : targetKcal;
        final ratio =
            templateKcal / (catalog.dayNutrition(day)['kcal'] as double);
        if (ratio < .65 || ratio > 1.4) continue;
        final groups = <String, double>{};
        final ids = <String>{};
        for (final meal in meals) {
          meal['portion'] = ratio;
          for (final entry
              in (catalog.recipes[meal['recipe_id']]!['ingredients'] as Map)
                  .entries) {
            final group = catalog.foods[entry.key]!['group'] as String;
            groups[group] = (groups[group] ?? 0) + (entry.value as num) * ratio;
            ids.add(entry.key as String);
          }
        }
        try {
          _validateDayNutrition(day, groups, ids);
          feasible = true;
          break;
        } on PlanRejected {
          /* Try another verified main dish. */
        }
      }
      if (!feasible) {
        throw const PlanRejected(
          'No safe local template for this profile and exclusions',
        );
      }
      days.add(day);
    }
    final result = <String, dynamic>{
      'schema_version': 1,
      'period_start': start,
      'days': days,
    };
    validate(result, start);
    return result;
  }

  bool allowed(String id) => catalog.allowed(id, avoid);
}

/// Past dates and every recorded meal are immutable during replanning.
Json mergeRemaining(
  Json old,
  Json candidate,
  Map<String, dynamic> records,
  String today,
) {
  final result = copyJson(candidate);
  for (var i = 0; i < 7; i++) {
    final day = old['days'][i];
    for (var j = 0; j < 3; j++) {
      final meal = day['meals'][j];
      final key = '${day['date']}/${meal['slot']}';
      if ((day['date'] as String).compareTo(today) < 0 ||
          ((records[key] as Map?)?['status'] ?? 'pending') != 'pending') {
        result['days'][i]['meals'][j] = copyJson(
          Map<String, dynamic>.from(meal),
        );
      }
    }
  }
  return result;
}

Map<String, Json> preservedPlanMeals(
  Json old,
  Map<String, dynamic> records,
  String today,
) => {
  for (final day in old['days'])
    for (final meal in day['meals'])
      if ((day['date'] as String).compareTo(today) < 0 ||
          ((records["${day['date']}/${meal['slot']}"] as Map?)?['status'] ??
                  'pending') !=
              'pending')
        "${day['date']}/${meal['slot']}": copyJson(
          Map<String, dynamic>.from(meal),
        ),
};

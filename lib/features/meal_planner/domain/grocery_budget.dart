import 'planner.dart';

/// A shopping estimate based on planned (not eaten) raw ingredient quantities.
/// No live prices: only explicitly entered local RMB/500g prices are trusted.
class GroceryBudget {
  static Json calculate(
    FoodCatalog catalog,
    Json plan,
    Map<String, dynamic> unitPrices,
  ) {
    final grams = <String, double>{};
    for (final rawDay in (plan['days'] as List)) {
      for (final rawMeal in (rawDay['meals'] as List)) {
        final meal = Map<String, dynamic>.from(rawMeal as Map);
        final recipe = catalog.recipes[meal['recipe_id']];
        final portion = meal['portion'];
        if (recipe == null ||
            portion is! num || !portion.isFinite || portion <= 0) {
          throw const PlanRejected('Invalid meal for grocery summary');
        }
        for (final ingredient in (recipe['ingredients'] as Map).entries) {
          final id = ingredient.key as String;
          if (!catalog.foods.containsKey(id) ||
              ingredient.value is! num) {
            throw const PlanRejected('Unknown shopping ingredient');
          }
          grams[id] = (grams[id] ?? 0) +
              (ingredient.value as num) * portion.toDouble();
        }
      }
    }
    var known = 0;
    var partial = 0.0;
    final ids = grams.keys.toList()..sort();
    final items = <Json>[];
    for (final id in ids) {
      final raw = unitPrices[id];
      final per500 = raw is num && raw.isFinite &&
              raw >= 0.01 && raw <= 2000
          ? raw.toDouble()
          : null;
      final subtotal = per500 == null ? null : grams[id]! / 500 * per500;
      if (subtotal != null) {
        known++;
        partial += subtotal;
      }
      items.add({
        'food_id': id,
        'name': catalog.foods[id]!['name'],
        'state': catalog.foods[id]!['state'],
        'grams': grams[id],
        'yuan_per_500g': per500,
        'estimated_yuan': subtotal,
      });
    }
    return {
      'price_source': 'user_entry_only',
      'currency': 'CNY',
      'time_scope': 'planned_seven_days',
      'items': items,
      'priced_items': known,
      'unpriced_items': items.length - known,
      'partial_known_yuan': partial,
      // A partial total must never masquerade as a complete household budget.
      'full_estimate_yuan': known == items.length ? partial : null,
      'note': '仅为计划中的食材可食部生重/干重之和，不是买菜重量。'
          '请按当地实际菜价填写；不可直接推断包装、去皮损耗或真实付款金额。',
    };
  }
}

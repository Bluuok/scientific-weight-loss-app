import 'package:flutter/material.dart';
import '../domain/planner.dart';
import '../domain/recipe_steps.dart';
import 'planner_visual.dart';

/// A focused reading route: ingredient quantities and cooking instructions
/// never expand the three-meal checklist underneath the user.
class PlannerRecipePage extends StatelessWidget {
  final FoodCatalog catalog;
  final String recipeId;
  final double portion;
  final String mealName;

  const PlannerRecipePage({
    super.key,
    required this.catalog,
    required this.recipeId,
    required this.portion,
    required this.mealName,
  });

  @override
  Widget build(BuildContext context) {
    final recipe = catalog.recipes[recipeId]!;
    final ingredients = recipe['ingredients'] as Map;
    final steps = RecipeSteps.instructions(catalog, recipeId, portion);
    final oil = ((ingredients['oil'] ?? 0) as num) * portion;
    final salt = ((ingredients['salt'] ?? 0) as num) * portion;
    return Scaffold(
      backgroundColor: PlannerVisual.background,
      appBar: AppBar(title: const Text('食材和做法')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Semantics(
            identifier: 'planner-recipe-return',
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('看完了，返回记录吃饭'),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Semantics(
          identifier: 'planner-recipe-details',
          child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(mealName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(recipe['name'] as String,
              style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Card(
              color: PlannerVisual.info,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '这餐用油 ${RecipeSteps.grams('oil', oil)} 克 · '
                  '放盐 ${RecipeSteps.grams('salt', salt)} 克\n'
                  '按下列重量备菜，不另加酱油或调味盐。',
                  style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: PlannerVisual.infoInk),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('先准备食材', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final item in ingredients.entries)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        catalog.foods[item.key]!['name'] as String,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${RecipeSteps.grams(item.key as String, (item.value as num) * portion)} 克（${catalog.foods[item.key]!['state']}）',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text('再照着做', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SelectableText(
                  steps,
                  style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(height: 1.65),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

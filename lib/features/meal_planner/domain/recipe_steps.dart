import 'planner.dart';

/// Quantities always come from the same catalogue and portion as nutrition.
/// These are home-cooking instructions, not a clinical prescription.
class RecipeSteps {
  static String grams(String id, num value) =>
      value.toStringAsFixed(id == 'salt' || id == 'oil' ? 2 : 1);

  static String instructions(
    FoodCatalog catalog,
    String recipeId,
    double portion,
  ) {
    final ingredients = catalog.recipes[recipeId]!['ingredients'] as Map;
    double amount(String id) =>
        ((ingredients[id] ?? 0) as num).toDouble() * portion;
    String item(String id) =>
        '${catalog.foods[id]!['name']} ${grams(id, amount(id))}克';
    final steps = <String>[];
    final oil = amount('oil');
    final salt = amount('salt');
    steps.add(
      '本餐合计：烹调油 ${grams('oil', oil)}克、食盐 ${grams('salt', salt)}克。先分别称好，下面各道菜合用这一份，不是每道菜再加一份。',
    );
    steps.add(
      '所有食材按清单的可食部称量；燕麦、糙米为干重，肉、鱼、蛋为生重。熟后重量会变化，请勿按熟重套用。盐不是全天总食盐当量，天然食物的钠也计入全天。',
    );
    if (ingredients.containsKey('oats')) {
      steps.add('${item('oats')}加水煮至软烂，再加入${item('milk')}温热；不加糖，不额外加油盐。');
      steps.add('${item('egg')}为去壳可食部生重，可磕入碗中蒸成全熟蛋羹，蛋液凝固后再食用，不吃溏心蛋。');
      steps.add('${item('walnut')}碾碎后拌入燕麦，坐稳后慢慢吃；牙口差时避免整颗坚果。');
    } else {
      steps.add('${item('rice')}淘洗，加水浸泡后用电饭锅煮软；可增加烹调用水改善口感，不能把清单干重当成熟饭重量。');
      if (ingredients.containsKey('chicken')) {
        steps.add(
          '${item('chicken')}切薄片，取本餐称好的油一半拌匀，加少量水蒸熟；中心温度达到74℃以上再食用，有条件用食品温度计检查，不能只看表面颜色。',
        );
      } else if (ingredients.containsKey('beef')) {
        steps.add(
          '${item('beef')}是牛肉糜，摊成薄肉饼；取本餐称好的油一半抹盘，放肉饼加少量水蒸熟，中心温度达到72℃以上，夹开确认没有生肉后再吃。',
        );
      } else if (ingredients.containsKey('fish')) {
        steps.add(
          '${item('fish')}检查并去除鱼刺，取本餐油的一半抹匀，放盘中蒸熟；中心温度达到63℃以上，不吃生鱼。进食时仍需留意细刺。',
        );
      } else if (ingredients.containsKey('tofu')) {
        steps.add('${item('tofu')}切小块，取本餐油的一半放入锅中，加少量水小火炖热至熟透，避免油炸和煎出硬壳。');
      } else if (ingredients.containsKey('egg')) {
        steps.add('${item('egg')}打散加少量水，取本餐油的一半抹碗后蒸成全熟蛋羹，不吃生蛋或溏心蛋。');
      }
      final vegetables = ingredients.keys
          .where((id) => catalog.foods[id]!['group'] == 'vegetable')
          .cast<String>()
          .toList();
      steps.add(
        '${vegetables.map(item).join('、')}洗净、切小块或细丝，分别加水煮熟或蒸软。把剩余一半油拌入熟蔬菜；不另用油炒菜。',
      );
      steps.add(
        '将本餐称好的食盐 ${grams('salt', salt)}克分配到熟主菜和蔬菜中调味，总量不变。不另加酱油、蚝油、鸡精、腌菜或浓汤；不用高钾代盐自行替换。',
      );
    }
    final fruits = ingredients.keys
        .where((id) => catalog.foods[id]!['group'] == 'fruit')
        .cast<String>();
    for (final id in fruits) {
      steps.add('${item(id)}按清单可食部取量，清洗、去核或去皮，切成易咀嚼的小块；牙口差可蒸软，不加糖。');
    }
    final tip = catalog.recipes[recipeId]?['flavor_tip'];
    if (tip is String && tip.trim().isNotEmpty) {
      steps.add('家常口感建议：$tip 所有做法仅使用清单中已有食材与称好的油盐。');
    }
    steps.add(
      '生熟分开操作；肉类做熟后尽快食用。上述步骤不指定固定蒸煮分钟数，以食材厚度、软熟程度和中心温度判断。吞咽困难需专门评估，不能仅靠切碎或煮软。',
    );
    return List.generate(
      steps.length,
      (i) => '${i + 1}. ${steps[i]}',
    ).join('\n\n');
  }
}

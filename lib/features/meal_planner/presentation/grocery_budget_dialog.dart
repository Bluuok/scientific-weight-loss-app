import 'package:flutter/material.dart';
import '../data/planner_repository.dart';
import '../domain/planner.dart';

/// Manual prices only. This widget cannot claim access to real-time markets.
class GroceryBudgetDialog extends StatefulWidget {
  final PlannerRepository repo;
  final Json plan;
  const GroceryBudgetDialog({
    super.key,
    required this.repo,
    required this.plan,
  });

  @override
  State<GroceryBudgetDialog> createState() => _GroceryBudgetDialogState();
}

class _GroceryBudgetDialogState extends State<GroceryBudgetDialog> {
  String? error;

  Future<void> _editPrice(Json item) async {
    final controller = TextEditingController(
      text: item['yuan_per_500g'] == null
          ? ''
          : (item['yuan_per_500g'] as num).toString(),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('设置${item['name']}的当地价格'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('人民币元 / 500克（1市斤）；请自行核对当地实际菜价。'),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '每斤价格'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'remove'),
            child: const Text('清除价格'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) {
      controller.dispose();
      return;
    }
    try {
      if (result == 'remove') {
        await widget.repo.setUnitPrice(item['food_id'] as String, null);
      } else {
        final value = double.tryParse(result.trim().replaceAll(',', '.'));
        if (value == null) throw const PlanRejected('价格必须是数字');
        await widget.repo.setUnitPrice(item['food_id'] as String, value);
      }
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final estimate = widget.repo.groceryEstimate(widget.plan);
    final items = List<Json>.from(estimate['items']);
    final complete = estimate['full_estimate_yuan'] as num?;
    return AlertDialog(
      title: const Text('本周采购清单'),
      content: SizedBox(
        width: 560,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('按7天计划的原料生重/干重合计。重量不等于实际购买重量。'),
            Text(
              complete == null
                  ? '尚有${estimate['unpriced_items']}种食材未录价；'
                    '已知部分仅作小计，不作为整周预算。'
                  : '按已录入本地价格计算：约 ¥${complete.toStringAsFixed(2)} / 7天',
            ),
            if (error != null)
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final grams = (item['grams'] as num).toStringAsFixed(1);
                  final price = item['yuan_per_500g'] as num?;
                  final subtotal = item['estimated_yuan'] as num?;
                  return Semantics(
                    identifier: 'planner-grocery-price-${item['food_id']}',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${item['name']} · ${grams}克'),
                      subtitle: Text(
                        price == null
                            ? '价格未填 · ${item['state']}'
                            : '¥${price.toStringAsFixed(2)}/斤 · 小计 ¥${subtotal!.toStringAsFixed(2)}',
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editPrice(item),
                    ),
                  );
                },
              ),
            ),
            const Text(
              '油盐一并计入；未计算包装、去皮损耗、运输和菜市场实际付款。'
              '已记录的替换餐不自动改变原计划采购清单。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

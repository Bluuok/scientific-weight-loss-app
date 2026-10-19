import 'package:flutter/material.dart';

/// A semantic light-only palette for the senior daily meal workflow.
/// Color supports icons and explicit text; it never carries status alone.
class PlannerVisual {
  static const background = Color(0xFFF6F8FC);
  static const ink = Color(0xFF243248);
  static const muted = Color(0xFF526079);
  static const breakfast = Color(0xFFFFF0D8);
  static const breakfastInk = Color(0xFF774500);
  static const lunch = Color(0xFFE3F3E9);
  static const lunchInk = Color(0xFF155C3C);
  static const dinner = Color(0xFFECEBFF);
  static const dinnerInk = Color(0xFF453E93);
  static const info = Color(0xFFE6F0FF);
  static const infoInk = Color(0xFF25518C);
  static const caution = Color(0xFFFFF2D2);
  static const cautionInk = Color(0xFF734600);

  static Color mealColor(String slot) => switch (slot) {
    'breakfast' => breakfast,
    'lunch' => lunch,
    _ => dinner,
  };
  static Color mealInk(String slot) => switch (slot) {
    'breakfast' => breakfastInk,
    'lunch' => lunchInk,
    _ => dinnerInk,
  };
  static IconData mealIcon(String slot) => switch (slot) {
    'breakfast' => Icons.wb_sunny_outlined,
    'lunch' => Icons.lunch_dining_rounded,
    _ => Icons.nights_stay_outlined,
  };
  static String statusText(String status) => switch (status) {
    'completed' => '已吃完并记录',
    'replaced' => '已记录其他食物',
    'skipped' => '已记录这餐没吃',
    _ => '还没记录',
  };
  static IconData statusIcon(String status) =>
      status == 'pending' ? Icons.radio_button_unchecked :
      status == 'skipped' ? Icons.remove_circle_outline :
      Icons.check_circle_outline;
}

/// Whole row is tappable; the same next step remains available by the hero CTA.
class PlannerMealRow extends StatelessWidget {
  final String slot;
  final String title;
  final String name;
  final String status;
  final VoidCallback? onTap;

  const PlannerMealRow({
    super.key,
    required this.slot,
    required this.title,
    required this.name,
    required this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = PlannerVisual.mealInk(slot);
    final scale = Theme.of(context).textTheme;
    return Semantics(
      identifier: 'planner-today-meal-$slot',
      button: onTap != null,
      child: Material(
        color: PlannerVisual.mealColor(slot),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PlannerVisual.mealIcon(slot), color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: scale.titleMedium?.copyWith(color: color)),
                      const SizedBox(height: 4),
                      Text(name, style: scale.bodyLarge?.copyWith(color: PlannerVisual.ink)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PlannerVisual.statusIcon(status),
                              color: color, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(PlannerVisual.statusText(status),
                                style: scale.bodySmall?.copyWith(color: color)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

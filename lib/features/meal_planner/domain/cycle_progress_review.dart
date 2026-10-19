import 'planner.dart';

/// A descriptive, 30-day review of the actual recorded actions.
/// Missing tap != skipped meal, and completion != biological weight loss.
class CycleProgressReview {
  static int _elapsed(String start, String day) {
    final a = DateTime.parse(start);
    final b = DateTime.parse(day);
    return DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;
  }

  static Json build({
    required String programStart,
    required String asOf,
    required List<Json> plans,
    required Map<String, dynamic> records,
  }) {
    final elapsed = _elapsed(programStart, asOf).clamp(0, 1000000).toInt();
    final cycleStart = nextDay(programStart, elapsed ~/ 30 * 30);
    final cycleEnd = nextDay(cycleStart, 29);
    final end = asOf.compareTo(cycleEnd) > 0 ? cycleEnd : asOf;
    final planned = <String>{};
    for (final revision in plans) {
      final plan = revision['plan'];
      if (plan is! Map || plan['days'] is! List) continue;
      for (final d in plan['days']) {
        if (d is Map && d['date'] is String) {
          final day = d['date'] as String;
          if (day.compareTo(cycleStart) >= 0 && day.compareTo(end) <= 0) {
            planned.add(day);
          }
        }
      }
    }
    final phases = List.generate(4, (i) => <String, dynamic>{
      'phase': i + 1,
      'planned_meals_due': 0,
      'recorded_as_planned': 0,
      'recorded_replaced': 0,
      'explicitly_skipped': 0,
      'unknown_meals': 0,
      'daily_reviews_recorded': 0,
    });
    for (final day in planned) {
      final index = _elapsed(cycleStart, day);
      if (index < 0 || index >= 30) continue;
      final phase = index < 7 ? 0 : index < 14 ? 1 : index < 21 ? 2 : 3;
      final row = phases[phase];
      for (final slot in ['breakfast', 'lunch', 'dinner']) {
        row['planned_meals_due'] = (row['planned_meals_due'] as int) + 1;
        final value = records['$day/$slot'];
        final status = value is Map ? value['status'] : null;
        final field = switch (status) {
          'completed' => 'recorded_as_planned',
          'replaced' => 'recorded_replaced',
          'skipped' => 'explicitly_skipped',
          _ => 'unknown_meals',
        };
        row[field] = (row[field] as int) + 1;
      }
      final review = records['$day/review'];
      if (review is Map && review['status'] == 'completed') {
        row['daily_reviews_recorded'] =
            (row['daily_reviews_recorded'] as int) + 1;
      }
    }
    int sum(String key) => phases.fold<int>(
      0, (value, row) => value + (row[key] as int),
    );
    final recorded = sum('recorded_as_planned') +
        sum('recorded_replaced') + sum('explicitly_skipped');
    return {
      'cycle_start': cycleStart,
      'cycle_end': cycleEnd,
      'as_of': end,
      'days_with_plans': planned.length,
      'planned_meals_due': sum('planned_meals_due'),
      'recorded_as_planned': sum('recorded_as_planned'),
      'recorded_replaced': sum('recorded_replaced'),
      'explicitly_skipped': sum('explicitly_skipped'),
      'unknown_meals': sum('unknown_meals'),
      'recorded_fraction': sum('planned_meals_due') == 0
          ? null : recorded / sum('planned_meals_due'),
      'phases': phases,
      'interpretation': 'Only diary/plan recording coverage. Unknown is not '
          'skipped or eaten. No inference about calories actually absorbed, '
          'blood pressure, muscle change, adherence, or future weight loss.',
    };
  }
}

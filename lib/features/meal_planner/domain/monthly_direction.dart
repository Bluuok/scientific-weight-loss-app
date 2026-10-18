import 'planner.dart';

/// A 30-day habit framework, not a promise to lose a specified mass in a month.
class MonthlyDirection {
  static const version = 'monthly-reference-v2';
  static const focuses = <String>[
    '建立规律：三餐按时、熟悉克数与油盐，真实记录，不追求快速下降',
    '形成轮换：鱼禽蛋豆与少量瘦牛肉轮换，保持每天蔬果、奶类和主食',
    '提高可坚持性：根据真实替换、饥饿和烹饪困难改善方便程度，不用挨饿换打卡率',
    '复盘与延续：看多次体重记录和执行难点，保留能坚持的习惯，不自动加大热量缺口',
  ];
  static int _days(String start, String date) {
    final a = DateTime.parse(start), b = DateTime.parse(date);
    return DateTime.utc(
      b.year,
      b.month,
      b.day,
    ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }

  static int phaseForDay(int day) => day <= 7
      ? 1
      : day <= 14
      ? 2
      : day <= 21
      ? 3
      : 4;
  /// Observed measurements only; never extrapolate or change calories
  /// from a few scale readings.
  static Json _weightEvidence(
    List<Json> measurements,
    String cycleStart,
    String weekStart,
  ) {
    final byDay = <String, double>{};
    for (final item in measurements) {
      final date = item['date'];
      final kg = item['kg'];
      if (date is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          date.compareTo(cycleStart) < 0 ||
          date.compareTo(weekStart) > 0 ||
          kg is! num ||
          !kg.isFinite ||
          kg <= 0) {
        continue;
      }
      try {
        if (localDay(DateTime.parse(date)) != date) continue;
        byDay[date] = kg.toDouble();
      } catch (_) {
        continue;
      }
    }
    final dates = byDay.keys.toList()..sort();
    final span = dates.length < 2 ? 0 : _days(dates.first, dates.last);
    final enough = dates.length >= 3 && span >= 7;
    final first = enough ? byDay[dates.first]! : null;
    final last = enough ? byDay[dates.last]! : null;
    return {
      'status': enough ? 'observed_only' : 'insufficient_data',
      'recorded_days': dates.length,
      'observation_span_days': span,
      'observed_change_kg': enough ? last! - first! : null,
      'observed_change_pct': enough ? (last! - first!) / first! * 100 : null,
      'interpretation':
          'This is only a difference between recorded weigh-ins. Daily fluctuation is not fat loss. '
          'Never infer muscle change or alter calories automatically. Missing data stays unknown.',
    };
  }

  static Json build({
    required String monthStart,
    required String weekStart,
    required double initialWeightKg,
    required double currentWeightKg,
    required double heightCm,
    required double targetKcal,
    required double minimumProtein,
    double? longTermGoalKg,
    List<Json> weightMeasurements = const [],
  }) {
    final elapsed = _days(monthStart, weekStart).clamp(0, 1000000).toInt();
    final cycleIndex = elapsed ~/ 30;
    final cycleStart = nextDay(monthStart, cycleIndex * 30);
    final day = elapsed % 30 + 1;
    final phase = phaseForDay(day);
    return {
      'version': version,
      'start_date': monthStart,
      'first_month_end': nextDay(monthStart, 29),
      'cycle_number': cycleIndex + 1,
      'cycle_start': cycleStart,
      'cycle_end': nextDay(cycleStart, 29),
      'overall_program_day': elapsed + 1,
      'horizon_days': 30,
      'weekly_window_days': 7,
      'program_day': day,
      'phase': phase,
      'focus': focuses[phase - 1],
      'reference_goal_kg': initialWeightKg * .95,
      'long_term_goal_kg': longTermGoalKg,
      'goal_deadline': 'none; 5% is a gradual stage goal, not a 30-day promise',
      'current_bmi': currentWeightKg / (heightCm / 100) / (heightCm / 100),
      'target_kcal': targetKcal,
      'minimum_protein_g': minimumProtein,
      'daily_invariants': [
        'three meals',
        'one simple meal',
        'whole grains, vegetables, fruit, dairy and protein each day',
        'sodium <= 2000mg',
        'cooking oil <= 30g',
        'no fasting or compensatory restriction',
      ],
      'weight_observation': _weightEvidence(
        weightMeasurements,
        cycleStart,
        weekStart,
      ),
      'phase_outline': [
        for (var i = 0; i < 4; i++) {'phase': i + 1, 'focus': focuses[i]},
      ],
      'day_focus': [
        for (var i = 0; i < 7; i++)
          {
            'date': nextDay(weekStart, i),
            'focus': focuses[phaseForDay((elapsed + i) % 30 + 1) - 1],
          },
      ],
      'continuity':
          'Use recorded meals to rotate main protein and improve practicality; unknown intake is not a deficiency. '
          'Do not compensate yesterday with excess nutrients or fasting today. Missing weight history stays unknown.',
    };
  }
}

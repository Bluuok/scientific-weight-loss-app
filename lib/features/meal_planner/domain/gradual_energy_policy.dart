import 'dart:math' as math;
import 'planner.dart';

/// Conservative product policy, NOT a prescribed calorie deficit.
/// Phase advancement requires actual tolerance reports from the PRIOR week.
class GradualEnergyPolicy {
  static const version = 'elder-satiety-v1';
  static const responses = <String, String>{
    'comfortable': '吃得饱',
    'hungry': '经常觉得饿',
    'too_hungry': '太饿或身体不舒服',
  };

  static int _dayOffset(String from, String to) {
    final a = DateTime.parse(from);
    final b = DateTime.parse(to);
    return DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }

  static Json stage({
    required String programStart,
    required String weekStart,
    required Map<String, dynamic> reports,
    String? asOfDate,
  }) {
    final elapsed = math.max(0, _dayOffset(programStart, weekStart));
    final previousWeeks = elapsed ~/ 7;
    var level = 0;
    var lastReason = '先适应一周：不强求挨饿，也不追求快速减重。';
    for (var index = 0; index < previousWeeks; index++) {
      final start = nextDay(programStart, index * 7);
      final end = nextDay(start, 6);
      final values = <String>[];
      for (final entry in reports.entries) {
        if (entry.key.compareTo(start) >= 0 &&
            entry.key.compareTo(end) <= 0 &&
            entry.key.compareTo(asOfDate ?? weekStart) <= 0 &&
            responses.containsKey(entry.value)) {
          values.add(entry.value as String);
        }
      }
      if (values.contains('too_hungry')) {
        level = 0;
        lastReason = '近期报告过明显饥饿或不适：不再增加节食强度，建议评估原因。';
      } else if (values.contains('hungry')) {
        lastReason = '上一阶段还有饥饿感：继续现有温和水平，不加大限制。';
      } else if (end.compareTo(asOfDate ?? weekStart) >= 0) {
        lastReason = '这一周尚未完整结束：保持现有水平，不提前加大限制。';
      } else if (values.length >= 3 &&
          values.every((value) => value == 'comfortable')) {
        level = math.min(2, level + 1);
        lastReason = '前一周至少3天明确反馈吃得饱，尝试小幅渐进；如饥饿立即停止加深。';
      } else {
        lastReason = '反馈不足：维持上次的温和水平，不凭空判断已经适应。';
      }
    }
    const deficits = [0.02, 0.05, 0.10];
    return {
      'version': version,
      'level': level + 1,
      'week': previousWeeks + 1,
      'deficit_fraction': deficits[level],
      'explanation': lastReason,
      'not_a_medical_clearance': true,
    };
  }

  static double calorieTarget(double maintenance, Json stage) {
    // Maximum planned deficit 350 kcal/day for this cautious product pathway.
    final deficit = math.min(350.0,
        maintenance * (stage['deficit_fraction'] as num).toDouble());
    return math.max(1800.0, maintenance - deficit);
  }
}

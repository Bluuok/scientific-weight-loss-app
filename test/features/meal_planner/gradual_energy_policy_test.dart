import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/gradual_energy_policy.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';

void main() {
  Json phase(String start, String week, Map<String, dynamic> reports) =>
      GradualEnergyPolicy.stage(
        programStart: start,
        weekStart: week,
        reports: reports,
      );
  test('first week is gentle; missing reports never trigger deeper restriction', () {
    final first = phase('2026-10-01', '2026-10-01', {});
    expect(first['level'], 1);
    expect(first['deficit_fraction'], .02);
    final fourth = phase('2026-10-01', '2026-10-22', {});
    expect(fourth['level'], 1);
    expect(GradualEnergyPolicy.calorieTarget(2600, first), closeTo(2548, .01));
  });
  test('only three earlier comfortable daily reports allow one step at a time', () {
    final firstWeek = {
      '2026-10-01': 'comfortable',
      '2026-10-02': 'comfortable',
      '2026-10-03': 'comfortable',
    };
    expect(phase('2026-10-01', '2026-10-08', firstWeek)['level'], 2);
    final secondWeek = {
      ...firstWeek,
      '2026-10-08': 'comfortable',
      '2026-10-09': 'comfortable',
      '2026-10-10': 'comfortable',
    };
    expect(phase('2026-10-01', '2026-10-15', secondWeek)['level'], 3);
    expect(phase('2026-10-01', '2026-11-12', secondWeek)['level'], 3);
  });
  test('hunger pauses progression; severe hunger backs off with no automatic cuts', () {
    final data = {
      '2026-10-01': 'comfortable',
      '2026-10-02': 'comfortable',
      '2026-10-03': 'comfortable',
      '2026-10-08': 'comfortable',
      '2026-10-09': 'hungry',
      '2026-10-10': 'comfortable',
    };
    expect(phase('2026-10-01', '2026-10-15', data)['level'], 2);
    data['2026-10-09'] = 'too_hungry';
    expect(phase('2026-10-01', '2026-10-15', data)['level'], 1);
    expect(phase('2026-10-01', '2026-10-15', data)['explanation'],
        contains('评估'));
  });
  test('the policy does not permit a large automatic daily deficit', () {
    final strong = {'deficit_fraction': .10};
    expect(GradualEnergyPolicy.calorieTarget(5000, strong), 4650);
    expect(GradualEnergyPolicy.calorieTarget(2000, strong), 1800);
  });

  test('three early comfortable days never stand in for a completed week', () {
    final result = GradualEnergyPolicy.stage(
      programStart: '2026-10-01', weekStart: '2026-10-08',
      asOfDate: '2026-10-03', reports: {
        '2026-10-01': 'comfortable', '2026-10-02': 'comfortable',
        '2026-10-03': 'comfortable',
      },
    );
    expect(result['level'], 1);
    expect(result['explanation'], contains('尚未完整结束'));
  });

  test('symptoms back off even before the latest week finishes', () {
    final result = GradualEnergyPolicy.stage(
      programStart: '2026-10-01', weekStart: '2026-10-15',
      asOfDate: '2026-10-10', reports: {
        '2026-10-01': 'comfortable', '2026-10-02': 'comfortable',
        '2026-10-03': 'comfortable', '2026-10-09': 'too_hungry',
      },
    );
    expect(result['level'], 1);
    expect(result['explanation'], contains('评估'));
  });

}

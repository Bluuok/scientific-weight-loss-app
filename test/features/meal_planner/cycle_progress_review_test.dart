import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/domain/cycle_progress_review.dart';

void main() {
  Json fakePlan(String date) => {
    'plan': {
      'period_start': date,
      'days': [
        for (var i = 0; i < 7; i++) {'date': nextDay(date, i)}
      ],
    },
  };
  test('unknown meals are not mislabelled skipped and future days excluded', () {
    final review = CycleProgressReview.build(
      programStart: '2026-10-16',
      asOf: '2026-10-18',
      plans: [fakePlan('2026-10-16')],
      records: {
        '2026-10-16/breakfast': {'status': 'completed'},
        '2026-10-16/lunch': {'status': 'replaced'},
        '2026-10-16/dinner': {'status': 'skipped'},
        '2026-10-17/review': {'status': 'completed'},
        '2026-10-20/breakfast': {'status': 'completed'},
      },
    );
    expect(review['planned_meals_due'], 9);
    expect(review['recorded_as_planned'], 1);
    expect(review['recorded_replaced'], 1);
    expect(review['explicitly_skipped'], 1);
    expect(review['unknown_meals'], 6);
    expect(review['recorded_fraction'], closeTo(1 / 3, 0.0001));
    expect(review['phases'][0]['daily_reviews_recorded'], 1);
  });
  test('all 30 days and overlapping revisions counted only once', () {
    final plans = [
      fakePlan('2026-10-16'),
      fakePlan('2026-10-23'),
      fakePlan('2026-10-30'),
      fakePlan('2026-11-06'),
      fakePlan('2026-11-13'),
      fakePlan('2026-11-13'),
    ];
    final r = CycleProgressReview.build(
      programStart: '2026-10-16',
      asOf: '2026-11-14',
      plans: plans,
      records: {},
    );
    expect(r['days_with_plans'], 30);
    expect(r['planned_meals_due'], 90);
    expect((r['phases'] as List).map((p) => p['planned_meals_due']),
        [21, 21, 21, 27]);
    expect(r['unknown_meals'], 90);
    expect(r['recorded_fraction'], 0);
  });
  test('cycle two starts fresh and incomplete data stays unknown', () {
    final r = CycleProgressReview.build(
      programStart: '2026-10-16',
      asOf: '2026-11-16',
      plans: [fakePlan('2026-10-16'), fakePlan('2026-11-15')],
      records: {'2026-10-16/breakfast': {'status': 'completed'}},
    );
    expect(r['cycle_start'], '2026-11-15');
    expect(r['days_with_plans'], 2);
    expect(r['unknown_meals'], 6);
    expect(r['recorded_fraction'], 0);
  });
}

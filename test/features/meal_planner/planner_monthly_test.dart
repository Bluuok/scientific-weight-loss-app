import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/domain/monthly_direction.dart';

void main() {
  test(
    '30-day direction uses current measurements, four phases and no monthly weight-loss deadline',
    () {
      final m = MonthlyDirection.build(
        monthStart: '2026-10-16',
        weekStart: '2026-10-23',
        initialWeightKg: 100,
        currentWeightKg: 99,
        heightCm: 178,
        targetKcal: 2330,
        minimumProtein: 80,
        longTermGoalKg: 85,
      );
      expect(m['phase'], 2);
      expect(m['program_day'], 8);
      expect(m['first_month_end'], '2026-11-14');
      expect(m['reference_goal_kg'], 95);
      expect(m['long_term_goal_kg'], 85);
      expect(m['current_bmi'], closeTo(31.246, 0.01));
      expect(m['target_kcal'], 2330);
      expect(m['phase_outline'].length, 4);
      expect(m['goal_deadline'].contains('not a 30-day promise'), true);
      expect(m['day_focus'].length, 7);
    },
  );
  test(
    'phase dates cross year/leap days and continue review after the first month',
    () {
      Json build(String start, String week) => MonthlyDirection.build(
        monthStart: start,
        weekStart: week,
        initialWeightKg: 100,
        currentWeightKg: 100,
        heightCm: 178,
        targetKcal: 2337,
        minimumProtein: 80,
      );
      expect(build('2026-12-28', '2027-01-04')['phase'], 2);
      expect(build('2028-02-25', '2028-03-03')['program_day'], 8);
      expect(build('2026-10-16', '2026-12-01')['phase'], 4);
    },
  );
  test(
    'simple meal protein rotation cannot be defeated by varying only breakfast and dinner',
    () {
      final catalog = FoodCatalog(
        jsonDecode(File('assets/meal_planner/catalog.json').readAsStringSync())
            as Json,
      );
      final rules = PlanRules(catalog, targetKcal: 2337, minimumProtein: 80);
      final plan = rules.fallback('2026-10-16');
      for (final day in plan['days']) {
        day['meals'][1]['recipe_id'] = 's0';
        final ratio =
            2337 /
            (catalog.dayNutrition(Map<String, dynamic>.from(day))['kcal']
                as double);
        for (final meal in day['meals']) {
          meal['portion'] *= ratio;
        }
      }
      expect(
        () => rules.validate(plan, '2026-10-16'),
        throwsA(isA<PlanRejected>()),
      );
    },
  );
}

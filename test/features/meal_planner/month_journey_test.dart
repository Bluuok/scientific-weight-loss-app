import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/domain/monthly_direction.dart';

void main() {
  test('offline month journey validates four consecutive weekly plans', () {
    final catalog = FoodCatalog(
      jsonDecode(File('assets/meal_planner/catalog.json').readAsStringSync())
          as Json,
    );
    final rules = PlanRules(
      catalog,
      targetKcal: 2337,
      minimumProtein: 100,
    );
    const start = '2026-10-16';
    for (var week = 0; week < 4; week++) {
      final weekStart = nextDay(start, week * 7);
      final plan = rules.fallback(weekStart);
      rules.validate(plan, weekStart);
      final direction = MonthlyDirection.build(
        monthStart: start,
        weekStart: weekStart,
        initialWeightKg: 100,
        currentWeightKg: 100,
        heightCm: 178,
        targetKcal: rules.targetKcal,
        minimumProtein: rules.minimumProtein,
      );
      expect(direction['phase'], week + 1);
      expect(plan['days'].length, 7);
      expect(plan['days'].last['date'], nextDay(weekStart, 6));
    }
  });
}

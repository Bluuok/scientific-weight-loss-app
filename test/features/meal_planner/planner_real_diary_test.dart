import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/tracked_day_data_source.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/hive_registrar.g.dart';
import 'package:opennutritracker/features/meal_planner/data/planner_repository.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'planner_persistence_test.dart'
    show TestDB, TestUser, TestWeights, OfflineCredentials;

class DiaryDB extends TestDB {
  late Box<TrackedDayDBO> days;
  @override
  Box<TrackedDayDBO> get trackedDayBox => days;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Hive.registerAdapters());
  test(
    'first completion creates a real day, updates totals, persists and undoes',
    () async {
      final dir = await Directory.systemTemp.createTemp('planner-real-diary-');
      Hive.init(dir.path);
      final db = DiaryDB();
      db.plans = await Hive.openBox<String>('plans');
      db.intakes = await Hive.openBox<IntakeDBO>('intakes');
      db.days = await Hive.openBox<TrackedDayDBO>('days');
      try {
        final intakes = IntakeRepository(IntakeDataSource(db));
        final tracker = AddTrackedDayUsecase(
          TrackedDayRepository(TrackedDayDataSource(db)),
        );
        final repo = PlannerRepository(
          db,
          intakes,
          TestUser(),
          TestWeights(),
          tracker,
          MealPlanningService(OfflineCredentials()),
        );
        await repo.initialize();
        final today = localDay(DateTime.now());
        final plan = await repo.generate(today);
        final meals = List<Json>.from(plan['plan']['days'][0]['meals']);
        expect(db.days.isEmpty, isTrue);
        for (final meal in meals) {
          await repo.record(today, meal, 'completed');
          expect(
            repo.state['records']['$today/${meal['slot']}']['sync_pending'],
            isFalse,
          );
        }
        expect(db.days.length, 1);
        expect(db.intakes.length, 3);
        final total = (await intakes.getAllIntakesDBO()).fold<double>(
          0,
          (sum, row) =>
              sum +
              row.amount * (row.meal.nutriments.energyKcal100 ?? 0) / 100,
        );
        expect(db.days.values.single.caloriesTracked, closeTo(total, .001));
        await repo.record(today, meals[0], 'completed');
        expect(db.intakes.length, 3);
        await db.plans.flush();
        await db.intakes.flush();
        await db.days.flush();
        await repo.initialize();
        expect(db.intakes.length, 3);
        for (final meal in meals) {
          await repo.record(today, meal, 'pending');
        }
        expect(db.intakes.isEmpty, isTrue);
        expect(db.days.values.single.caloriesTracked, 0);
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

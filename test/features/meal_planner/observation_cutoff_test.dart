import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/features/meal_planner/data/planner_repository.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'package:opennutritracker/hive_registrar.g.dart';
import 'planner_persistence_test.dart'
    show TestDB, TestUser, TestWeights, TestTracked, OfflineCredentials;

class ObservedWeights extends TestWeights {
  List<WeightLogEntity> entries = [];
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => entries;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(Hive.registerAdapters);
  late Directory dir;
  late PlannerRepository repo;
  late ObservedWeights weights;
  var today = DateTime(2026, 10, 26);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ont-observation-cutoff-');
    Hive.init(dir.path);
    final db = TestDB();
    db.plans = await Hive.openBox<String>('plans');
    db.intakes = await Hive.openBox<IntakeDBO>('intakes');
    weights = ObservedWeights();
    today = DateTime(2026, 10, 26);
    repo = PlannerRepository(
      db,
      IntakeRepository(IntakeDataSource(db)),
      TestUser(),
      weights,
      TestTracked(),
      MealPlanningService(OfflineCredentials()),
      now: () => today,
    );
    await repo.initialize();
    await repo.generate('2026-10-16');
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test(
    'adjusting an existing week includes actual weigh-ins after its start',
    () async {
      weights.entries = [
        WeightLogEntity(date: DateTime(2026, 10, 18), weightKg: 100),
        WeightLogEntity(date: DateTime(2026, 10, 21), weightKg: 99.5),
        WeightLogEntity(date: DateTime(2026, 10, 25), weightKg: 99),
      ];
      final direction = await repo.monthlyDirection('2026-10-18');
      expect(direction['weight_observation']['recorded_days'], 3);
      expect(direction['weight_observation']['status'], 'observed_only');
      expect(direction['weight_observation']['observed_change_kg'], -1);
      expect(direction['target_kcal'], (await repo.rules()).targetKcal);
    },
  );
  test(
    'a future plan does not treat future-dated weights as actual evidence',
    () async {
      today = DateTime(2026, 10, 18);
      weights.entries = [
        WeightLogEntity(date: DateTime(2026, 10, 16), weightKg: 100),
        WeightLogEntity(date: DateTime(2026, 10, 18), weightKg: 99.5),
        WeightLogEntity(date: DateTime(2026, 10, 23), weightKg: 99),
      ];
      final direction = await repo.monthlyDirection('2026-10-30');
      expect(direction['weight_observation']['recorded_days'], 2);
      expect(direction['weight_observation']['status'], 'insufficient_data');
      expect(direction['weight_observation']['observed_change_kg'], isNull);
    },
  );
  test(
    'observations for an old cycle exclude measurements in the next cycle',
    () async {
      today = DateTime(2026, 11, 20);
      weights.entries = [
        WeightLogEntity(date: DateTime(2026, 10, 18), weightKg: 100),
        WeightLogEntity(date: DateTime(2026, 10, 21), weightKg: 99.5),
        WeightLogEntity(date: DateTime(2026, 10, 25), weightKg: 99),
        WeightLogEntity(date: DateTime(2026, 11, 15), weightKg: 98),
        WeightLogEntity(date: DateTime(2026, 11, 19), weightKg: 97),
      ];
      final direction = await repo.monthlyDirection('2026-11-13');
      expect(direction['weight_observation']['recorded_days'], 3);
      expect(direction['weight_observation']['observed_change_kg'], -1);
    },
  );
}

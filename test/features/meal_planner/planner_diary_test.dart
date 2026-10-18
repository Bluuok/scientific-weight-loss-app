import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/hive_registrar.g.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/data/planner_repository.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'planner_persistence_test.dart'
    show TestDB, TestUser, TestWeights, TestTracked, OfflineCredentials;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Hive.registerAdapters());
  late Directory dir;
  late PlannerRepository repo;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ont-diary-integration-');
    Hive.init(dir.path);
    final db = TestDB();
    db.plans = await Hive.openBox<String>('plans');
    db.intakes = await Hive.openBox<IntakeDBO>('intakes');
    repo = PlannerRepository(
      db,
      IntakeRepository(IntakeDataSource(db)),
      TestUser(),
      TestWeights(),
      TestTracked(),
      MealPlanningService(OfflineCredentials()),
    );
    await repo.initialize();
    await repo.generate(localDay(DateTime.now()));
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test(
    'a diary replacement removes only planner-owned intake; undo retains actual food and blocks duplicate completion',
    () async {
      final today = localDay(DateTime.now());
      final meal = Map<String, dynamic>.from(
        repo.state['plans'][0]['plan']['days'][0]['meals'][0],
      );
      await repo.record(today, meal, 'completed');
      final planned = (await repo.intakes.getAllIntakesDBO()).single;
      await repo.intakes.addIntake(
        IntakeEntity(
          id: 'actual-food',
          unit: planned.unit,
          amount: planned.amount,
          type: IntakeEntity.fromIntakeDBO(planned).type,
          meal: IntakeEntity.fromIntakeDBO(planned).meal,
          dateTime: planned.dateTime,
        ),
      );
      await repo.record(
        today,
        meal,
        'replaced',
        notes: '实际食物',
        externalIds: ['actual-food'],
      );
      expect(
        (await repo.intakes.getAllIntakesDBO()).map((m) => m.id).toList(),
        ['actual-food'],
      );
      await repo.record(today, meal, 'pending');
      expect((await repo.intakes.getAllIntakesDBO()).length, 1);
      await expectLater(
        repo.record(today, meal, 'completed'),
        throwsA(isA<PlanRejected>()),
      );
      expect((await repo.intakes.getAllIntakesDBO()).length, 1);
    },
  );
  test(
    'local swap creates a new validated version, while a completed meal is locked',
    () async {
      final today = localDay(DateTime.now());
      final original = repo.state['plans'][0]['plan'];
      final day = await repo.swap(today, 'lunch', 's1');
      expect(repo.state['plans'].length, 2);
      expect(original['days'][0]['meals'][1]['recipe_id'], 's0');
      expect(day['meals'][1]['recipe_id'], 's1');
      expect(repo.state['plans'].last['source'], 'manual');
      final rule = await repo.rules();
      rule.validate(repo.state['plans'].last['plan'], today);
      await repo.record(
        today,
        Map<String, dynamic>.from(day['meals'][1]),
        'completed',
      );
      await expectLater(
        repo.swap(today, 'lunch', 's2'),
        throwsA(isA<PlanRejected>()),
      );
      expect(repo.state['plans'].length, 2);
    },
  );
}

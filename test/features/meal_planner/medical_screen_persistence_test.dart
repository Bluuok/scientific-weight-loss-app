import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/features/meal_planner/data/planner_repository.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'package:opennutritracker/features/meal_planner/domain/medical_safety_screen.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/hive_registrar.g.dart';
import 'planner_persistence_test.dart'
    show TestDB, TestUser, TestWeights, TestTracked, OfflineCredentials;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(Hive.registerAdapters);
  late Directory dir;
  late TestDB db;
  late PlannerRepository repo;
  Future<void> open() async {
    db = TestDB();
    db.plans = await Hive.openBox<String>('plans');
    db.intakes = await Hive.openBox<IntakeDBO>('intakes');
    repo = PlannerRepository(
      db,
      IntakeRepository(IntakeDataSource(db)),
      TestUser(),
      TestWeights(),
      TestTracked(),
      MealPlanningService(OfflineCredentials()),
      enforceMedicalScreen: true,
    );
    await repo.initialize();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ont-risk-screen-');
    Hive.init(dir.path);
    await open();
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test('production-style gate requires every answer; persists on restart',
      () async {
    expect(repo.medicalSafetyIssue, isNotNull);
    await expectLater(repo.rules(), throwsA(isA<PlanRejected>()));
    await repo.saveMedicalScreen({
      for (final key in MedicalSafetyScreen.labels.keys) key: 'unknown',
    });
    await expectLater(repo.rules(), throwsA(isA<PlanRejected>()));
    await repo.saveMedicalScreen({
      for (final key in MedicalSafetyScreen.labels.keys) key: 'no',
    });
    expect(repo.medicalSafetyIssue, isNull);
    expect((await repo.rules()).minimumProtein, greaterThan(0));
    await Hive.close();
    await open();
    expect(repo.medicalSafetyIssue, isNull);
    final revised = {
      for (final key in MedicalSafetyScreen.labels.keys) key: 'no',
      'kidney_disease': 'yes',
    };
    await repo.saveMedicalScreen(revised);
    expect(repo.medicalSafetyIssue, contains('肾病'));
    await expectLater(
      repo.generate(localDay(DateTime.now())),
      throwsA(isA<PlanRejected>()),
    );
    expect(repo.state['plans'], isEmpty);
  });
}

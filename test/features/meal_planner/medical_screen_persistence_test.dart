import 'dart:io';
import 'package:flutter/material.dart';
import 'package:opennutritracker/features/meal_planner/presentation/medical_safety_page.dart';
import 'generation_consistency_test.dart' show DeferredService;
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
  Future<void> open({MealPlanningService? service}) async {
    db = TestDB();
    db.plans = await Hive.openBox<String>('plans');
    db.intakes = await Hive.openBox<IntakeDBO>('intakes');
    repo = PlannerRepository(
      db,
      IntakeRepository(IntakeDataSource(db)),
      TestUser(),
      TestWeights(),
      TestTracked(),
      service ?? MealPlanningService(OfflineCredentials()),
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
  test('risk added while AI is running prevents publishing the result', () async {
    await Hive.close();
    final service = DeferredService();
    await open(service: service);
    final answers = {
      for (final key in MedicalSafetyScreen.labels.keys) key: 'no',
    };
    await repo.saveMedicalScreen(answers);
    final request = repo.generate(localDay(DateTime.now()));
    await service.started.future;
    await repo.saveMedicalScreen({...answers, 'kidney_disease': 'yes'});
    service.finish.complete(service.answer);
    await expectLater(request, throwsA(isA<PlanRejected>()));
    expect(repo.state['plans'], isEmpty);
  });

  testWidgets('risk screen is usable at 360dp with twice-sized text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: MedicalSafetyPage(repo: repo),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('保存健康风险核对'), 500);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(repo.medicalSafetyIssue, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

}

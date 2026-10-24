import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/hive_registrar.g.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'package:opennutritracker/features/meal_planner/data/planner_repository.dart';
import 'planner_persistence_test.dart'
    show TestDB, TestUser, TestWeights, TestTracked, OfflineCredentials;

class SwitchingDB extends TestDB {
  String profile = 'test-profile';
  @override
  String get activeProfileId => profile;
}

class DeferredService extends MealPlanningService {
  final started = Completer<void>();
  final finish = Completer<Json>();
  late Json answer;
  DeferredService() : super(OfflineCredentials());
  @override
  Future<Json> generate(
    PlanRules rules,
    String start,
    Json input, {
    bool mock = false,
    Map<String, Json> preservedMeals = const {},
  }) {
    answer = {
      'plan': rules.fallback(start),
      'source': 'mock',
      'model': 'local',
      'notice': '',
    };
    started.complete();
    return finish.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Hive.registerAdapters());
  late Directory dir;
  late SwitchingDB db;
  late PlannerRepository repo;
  late TestUser user;
  late DeferredService service;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ont-consistency-');
    Hive.init(dir.path);
    db = SwitchingDB();
    db.plans = await Hive.openBox<String>('plans');
    db.intakes = await Hive.openBox<IntakeDBO>('intakes');
    user = TestUser();
    service = DeferredService();
    repo = PlannerRepository(
      db,
      IntakeRepository(IntakeDataSource(db)),
      user,
      TestWeights(),
      TestTracked(),
      service,
    );
    await repo.initialize();
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  for (final change in ['preferences', 'weight', 'profile']) {
    test(
      'in-flight $change change cannot publish a stale or cross-profile plan',
      () async {
        final request = repo.generate(localDay(DateTime.now()));
        await service.started.future;
        if (change == 'preferences') {
          final prefs = Map<String, dynamic>.from(repo.state['preferences']);
          prefs['avoid'] = ['beef'];
          await repo.preferences(prefs);
        }
        if (change == 'weight') user.weight = 99;
        if (change == 'profile') db.profile = 'another-profile';
        service.finish.complete(service.answer);
        await expectLater(request, throwsA(isA<PlanRejected>()));
        expect(repo.state['plans'], isEmpty);
        expect(await repo.intakes.getAllIntakesDBO(), isEmpty);
      },
    );
  }
  test('undoing the evidence while generating rejects a stale deeper target', () async {
    final today = localDay(DateTime.now());
    final start = nextDay(today, -7);
    final plan = (await repo.rules(planningStart: start)).fallback(start);
    final initial = repo.state;
    initial['plans'] = [{'id': 'seed', 'plan': plan}];
    await db.plans.put('state', jsonEncode(initial));
    for (var i = 0; i < 3; i++) {
      for (final meal in plan['days'][i]['meals']) {
        await repo.record(nextDay(start, i), Map<String, dynamic>.from(meal), 'completed');
      }
      await repo.saveSatiety(nextDay(start, i), 'comfortable');
    }
    expect(repo.gradualStage(today)['level'], 2);
    final request = repo.generate(today);
    await service.started.future;
    await repo.record(start, Map<String, dynamic>.from(plan['days'][0]['meals'][0]), 'pending');
    expect(repo.gradualStage(today)['level'], 1);
    service.finish.complete(service.answer);
    await expectLater(request, throwsA(isA<PlanRejected>()));
    expect(repo.state['plans'].length, 1);
    expect((await repo.intakes.getAllIntakesDBO()).length, 8);
  });

}

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mockito/mockito.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_pal_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/domain/entity/weight_log_entity.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/hive_registrar.g.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/data/planner_repository.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';

class TestDB extends HiveDBProvider {
  late Box<String> plans;
  late Box<IntakeDBO> intakes;
  @override
  Box<String> get plannerBox => plans;
  @override
  Box<IntakeDBO> get intakeBox => intakes;
}

class TestUser extends Mock implements UserRepository {
  double weight;
  UserWeightGoalEntity goal;
  TestUser({this.weight = 100, this.goal = UserWeightGoalEntity.loseWeight});
  @override
  Future<UserEntity> getUserData() async => UserEntity(
    birthday: DateTime(DateTime.now().year - 60, 1, 1),
    heightCM: 178,
    weightKG: weight,
    gender: UserGenderEntity.male,
    pal: UserPALEntity.sedentary,
    goal: goal,
  );
}

class TestWeights extends Mock implements WeightLogRepository {
  @override
  Future<List<WeightLogEntity>> getAllEntries() async => [];
}

class TestTracked extends Mock implements AddTrackedDayUsecase {
  final totals = <String, List<double>>{};
  @override
  Future<bool> hasTrackedDay(DateTime day) async => true;
  @override
  Future<void> reconcileDayTracked(
    DateTime day,
    double calories,
    double carbs,
    double fat,
    double protein,
  ) async {
    totals[localDay(day)] = [calories, carbs, fat, protein];
  }
}

class OfflineCredentials extends PlanningCredentials {
  @override
  Future<Json> read() async => {
    'key': '',
    'model': 'deepseek-flash',
    'base_url': 'https://api.deepseek.com',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Hive.registerAdapters());
  late Directory dir;
  late TestDB db;
  late PlannerRepository repo;
  late IntakeRepository intake;
  late TestTracked tracked;
  late TestUser user;
  final cipher = HiveAesCipher(List<int>.generate(32, (i) => i));
  Future<void> open() async {
    db = TestDB();
    db.plans = await Hive.openBox<String>(
      'plans',
      encryptionCipher: cipher,
      crashRecovery: false,
    );
    db.intakes = await Hive.openBox<IntakeDBO>(
      'intakes',
      encryptionCipher: cipher,
      crashRecovery: false,
    );
    intake = IntakeRepository(IntakeDataSource(db));
    tracked = TestTracked();
    user = TestUser();
    repo = PlannerRepository(
      db,
      intake,
      user,
      TestWeights(),
      tracked,
      MealPlanningService(OfflineCredentials()),
    );
    await repo.initialize();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ont-planner-test-');
    Hive.init(dir.path);
    await open();
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test('real weekly plans adapt only after satiety reports and persist locally',
      () async {
    final start = nextDay(localDay(DateTime.now()), -14);
    final first = await repo.generate(start);
    final initial = (first['target_kcal'] as num).toDouble();
    expect(first['gradual_energy_stage']['level'], 1);
    expect(initial, greaterThan(1800));
    for (var i = 0; i < 3; i++) {
      for (final meal in first['plan']['days'][i]['meals']) {
        await repo.record(nextDay(start, i), Map<String, dynamic>.from(meal), 'completed');
      }
      await repo.saveSatiety(nextDay(start, i), 'comfortable');
    }
    final second = await repo.generate(nextDay(start, 7));
    expect(second['gradual_energy_stage']['level'], 2);
    expect((second['target_kcal'] as num).toDouble(), lessThan(initial));
    await Hive.close();
    await open();
    expect(repo.satietyReports[nextDay(start, 0)], 'comfortable');
    expect(repo.state['plans'].length, 2);
    // A symptom report should never cause a deeper third-week cut.
    await repo.saveSatiety(nextDay(start, 9), 'too_hungry');
    final proposed = await repo.rules(planningStart: nextDay(start, 14));
    final secondGoal = (second['target_kcal'] as num).toDouble();
    expect(proposed.targetKcal, greaterThan(secondGoal));
    final third = await repo.generate(nextDay(start, 14));
    expect(third['gradual_energy_stage']['level'], 1);
    expect(first['plan'], isNotNull);
    expect(repo.state['plans'][0]['target_kcal'], initial);
    await expectLater(
      repo.saveSatiety(nextDay(localDay(DateTime.now()), 1), 'comfortable'),
      throwsA(isA<PlanRejected>()),
    );
  });

  test('local price entries persist across encrypted Hive restart', () async {
    final today = localDay(DateTime.now());
    final revision = await repo.generate(today);
    final before = repo.groceryEstimate(revision['plan']);
    expect(before['full_estimate_yuan'], isNull);
    await repo.setUnitPrice('rice', 9);
    final partly = repo.groceryEstimate(revision['plan']);
    expect(partly['priced_items'], 1);
    expect(partly['full_estimate_yuan'], isNull);
    await Hive.close();
    await open();
    expect(repo.unitPrices['rice'], 9);
    final after = repo.groceryEstimate(revision['plan']);
    expect(after['priced_items'], 1);
    await expectLater(
      repo.setUnitPrice('rice', -3),
      throwsA(isA<PlanRejected>()),
    );
    await repo.setUnitPrice('rice', null);
    expect(repo.unitPrices.containsKey('rice'), false);
  });
  test(
    'ineligible profile cannot generate or log an old weight-loss plan',
    () async {
      final date = localDay(DateTime.now());
      final revision = await repo.generate(date);
      final oldState = db.plans.get('state');
      user.weight = 55;
      user.goal = UserWeightGoalEntity.gainWeight;
      await expectLater(
        repo.generate(nextDay(date, 7)),
        throwsA(isA<PlanRejected>()),
      );
      await expectLater(
        repo.record(date, revision['plan']['days'][0]['meals'][0], 'completed'),
        throwsA(isA<PlanRejected>()),
      );
      expect(await intake.getAllIntakesDBO(), isEmpty);
      expect(db.plans.get('state'), oldState);
    },
  );
  test(
    'complete / duplicate / undo is durable and idempotent in encrypted Hive and real intake repo',
    () async {
      final today = localDay(DateTime.now());
      final revision = await repo.generate(today);
      expect(revision['monthly_direction']['horizon_days'], 30);
      final meal = Map<String, dynamic>.from(
        revision['plan']['days'][0]['meals'][0],
      );
      await repo.record(today, meal, 'completed');
      await repo.record(today, meal, 'completed');
      expect((await intake.getAllIntakesDBO()).length, 1);
      expect(tracked.totals[today]![0], greaterThan(0));
      await Hive.close();
      await open();
      expect(repo.state['records']['$today/breakfast']['status'], 'completed');
      expect((await intake.getAllIntakesDBO()).length, 1);
      await repo.record(today, meal, 'pending');
      expect((await intake.getAllIntakesDBO()), isEmpty);
      expect(tracked.totals[today]![0], 0);
      expect(repo.state['records']['$today/breakfast']['status'], 'pending');
      expect(repo.state['records']['$today/lunch'], null);
    },
  );
  test(
    'future dates rejected, interrupted writes repaired, history and old revisions retained',
    () async {
      final today = localDay(DateTime.now());
      final revision = await repo.generate(today);
      final meal = Map<String, dynamic>.from(
        revision['plan']['days'][0]['meals'][1],
      );
      await expectLater(
        repo.record(nextDay(today, 1), meal, 'completed'),
        throwsA(isA<PlanRejected>()),
      );
      final s = repo.state;
      s['records']['$today/lunch'] = {
        'status': 'completed',
        'meal': meal,
        'sync_pending': true,
      };
      await db.plannerBox.put('state', jsonEncode(s));
      await Hive.close();
      await open();
      expect((await intake.getAllIntakesDBO()).length, 1);
      expect(repo.state['records']['$today/lunch']['sync_pending'], false);
      final next = await repo.generate(nextDay(today, 7));
      expect(repo.state['plans'].length, 2);
      expect(next['source'], 'fallback');
      final history = await repo.history(nextDay(today, 7));
      expect(history['actual_diary'].length, 1);
      expect(history['weight_trend'], null);
      await expectLater(repo.generate(today), throwsA(isA<PlanRejected>()));
      expect(repo.state['plans'].length, 2);
    },
  );

  test('missing meals and undone meals cannot count as comfortable evidence', () async {
    final start = nextDay(localDay(DateTime.now()), -7);
    final first = await repo.generate(start);
    await expectLater(repo.saveSatiety(start, 'comfortable'),
        throwsA(isA<PlanRejected>()));
    await repo.saveSatiety(start, 'hungry');
    for (var i = 0; i < 3; i++) {
      for (final meal in first['plan']['days'][i]['meals']) {
        await repo.record(nextDay(start, i), Map<String, dynamic>.from(meal), 'completed');
      }
      await repo.saveSatiety(nextDay(start, i), 'comfortable');
    }
    expect(repo.gradualStage(nextDay(start, 7))['level'], 2);
    await repo.record(start, Map<String, dynamic>.from(first['plan']['days'][0]['meals'][0]), 'pending');
    expect(repo.gradualStage(nextDay(start, 7))['level'], 1);
    expect(repo.satietyReports[start], 'comfortable');
  });

  test('actual energy bounds and saved targets survive regeneration and feedback changes', () async {
    final start = nextDay(localDay(DateTime.now()), -14);
    for (var week = 0; week < 2; week++) {
      final weekStart = nextDay(start, week * 7);
      final revision = await repo.generate(weekStart);
      for (var i = 0; i < 3; i++) {
        for (final meal in revision['plan']['days'][i]['meals']) {
          await repo.record(nextDay(weekStart, i), Map<String, dynamic>.from(meal), 'completed');
        }
        await repo.saveSatiety(nextDay(weekStart, i), 'comfortable');
      }
    }
    final today = nextDay(start, 14);
    final third = await repo.generate(today);
    expect(third['gradual_energy_stage']['level'], 3);
    final rule = await repo.rulesForDate(today);
    final maintenance = (third['target_kcal'] as num).toDouble() / .9;
    expect(rule.minimumKcal, greaterThanOrEqualTo(maintenance - 350.0001));
    expect(rule.maximumKcal, lessThanOrEqualTo(maintenance + .0001));
    for (final day in third['plan']['days']) {
      final kcal = repo.catalog.dayNutrition(Map<String, dynamic>.from(day))['kcal'] as num;
      expect(kcal, inInclusiveRange(rule.minimumKcal, rule.maximumKcal));
    }
    await repo.saveSatiety(start, 'too_hungry');
    final regenerated = await repo.generate(today, previous: third);
    expect(regenerated['target_kcal'], third['target_kcal']);
    expect(regenerated['minimum_kcal'], third['minimum_kcal']);
    expect(regenerated['maximum_kcal'], third['maximum_kcal']);
    expect(regenerated['gradual_energy_stage'], third['gradual_energy_stage']);
    expect(regenerated['monthly_direction']['target_kcal'], third['target_kcal']);
    final sameMeal = Map<String, dynamic>.from(regenerated['plan']['days'][0]['meals'][0]);
    await repo.swap(today, sameMeal['slot'], sameMeal['recipe_id']);
    expect(repo.state['plans'].last['target_kcal'], third['target_kcal']);
  });

}

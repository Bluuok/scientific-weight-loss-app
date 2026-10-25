import 'dart:convert';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:synchronized/synchronized.dart';
import 'package:opennutritracker/core/utils/hive_db_provider.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/domain/usecase/add_tracked_day_usecase.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/utils/calc/tdee_calc.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import '../domain/planner.dart';
import '../domain/nutrition_source_audit.dart';
import '../domain/monthly_direction.dart';
import '../domain/grocery_budget.dart';
import '../domain/cycle_progress_review.dart';
import '../domain/gradual_energy_policy.dart';
import '../domain/meal_plan_policy_release.dart';
import '../domain/weight_loss_eligibility.dart';
import '../domain/medical_safety_screen.dart';
import 'meal_planning_service.dart';
import 'authority_sources_service.dart';

class PlannerRepository {
  final HiveDBProvider db;
  final IntakeRepository intakes;
  final UserRepository users;
  final WeightLogRepository weights;
  final AddTrackedDayUsecase tracked;
  final MealPlanningService service;
  final ConfigRepository? config;
  final bool enforceMedicalScreen;
  final DateTime Function() now;
  final Lock _lock = Lock();
  late FoodCatalog catalog;
  PlannerRepository(
    this.db,
    this.intakes,
    this.users,
    this.weights,
    this.tracked,
    this.service, {
    this.config,
    this.enforceMedicalScreen = false,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  Json get state =>
      jsonDecode(
            db.plannerBox.get('state') ??
                '{"schema_version":1,"plans":[],"records":{},"preferences":{"avoid":[],"simple_slot":"lunch","taste":"light","budget":"normal","quick":true},"safety_ack":false}',
          )
          as Json;
  Future<void> _save(Json value) =>
      db.plannerBox.put('state', jsonEncode(value));

  Future<void> initialize() async {
    catalog = FoodCatalog(
      jsonDecode(
            await rootBundle.loadString('assets/meal_planner/catalog.json'),
          )
          as Json,
    );
    NutritionSourceAudit.validate(catalog);
    await _lock.synchronized(() async {
      final s = state;
      // Durable write-ahead intent: repair interrupted cross-box diary writes after restart.
      var repaired = false;
      for (final entry in (s['records'] as Map).entries.toList()) {
        if (entry.value['sync_pending'] == true) {
          await _sync(entry.key, Map<String, dynamic>.from(entry.value));
          entry.value['sync_pending'] = false;
          repaired = true;
        }
      }
      if (repaired) await _save(s);
    });
  }

  List<Json> get sourceLookups => List<Json>.from(
    jsonDecode(db.plannerBox.get('authority_sources') ?? '[]'),
  );
  List<Json> get referenceMaterial => sourceLookups.where((r) {
    final age = now().toUtc().difference(DateTime.parse(r['retrieved_at']));
    return r['status'] == 'verified' &&
        !age.isNegative &&
        age < const Duration(hours: 24);
  }).toList();
  Future<List<Json>> querySources() async {
    final results = await AuthoritySourcesService().fetch();
    await db.plannerBox.put('authority_sources', jsonEncode(results));
    return results;
  }

  String? get medicalSafetyIssue =>
      MedicalSafetyScreen.issue(state['medical_screen']);

  Future<void> saveMedicalScreen(Json answers) =>
      _lock.synchronized(() async {
        final screen = MedicalSafetyScreen.normalize(answers);
        final s = state;
        s['medical_screen'] = screen;
        await _save(s);
      });

  /// Plans already saved remain immutable; satiety only influences NEW weeks.
  Json gradualStage(String start) {
    final snapshot = state;
    final existing = (snapshot['plans'] as List)
        .map((row) => row['plan']['period_start'] as String)
        .toList()..sort();
    final resets = (snapshot['plans'] as List)
        .where((row) => row['policy_refresh_source_id'] != null &&
            (row['plan']['period_start'] as String).compareTo(start) <= 0)
        .map((row) => row['plan']['period_start'] as String)
        .toList()..sort();
    // After a major policy reset, prior tolerance must NOT unlock a more
    // restrictive first week. Begin a new adaptation window.
    final first = resets.isNotEmpty
        ? resets.last
        : existing.isEmpty || start.compareTo(existing.first) < 0
            ? start : existing.first;
    return GradualEnergyPolicy.stage(
      programStart: first,
      weekStart: start,
      asOfDate: localDay(now()),
      reports: {
        for (final entry in (snapshot['satiety_reports'] as Map? ?? {}).entries)
          if (entry.value != 'comfortable' ||
              _threeRecordedMeals(entry.key as String, snapshot['records'] as Map))
            entry.key: entry.value,
      },
    );
  }

  Map<String, dynamic> get satietyReports => Map<String, dynamic>.from(
    state['satiety_reports'] ?? const <String, dynamic>{},
  );

  bool hasThreeRecordedMeals(String date) =>
      _threeRecordedMeals(date, state['records'] as Map);

  static bool _threeRecordedMeals(String date, Map records) =>
      ['breakfast', 'lunch', 'dinner'].every((slot) {
        final record = records['$date/$slot'];
        return record?['status'] == 'completed' ||
            (record?['status'] == 'replaced' &&
                (record?['actual_portion'] != null ||
                    (record?['external_intake_ids'] as List? ?? []).isNotEmpty));
      });

  Future<void> saveSatiety(String date, String? value) {
    final profileId = db.activeProfileId;
    return _lock.synchronized(() async {
        if (db.activeProfileId != profileId) {
          throw const PlanRejected('家人资料已切换，请重新打开当天计划。');
        }
        if ((value != null && !GradualEnergyPolicy.responses.containsKey(value)) ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
            date.compareTo(localDay(now())) > 0 ||
            !(state['plans'] as List).any((revision) =>
                (revision['plan']['days'] as List)
                    .any((day) => day['date'] == date))) {
          throw const PlanRejected('请从已有计划的当天记录饱腹感');
        }
        if (value == 'comfortable' && !hasThreeRecordedMeals(date)) {
          throw const PlanRejected('先如实记录当天三餐，再确认一整天吃得饱；饥饿或不适可随时反馈。');
        }
        final s = state;
        final reports = Map<String, dynamic>.from(
          s['satiety_reports'] ?? const <String, dynamic>{},
        );
        if (value == null) {
          reports.remove(date);
        } else {
          reports[date] = value;
        }
        s['satiety_reports'] = reports;
        await _save(s);
      });
  }

  Future<PlanRules> rules({
    String? simpleSlot,
    String? planningStart,
    double? preservedTargetKcal,
    double? preservedMinimumKcal,
    double? preservedMaximumKcal,
    bool resetAdaptation = false,
  }) async {
    if (enforceMedicalScreen) {
      final issue = medicalSafetyIssue;
      if (issue != null) throw PlanRejected(issue);
    }
    final user = await users.getUserData();
    final issue = weightLossIssue(user);
    if (issue != null) throw PlanRejected(issue);
    final maintenance = TDEECalc.getTDEEKcalIOM2005(user);
    final stageStart = planningStart ?? localDay(now());
    final phase = resetAdaptation
        ? GradualEnergyPolicy.stage(
            programStart: stageStart, weekStart: stageStart, reports: {})
        : gradualStage(stageStart);
    final legacyContract = preservedTargetKcal != null &&
        preservedMinimumKcal == null && preservedMaximumKcal == null;
    final target = preservedTargetKcal ??
        GradualEnergyPolicy.calorieTarget(maintenance, phase);
    // No forced weight-loss plan if this catalogue's floor cannot safely fit.
    if (!maintenance.isFinite || maintenance <= 1800 ||
        target >= maintenance ||
        (legacyContract && target * 1.1 >= maintenance)) {
      throw const PlanRejected('当前估算能量与本餐单模板不匹配，需要营养师个体评估，暂不自动生成减重餐单。');
    }
    final prefs = state['preferences'];
    return PlanRules(
      catalog,
      targetKcal: target,
      minimumProtein: math.min(
        120,
        math.max(60, user.weightKG * (user.age >= 60 ? 1.0 : .8)),
      ),
      avoid: List<String>.from(prefs['avoid']),
      simpleSlot: simpleSlot ?? prefs['simple_slot'],
      budget: prefs['budget'] == 'economy' ? 'economy' : 'normal',
      calorieCeiling: legacyContract ? null :
          math.min(preservedMaximumKcal ?? maintenance, maintenance),
      calorieFloor: legacyContract ? null : math.max(
          preservedMinimumKcal ?? 1800.0, maintenance - 350.0),
      minimumRatio: preservedMinimumKcal != null
          ? preservedMinimumKcal / target : legacyContract ? .9 : .97,
    );
  }

  /// User-entered local prices, in RMB per 市斤 (500g), scoped to this profile.
  Map<String, dynamic> get unitPrices => Map<String, dynamic>.from(
    state['unit_prices_yuan_per_500g'] ?? const <String, dynamic>{},
  );

  Json groceryEstimate(Json plan) =>
      GroceryBudget.calculate(catalog, plan, unitPrices);

  Future<void> setUnitPrice(String foodId, double? yuanPer500g) =>
      _lock.synchronized(() async {
        if (!catalog.foods.containsKey(foodId) ||
            (yuanPer500g != null &&
                (!yuanPer500g.isFinite ||
                 yuanPer500g < 0.01 ||
                 yuanPer500g > 2000))) {
          throw const PlanRejected('无效食材或菜价；请填写每斤人民币金额');
        }
        final s = state;
        final prices = Map<String, dynamic>.from(
          s['unit_prices_yuan_per_500g'] ?? const <String, dynamic>{},
        );
        if (yuanPer500g == null) {
          prices.remove(foodId);
        } else {
          prices[foodId] = yuanPer500g;
        }
        s['unit_prices_yuan_per_500g'] = prices;
        await _save(s);
      });

  Future<void> preferences(Json prefs) => _lock.synchronized(() async {
    final s = state;
    s['preferences'] = prefs;
    await _save(s);
  });
  Future<void> acknowledge() => _lock.synchronized(() async {
    final s = state;
    s['safety_ack'] = true;
    s['safety_ack_version'] = 'older-obesity-v3';
    await _save(s);
  });

  Json cycleReview(String asOf) {
    final s = state;
    final starts = (s['plans'] as List)
        .map((p) => p['plan']['period_start'] as String)
        .toList()..sort();
    if (starts.isEmpty) {
      return {
        'status': 'no_plan',
        'message': '没有已创建的周计划，不能计算执行反馈。',
      };
    }
    return CycleProgressReview.build(
      programStart: starts.first,
      asOf: asOf,
      plans: List<Json>.from(s['plans']),
      records: Map<String, dynamic>.from(s['records']),
    );
  }

  Future<PlanRules> rulesForDate(String date, {String? simpleSlot}) async {
    final matching = (state['plans'] as List).where((row) =>
        date.compareTo(row['plan']['period_start']) >= 0 &&
        date.compareTo(nextDay(row['plan']['period_start'], 6)) <= 0);
    final previous = matching.isEmpty ? null : matching.last;
    return rules(
      simpleSlot: simpleSlot,
      planningStart: previous?['plan']['period_start'] as String? ?? date,
      preservedTargetKcal: (previous?['target_kcal'] as num?)?.toDouble(),
      preservedMinimumKcal: (previous?['minimum_kcal'] as num?)?.toDouble(),
      preservedMaximumKcal: (previous?['maximum_kcal'] as num?)?.toDouble(),
    );
  }

  Future<Json> monthlyDirection(String weekStart, {PlanRules? planRules}) async {
    final s = state;
    final starts =
        (s['plans'] as List)
            .map((p) => p['plan']['period_start'] as String)
            .toList()
          ..sort();
    final user = await users.getUserData();
    final rule = planRules ?? await rulesForDate(weekStart);
    final measurements = (await weights.getAllEntries())
        .map(
          (w) => <String, dynamic>{'date': localDay(w.date), 'kg': w.weightKg},
        )
        .toList();
    return MonthlyDirection.build(
      monthStart: starts.isEmpty ? weekStart : starts.first,
      weekStart: weekStart,
      initialWeightKg:
          (s['initial_weight_kg'] as num?)?.toDouble() ?? user.weightKG,
      currentWeightKg: user.weightKG,
      heightCm: user.heightCM,
      targetKcal: rule.targetKcal,
      minimumProtein: rule.minimumProtein,
      longTermGoalKg: user.targetWeightKg,
      weightMeasurements: measurements,
      observationAsOf: localDay(now()),
    );
  }

  Future<Json> history(String start) async {
    final from = nextDay(start, -14);
    final meals =
        (await intakes.getAllIntakesDBO())
            .where(
              (m) =>
                  localDay(m.dateTime).compareTo(from) >= 0 &&
                  localDay(m.dateTime).compareTo(start) < 0,
            )
            .toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final weight =
        (await weights.getAllEntries())
            .where(
              (w) =>
                  localDay(w.date).compareTo(from) >= 0 &&
                  localDay(w.date).compareTo(start) < 0,
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final records = state['records'] as Map;
    final keys =
        records.keys
            .cast<String>()
            .where(
              (k) =>
                  k.substring(0, 10).compareTo(from) >= 0 &&
                  k.substring(0, 10).compareTo(start) < 0,
            )
            .toList()
          ..sort();
    final knownProteins = <Json>[];
    for (final m in meals) {
      final matching = catalog.recipes.values.where(
        (r) => r['name'] == m.meal.name && r['simple'] == true,
      );
      if (matching.isNotEmpty) {
        final protein = catalog.primaryProtein(matching.first['id']);
        if (protein != null) {
          knownProteins.add({
            'date': localDay(m.dateTime),
            'slot': m.type.name,
            'protein': protein,
            'status': 'recorded',
          });
        }
      }
    }
    return {
      'known_recent_simple_proteins': knownProteins,
      'nutrition_deficiencies':
          'unknown; do not infer micronutrient deficiencies from limited logs',
      'actual_diary': meals
          .map(
            (m) => {
              'date': localDay(m.dateTime),
              'slot': m.type.name,
              'food': m.meal.name,
              'amount': m.amount,
              'unit': m.unit,
            },
          )
          .toList(),
      'execution': {
        for (final k in keys)
          k: {
            'status': records[k]['status'],
            'notes': records[k]['notes'] ?? '',
          },
      },
      'weight_kg': weight
          .map((w) => {'date': localDay(w.date), 'kg': w.weightKg})
          .toList(),
      'weight_trend': weight.length < 2
          ? null
          : {'change_kg': weight.last.weightKg - weight.first.weightKg},
      'missing_records': 'unknown; unrecorded is never skipped',
    };
  }

  bool policyRefreshNeeded(Json revision) =>
      MealPlanPolicyRelease.refreshNeeded(
        revision,
        List<Json>.from(state['plans']),
      );

  /// Keep anything already eaten today. The fresh seven-day plan can start
  /// today only if there are no actual/explicit meal records for today.
  Future<String> policyRefreshStart(Json source) async {
    if (!policyRefreshNeeded(source)) {
      throw const PlanRejected('该计划已使用新策略或已经重建，无须重复生成。');
    }
    final today = localDay(now());
    if (!(source['plan']['days'] as List).any((d) => d['date'] == today)) {
      throw const PlanRejected('只能从正在执行的旧计划升级未来餐次。');
    }
    var already = ['breakfast', 'lunch', 'dinner'].any((slot) {
      final record = state['records']['$today/$slot'];
      return record != null && record['status'] != 'pending';
    });
    for (final slot in ['breakfast', 'lunch', 'dinner']) {
      if (await diarySlotRecorded(today, slot)) already = true;
    }
    return already ? nextDay(today, 1) : today;
  }

  Future<Json> generate(
    String start, {
    Json? previous,
    bool mock = false,
    String reason = '',
    String? policyRefreshSourceId,
  }) async {
    if (policyRefreshSourceId != null) {
      if (previous != null) {
        throw const PlanRejected('策略升级和旧计划微调不能同时进行。');
      }
      final candidates = List<Json>.from(state['plans'])
          .where((p) => p['id'] == policyRefreshSourceId).toList();
      if (candidates.length != 1 ||
          start != await policyRefreshStart(candidates.single)) {
        throw const PlanRejected('旧计划或已记录餐次发生变化，请重新打开并升级。');
      }
    }
    final previousSlot = previous == null
        ? null
        : ((previous['plan']['days'][0]['meals'] as List).firstWhere(
                (m) => m['simple'] == true,
              )['slot']
              as String);
    final rule = await rules(
      simpleSlot: previousSlot,
      planningStart: start,
      preservedTargetKcal: (previous?['target_kcal'] as num?)?.toDouble(),
      preservedMinimumKcal: (previous?['minimum_kcal'] as num?)?.toDouble(),
      preservedMaximumKcal: (previous?['maximum_kcal'] as num?)?.toDouble(),
      resetAdaptation: policyRefreshSourceId != null,
    );
    final user = await users.getUserData();
    final s = state;
    final originProfileId = db.activeProfileId;
    final preferencesStamp = jsonEncode(s['preferences']);
    final satietyStamp = jsonEncode(s['satiety_reports']);
    final stageStamp = jsonEncode(gradualStage(start));
    final energyStage = policyRefreshSourceId != null
        ? GradualEnergyPolicy.stage(
            programStart: start, weekStart: start, reports: {})
        : previous == null ? gradualStage(start) :
        previous['gradual_energy_stage'] ?? <String, dynamic>{
          'version': 'legacy-saved-target',
          'explanation': '沿用已保存计划的能量目标，不自动改写历史安排。',
        };
    final medicalStamp = jsonEncode(s['medical_screen']);
    String profileStamp(UserEntity user) => jsonEncode([
      user.birthday.toIso8601String(),
      user.heightCM,
      user.weightKG,
      user.gender.name,
      user.pal.name,
      user.goal.name,
      user.targetWeightKg,
    ]);
    final originalProfileStamp = profileStamp(user);
    final requestLocks = Map<String, dynamic>.from(s['records']);
    if (previous != null) {
      final today = localDay(now());
      for (final slot in ['breakfast', 'lunch', 'dinner']) {
        if (await diarySlotRecorded(today, slot)) {
          requestLocks['$today/$slot'] = {'status': 'completed'};
        }
      }
    }
    final requestPreserved = previous == null
        ? <String, Json>{}
        : preservedPlanMeals(previous['plan'], requestLocks, localDay(now()));
    final result = await service.generate(
      rule,
      start,
      {
        'mode': policyRefreshSourceId != null
            ? 'policy_refresh'
            : previous == null
                ? ((s['plans'] as List).isEmpty ? 'initial' : 'next_week')
                : 'adjust_remaining',
        'profile': {
          'self_reported_risk_screen': enforceMedicalScreen
              ? 'no_reported_risk_flags_not_medical_clearance'
              : 'not_collected',
          'age_approx': user.age,
          'sex': user.gender.name,
          'height_cm': user.heightCM,
          'weight_kg': user.weightKG,
          'long_term_goal_kg': user.targetWeightKg,
          'intended_audience':
              'older_adults_with_hypertension_and_obesity_male_priority',
          'hypertension_known': null,
          'blood_pressure_uncontrolled': null,
          'taking_antihypertensives': null,
          'renal_function': 'unknown',
          'activity_level': user.pal.name,
          'medical_nutrition_restrictions': 'unknown',
        },
        'monthly_direction': await monthlyDirection(start, planRules: rule),
        'gradual_energy_stage': energyStage,
        'cycle_execution_review': cycleReview(localDay(now())),
        'reference_material': referenceMaterial,
        'references_status': referenceMaterial.isEmpty
            ? 'not_queried_or_unavailable'
            : 'verified_public_sources',
        'preferences': {
          ...Map<String, dynamic>.from(s['preferences']),
          'simple_slot': rule.simpleSlot,
        },
        // A policy refresh starts a genuinely new menu: no old recipe text,
        // no reuse of earlier AI suggestions. Actual eaten data remains local.
        'history_summary': policyRefreshSourceId == null
            ? await history(
                previous == null ? start : nextDay(localDay(now()), 1))
            : <String, dynamic>{
                'policy_refresh': 'do_not_copy_old_menus',
                'previous_intake_not_sent': true,
              },
        'current_plan': policyRefreshSourceId != null ? null : previous?['plan'],
        'execution_records': {
          for (final e in (s['records'] as Map).entries)
            if (policyRefreshSourceId == null &&
                (e.key as String).compareTo(nextDay(start, -14)) >= 0 &&
                (e.key as String)
                        .substring(0, 10)
                        .compareTo(nextDay(start, 6)) <=
                    0)
              e.key: e.value,
        },
        'start_date': start,
        'reason': reason,
        'constraints': {
          'target_kcal': rule.targetKcal,
          'minimum_protein_g': rule.minimumProtein,
          'sodium_mg_max': 2000,
          'cooking_oil_g_max': 30,
          'rules_version': PlanRules.version,
        },
      },
      mock: mock,
      preservedMeals: requestPreserved,
    );
    return _lock.synchronized(() async {
      if (db.activeProfileId != originProfileId) {
        throw const PlanRejected('生成期间已切换资料，结果未保存，请在当前资料重新生成。');
      }
      final currentUser = await users.getUserData();
      final issue = weightLossIssue(currentUser);
      if (issue != null) throw PlanRejected(issue);
      if (profileStamp(currentUser) != originalProfileStamp) {
        throw const PlanRejected('生成期间身体资料已更新，结果未保存，请重新生成。');
      }
      final latest = state;
      if (enforceMedicalScreen) {
        final issue = MedicalSafetyScreen.issue(latest['medical_screen']);
        if (issue != null) throw PlanRejected(issue);
        if (jsonEncode(latest['medical_screen']) != medicalStamp) {
          throw const PlanRejected(
            '生成期间健康风险核对已修改；请重新生成，避免使用旧方案。',
          );
        }
      }
      if (jsonEncode(latest['satiety_reports']) != satietyStamp ||
          (previous == null && jsonEncode(gradualStage(start)) != stageStamp)) {
        throw const PlanRejected('生成过程中饱腹感记录已改变，请重新生成避免使用旧目标。');
      }
      if (jsonEncode(latest['preferences']) != preferencesStamp) {
        throw const PlanRejected('生成期间偏好或忌口已更改，结果未保存，请重新生成。');
      }
      latest['initial_weight_kg'] ??= user.weightKG;
      final plans = latest['plans'] as List;
      final existing = plans
          .where((p) => p['plan']['period_start'] == start)
          .toList();
      if (policyRefreshSourceId != null) {
        final sources = plans.where((p) => p['id'] == policyRefreshSourceId)
            .toList();
        if (sources.length != 1 ||
            !MealPlanPolicyRelease.refreshNeeded(
                Map<String, dynamic>.from(sources.single),
                List<Json>.from(plans))) {
          throw const PlanRejected('该旧计划已升级，请勿重复提交。');
        }
        if (start != await policyRefreshStart(
            Map<String, dynamic>.from(sources.single))) {
          throw const PlanRejected('新记录改变了升级起始日期，请重新生成以保护已吃餐次。');
        }
      }
      if (policyRefreshSourceId == null &&
          previous == null && existing.isNotEmpty) {
        throw const PlanRejected('This week already exists');
      }
      if (policyRefreshSourceId == null &&
          previous == null &&
          plans.any(
            (p) =>
                start.compareTo(nextDay(p['plan']['period_start'], 6)) <= 0 &&
                nextDay(start, 6).compareTo(p['plan']['period_start']) >= 0,
          )) {
        throw const PlanRejected('Overlapping plan dates');
      }
      if (previous != null &&
          (existing.isEmpty || existing.last['id'] != previous['id'])) {
        throw const PlanRejected('Plan changed; reopen before adjusting');
      }
      var preserved = <String, Json>{};
      if (previous != null) {
        final locks = Map<String, dynamic>.from(latest['records']);
        final today = localDay(now());
        for (final day in previous['plan']['days']) {
          if (day['date'] == today) {
            for (final meal in day['meals']) {
              if (await diarySlotRecorded(today, meal['slot'])) {
                locks["$today/${meal['slot']}"] = {'status': 'completed'};
              }
            }
          }
        }
        preserved = preservedPlanMeals(
          previous['plan'],
          locks,
          localDay(now()),
        );
        result['plan'] = mergeRemaining(
          previous['plan'],
          result['plan'],
          locks,
          localDay(now()),
        );
      }
      // Includes frozen meals: never publish a merged week without revalidation.
      rule.validate(result['plan'], start, preservedMeals: preserved);
      if (previousSlot != null &&
          previousSlot != s['preferences']['simple_slot']) {
        result['notice'] = '简洁餐时段变更从下一周生效，本周保留原时段并调整尚未执行的菜式。';
      }
      final revision = <String, dynamic>{
        ...result,
        'id': '$start-v${existing.length + 1}',
        'version': existing.length + 1,
        'created_at': now().toIso8601String(),
        'validation_version': PlanRules.version,
        'planning_policy_version': MealPlanPolicyRelease.current,
        if (policyRefreshSourceId != null)
          'policy_refresh_source_id': policyRefreshSourceId,
        'reason': reason,
        'preferences': latest['preferences'],
        'monthly_direction': await monthlyDirection(start, planRules: rule),
        'target_kcal': rule.targetKcal,
        'minimum_kcal': rule.minimumKcal,
        'maximum_kcal': rule.maximumKcal,
        'gradual_energy_stage': energyStage,
      };
      plans.add(revision);
      await _save(latest);
      return revision;
    });
  }

  Future<void> record(
    String date,
    Json? meal,
    String status, {
    String notes = '',
    double? actualPortion,
    List<String>? externalIds,
  }) => _lock.synchronized(() async {
    if (!['pending', 'completed', 'replaced', 'skipped'].contains(status)) {
      throw const PlanRejected('Invalid status');
    }
    if (date.compareTo(localDay(now())) > 0 && status != 'pending') {
      throw const PlanRejected('Cannot record future meals');
    }
    if (actualPortion != null &&
        (!actualPortion.isFinite || actualPortion <= 0 || actualPortion > 3)) {
      throw const PlanRejected('Invalid actual portion');
    }
    if (meal != null && (status == 'completed' || actualPortion != null)) {
      await rulesForDate(date); // Check before persisting or writing any intake.
      if (!catalog.allowed(
        meal['recipe_id'],
        List<String>.from(state['preferences']['avoid']),
      )) {
        throw const PlanRejected('这份旧计划含新增忌口，请先调整未执行计划；实际吃过的食物请在日记记录。');
      }
    }
    final key = '$date/${meal?['slot'] ?? 'review'}';
    final s = state;
    final linked =
        externalIds ??
        List<String>.from(s['records'][key]?['external_intake_ids'] ?? []);
    if (status == 'completed' || actualPortion != null) {
      for (final id in linked) {
        if (await intakes.getIntakeById(id) != null) {
          throw const PlanRejected('实际日记中已有替换餐，请先在日记核对，避免重复记账。');
        }
      }
    }
    final record = <String, dynamic>{
      'external_intake_ids': linked,
      'status': status,
      'notes': notes,
      'updated_at': now().toIso8601String(),
      'meal': meal,
      'actual_portion': actualPortion,
      'sync_pending': meal != null,
    };
    s['records'][key] = record;
    await _save(s);
    if (meal != null) {
      await _sync(key, record);
      record['sync_pending'] = false;
      await _save(s);
    }
  });

  Future<bool> diarySlotRecorded(String date, String slot) async {
    final settings = await config?.getConfig();
    final offset = DayBoundaryCalc.totalMinutesOf(
      settings?.dayStartOffsetHours ?? 0,
      settings?.dayStartOffsetMinutes ?? 0,
    );
    return (await intakes.getAllIntakesDBO()).any(
      (i) =>
          i.type.name == slot &&
          DayBoundaryCalc.isMomentInLogicalDayMinutes(
            DateTime.parse(date),
            i.dateTime,
            offset,
          ),
    );
  }

  Future<Json> swap(String date, String slot, String recipeId) async {
    final periods = (state['plans'] as List)
        .where(
          (p) =>
              date.compareTo(p['plan']['period_start']) >= 0 &&
              date.compareTo(nextDay(p['plan']['period_start'], 6)) <= 0,
        )
        .toList();
    final oldSlot = periods.isEmpty
        ? null
        : (periods.last['plan']['days'][0]['meals'] as List).firstWhere(
                (m) => m['simple'] == true,
              )['slot']
              as String;
    final rule = await rulesForDate(date, simpleSlot: oldSlot);
    if (await diarySlotRecorded(date, slot)) {
      throw const PlanRejected('饮食日记已有这餐的实际记录，请保留已吃餐次。');
    }
    return _lock.synchronized(() async {
      final s = state;
      if (date.compareTo(localDay(now())) < 0 ||
          (s['records']['$date/$slot']?['status'] ?? 'pending') != 'pending') {
        throw const PlanRejected(
          'Only today or future unrecorded meals can be swapped',
        );
      }
      final revisions = (s['plans'] as List)
          .where(
            (p) =>
                date.compareTo(p['plan']['period_start']) >= 0 &&
                date.compareTo(nextDay(p['plan']['period_start'], 6)) <= 0,
          )
          .toList();
      if (revisions.isEmpty) throw const PlanRejected('Plan missing');
      final updated = copyJson(Map<String, dynamic>.from(revisions.last));
      final day = (updated['plan']['days'] as List).firstWhere(
        (d) => d['date'] == date,
      );
      final meal = (day['meals'] as List).firstWhere((m) => m['slot'] == slot);
      meal['recipe_id'] = recipeId;
      rule.validate(
        updated['plan'],
        updated['plan']['period_start'],
        preservedMeals: preservedPlanMeals(
          Map<String, dynamic>.from(revisions.last['plan']),
          Map<String, dynamic>.from(s['records']),
          localDay(now()),
        ),
      );
      updated['id'] =
          "${updated['plan']['period_start']}-v${revisions.length + 1}";
      updated['version'] = revisions.length + 1;
      updated['source'] = 'manual';
      updated['notice'] = 'local recipe swap';
      updated['reason'] = 'user requested $date/$slot swap';
      updated['created_at'] = now().toIso8601String();
      s['plans'].add(updated);
      await _save(s);
      return Map<String, dynamic>.from(day);
    });
  }

  Future<void> _sync(String key, Json record) async {
    final id = 'mp:$key';
    final old = await intakes.getIntakeById(id);
    final shouldLog =
        record['status'] == 'completed' ||
        (record['status'] == 'replaced' && record['actual_portion'] != null);
    final settings = await config?.getConfig();
    final offset = DayBoundaryCalc.totalMinutesOf(
      settings?.dayStartOffsetHours ?? 0,
      settings?.dayStartOffsetMinutes ?? 0,
    );
    final date = DateTime.parse(key.substring(0, 10));
    final loggedAt = DateTime(
      date.year,
      date.month,
      date.day,
    ).add(Duration(minutes: offset + 720));
    if (old != null) await intakes.deleteIntake(old);
    if (shouldLog) {
      final meal = record['meal'];
      final portion = (record['actual_portion'] ?? meal['portion'] as num)
          .toDouble();
      if (!portion.isFinite || portion <= 0 || portion > 3) {
        throw const PlanRejected('Invalid actual portion');
      }
      final n = catalog.nutrition(meal['recipe_id'], portion);
      final recipe = catalog.recipes[meal['recipe_id']]!;
      final totalGrams = (recipe['ingredients'] as Map).values.fold<double>(
        0,
        (sum, g) => sum + (g as num) * portion,
      );
      double per100(String field) => (n[field] as double) * 100 / totalGrams;
      // Preserve the actual ingredient mass; nutrients remain per 100g in the diary.
      await intakes.addIntake(
        IntakeEntity(
          id: id,
          unit: 'g',
          amount: totalGrams,
          type: IntakeTypeEntity.values.byName(meal['slot']),
          dateTime: loggedAt,
          meal: MealEntity(
            code: id,
            name: catalog.recipes[meal['recipe_id']]!['name'],
            url: 'https://fdc.nal.usda.gov/',
            mealQuantity: '$totalGrams',
            mealUnit: 'g',
            servingQuantity: totalGrams,
            servingUnit: 'g',
            servingSize: '1 meal',
            source: MealSourceEntity.custom,
            nutriments: MealNutrimentsEntity(
              energyKcal100: per100('kcal'),
              carbohydrates100: per100('carbs'),
              fat100: per100('fat'),
              proteins100: per100('protein'),
              sodium100: per100('sodium'),
              fiber100: per100('fiber'),
              sugars100: null,
              saturatedFat100: null,
            ),
          ),
        ),
      );
    }
    final rows = (await intakes.getAllIntakesDBO())
        .where(
          (i) => DayBoundaryCalc.isMomentInLogicalDayMinutes(
            date,
            i.dateTime,
            offset,
          ),
        )
        .map(IntakeEntity.fromIntakeDBO)
        .toList();
    if (!await tracked.hasTrackedDay(date)) {
      final rule = await rulesForDate(localDay(date));
      await tracked.addNewTrackedDay(
        date,
        rule.targetKcal,
        rule.targetKcal * .5 / 4,
        rule.targetKcal * .3 / 9,
        rule.minimumProtein,
      );
    }
    double sum(double Function(IntakeEntity) get) =>
        rows.fold(0.0, (s, m) => s + get(m));
    await tracked.reconcileDayTracked(
      date,
      sum((m) => m.totalKcal),
      sum((m) => m.totalCarbsGram),
      sum((m) => m.totalFatsGram),
      sum((m) => m.totalProteinsGram),
    );
  }
}

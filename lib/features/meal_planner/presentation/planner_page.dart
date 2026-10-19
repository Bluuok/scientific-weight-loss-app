import 'dart:async';
import 'dart:convert';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_screen.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import '../data/planner_repository.dart';
import '../domain/planner.dart';
import '../domain/recipe_steps.dart';
import '../domain/weight_loss_eligibility.dart';
import 'planner_text.dart';
import 'grocery_budget_dialog.dart';
import 'medical_safety_page.dart';
import 'planner_visual.dart';

Widget plannerSurface(String id, Widget child) =>
    Semantics(identifier: 'planner-$id', child: child);

Widget plannerButton(
  String id,
  String label,
  VoidCallback? action, {
  bool primary = true,
}) => Semantics(
  identifier: 'planner-$id',
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: primary
        ? FilledButton(
            onPressed: action,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 56)),
            child: Text(label, textAlign: TextAlign.center),
          )
        : OutlinedButton(
            onPressed: action,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 56)),
            child: Text(label, textAlign: TextAlign.center),
          ),
  ),
);

Widget plannerSecondaryButton(String id, String label, VoidCallback? action) =>
    plannerButton(id, label, action, primary: false);

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  final repo = locator<PlannerRepository>();
  bool ready = false, busy = false;
  Future<UserEntity>? _userFuture;
  String? selected, error, _profileIssue;
  late final AppLifecycleListener _lifecycle;
  String t(String key) => plannerText(context, key);
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (mounted) setState(() {});
      },
    );
    _load();
  }

  Future<void> _load() async {
    try {
      await repo.initialize();
      final user = await repo.users.getUserData();
      _userFuture = Future.value(user);
      _profileIssue = weightLossIssue(user);
      if (mounted) setState(() => ready = true);
    } catch (_) {
      if (mounted) setState(() => error = t('storageError'));
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    repo.service.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(() => error = '${t('failed')}: ${plannerErrorText(e)}');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('agree')),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _openMedicalSafety() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicalSafetyPage(repo: repo),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _generate(String start, {Json? previous}) async {
    try {
      if (repo.enforceMedicalScreen && repo.medicalSafetyIssue != null) {
        await _openMedicalSafety();
        if (!mounted || repo.medicalSafetyIssue != null) return;
      }
      final rules = await repo.rules();
      if (repo.state['safety_ack_version'] != 'older-obesity-v3') {
        if (!await _confirm(t('safetyTitle'), t('safety'))) return;
        await repo.acknowledge();
      }
      if (!await _confirm(
        t('reference'),
        '${t('target')}: ${rules.targetKcal.round()} 千卡 / ${t('protein')}: ≥${rules.minimumProtein.round()} 克\n'
        '${t('limits')}\n${previous == null ? t('generateNote') : t('adjustNote')}',
      )) {
        return;
      }
      final settings = await repo.service.credentials.read();
      if ((settings['key'] as String).isNotEmpty &&
          settings['consented_url'] != settings['base_url']) {
        if (!await _confirm(
          t('privacyTitle'),
          '${t('privacy')}\n${settings['base_url']}',
        )) {
          return;
        }
        await repo.service.credentials.consent(settings['base_url']);
      }
      await _run(() async {
        final revision = await repo.generate(
          start,
          previous: previous,
          reason: previous == null
              ? 'user requested week'
              : 'user requested remaining meals',
        );
        selected = revision['id'];
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = '${t('failed')}: ${plannerErrorText(e)}');
      }
    }
  }

  Future<void> _openDay(Json day) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: NavigationOptions.plannerDayRoute),
        builder: (_) => PlannerDayPage(repo: repo, day: copyJson(day)),
      ),
    );
    final user = await repo.users.getUserData();
    if (mounted) {
      setState(() {
        _userFuture = Future.value(user);
        _profileIssue = weightLossIssue(user);
      });
    }
  }

  Future<void> _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('每天这样用'),
      content: const SingleChildScrollView(
        child: Text(
          '第一次：在“我的资料”填好使用者的身体资料，再在“饮食偏好”选好忌口。点击生成，AI会安排7天餐单。\n\n'
          '每天：打开“今天吃什么”，查看食材和做法；真正吃完后，点击“按这份吃完了”。\n\n'
          '吃得不一样：展开“换餐或其他记录”，填写实际份量、吃了别的或这餐没吃。点错可以撤销。\n\n'
          '下周：生成下一周；想调整还没吃的餐次，使用“调整剩余餐单”。\n\n'
          '“饮食记录”查看已经吃的内容；“我的资料”记录体重、添加或切换家人。每位家人的计划和记录分别保存。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return Scaffold(
        appBar: AppBar(title: Text(t('title'))),
        body: Center(
          child: error != null
              ? Text(error!)
              : const CircularProgressIndicator(),
        ),
      );
    }
    final state = repo.state;
    final revisions = List<Json>.from(state['plans']);
    final latest = <String, Json>{};
    for (final p in revisions) {
      latest[p['plan']['period_start']] = p;
    }
    final weeks = (_profileIssue == null ? latest.values.toList() : <Json>[])
      ..sort(
        (a, b) =>
            b['plan']['period_start'].compareTo(a['plan']['period_start']),
      );
    final today = localDay(repo.now());
    final current =
        weeks.where((p) => p['id'] == selected).firstOrNull ??
        weeks
            .where(
              (p) => (p['plan']['days'] as List).any((d) => d['date'] == today),
            )
            .firstOrNull ??
        weeks.firstOrNull;
    final todayPlan = weeks
        .where(
          (p) => (p['plan']['days'] as List).any((d) => d['date'] == today),
        )
        .firstOrNull;
    final todayMeal = todayPlan == null
        ? null
        : (todayPlan['plan']['days'] as List).firstWhere(
            (d) => d['date'] == today,
          );
    final records = state['records'] as Map;
    bool hasRecord(String date, String slot) =>
        (records['$date/$slot']?['status'] ?? 'pending') != 'pending';
    int mealRecordCount(String date) =>
        ['breakfast', 'lunch', 'dinner']
            .where((slot) => hasRecord(date, slot))
            .length;
    final days = current == null
        ? <dynamic>[]
        : current['plan']['days'] as List;
    final weekMealsRecorded = days.fold<int>(
      0, (total, day) => total + mealRecordCount(day['date'] as String),
    );
    final weekReviewsRecorded = days.where(
      (day) => hasRecord(day['date'] as String, 'review'),
    ).length;
    return Scaffold(
      backgroundColor: PlannerVisual.background,
      appBar: AppBar(
        title: Text(t('title')),
        actions: [
          Semantics(
            identifier: 'planner-help',
            child: TextButton(onPressed: _help, child: const Text('怎么用')),
          ),
          Semantics(
            identifier: 'planner-settings',
            child: plannerSurface(
              'control-5242',
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => PlannerSettings(repo: repo),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                child: Text(t('settings')),
              ),
            ),
          ),
        ],
      ),
      body: Semantics(
        identifier: 'planner-weeks',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '每天吃好三顿饭',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '先看今天的菜，吃过再记录。其他安排放在下面。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PlannerVisual.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (busy) ...[
              const LinearProgressIndicator(),
              const Text('AI 正在安排餐单，请稍候。完成后会显示在这里。'),
              plannerButton(
                'cancel',
                '取消生成',
                repo.service.cancel,
                primary: false,
              ),
            ],
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_profileIssue != null)
              Card(
                color: PlannerVisual.caution,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          color: PlannerVisual.cautionInk, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '先检查家人的身体资料\n$_profileIssue\n原有饮食记录不会丢失。',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: PlannerVisual.cautionInk),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_profileIssue != null)
              plannerButton(
                'family-profiles',
                '添加或切换家人资料',
                () => Navigator.pushNamed(
                  context,
                  NavigationOptions.manageProfilesRoute,
                ),
              ),
            if (_profileIssue == null &&
                repo.enforceMedicalScreen &&
                repo.medicalSafetyIssue != null)
              Card(
                color: PlannerVisual.caution,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.health_and_safety_outlined,
                              color: PlannerVisual.cautionInk, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('第1步：先确认身体情况',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: PlannerVisual.cautionInk)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(repo.medicalSafetyIssue!,
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: PlannerVisual.cautionInk)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: plannerButton(
                          'medical-risk-check', '开始健康核对',
                          busy ? null : _openMedicalSafety,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_profileIssue == null && todayMeal != null)
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.restaurant_menu_rounded,
                              color: PlannerVisual.infoInk, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('今天吃什么',
                                  style: Theme.of(context).textTheme.headlineSmall),
                                Text('$today · ${mealRecordCount(today)}/3餐有记录',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: PlannerVisual.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ...List<Json>.from(todayMeal['meals']).map(
                        (m) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: PlannerMealRow(
                            slot: m['slot'] as String,
                            title: t(m['slot']),
                            name: repo.catalog.recipes[m['recipe_id']]!['name'] as String,
                            status: (records['$today/${m['slot']}']?['status'] ?? 'pending') as String,
                            onTap: busy ? null : () => _openDay(copyJson(todayMeal)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      plannerButton(
                        'open-today',
                        mealRecordCount(today) == 3
                            ? '查看今天的记录和食谱'
                            : '查看食谱 · 吃完记一下',
                        busy ? null : () => _openDay(copyJson(todayMeal)),
                      ),
                      Text(
                        hasRecord(today, 'review') ? '今日回顾已经保存' : '吃完三餐后，可以写一句今天的感受',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: PlannerVisual.muted),
                      ),
                    ],
                  ),
                ),
              ),
            if (_profileIssue == null &&
                repo.enforceMedicalScreen &&
                repo.medicalSafetyIssue == null)
              Align(
                alignment: Alignment.centerLeft,
                child: plannerSecondaryButton(
                  'medical-risk-check',
                  '健康核对已完成 · 查看或更新',
                  busy ? null : _openMedicalSafety,
                ),
              ),
            if (_profileIssue == null && todayMeal == null)
              Card(
                color: PlannerVisual.info,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: PlannerVisual.infoInk, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '还没有今天的餐单。\n完成身体资料和健康核对后，生成一周菜单就能每天照着吃。',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: PlannerVisual.infoInk),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (current == null &&
                (_profileIssue != null ||
                 !repo.enforceMedicalScreen ||
                 repo.medicalSafetyIssue == null))
              SizedBox(
                width: double.infinity,
                child: plannerButton(
                  'generate',
                  '第2步：生成一周菜谱',
                  busy || _profileIssue != null
                      ? null
                      : () async {
                          var start = weeks.isEmpty
                              ? today
                              : nextDay(weeks.first['plan']['period_start'], 7);
                          if (start.compareTo(today) < 0) start = today;
                          await _generate(start);
                        },
                ),
              ),
            if (current != null) ...[
              const SizedBox(height: 14),
              Card(
                color: PlannerVisual.info,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.fact_check_outlined,
                          color: PlannerVisual.infoInk, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('本周记录情况',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: PlannerVisual.infoInk)),
                            Text('$weekMealsRecorded / 21 餐已记录 · '
                              '$weekReviewsRecorded / 7 天已回顾',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: PlannerVisual.infoInk)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text('包含主动标记“没吃”的记录，不代表饮食或减重达标。',
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              Card(
                color: Colors.white,
                child: plannerSurface(
                  'weekly-tools',
                  ExpansionTile(
                    leading: const Icon(Icons.calendar_month_outlined,
                        color: PlannerVisual.infoInk, size: 30),
                    title: const Text('查看一周安排'),
                    subtitle: const Text('其他日期、采购清单、下周菜单'),
                    childrenPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    children: [
                      Text('当前查看哪一周',
                          style: Theme.of(context).textTheme.titleMedium),
                      Semantics(
                        identifier: 'planner-week-select',
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: current['id'],
                          items: weeks.map(
                            (p) => DropdownMenuItem<String>(
                              value: p['id'],
                              child: Text(
                                "${p['plan']['period_start']} — ${nextDay(p['plan']['period_start'], 6)}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ).toList(),
                          onChanged: busy ? null : (value) =>
                              setState(() => selected = value),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final day in days)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: day['date'] == today
                                ? PlannerVisual.lunch
                                : PlannerVisual.background,
                            borderRadius: BorderRadius.circular(16),
                            child: plannerSurface(
                              'control-7691',
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                leading: Icon(
                                  day['date'] == today
                                    ? Icons.today_rounded
                                    : Icons.event_note_rounded,
                                  color: day['date'] == today
                                    ? PlannerVisual.lunchInk
                                    : PlannerVisual.infoInk,
                                ),
                                title: Text(
                                  "${day['date']}${day['date'] == today ? ' · 今天' : ''}",
                                ),
                                subtitle: Text(
                                  "${mealRecordCount(day['date'])}/3餐有记录 · "
                                  "${hasRecord(day['date'], 'review') ? '已回顾' : '未回顾'}",
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: busy ? null : () => _openDay(
                                    Map<String, dynamic>.from(day)),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      plannerSecondaryButton(
                        'grocery-list',
                        '查看7天买菜清单',
                        busy ? null : () => showDialog<void>(
                          context: context,
                          builder: (_) => GroceryBudgetDialog(
                              repo: repo, plan: current['plan']),
                        ),
                      ),
                      plannerSecondaryButton(
                        'generate',
                        '安排下一周菜谱',
                        busy ? null : () async {
                          var start = nextDay(
                              weeks.first['plan']['period_start'], 7);
                          if (start.compareTo(today) < 0) start = today;
                          await _generate(start);
                        },
                      ),
                      plannerSecondaryButton(
                        'adjust',
                        busy ? '正在调整菜单…' : '调整本周还没吃的菜',
                        busy ? null : () => _generate(
                          current['plan']['period_start'],
                          previous: current,
                        ),
                      ),
                      Text(
                        '菜谱来源：${current['notice'] == 'local recipe swap' ? '手动换菜' : t(current['source'])} · '
                        '第${current['version']}版',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (current['notice'] != '')
                        Text(
                          current['notice'] == 'local recipe swap'
                            ? '已按选择换菜并重新核算营养。'
                            : current['source'] == 'ai'
                              ? plannerErrorText(current['notice'])
                              : t('fallbackNotice'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (current != null)
              plannerSurface(
                'cycle-progress',
                ExpansionTile(
                  title: const Text('本月四阶段执行复盘'),
                  subtitle: const Text('只统计主动记录；未记录不等于没吃'),
                  children: [
                    Builder(
                      builder: (context) {
                        final review = repo.cycleReview(today);
                        if (review['status'] == 'no_plan') {
                          return const Text('暂无可复盘的餐单。');
                        }
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${review['cycle_start']} — ${review['cycle_end']}",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                "截至${review['as_of']}：按计划记录 ${review['recorded_as_planned']} 餐、"
                                "替换记录 ${review['recorded_replaced']} 餐、"
                                "明确没吃 ${review['explicitly_skipped']} 餐、"
                                "未记录 ${review['unknown_meals']} 餐。",
                              ),
                              for (final phase in (review['phases'] as List))
                                Text(
                                  "第${phase['phase']}阶段："
                                  "有记录 ${phase['recorded_as_planned'] + phase['recorded_replaced'] + phase['explicitly_skipped']}/"
                                  "${phase['planned_meals_due']} 餐；"
                                  "未记录 ${phase['unknown_meals']} 餐",
                                ),
                              const Text(
                                '这些数字只是记录覆盖情况，无法证明血压改善、保留肌肉或实际减脂效果。',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            if (current != null && current['monthly_direction'] != null)
              plannerSurface(
                'month-details',
                ExpansionTile(
                  title: const Text('查看月度方向与目标'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('monthlyTitle'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${current['monthly_direction']['start_date']} — ${current['monthly_direction']['first_month_end']}',
                          ),
                          Text(
                            '${t('monthlyPhase')} ${current['monthly_direction']['phase']}/4 · ${current['monthly_direction']['focus']}',
                          ),
                          Text(t('monthlyNoPromise')),
                          if (current['monthly_direction']['long_term_goal_kg'] !=
                              null)
                            Text(
                              "长期目标：${current['monthly_direction']['long_term_goal_kg']} 千克；约5%仅为首阶段参考",
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            FutureBuilder(
              future: _userFuture,
              builder: (context, snapshot) =>
                  snapshot.hasData && _profileIssue == null
                  ? Text(
                      '${t('stage')}: ${((state['initial_weight_kg'] ?? snapshot.data!.weightKG) * .95).toStringAsFixed(1)} 千克 · ${t('weight')}: ${snapshot.data!.weightKG} 千克',
                    )
                  : const SizedBox(),
            ),
            if (revisions.length > weeks.length)
              plannerSurface(
                'control-10280',
                ExpansionTile(
                  title: Text(t('versions')),
                  children: revisions
                      .map(
                        (p) => plannerSurface(
                          'control-10430',
                          ListTile(
                            title: Text(
                              "${p['plan']['period_start']} · 第${p['version']}版",
                            ),
                            subtitle: const Text('历史计划，仅供查看'),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: Text(t('versions'))),
                                  body: ListView(
                                    children: (p['plan']['days'] as List)
                                        .map(
                                          (d) => plannerSurface(
                                            'control-11035',
                                            ListTile(
                                              title: Text(d['date']),
                                              subtitle: Text(
                                                (d['meals'] as List)
                                                    .map(
                                                      (m) => repo
                                                          .catalog
                                                          .recipes[m['recipe_id']]!['name'],
                                                    )
                                                    .join(' / '),
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            Text(t('disclaimer')),
          ],
        ),
      ),
    );
  }
}

class PlannerDayPage extends StatefulWidget {
  final PlannerRepository repo;
  final Json day;
  const PlannerDayPage({super.key, required this.repo, required this.day});
  @override
  State<PlannerDayPage> createState() => _PlannerDayPageState();
}

class _PlannerDayPageState extends State<PlannerDayPage> {
  bool busy = false;
  String? error, savingSlot;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  String t(String k) => plannerText(context, k);
  void _showFeedback(String message, {bool failed = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: failed ? 8 : 4),
        ),
      );
  }

  void _showFailure(Object cause) {
    if (!mounted) return;
    setState(() => error = '${t('failed')}: ${plannerErrorText(cause)}');
    _showFeedback(error!, failed: true);
  }

  Future<void> record(
    Json? meal,
    String status, {
    String notes = '',
    double? portion,
    List<String>? externalIds,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      savingSlot = meal?['slot'] ?? 'review';
      error = null;
    });
    try {
      await widget.repo.record(
        widget.day['date'],
        meal,
        status,
        notes: notes,
        actualPortion: portion,
        externalIds: externalIds,
      );
      if (mounted) {
        final label = meal == null ? '今日回顾' : t(meal['slot']);
        final message = status == 'pending'
            ? '$label已撤销'
            : meal == null
            ? '今日回顾已保存'
            : status == 'skipped'
            ? '$label已标记为没吃'
            : '$label已记录，可在“饮食记录”查看';
        _showFeedback(message);
      }
    } catch (e) {
      _showFailure(e);
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          savingSlot = null;
        });
      }
    }
  }

  Future<String?> input(
    String title, {
    String initial = '',
    bool numeric = false,
  }) async {
    final controller = TextEditingController(text: initial);
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Semantics(
          identifier: 'planner-edit-input',
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.multiline,
            maxLength: numeric ? 6 : 300,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(t('save')),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push(route);
    unawaited(route.completed.then((_) => controller.dispose()));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    final date = widget.day['date'] as String;
    final n = repo.catalog.dayNutrition(widget.day);
    final records = repo.state['records'];
    final futureDay = date.compareTo(localDay(repo.now())) > 0;
    final medicalBlocked = repo.enforceMedicalScreen &&
        repo.medicalSafetyIssue != null;
    final editable = !futureDay && !busy && !medicalBlocked;
    final recordedMeals = ['breakfast', 'lunch', 'dinner'].where(
      (slot) => (records['$date/$slot']?['status'] ?? 'pending') != 'pending',
    ).length;
    return Scaffold(
      backgroundColor: PlannerVisual.background,
      appBar: AppBar(title: Text('$date · 三餐食谱')),
      body: Semantics(
        identifier: 'planner-day-list',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: PlannerVisual.info,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.checklist_rounded,
                        size: 32, color: PlannerVisual.infoInk),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('今天的三餐',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: PlannerVisual.infoInk)),
                          Text('$recordedMeals/3餐有记录 · 先看做法，吃过再打卡',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: PlannerVisual.infoInk)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (futureDay)
              const Text('这是未来的餐单；可以先看菜谱，到当天再记录。'),
            if (recordedMeals == 3 &&
                !futureDay && !medicalBlocked &&
                records['$date/review']?['status'] != 'completed')
              Card(
                color: PlannerVisual.lunch,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('今天三餐都有记录了',
                        style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: PlannerVisual.lunchInk)),
                      const Text('可以写一句今天吃得怎么样，也可以稍后再写。'),
                      plannerButton(
                        'quick-review',
                        '写一句今天的感受',
                        busy ? null : () async {
                          final note = await input(t('reviewHint'));
                          if (note != null) {
                            await record(null, 'completed', notes: note);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (medicalBlocked)
              Card(
                color: PlannerVisual.caution,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repo.medicalSafetyIssue!,
                        style: const TextStyle(
                          color: PlannerVisual.cautionInk, fontSize: 18),
                      ),
                      plannerSecondaryButton(
                        'day-medical-risk-check',
                        '重新核对健康风险',
                        busy ? null : () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MedicalSafetyPage(repo: repo),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ...List<Json>.from(widget.day['meals']).map((meal) {
              final recipe = repo.catalog.recipes[meal['recipe_id']]!;
              final status =
                  records['$date/${meal['slot']}']?['status'] ?? 'pending';
              final note = records['$date/${meal['slot']}']?['notes'] ?? '';
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Card(
                  color: PlannerVisual.mealColor(meal['slot'] as String),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              PlannerVisual.mealIcon(meal['slot'] as String),
                              size: 30,
                              color: PlannerVisual.mealInk(meal['slot'] as String),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t(meal['slot']),
                                    style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(color: PlannerVisual.mealInk(
                                          meal['slot'] as String))),
                                  Text(
                                    PlannerVisual.statusText(status as String),
                                    style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: PlannerVisual.mealInk(
                                          meal['slot'] as String))),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(recipe['name'],
                          style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(color: PlannerVisual.ink)),
                        if (meal['simple'])
                          const Text('这是一顿简洁餐，照着做就行。'),
                      Text(
                        '本餐用油 ${RecipeSteps.grams('oil', ((recipe['ingredients']['oil'] ?? 0) as num) * meal['portion'])}克 · 食盐 ${RecipeSteps.grams('salt', ((recipe['ingredients']['salt'] ?? 0) as num) * meal['portion'])}克',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      plannerSurface(
                        'control-16208',
                        ExpansionTile(
                          leading: const Icon(Icons.menu_book_outlined),
                          title: const Text('看做法和每样食材的重量'),
                          children: [
                            ...((recipe['ingredients'] as Map).entries.map((e) {
                              final food = repo.catalog.foods[e.key]!;
                              return plannerSurface(
                                'control-16497',
                                ListTile(
                                  title: Text(
                                    '${food['name']} ${RecipeSteps.grams(e.key as String, e.value * meal['portion'])} 克（${food['state']}）',
                                  ),
                                ),
                              );
                            })),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                RecipeSteps.instructions(
                                  repo.catalog,
                                  meal['recipe_id'],
                                  (meal['portion'] as num).toDouble(),
                                ),
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (note != '') Text(note),
                      SizedBox(
                        width: double.infinity,
                        child: plannerButton(
                          'complete-${meal['slot']}',
                          busy && savingSlot == meal['slot']
                              ? '正在保存…'
                              : futureDay
                              ? '到这一天再记录'
                              : status != 'pending'
                              ? t('undo')
                              : t('complete'),
                          editable
                              ? () => record(
                                  meal,
                                  status != 'pending' ? 'pending' : 'completed',
                                )
                              : null,
                          primary: status == 'pending',
                        ),
                      ),
                      plannerSurface(
                        'more-${meal['slot']}',
                        ExpansionTile(
                          title: const Text('吃的不一样？换菜或修改记录'),
                          children: [
                            Wrap(
                              spacing: 8,
                              children: [
                                plannerSecondaryButton(
                                  'swap-${meal['slot']}',
                                  t('swap'),
                                  !busy &&
                                          status == 'pending' &&
                                          date.compareTo(
                                                localDay(repo.now()),
                                              ) >=
                                              0
                                      ? () async {
                                          final id = await showDialog<String>(
                                            context: context,
                                            builder: (context) => SimpleDialog(
                                              title: Text(t('swap')),
                                              children: repo
                                                  .catalog
                                                  .recipes
                                                  .values
                                                  .where(
                                                    (r) =>
                                                        (r['slots'] as List)
                                                            .contains(
                                                              meal['slot'],
                                                            ) &&
                                                        r['simple'] ==
                                                            meal['simple'],
                                                  )
                                                  .map(
                                                    (r) => plannerSurface(
                                                      'control-18626',
                                                      SimpleDialogOption(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              context,
                                                              r['id'],
                                                            ),
                                                        child: Text(r['name']),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          );
                                          if (id == null) return;
                                          setState(() => busy = true);
                                          try {
                                            final updated = await repo.swap(
                                              date,
                                              meal['slot'],
                                              id,
                                            );
                                            widget.day
                                              ..clear()
                                              ..addAll(updated);
                                          } catch (e) {
                                            _showFailure(e);
                                          }
                                          if (mounted) {
                                            setState(() => busy = false);
                                          }
                                        }
                                      : null,
                                ),
                                plannerSecondaryButton(
                                  'portion-${meal['slot']}',
                                  t('actualPortion'),
                                  editable
                                      ? () async {
                                          final value = await input(
                                            '吃了这份的百分之多少？\n例如：100为一整份，50为半份，150为一份半。',
                                            initial: '100',
                                            numeric: true,
                                          );
                                          if (value == null) return;
                                          final percent = double.tryParse(
                                            value,
                                          );
                                          final portion = percent == null
                                              ? null
                                              : percent /
                                                    100 *
                                                    (meal['portion'] as num);
                                          if (portion == null ||
                                              !portion.isFinite ||
                                              portion <= 0 ||
                                              portion > 3) {
                                            _showFailure(
                                              PlanRejected(t('invalidPortion')),
                                            );
                                            return;
                                          }
                                          await record(
                                            meal,
                                            'replaced',
                                            notes: '实际吃了这份的 $percent%',
                                            portion: portion,
                                          );
                                        }
                                      : null,
                                ),
                                plannerSecondaryButton(
                                  'replace-${meal['slot']}',
                                  t('ateOther'),
                                  editable
                                      ? () async {
                                          if (!context.mounted) return;
                                          final before =
                                              (await repo.intakes
                                                      .getAllIntakesDBO())
                                                  .map((m) => m.id)
                                                  .toSet();
                                          if (!context.mounted) return;
                                          await Navigator.pushNamed(
                                            context,
                                            NavigationOptions.addMealRoute,
                                            arguments: AddMealScreenArguments(
                                              AddMealType.values.byName(
                                                '${meal['slot']}Type',
                                              ),
                                              DateTime.parse(date),
                                            ),
                                          );
                                          if (!context.mounted) return;
                                          final added =
                                              (await repo.intakes
                                                      .getAllIntakesDBO())
                                                  .where(
                                                    (m) =>
                                                        !before.contains(
                                                          m.id,
                                                        ) &&
                                                        !m.id.startsWith('mp:'),
                                                  )
                                                  .toList();
                                          if (added.isNotEmpty) {
                                            await record(
                                              meal,
                                              'replaced',
                                              notes: added
                                                  .map((m) => m.meal.name ?? '')
                                                  .join(' / '),
                                              externalIds: added
                                                  .map((m) => m.id)
                                                  .toList(),
                                            );
                                          } else {
                                            final note = await input(
                                              t('confirmOther'),
                                            );
                                            if (note != null &&
                                                note.trim().isNotEmpty) {
                                              await record(
                                                meal,
                                                'replaced',
                                                notes: note.trim(),
                                              );
                                            }
                                          }
                                        }
                                      : null,
                                ),
                                plannerSecondaryButton(
                                  'skip-${meal['slot']}',
                                  t('skip'),
                                  editable
                                      ? () => record(meal, 'skipped')
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            }),
            const SizedBox(height: 14),
            Card(
              color: Colors.white,
              child: plannerSurface(
                'nutrition-details',
              ExpansionTile(
                title: const Text('查看全天营养估算'),
                children: [
                  Text(
                    '${t('planned')}: ${n['kcal'].round()} 千卡 · ${t('protein')} ${n['protein'].toStringAsFixed(1)} 克\n'
                    '${t('sodium')} ${n['sodium'].round()} 毫克 · ${t('saltEquivalent')} ${(n['sodium'] * .0025).toStringAsFixed(1)} 克 · ${t('oil')} ${n['oil'].toStringAsFixed(1)} 克',
                    style: const TextStyle(fontSize: 18),
                  ),
                  Text(t('unknownNote')),
                ],
              ),
            ),
            ),
            Card(
              color: PlannerVisual.info,
              child: plannerSurface(
                'control-24402',
                ListTile(
                  title: Text(
                    t('review'),
                    style: const TextStyle(fontSize: 20),
                  ),
                  subtitle: Text(
                    '${t(records['$date/review']?['status'] ?? 'pending')} · ${records['$date/review']?['notes'] ?? ''}',
                  ),
                  onTap: editable
                      ? () async {
                          final note = await input(t('reviewHint'));
                          if (note != null) {
                            await record(null, 'completed', notes: note);
                          }
                        }
                      : null,
                  trailing: plannerSurface(
                    'control-25015',
                    IconButton(
                      tooltip: '撤销今日回顾',
                      icon: const Icon(Icons.undo),
                      onPressed: editable
                          ? () => record(null, 'pending')
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            plannerButton(
              'weight',
              '查看体重记录',
              () => Navigator.pushNamed(
                context,
                NavigationOptions.weightHistoryRoute,
              ),
              primary: false,
            ),
          ],
        ),
      ),
    );
  }
}

class PlannerSettings extends StatefulWidget {
  final PlannerRepository repo;
  const PlannerSettings({super.key, required this.repo});
  @override
  State<PlannerSettings> createState() => _PlannerSettingsState();
}

class _PlannerSettingsState extends State<PlannerSettings> {
  final url = TextEditingController(),
      model = TextEditingController(),
      key = TextEditingController();
  bool configured = false, busy = false, loaded = false;
  String? message;
  late Json prefs;
  late String savedPreferences;
  bool allowLeave = false;
  String t(String k) => plannerText(context, k);
  @override
  void initState() {
    super.initState();
    prefs = copyJson(widget.repo.state['preferences']);
    savedPreferences = jsonEncode(prefs);
    load();
  }

  Future<void> load() async {
    final c = await widget.repo.service.credentials.read();
    if (!mounted) return;
    setState(() {
      url.text = c['base_url'];
      model.text = c['model'];
      configured = (c['key'] as String).isNotEmpty;
      loaded = true;
    });
  }

  @override
  void dispose() {
    url.dispose();
    model.dispose();
    key.dispose();
    super.dispose();
  }

  void _showSaveFeedback(String value, {bool failed = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(value),
        duration: Duration(seconds: failed ? 8 : 4),
      ),
    );
  }

  Future<void> save({bool probe = false, bool connection = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (connection || probe) {
        await widget.repo.service.credentials.save(
          url.text,
          model.text,
          key.text.isEmpty ? null : key.text,
        );
      } else {
        await widget.repo.preferences(prefs);
        savedPreferences = jsonEncode(prefs);
      }
      if (probe) await widget.repo.service.probe();
      if (mounted) {
        setState(() {
          message = t(probe ? 'probeOk' : 'saved');
          configured = configured || key.text.isNotEmpty;
          key.clear();
        });
        _showSaveFeedback(message!);
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = '${t('failed')}: ${plannerErrorText(e)}');
        _showSaveFeedback(message!, failed: true);
      }
    }
    if (mounted) setState(() => busy = false);
  }

  Widget field(
    String id,
    String label,
    TextEditingController controller, {
    bool obscure = false,
  }) => Semantics(
    identifier: 'planner-$id',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowLeave || (!busy && jsonEncode(prefs) == savedPreferences),
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || busy) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('饮食偏好还没保存'),
          content: const Text('返回后这次修改不会保留。可以留下，点击底部保存。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续修改'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('不保存，返回'),
            ),
          ],
        ),
      );
      if (discard == true && mounted) {
        setState(() => allowLeave = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.maybePop(context)),
        title: const Text('饮食偏好'),
      ),
      bottomNavigationBar: !loaded
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: plannerButton(
                  'save-settings',
                  '保存饮食偏好',
                  busy ? null : () => save(),
                ),
              ),
            ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : Semantics(
              identifier: 'planner-settings-list',
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: PlannerVisual.info,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        '只需选平时的吃饭习惯，其他保持默认就行。'
                        '改完后点击下面的“保存饮食偏好”。',
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: PlannerVisual.infoInk),
                      ),
                    ),
                  ),
                  if (message != null)
                    Semantics(liveRegion: true, child: Text(message!)),
                  const SizedBox(height: 10),
                  Card(
                    color: PlannerVisual.caution,
                    child: ExpansionTile(
                      leading: const Icon(Icons.no_food_outlined,
                        color: PlannerVisual.cautionInk),
                      title: const Text('哪些食物不能吃？'),
                      subtitle: Text(
                        (prefs['avoid'] as List).isEmpty
                          ? '如有过敏或忌口，点这里选择'
                          : '已排除 ${(prefs['avoid'] as List).length} 种食材 · 点开检查',
                      ),
                      initiallyExpanded: (prefs['avoid'] as List).isNotEmpty,
                      childrenPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                      children: [
                        const Text('勾选后，系统不会把这些食材加入新餐单。'),
                      Wrap(
                        spacing: 6,
                        children: widget.repo.catalog.foods.values
                            .where((f) => !['salt', 'oil'].contains(f['group']))
                            .map(
                              (f) => plannerSurface(
                                'control-29339',
                                FilterChip(
                                  label: Text(f['name']),
                                  selected: (prefs['avoid'] as List).contains(
                                    f['id'],
                                  ),
                                  onSelected: (v) => setState(() {
                                    if (v) {
                                      prefs['avoid'].add(f['id']);
                                    } else {
                                      prefs['avoid'].remove(f['id']);
                                    }
                                  }),
                                ),
                              ),
                            )
                            .toList(),
                      ),
    
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('哪一餐想做得更简单？',
                    style: Theme.of(context).textTheme.titleLarge),
                  plannerSurface(
                    'control-29953',
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'lunch', label: Text(t('lunch'))),
                        ButtonSegment(
                          value: 'dinner',
                          label: Text(t('dinner')),
                        ),
                      ],
                      selected: {prefs['simple_slot']},
                      onSelectionChanged: (v) =>
                          setState(() => prefs['simple_slot'] = v.first),
                    ),
                  ),
                  Card(
                    color: PlannerVisual.info,
                    child: plannerSurface(
                    'control-30385',
                    SwitchListTile(
                      title: Text(t('quick')),
                      value: prefs['quick'],
                      onChanged: (v) => setState(() => prefs['quick'] = v),
                    ),
                  ),
                  ),
                  Card(
                    color: PlannerVisual.lunch,
                    child: plannerSurface(
                    'control-30592',
                    SwitchListTile(
                      title: Text(t('budget')),
                      value: prefs['budget'] == 'economy',
                      onChanged: (v) => setState(
                        () => prefs['budget'] = v ? 'economy' : 'normal',
                      ),
                    ),
                  ),
                  ),
                  Card(
                    color: PlannerVisual.breakfast,
                    child: plannerSurface(
                    'control-30879',
                    SwitchListTile(
                      title: Text(t('spicy')),
                      value: prefs['taste'] == 'spicy',
                      onChanged: (v) => setState(
                        () => prefs['taste'] = v ? 'spicy' : 'light',
                      ),
                    ),
                  ),
                  ),
                  plannerSurface(
                    'advanced-settings',
                    ExpansionTile(
                      title: const Text('高级设置（家人协助）'),
                      subtitle: Text(
                        configured ? 'AI 已配置，平时不用修改' : 'AI 尚未配置，暂用备用餐单',
                      ),
                      children: [
                        field('base-url', '服务地址', url),
                        field('model', '模型标识', model),
                        field(
                          'api-key',
                          configured ? t('keyConfigured') : '访问密钥',
                          key,
                          obscure: true,
                        ),
                        Text(t('keyHint')),
                        plannerButton(
                          'save-connection',
                          '保存服务配置',
                          busy ? null : () => save(connection: true),
                        ),
                        plannerButton(
                          'probe',
                          t('probe'),
                          busy ? null : () => save(probe: true),
                        ),
                        if (message != null) Text(message!),
                        if (busy) const LinearProgressIndicator(),
                        plannerButton(
                          'clear-key',
                          t('clearKey'),
                          busy
                              ? null
                              : () async {
                                  await widget.repo.service.credentials.save(
                                    url.text,
                                    model.text,
                                    '',
                                  );
                                  if (mounted) {
                                    setState(() => configured = false);
                                  }
                                },
                        ),
                        plannerButton(
                          'query-sources',
                          t('querySources'),
                          busy
                              ? null
                              : () async {
                                  setState(() => busy = true);
                                  try {
                                    final results = await widget.repo
                                        .querySources();
                                    if (mounted) {
                                      setState(
                                        () => message =
                                            '${t('sourcesChecked')}: ${results.where((r) => r['status'] == 'verified').length}/${results.length}',
                                      );
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      setState(
                                        () => message = t('sourcesFailed'),
                                      );
                                    }
                                  }
                                  if (mounted) setState(() => busy = false);
                                },
                        ),
                        ...widget.repo.sourceLookups.map(
                          (r) => Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (r['url'] as String).contains(
                                          'nhlbi.nih.gov',
                                        )
                                        ? '美国国立卫生研究院 · 得舒饮食'
                                        : '中国居民膳食指南',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${r['status'] == 'verified' ? t('sourcesVerified') : t('sourcesFailed')} · ${r['retrieved_at']}',
                                  ),
                                  const Text('已保留原文供智能计划参考，界面不展开外文原文。'),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Text(t('searchUnavailable')),
                        Text(t('sources')),
                      ],
                    ),
                  ),
                  Text(t('disclaimer')),
                ],
              ),
            ),
    ),
  );
}

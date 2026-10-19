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
  Future<void> _generate(String start, {Json? previous}) async {
    try {
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
    int count(String date) => ['breakfast', 'lunch', 'dinner', 'review']
        .where(
          (slot) =>
              (records['$date/$slot']?['status'] ?? 'pending') != 'pending',
        )
        .length;
    final days = current == null
        ? <dynamic>[]
        : current['plan']['days'] as List;
    return Scaffold(
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
            const Text(
              'AI 科学饮食计划',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const Text('每天看餐单，吃完记一下。'),
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '$_profileIssue\n如果给家人使用，请先添加或切换家人资料。你的饮食记录仍可使用。',
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
            if (_profileIssue == null && todayMeal != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '今天吃什么',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text('$today · 已记录 ${count(today)}/4 项'),
                      ...List<Json>.from(todayMeal['meals']).map(
                        (m) => Text(
                          "${t(m['slot'])}：${repo.catalog.recipes[m['recipe_id']]!['name']}",
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: plannerButton(
                          'open-today',
                          '查看今天餐单并记录',
                          busy ? null : () => _openDay(copyJson(todayMeal)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_profileIssue == null && todayMeal == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('先在“我的资料”确认身体资料，再选好饮食偏好，最后生成餐单。生成后每天在这里查看。'),
              ),
            plannerButton(
              'generate',
              current == null ? 'AI 生成7天餐单（从今天起）' : t('nextWeek'),
              busy || _profileIssue != null
                  ? null
                  : () async {
                      String start;
                      start = weeks.isEmpty
                          ? today
                          : nextDay(weeks.first['plan']['period_start'], 7);
                      if (start.compareTo(today) < 0) start = today;
                      await _generate(start);
                    },
              primary: current == null,
            ),
            if (weeks.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('本周与其他日期'),
              ),
            if (weeks.isNotEmpty)
              Semantics(
                identifier: 'planner-week-select',
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: current!['id'],
                  items: weeks
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p['id'],
                          child: Text(
                            '${p['plan']['period_start']} — ${nextDay(p['plan']['period_start'], 6)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => selected = v),
                ),
              ),
            if (current != null) ...[
              Text(
                '${t('source')}: ${current['notice'] == 'local recipe swap' ? t('manual') : t(current['source'])} · 第${current['version']}版',
              ),
              if (current['notice'] != '')
                Text(
                  current['notice'] == 'local recipe swap'
                      ? '已按你的选择换菜，并重新核验营养。'
                      : current['source'] == 'ai'
                      ? plannerErrorText(current['notice'])
                      : t('fallbackNotice'),
                ),
              Text(
                '${t('progress')}: ${days.fold<int>(0, (n, d) => n + count(d['date']))}/28',
              ),
              plannerSecondaryButton(
                'grocery-list',
                '本周采购清单与当地菜价',
                busy ? null : () => showDialog<void>(
                  context: context,
                  builder: (_) => GroceryBudgetDialog(
                    repo: repo,
                    plan: current['plan'],
                  ),
                ),
              ),
              ...days.map(
                (day) => Card(
                  child: plannerSurface(
                    'control-7691',
                    ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Icon(
                        day['date'] == today
                            ? Icons.today
                            : Icons.calendar_today,
                      ),
                      title: Text(
                        '${day['date']}${day['date'] == today ? ' · ${t('today')}' : ''}',
                        style: const TextStyle(fontSize: 20),
                      ),
                      subtitle: Text(
                        '${count(day['date'])}/4 ${t('recorded')}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy
                          ? null
                          : () async {
                              await _openDay(Map<String, dynamic>.from(day));
                            },
                    ),
                  ),
                ),
              ),
              plannerButton(
                'adjust',
                busy ? 'AI 正在调整，请稍候…' : '调整剩余餐单',
                busy
                    ? null
                    : () => _generate(
                        current['plan']['period_start'],
                        previous: current,
                      ),
                primary: false,
              ),
            ],
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
    final editable = !futureDay && !busy;
    return Scaffold(
      appBar: AppBar(title: Text(date)),
      body: Semantics(
        identifier: 'planner-day-list',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('先看食材和做法，真正吃完后再记录。点错可以撤销。'),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (date.compareTo(localDay(repo.now())) > 0)
              const Text('这是未来的餐单，可以先查看或换餐，到当天再记录吃了什么。'),
            plannerSurface(
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
            ...List<Json>.from(widget.day['meals']).map((meal) {
              final recipe = repo.catalog.recipes[meal['recipe_id']]!;
              final status =
                  records['$date/${meal['slot']}']?['status'] ?? 'pending';
              final note = records['$date/${meal['slot']}']?['notes'] ?? '';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t(meal['slot'])} · ${t(status)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        recipe['name'],
                        style: const TextStyle(fontSize: 19),
                      ),
                      if (meal['simple']) Text(t('simpleMeal')),
                      Text(
                        (recipe['ingredients'] as Map).entries
                            .map(
                              (e) =>
                                  "${repo.catalog.foods[e.key]!['name']} ${RecipeSteps.grams(e.key as String, e.value * meal['portion'])}克",
                            )
                            .join('、'),
                      ),
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
                          title: const Text('食材称量与详细做法'),
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
                        ),
                      ),
                      plannerSurface(
                        'more-${meal['slot']}',
                        ExpansionTile(
                          title: const Text('换餐或其他记录'),
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
              );
            }),
            Card(
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
              t('weightHistory'),
              () => Navigator.pushNamed(
                context,
                NavigationOptions.weightHistoryRoute,
              ),
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
                  Text(t('reuseProfile')),
                  const Text('选中不能吃的食材，其他选项可以保持默认。修改后点击底部保存。'),
                  if (message != null)
                    Semantics(liveRegion: true, child: Text(message!)),
                  Text(t('avoid'), style: const TextStyle(fontSize: 20)),
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
                  Text(t('simpleSlot')),
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
                  plannerSurface(
                    'control-30385',
                    SwitchListTile(
                      title: Text(t('quick')),
                      value: prefs['quick'],
                      onChanged: (v) => setState(() => prefs['quick'] = v),
                    ),
                  ),
                  plannerSurface(
                    'control-30592',
                    SwitchListTile(
                      title: Text(t('budget')),
                      value: prefs['budget'] == 'economy',
                      onChanged: (v) => setState(
                        () => prefs['budget'] = v ? 'economy' : 'normal',
                      ),
                    ),
                  ),
                  plannerSurface(
                    'control-30879',
                    SwitchListTile(
                      title: Text(t('spicy')),
                      value: prefs['taste'] == 'spicy',
                      onChanged: (v) => setState(
                        () => prefs['taste'] = v ? 'spicy' : 'light',
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

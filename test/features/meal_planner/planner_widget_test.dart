import 'dart:io';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/hive_registrar.g.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/data/planner_repository.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'package:opennutritracker/features/meal_planner/presentation/planner_page.dart';
import 'planner_persistence_test.dart'
    show TestDB, TestUser, TestWeights, TestTracked, OfflineCredentials;

class CountingUser extends TestUser {
  int reads = 0;
  @override
  Future<UserEntity> getUserData() {
    reads++;
    return super.getUserData();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    Hive.registerAdapters();
    final font = File(r'C:\Windows\Fonts\msyh.ttc');
    if (font.existsSync()) {
      final loader = FontLoader('PlannerTestFont')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
      final buttonFont = FontLoader('Nunito')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await buttonFont.load();
      final icons = File(
        '.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        final iconLoader = FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
        await iconLoader.load();
      }
    }
  });
  late Directory dir;
  late PlannerRepository repo;
  late CountingUser user;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ont-planner-widget-');
    Hive.init(dir.path);
    final db = TestDB();
    db.plans = await Hive.openBox<String>('plans');
    db.intakes = await Hive.openBox<IntakeDBO>('intakes');
    user = CountingUser();
    repo = PlannerRepository(
      db,
      IntakeRepository(IntakeDataSource(db)),
      user,
      TestWeights(),
      TestTracked(),
      MealPlanningService(OfflineCredentials()),
    );
    await repo.initialize();
    await repo.generate(localDay(DateTime.now()));
    locator.registerSingleton<PlannerRepository>(repo);
  });
  tearDown(() async {
    await locator.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });
  Widget app(Widget child, {double scale = 1}) => MaterialApp(
    locale: const Locale('zh'),
    theme: buildAppTheme(AppPalette.light).copyWith(
      textTheme: buildAppTheme(
        AppPalette.light,
      ).textTheme.apply(fontFamily: 'PlannerTestFont'),
    ),
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: child,
  );

  testWidgets(
    'underweight profile hides previous loss target and disables generation',
    (tester) async {
      user.weight = 55;
      await tester.runAsync(() async {
        await tester.pumpWidget(app(const PlannerPage()));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('当前资料显示体重偏低'), findsOneWidget);
      expect(find.text('30天饮食方向'), findsNothing);
      final generate = find.bySemanticsIdentifier('planner-generate');
      expect(generate, findsOneWidget);
      final button = tester.widget<FilledButton>(
        find
            .descendant(of: generate, matching: find.byType(FilledButton))
            .first,
      );
      expect(button.onPressed, isNull);
    },
  );
  testWidgets(
    'Chinese week overview opens day, completes and undoes one meal without duplicate diary',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final overviewBoundary = GlobalKey();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          app(
            RepaintBoundary(key: overviewBoundary, child: const PlannerPage()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('我的计划'), findsOneWidget);
      expect(find.text('今天吃什么'), findsOneWidget);
      expect(find.textContaining('0/3餐有记录'), findsWidgets);
      expect(find.bySemanticsIdentifier('planner-today-meal-breakfast'), findsOneWidget);
      expect(find.bySemanticsIdentifier('planner-today-meal-lunch'), findsOneWidget);
      expect(find.bySemanticsIdentifier('planner-today-meal-dinner'), findsOneWidget);
      expect(
        tester.getRect(find.bySemanticsIdentifier('planner-open-today')).bottom,
        lessThan(780),
      );
      final readsAfterLoad = user.reads;
      // Rebuild the same overview state; it must reuse the profile future.
      await tester.pumpWidget(
        app(RepaintBoundary(key: overviewBoundary, child: const PlannerPage())),
      );
      await tester.pumpAndSettle();
      expect(user.reads, readsAfterLoad);
      await tester.runAsync(() async {
        final frame =
            await (overviewBoundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final png = await frame.toByteData(format: ui.ImageByteFormat.png);
        await Directory('.local/screenshots').create(recursive: true);
        await File(
          '.local/screenshots/planner-overview-widget.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        frame.dispose();
      });
      await tester.tap(find.bySemanticsIdentifier('planner-open-today'));
      await tester.pumpAndSettle();
      expect(find.text('今天的三餐'), findsOneWidget);
      await tester.ensureVisible(find.text('按这份吃完了').first);
      await tester.runAsync(() async {
        await tester.tap(find.text('按这份吃完了').first);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect((await repo.intakes.getAllIntakesDBO()).length, 1);
      expect(find.textContaining('已记录，可在'), findsOneWidget);
      final undo = find.bySemanticsIdentifier('planner-complete-breakfast');
      expect(
        find.descendant(of: undo, matching: find.byType(OutlinedButton)),
        findsOneWidget,
        reason: 'Undo must be a lower-emphasis action after completion',
      );
      await tester.ensureVisible(find.text('撤销记录').first);
      await tester.runAsync(() async {
        await tester.tap(find.text('撤销记录').first);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect((await repo.intakes.getAllIntakesDBO()), isEmpty);
      final readsBeforeReturn = user.reads;
      Navigator.of(tester.element(find.byType(PlannerDayPage))).pop();
      await tester.pumpAndSettle();
      expect(
        user.reads,
        readsBeforeReturn + 1,
        reason:
            'Returning from daily weight edits refreshes the cached profile',
      );
      expect(find.textContaining('0/3餐有记录'), findsWidgets);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'failed completion is visible without scrolling and leaves no intake',
    (tester) async {
      final day = copyJson(repo.state['plans'][0]['plan']['days'][0]);
      user.weight = 55;
      await tester.pumpWidget(app(PlannerDayPage(repo: repo, day: day)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('按这份吃完了').first);
      await tester.runAsync(() async {
        await tester.tap(find.text('按这份吃完了').first);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('体重偏低'),
        ),
        findsOneWidget,
      );
      expect(await repo.intakes.getAllIntakesDBO(), isEmpty);
      expect(find.text('正在保存…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'future meal action explicitly says when recording becomes available',
    (tester) async {
      final day = copyJson(repo.state['plans'][0]['plan']['days'][1]);
      await tester.pumpWidget(app(PlannerDayPage(repo: repo, day: day)));
      await tester.pumpAndSettle();
      expect(find.text('到这一天再记录'), findsWidgets);
      expect(find.text('这一天的三餐'), findsOneWidget);
      expect(find.text('今天的三餐'), findsNothing);
      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.bySemanticsIdentifier('planner-complete-breakfast'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(await repo.intakes.getAllIntakesDBO(), isEmpty);
    },
  );

  testWidgets('resuming across midnight enables the formerly future meal', (
    tester,
  ) async {
    var clock = DateTime.now();
    final clockRepo = PlannerRepository(
      repo.db,
      repo.intakes,
      repo.users,
      repo.weights,
      repo.tracked,
      repo.service,
      now: () => clock,
    );
    await tester.runAsync(clockRepo.initialize);
    final day = copyJson(repo.state['plans'][0]['plan']['days'][1]);
    await tester.pumpWidget(app(PlannerDayPage(repo: clockRepo, day: day)));
    await tester.pumpAndSettle();
    expect(find.text('到这一天再记录'), findsWidgets);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    clock = clock.add(const Duration(days: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('到这一天再记录'), findsNothing);
    expect(find.text('按这份吃完了'), findsWidgets);
    final button = tester.widget<FilledButton>(
      find.descendant(
        of: find.bySemanticsIdentifier('planner-complete-breakfast'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large text day and settings render without overflow; captures actual Flutter frames',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repaint = GlobalKey();
      final day = Map<String, dynamic>.from(
        repo.state['plans'][0]['plan']['days'][0],
      );
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: repaint,
            child: PlannerDayPage(repo: repo, day: day),
          ),
          scale: 1.4,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      // Screenshots are widget-rendered QA, not an Android device acceptance claim.
      await tester.runAsync(() async {
        final image =
            await (repaint.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final out = Directory('.local/screenshots');
        await out.create(recursive: true);
        await File(
          '${out.path}/planner-day-widget.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(app(PlannerSettings(repo: repo), scale: 1.4));
      await tester.pumpAndSettle();
      expect(find.text('饮食偏好'), findsOneWidget);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'future week does not replace today on launch; help explains daily transitions',
    (tester) async {
      await tester.runAsync(
        () => repo.generate(nextDay(localDay(DateTime.now()), 7)),
      );
      await tester.runAsync(() async {
        await tester.pumpWidget(app(const PlannerPage()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('查看一周安排'), 210,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('查看一周安排'));
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(dropdown.value, repo.state['plans'][0]['id']);
      await tester.tap(find.text('怎么用'));
      await tester.pumpAndSettle();
      expect(find.textContaining('真正吃完后'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'every meal has one primary action; half portion is relative to displayed meal',
    (tester) async {
      final day = copyJson(repo.state['plans'][0]['plan']['days'][0]);
      final planned = (day['meals'][0]['portion'] as num).toDouble();
      await tester.pumpWidget(app(PlannerDayPage(repo: repo, day: day)));
      await tester.pumpAndSettle();
      expect(find.text('吃的份量不一样'), findsNothing);
      final more = find.bySemanticsIdentifier('planner-more-breakfast');
      await tester.ensureVisible(more);
      await tester.tap(
        find.descendant(of: more, matching: find.text('吃的不一样？换菜或修改记录')),
      );
      await tester.pumpAndSettle();
      final portion = find.bySemanticsIdentifier('planner-portion-breakfast');
      await tester.ensureVisible(portion);
      await tester.runAsync(() => tester.tap(portion));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '50');
      await tester.runAsync(() async {
        await tester.tap(find.text('保存'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      final record = repo.state['records']["${day['date']}/breakfast"];
      expect(record['status'], 'replaced');
      expect(record['actual_portion'], closeTo(planned * .5, .0001));
      expect(record['sync_pending'], isFalse);
      expect((await repo.intakes.getAllIntakesDBO()).length, 1);

      final primary = find.bySemanticsIdentifier('planner-complete-breakfast');
      expect(
        find.descendant(of: primary, matching: find.text('撤销记录')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preferences have persistent bottom save, hide service fields and guard unsaved exit',
    (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PlannerSettings(repo: repo),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('服务地址'), findsNothing);
      expect(find.text('模型标识'), findsNothing);
      expect(
        find.bySemanticsIdentifier('planner-save-settings'),
        findsOneWidget,
      );
      await tester.tap(find.text('哪些食物不能吃？'));
      await tester.pumpAndSettle();
      final chip = find.byType(FilterChip).first;
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('饮食偏好还没保存'), findsOneWidget);
      await tester.tap(find.text('继续修改'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('保存饮食偏好'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(repo.state['preferences']['avoid'], isNotEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('保存'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '360dp screen at twice text size keeps home, day and preferences usable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await tester.pumpWidget(app(const PlannerPage(), scale: 2));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.bySemanticsIdentifier('planner-open-today'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('planner-open-today'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.bySemanticsIdentifier('planner-complete-breakfast'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.bySemanticsIdentifier('planner-complete-breakfast'))
            .height,
        greaterThanOrEqualTo(56),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(PlannerSettings(repo: repo), scale: 2));
      await tester.pumpAndSettle();
      expect(find.text('保存饮食偏好'), findsOneWidget);
      expect(
        tester
            .getRect(find.bySemanticsIdentifier('planner-save-settings'))
            .bottom,
        lessThanOrEqualTo(800),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('three actual meal records make the optional reflection next step visible',
      (tester) async {
    final day = copyJson(repo.state['plans'][0]['plan']['days'][0]);
    await tester.runAsync(() async {
      for (final raw in day['meals']) {
        await repo.record(day['date'], Map<String, dynamic>.from(raw), 'completed');
      }
    });
    await tester.pumpWidget(app(PlannerDayPage(repo: repo, day: day)));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('planner-quick-review'), findsOneWidget);
    expect(find.textContaining('今天三餐都有记录了'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.bySemanticsIdentifier('planner-quick-review'));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '今天胃口不错');
    await tester.runAsync(() async {
      await tester.tap(find.text('保存').last);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pumpAndSettle();
    expect(repo.state['records']["${day['date']}/review"]['status'], 'completed');
    expect(repo.state['records']["${day['date']}/review"]['notes'], '今天胃口不错');
    expect(tester.takeException(), null);
  });

  for (final scale in [1.0, 2.0]) {
    for (final slot in ['lunch', 'dinner']) {
      testWidgets('home $slot card focuses that meal at text scale $scale', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(() async {
          await tester.pumpWidget(app(const PlannerPage(), scale: scale));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        final row = find.bySemanticsIdentifier('planner-today-meal-$slot');
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        final action = find.bySemanticsIdentifier('planner-complete-$slot');
        expect(tester.getRect(action).overlaps(const Rect.fromLTWH(0, 56, 360, 744)), isTrue,
          reason: 'Opening a meal must bring its action into the viewport');
        expect(repo.state['records'], isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('weekly tools stay discoverable and open the grocery list', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app(const PlannerPage()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('planner-week-select'), findsNothing);
    await tester.scrollUntilVisible(find.text('查看一周安排'), 200);
    expect(find.textContaining('0 / 21 餐已记录'), findsOneWidget);
    expect(find.textContaining('不代表饮食或减重达标'), findsOneWidget);
    await tester.tap(find.text('查看一周安排'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier('planner-week-select'), findsOneWidget);
    final grocery = find.bySemanticsIdentifier('planner-grocery-list');
    await tester.ensureVisible(grocery);
    await tester.pumpAndSettle();
    await tester.tap(grocery);
    await tester.pumpAndSettle();
    expect(find.text('本周采购清单'), findsOneWidget);
    expect(find.textContaining('不作为整周预算'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('risk blocks new planned meals while keeping mistaken records reversible', (tester) async {
    final day = copyJson(repo.state['plans'][0]['plan']['days'][0]);
    await tester.runAsync(() async {
      await repo.record(day['date'], Map<String, dynamic>.from(day['meals'][0]), 'completed');
    });
    final gated = PlannerRepository(repo.db, repo.intakes, repo.users,
      repo.weights, repo.tracked, repo.service, enforceMedicalScreen: true);
    await tester.runAsync(gated.initialize);
    await tester.pumpWidget(app(PlannerDayPage(repo: gated, day: day, initialSlot: 'lunch')));
    await tester.pumpAndSettle();
    expect(find.textContaining('请先完成健康风险核对'), findsOneWidget);
    final undo = find.bySemanticsIdentifier('planner-complete-breakfast');
    expect(tester.widget<OutlinedButton>(find.descendant(of: undo,
      matching: find.byType(OutlinedButton))).onPressed, isNotNull);
    final lunch = find.bySemanticsIdentifier('planner-complete-lunch');
    expect(tester.widget<FilledButton>(find.descendant(of: lunch,
      matching: find.byType(FilledButton))).onPressed, isNull);
    await tester.ensureVisible(undo);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(undo);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(await repo.intakes.getAllIntakesDBO(), isEmpty);
    expect(gated.state['records']["${day['date']}/breakfast"]['status'], 'pending');
    expect(gated.medicalSafetyIssue, isNotNull);
    expect(tester.takeException(), isNull);
  });

}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/features/meal_planner/data/planner_repository.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/presentation/grocery_budget_dialog.dart';
import 'package:opennutritracker/hive_registrar.g.dart';
import 'planner_persistence_test.dart'
    show TestDB, TestUser, TestWeights, TestTracked, OfflineCredentials;

class UiPriceRepository extends PlannerRepository {
  UiPriceRepository(TestDB db) : super(db,
    IntakeRepository(IntakeDataSource(db)), TestUser(), TestWeights(),
    TestTracked(), MealPlanningService(OfflineCredentials()));
  final prices = <String, dynamic>{};
  @override
  Map<String, dynamic> get unitPrices => Map.from(prices);
  @override
  Future<void> setUnitPrice(String id, double? price) async {
    if (price == null) { prices.remove(id); } else { prices[id] = price; }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(Hive.registerAdapters);
  late Directory dir;
  late PlannerRepository repo;
  late Json plan;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ont-grocery-widget-');
    Hive.init(dir.path);
    final db = TestDB();
    db.plans = await Hive.openBox<String>('plans');
    db.intakes = await Hive.openBox<IntakeDBO>('intakes');
    repo = UiPriceRepository(db);
    await repo.initialize();
    plan = (await repo.rules()).fallback('2026-10-19');
  });
  tearDown(() async { await Hive.close(); await dir.delete(recursive: true); });
  Future<void> open(WidgetTester tester, double scale) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () => showDialog<void>(context: context,
          builder: (_) => GroceryBudgetDialog(repo: repo, plan: plan)),
        child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
  testWidgets('grocery list supports 360dp with twice-sized text', (tester) async {
    await open(tester, 2);
    expect(tester.takeException(), isNull);
    expect(find.text('关闭'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('price dialog can cancel and reopen without disposed controller', (tester) async {
    await open(tester, 1);
    final row = find.byType(ListTile).first;
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '8.5');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repo.unitPrices, isEmpty);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('price save and clear update the displayed estimate', (tester) async {
    await open(tester, 1);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '8.5');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repo.unitPrices.values.single, 8.5);
    expect(tester.takeException(), isNull);
    expect(repo.groceryEstimate(plan)['full_estimate_yuan'], isNull);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除价格'));
    await tester.pumpAndSettle();
    expect(repo.unitPrices, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

}

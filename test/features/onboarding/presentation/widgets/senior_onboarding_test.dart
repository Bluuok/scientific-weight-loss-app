import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_overview_page_body.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_body_measurements_page_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/styles/app_theme.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/features/onboarding/presentation/widgets/onboarding_other_options_page_body.dart';
import 'package:opennutritracker/generated/l10n.dart';

void main() {
  testWidgets(
    'focused onboarding explains next steps without technical configuration',
    (tester) async {
      bool reminder = false;
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppPalette.light),
          locale: const Locale('zh'),
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
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: OnboardingOtherOptionsPageBody(
              focused: true,
              initialTheme: AppThemeEntity.system,
              initialFoodSourceToggles: const {},
              initialDailyReminderEnabled: false,
              initialUseMaterialYou: false,
              initialAccentColor: null,
              setPageContent: (_, _, enabled, _, _) => reminder = enabled,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('今天吃什么'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SegmentedButton<AppThemeEntity>), findsNothing);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(reminder, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'older adult target does not offer young adult BMI weight suggestion',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [S.delegate],
          supportedLocales: S.supportedLocales,
          home: Scaffold(
            body: OnboardingBodyMeasurementsPageBody(
              olderAdult: true,
              initialHeightCm: 178,
              initialWeightKg: 100,
              setButtonContent: (_, _, _, _, _, _, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('不直接套用年轻成人'), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'planner overview avoids a conflicting fixed calorie target at double text size',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: OnboardingOverviewPageBody(
                  plannerOverview: true,
                  setButtonActive: (_) {},
                  calorieGoalDayString: '2047',
                  carbsGoalString: '307',
                  fatGoalString: '56',
                  proteinGoalString: '77',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2047'), findsNothing);
      expect(find.textContaining('进入“我的计划”'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

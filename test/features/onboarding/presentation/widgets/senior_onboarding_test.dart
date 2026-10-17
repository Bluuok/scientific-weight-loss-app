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
}

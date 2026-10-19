import 'package:flutter/material.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/meal_planner/presentation/planner_page.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/add_item_bottom_sheet.dart';
import 'package:opennutritracker/core/presentation/widgets/demo_mode_banner.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/health_rationale_service.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/diary/diary_page.dart';
import 'package:opennutritracker/core/presentation/widgets/home_appbar.dart';
import 'package:opennutritracker/core/presentation/widgets/main_appbar.dart';
import 'package:opennutritracker/features/profile/profile_page.dart';
import 'package:opennutritracker/generated/l10n.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedPageIndex = 0;
  bool _isDemoData = false;

  /// Guards against two lifecycle events asking the platform at once. The
  /// platform side clears the flag on read, so a race would not open the
  /// screen twice — but it would spend two channel round trips finding out.
  bool _checkingHealthRationale = false;

  late List<Widget> _bodyPages;
  late List<PreferredSizeWidget> _appbarPages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfigDrivenUi();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The activity is singleTop, so Health Connect reaching a process that is
    // already running never rebuilds this screen — a resume is the only signal
    // that an intent arrived.
    if (state == AppLifecycleState.resumed) {
      _maybeOpenHealthRationale();
    }
  }

  // Checked once per screen instance rather than kept live — leaving demo mode
  // always replaces this whole screen with the onboarding route (see
  // DemoModeBanner), so there is no in-place transition to react to.
  //
  // The policy-change notice #887 specified is deliberately **not** shown for
  // revision 1. #887's reasoning stands on the record and was not refuted —
  // the corrections name recipients that were always receiving data, so users
  // were under-informed for the whole time rather than recently — but the call
  // was made not to spend a first-launch dialog on it. The mechanism itself is
  // kept, not deleted: `URLConst.policyRevision`, the seeding in
  // `OnboardingBloc.saveOnboardingData` and `PolicyChangeDialog` are all still
  // live and tested, so a future revision that does warrant telling people can
  // restore this by calling the dialog again. What is gone is one call, not
  // the ability to notify.
  Future<void> _loadConfigDrivenUi() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!mounted) return;
    setState(() => _isDemoData = config.isDemoData);
    await _maybeOpenHealthRationale();
  }

  /// Opens the health-sync screen when Health Connect asked the app to explain
  /// what it wants health data for (#927).
  ///
  /// Health Connect starts the app rather than rendering anything itself, so
  /// without this the user is dropped on the diary having asked a question
  /// nothing answered. The screen names the data, says what it is used for,
  /// and links the privacy policy.
  Future<void> _maybeOpenHealthRationale() async {
    if (_checkingHealthRationale) return;
    _checkingHealthRationale = true;
    final bool requested;
    try {
      requested = await HealthRationaleService.consumePendingRequest();
    } finally {
      _checkingHealthRationale = false;
    }
    if (!requested || !mounted) return;
    await Navigator.of(context).pushNamed(NavigationOptions.healthSyncRoute);
  }

  @override
  void didChangeDependencies() {
    _bodyPages = [
      const PlannerPage(),
      const DiaryPage(focused: true),
      const ProfilePage(focused: true),
    ];
    _appbarPages = [
      const HomeAppbar(),
      MainAppbar(title: '饮食记录', iconData: Icons.book),
      MainAppbar(title: '我的资料', iconData: Icons.account_circle),
    ];
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Scaffold(
      appBar: _selectedPageIndex == 0 ? null : _appbarPages[_selectedPageIndex],
      body: Column(
        children: [
          if (_isDemoData) const DemoModeBanner(),
          Expanded(
            child: IndexedStack(
              index: _selectedPageIndex,
              children: _bodyPages,
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedPageIndex != 1
          ? null
          : Semantics(
              identifier: 'fab-add-item',
              child: FloatingActionButton.extended(
                onPressed: () => _onFabPressed(context),
                tooltip: S.of(context).addLabel,
                icon: const Icon(Icons.add, size: 30),
                label: const Text('记录饮食'),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: BottomAppBar(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height:
            78 + 2 * (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 60),
        padding: EdgeInsets.zero,
        shape: const AutomaticNotchedShape(RoundedRectangleBorder()),
        notchMargin: 8,
        child: Row(
          children: [
            _NavItem(
              id: 'nav-home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: '我的计划',
              index: 0,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
            _NavItem(
              id: 'nav-diary',
              icon: Icons.book_outlined,
              selectedIcon: Icons.book_rounded,
              label: '饮食记录',
              index: 1,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
            _NavItem(
              id: 'nav-you',
              icon: Icons.account_circle_outlined,
              selectedIcon: Icons.account_circle_rounded,
              label: '我的资料',
              index: 2,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
          ],
        ),
      ),
    );
  }

  void _setPage(int selectedIndex) {
    if (_selectedPageIndex == 0 && selectedIndex != 0) {
      locator<HomeBloc>().add(const LoadItemsEvent());
      locator<DiaryBloc>().add(const LoadDiaryYearEvent());
      locator<CalendarDayBloc>().add(const RefreshCalendarDayEvent());
    }
    setState(() {
      if (selectedIndex == 0 && _selectedPageIndex != 0) {
        _bodyPages[0] = PlannerPage(key: UniqueKey());
      }
      _selectedPageIndex = selectedIndex;
    });
  }

  Future<void> _onFabPressed(BuildContext context) async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return AddItemBottomSheet(
          focused: true,
          day: DateTime.now(),
          showActivityTracking: false,
          usesImperialUnits: config.usesImperialFoodUnits,
          suggestedType: MealTypeSuggester.suggestFromTime(DateTime.now()),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final String id;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int index;
  final int selectedIndex;
  final AppPalette palette;
  final void Function(int) onTap;

  const _NavItem({
    required this.id,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = index == selectedIndex;
    // Each destination retains its own visual identity on the fixed light canvas.
    const accents = [
      Color(0xFF155C3C), // My plan — green
      Color(0xFF25518C), // Diary — blue
      Color(0xFF453E93), // Profile — violet
    ];
    const lightFills = [
      Color(0xFFE3F3E9),
      Color(0xFFE6F0FF),
      Color(0xFFECEBFF),
    ];
    final color = selected ? accents[index] : palette.textMuted;
    return Expanded(
      child: Semantics(
        identifier: id,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: selected ? lightFills[index] : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 6),
                  child: Icon(selected ? selectedIcon : icon,
                      color: color, size: 27),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

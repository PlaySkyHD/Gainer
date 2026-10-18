import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/services/auth/mobile_auth_controller.dart';
import '../../features/access/account_operator_screen.dart';
import '../../features/body/body_screen.dart';
import '../../features/body/health/health_review_screen.dart';
import '../../features/cardio/cardio_feature.dart';
import '../../features/cardio/cardio_live_screen.dart';
import '../../features/cardio/cardio_settings_screen.dart';
import '../../features/coach/coach_screen.dart';
import '../../features/nutrition/nutrition_screen.dart';
import '../../features/progress/progress_screen.dart';
import '../../features/sync/sync_screen.dart';
import '../../features/training/compact_training_bar.dart';
import '../../features/training/training_home_screen.dart';
import '../../features/training/workout_screen.dart';
import '../components/components.dart';
import '../theme.dart';
import '../view_models/mobile_shell_view_model.dart';
import 'mobile_tab_scaffold.dart';
import 'sync_now_section.dart';
import 'sync_status_banner.dart';

class MobileShell extends StatelessWidget {
  const MobileShell({
    required this.controller,
    required this.account,
    super.key,
  });

  final MobileAuthController controller;
  final AccountScope account;

  @override
  Widget build(BuildContext context) {
    return _ActiveWorkoutOpener(
      model: controller.shell,
      account: account,
      child: ChangeNotifierProvider<MobileShellViewModel>.value(
        value: controller.shell,
        child: Consumer<MobileShellViewModel>(
          builder: (context, model, _) => MobileTabScaffold(
            model: model,
            compactTrainingBar: CompactTrainingBar(
              activeWorkout: account.activeWorkout,
              repository: account.training,
            ),
            contentWrapper: (context, content) => SyncStatusBanner(
              status: account.syncStatus,
              synchronize: account.synchronize,
              child: content,
            ),
            tabBuilder: (context, area) => CupertinoTabView(
              builder: (context) => switch (area) {
                MobileArea.training => TrainingHomeScreen(
                  repository: account.training,
                  activeWorkout: account.activeWorkout,
                  cardio: _cardioOf(account),
                ),
                MobileArea.nutrition => NutritionScreen(
                  viewModel: account.nutritionViewModel,
                ),
                MobileArea.body => BodyScreen(viewModel: account.bodyViewModel),
                MobileArea.progress => ProgressScreen(
                  viewModel: account.progressViewModel,
                  onOpenArea: (area) => model.selectTab(area.index),
                ),
                MobileArea.more => _MoreScreen(
                  controller: controller,
                  account: account,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

CardioFeature _cardioOf(AccountScope account) => CardioFeature(
  repository: account.cardio,
  session: account.cardioSession,
  health: account.cardioHealth,
);

/// Öffnet das aktive Training, wenn der Controller es nach einem Tab-Wechsel
/// angefordert hat. Nur ein Training des aktuellen, noch aktiven Kontos.
class _ActiveWorkoutOpener extends StatefulWidget {
  const _ActiveWorkoutOpener({
    required this.model,
    required this.account,
    required this.child,
  });

  final MobileShellViewModel model;
  final AccountScope account;
  final Widget child;

  @override
  State<_ActiveWorkoutOpener> createState() => _ActiveWorkoutOpenerState();
}

class _ActiveWorkoutOpenerState extends State<_ActiveWorkoutOpener> {
  @override
  void initState() {
    super.initState();
    widget.model.addListener(_handleRequest);
  }

  @override
  void didUpdateWidget(_ActiveWorkoutOpener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model)) {
      oldWidget.model.removeListener(_handleRequest);
      widget.model.addListener(_handleRequest);
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_handleRequest);
    super.dispose();
  }

  void _handleRequest() {
    if (widget.model.takeRequestedCardio()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final account = widget.account;
        if (!account.isSessionActive() || !account.cardioSession.isRunning) {
          return;
        }
        openCardioLive(context, _cardioOf(account));
      });
      return;
    }
    final workoutId = widget.model.takeRequestedWorkout();
    if (workoutId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final account = widget.account;
      if (!account.isSessionActive() ||
          account.activeWorkout.active?.workoutId != workoutId) {
        return;
      }
      openWorkoutScreen(
        context,
        repository: account.training,
        activeWorkout: account.activeWorkout,
        workoutId: workoutId,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen({required this.controller, required this.account});
  final MobileAuthController controller;
  final AccountScope account;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerScaffold(
      title: 'Mehr',
      children: [
        GainerCard(
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(CupertinoIcons.person_fill, color: colors.onAccent),
              ),
              const SizedBox(width: GainerSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.session.email,
                      style: GainerTypography.cardTitle.copyWith(
                        color: colors.primaryText,
                      ),
                      softWrap: true,
                    ),
                    const SizedBox(height: GainerSpacing.xxs),
                    Text(
                      account.online ? 'Angemeldetes Konto' : 'Lokales Profil',
                      style: GainerTypography.label.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          header: 'Konto & Geräte',
          children: [
            GainerListRow(
              title: 'Sync & Gerätewechsel',
              leadingIcon: CupertinoIcons.arrow_2_squarepath,
              showChevron: true,
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => SyncScreen(
                    sync: account.sync,
                    isOnline: account.online,
                    accountId: account.store.accountId,
                    apiOrigin: account.api.configuration.canonicalApiOrigin,
                    isScopeActive: account.isSessionActive,
                  ),
                ),
              ),
            ),
            GainerListRow(
              title: 'Apple Health',
              leadingIcon: CupertinoIcons.heart,
              showChevron: true,
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) =>
                      HealthReviewScreen(viewModel: account.healthViewModel),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          header: 'Weitere Bereiche',
          children: [
            GainerListRow(
              title: 'Coach',
              leadingIcon: CupertinoIcons.chat_bubble_2,
              showChevron: true,
              onTap: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) =>
                      CoachScreen(viewModel: account.coachViewModel),
                ),
              ),
            ),
            GainerListRow(
              title: 'Cardio',
              leadingIcon: CupertinoIcons.heart_circle,
              showChevron: true,
              onTap: () => openCardioSettings(
                context,
                preferences: account.cardio.preferences,
              ),
            ),
            if (account.session.isAccountOperator)
              GainerListRow(
                title: 'Kontoverwaltung',
                leadingIcon: CupertinoIcons.person_2,
                showChevron: true,
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) =>
                        AccountOperatorScreen(controller: controller),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        SyncNowSection(
          online: account.online,
          synchronize: account.synchronize,
          status: account.syncStatus,
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerGroupedSection(
          children: [
            GainerListRow(
              title: 'Abmelden',
              leadingIcon: CupertinoIcons.square_arrow_right,
              onTap: controller.logout,
            ),
          ],
        ),
      ],
    );
  }
}

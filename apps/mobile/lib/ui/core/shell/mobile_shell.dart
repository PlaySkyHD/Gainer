import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/sync/sync_repository.dart';
import '../../../data/services/auth/mobile_auth_controller.dart';
import '../../features/access/account_operator_screen.dart';
import '../../features/body/body_screen.dart';
import '../../features/body/health/health_review_screen.dart';
import '../../features/coach/coach_screen.dart';
import '../../features/nutrition/nutrition_screen.dart';
import '../../features/progress/progress_screen.dart';
import '../../features/sync/sync_screen.dart';
import '../../features/training/training_screen.dart';
import '../components/components.dart';
import '../theme.dart';
import '../view_models/mobile_shell_view_model.dart';
import 'mobile_tab_scaffold.dart';

class MobileShell extends StatelessWidget {
  const MobileShell({
    required this.controller,
    required this.account,
    this.compactTrainingBar,
    super.key,
  });

  final MobileAuthController controller;
  final AccountScope account;

  /// Slot über der Tableiste für die kompakte Trainingsleiste; standardmäßig leer.
  final Widget? compactTrainingBar;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MobileShellViewModel>.value(
      value: controller.shell,
      child: Consumer<MobileShellViewModel>(
        builder: (context, model, _) => MobileTabScaffold(
          model: model,
          compactTrainingBar: compactTrainingBar,
          tabBuilder: (context, area) => CupertinoTabView(
            builder: (context) => switch (area) {
              MobileArea.training => TrainingScreen(
                viewModel: account.trainingViewModel,
              ),
              MobileArea.nutrition => NutritionScreen(
                viewModel: account.nutritionViewModel,
              ),
              MobileArea.body => BodyScreen(viewModel: account.bodyViewModel),
              MobileArea.progress => ProgressScreen(
                viewModel: account.progressViewModel,
              ),
              MobileArea.more => _MoreScreen(
                controller: controller,
                account: account,
              ),
            },
          ),
        ),
      ),
    );
  }
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
          header: 'KONTO & GERÄTE',
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
          header: 'WEITERE BEREICHE',
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
        _SyncButton(account: account),
        const SizedBox(height: GainerSpacing.s),
        GainerPillButton(
          label: 'Abmelden',
          variant: GainerPillVariant.tonal,
          expand: true,
          onPressed: controller.logout,
        ),
      ],
    );
  }
}

class _SyncButton extends StatefulWidget {
  const _SyncButton({required this.account});
  final AccountScope account;
  @override
  State<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<_SyncButton> {
  bool _busy = false;
  String? _status;
  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await widget.account.synchronize();
      if (!mounted) {
        return;
      }
      setState(
        () => _status = switch (result.state) {
          SyncRunState.synced => 'Änderungen synchronisiert.',
          SyncRunState.retryPending =>
            'Änderungen warten auf einen erneuten Sync-Versuch.',
          SyncRunState.authBlocked => 'Bitte melde dich erneut an; lokale Änderungen bleiben gespeichert.',
          SyncRunState.upgradeRequired =>
            'Aktualisiere die App, um die Synchronisierung fortzusetzen.',
          SyncRunState.inactiveClient =>
            'Dieses Gerät ist nicht als aktiver Schreiber registriert.',
          SyncRunState.busy => 'Synchronisierung läuft bereits.',
          SyncRunState.idle => 'Keine ausstehenden Änderungen.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Synchronisierung nicht möglich. Lokale Änderungen bleiben erhalten.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final enabled = widget.account.online && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerPillButton(
          label: 'Jetzt synchronisieren',
          expand: true,
          isLoading: _busy,
          onPressed: enabled ? _sync : null,
        ),
        if (_status case final value?)
          Padding(
            padding: const EdgeInsets.only(top: GainerSpacing.s),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: GainerTypography.body.copyWith(
                color: colors.secondaryText,
              ),
            ),
          ),
      ],
    );
  }
}

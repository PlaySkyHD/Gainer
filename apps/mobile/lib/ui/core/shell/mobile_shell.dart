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
import '../theme.dart';
import '../view_models/mobile_shell_view_model.dart';

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
    return ChangeNotifierProvider<MobileShellViewModel>.value(
      value: controller.shell,
      child: Consumer<MobileShellViewModel>(
        builder: (context, model, _) => CupertinoTabScaffold(
          controller: model.tabController,
          tabBar: CupertinoTabBar(
            currentIndex: model.selectedIndex,
            inactiveColor: GainerTheme.secondaryText(context),
            onTap: model.selectTab,
            items: [
              for (final area in MobileArea.values)
                BottomNavigationBarItem(
                  icon: Icon(area.icon),
                  label: area.label,
                  tooltip: area.label,
                ),
            ],
          ),
          tabBuilder: (context, index) => CupertinoTabView(
            builder: (context) => switch (MobileArea.values[index]) {
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
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Mehr')),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: CupertinoColors.secondarySystemGroupedBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: GainerTheme.actionColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.person_fill,
                          color: CupertinoColors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.session.email,
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .navTitleTextStyle,
                              softWrap: true,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              account.online
                                  ? 'Angemeldetes Konto'
                                  : 'Lokales Profil',
                              style: TextStyle(
                                color: GainerTheme.secondaryText(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                CupertinoListSection.insetGrouped(
                  backgroundColor: CupertinoTheme.of(context)
                      .scaffoldBackgroundColor,
                  header: Text(
                    'KONTO & GERÄTE',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GainerTheme.secondaryText(context),
                    ),
                  ),
                  children: [
                    CupertinoListTile(
                      title: const Text('Sync & Gerätewechsel'),
                      leading: const Icon(CupertinoIcons.arrow_2_squarepath),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => SyncScreen(
                            sync: account.sync,
                            isOnline: account.online,
                            accountId: account.store.accountId,
                            apiOrigin:
                                account.api.configuration.canonicalApiOrigin,
                            isScopeActive: account.isSessionActive,
                          ),
                        ),
                      ),
                    ),
                    CupertinoListTile(
                      title: const Text('Apple Health'),
                      leading: const Icon(CupertinoIcons.heart),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => HealthReviewScreen(
                            viewModel: account.healthViewModel,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  backgroundColor: CupertinoTheme.of(context)
                      .scaffoldBackgroundColor,
                  header: Text(
                    'WEITERE BEREICHE',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: GainerTheme.secondaryText(context),
                    ),
                  ),
                  children: [
                    CupertinoListTile(
                      title: const Text('Coach'),
                      leading: const Icon(CupertinoIcons.chat_bubble_2),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) =>
                              CoachScreen(viewModel: account.coachViewModel),
                        ),
                      ),
                    ),
                    if (account.session.isAccountOperator)
                      CupertinoListTile(
                        title: const Text('Kontoverwaltung'),
                        leading: const Icon(CupertinoIcons.person_2),
                        trailing: const CupertinoListTileChevron(),
                        onTap: () => Navigator.of(context).push(
                          CupertinoPageRoute<void>(
                            builder: (_) =>
                                AccountOperatorScreen(controller: controller),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _SyncButton(account: account),
                CupertinoButton(
                  minimumSize: const Size(double.infinity, 48),
                  onPressed: controller.logout,
                  child: const Text('Abmelden'),
                ),
              ],
            ),
          ),
        ),
      ),
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
    final enabled = widget.account.online && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoButton.filled(
          minimumSize: const Size(double.infinity, 48),
          onPressed: enabled ? _sync : null,
          child: _busy
              ? const CupertinoActivityIndicator()
              : Text(
                  'Jetzt synchronisieren',
                  style: TextStyle(
                    color: enabled
                        ? CupertinoColors.white
                        : GainerTheme.secondaryText(context),
                  ),
                ),
        ),
        if (_status case final value?)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(value, textAlign: TextAlign.center),
          ),
      ],
    );
  }
}

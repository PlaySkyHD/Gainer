import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../../data/repositories/sync/sync_repository.dart';
import '../../../data/repositories/sync/sync_status.dart';
import '../components/components.dart';
import '../theme.dart';
import 'sync_now_section.dart';

/// Legt über alle Tabs einen Hinweis, solange dieses iPhone nicht das
/// Schreibgerät ist, mit „Übernehmen“ im gleichen Ablauf wie unter Mehr.
/// Der Inhalt behält seine Safe-Area; sie wandert nur unter den Hinweis.
class SyncStatusBanner extends StatefulWidget {
  const SyncStatusBanner({
    required this.status,
    required this.synchronize,
    required this.child,
    super.key,
  });

  final ValueListenable<SyncStatus> status;
  final Future<SyncRunReport> Function({bool takeOverWriting}) synchronize;
  final Widget child;

  @override
  State<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends State<SyncStatusBanner> {
  bool _busy = false;

  Future<void> _takeOver() async {
    if (!await confirmTakeOverWriting(context) || !mounted) return;
    setState(() => _busy = true);
    Object? failure;
    try {
      await widget.synchronize(takeOverWriting: true);
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      await showGainerStackedDialog<bool>(
        context: context,
        title: 'Übernehmen nicht möglich',
        message: syncFailureMessage(failure),
        actions: const [GainerDialogAction(label: 'OK', value: true)],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: widget.status,
      builder: (context, status, child) {
        final media = MediaQuery.of(context);
        // Ein nötiges Update geht vor: Ohne es synchronisiert nichts mehr.
        final showBanner = status.upgradeRequired || !status.isWriter;
        // Gleicher Aufbau mit und ohne Hinweis, damit die Tabs ihren Zustand
        // (Navigation, Scrollposition) behalten.
        return Column(
          children: [
            if (showBanner)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  GainerSpacing.m,
                  media.padding.top + GainerSpacing.xs,
                  GainerSpacing.m,
                  GainerSpacing.xs,
                ),
                child: status.upgradeRequired
                    ? const _UpgradeCard()
                    : _BannerCard(busy: _busy, onTakeOver: _takeOver),
              )
            else
              const SizedBox.shrink(),
            Expanded(
              child: MediaQuery(
                data: showBanner ? media.removePadding(removeTop: true) : media,
                child: child!,
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

/// Der Server hat Daten, die diese App-Version nicht kennt. Lokale Änderungen
/// bleiben gespeichert; nach dem Update geht der Sync weiter.
class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard();

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: GainerCard(
        key: const ValueKey('sync-upgrade-banner'),
        padding: const EdgeInsets.all(GainerSpacing.s),
        child: Row(
          children: [
            Icon(CupertinoIcons.arrow_down_circle, color: colors.warning),
            const SizedBox(width: GainerSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bitte App aktualisieren',
                    style: GainerTypography.cardTitle.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: GainerSpacing.xxs),
                  Text(
                    'Neue Daten brauchen eine neuere Version. Lokale '
                    'Änderungen bleiben gespeichert.',
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
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.busy, required this.onTakeOver});

  final bool busy;
  final VoidCallback onTakeOver;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Semantics(
      container: true,
      child: GainerCard(
        padding: const EdgeInsets.all(GainerSpacing.s),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: colors.warning,
            ),
            const SizedBox(width: GainerSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dieses iPhone lädt nichts hoch',
                    style: GainerTypography.cardTitle.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: GainerSpacing.xxs),
                  Text(
                    'Ein anderes Gerät schreibt.',
                    style: GainerTypography.label.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: GainerSpacing.s),
            GainerPillButton(
              label: 'Übernehmen',
              variant: GainerPillVariant.tonal,
              isLoading: busy,
              onPressed: onTakeOver,
            ),
          ],
        ),
      ),
    );
  }
}

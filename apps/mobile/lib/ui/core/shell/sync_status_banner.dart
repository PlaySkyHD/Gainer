import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../../data/repositories/sync/sync_repository.dart';
import '../../../data/repositories/sync/sync_status.dart';
import '../components/components.dart';
import '../theme.dart';
import 'sync_now_section.dart';

/// Legt über alle Tabs einen Hinweis, solange dieses iPhone nicht das
/// Schreibgerät ist, mit „Übernehmen“ im gleichen Ablauf wie unter Mehr.
/// Abgelehnte Änderungen zeigt er ebenfalls, damit sie nicht unbemerkt
/// fehlen. Der Inhalt behält seine Safe-Area; sie wandert nur unter den
/// Hinweis.
class SyncStatusBanner extends StatefulWidget {
  const SyncStatusBanner({
    required this.status,
    required this.synchronize,
    required this.child,
    this.onOpenConflicts,
    super.key,
  });

  final ValueListenable<SyncStatus> status;
  final Future<SyncRunReport> Function({bool takeOverWriting}) synchronize;
  final Widget child;

  /// Öffnet „Sync & Gerät“ mit den Konflikten; ohne Wert kein Konflikthinweis.
  final VoidCallback? onOpenConflicts;

  @override
  State<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends State<SyncStatusBanner> {
  bool _busy = false;

  Future<void> _takeOver() async {
    if (!await confirmTakeOverWriting(context) || !mounted) return;
    setState(() => _busy = true);
    String? problem;
    try {
      final report = await widget.synchronize(takeOverWriting: true);
      problem = takeOverProblemMessage(report.state);
    } catch (error) {
      problem = syncFailureMessage(error);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (problem != null) {
      await showGainerStackedDialog<bool>(
        context: context,
        title: 'Übernehmen nicht möglich',
        message: problem,
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
        final openConflicts = widget.onOpenConflicts;
        final showConflicts = openConflicts != null && status.conflictCount > 0;
        final showBanner =
            status.upgradeRequired || !status.isWriter || showConflicts;
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
                    : !status.isWriter
                    ? _BannerCard(busy: _busy, onTakeOver: _takeOver)
                    : _ConflictCard(
                        count: status.conflictCount,
                        onOpen: openConflicts!,
                      ),
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

/// Der Server hat Änderungen abgelehnt; bis zur Auflösung fehlen sie dort.
/// Reicht die Breite nicht für Text und Knopf nebeneinander (schmales Gerät
/// oder große Schrift), steht „Ansehen“ unter dem Text.
class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.count, required this.onOpen});

  final int count;
  final VoidCallback onOpen;

  /// Breite je Textskalierung, ab der Text und Knopf nebeneinander passen.
  static const _sideBySideWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          count == 1
              ? '1 Änderung nicht gespeichert'
              : '$count Änderungen nicht gespeichert',
          style: GainerTypography.cardTitle.copyWith(color: colors.primaryText),
        ),
        const SizedBox(height: GainerSpacing.xxs),
        Text(
          'Der Server hat sie abgelehnt.',
          style: GainerTypography.label.copyWith(color: colors.secondaryText),
        ),
      ],
    );
    final button = GainerPillButton(
      label: 'Ansehen',
      variant: GainerPillVariant.tonal,
      onPressed: onOpen,
    );
    final icon = Icon(
      CupertinoIcons.exclamationmark_triangle,
      color: colors.warning,
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: GainerCard(
        key: const ValueKey('sync-conflict-banner'),
        padding: const EdgeInsets.all(GainerSpacing.s),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth < _sideBySideWidth * scale
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        const SizedBox(width: GainerSpacing.s),
                        Expanded(child: text),
                      ],
                    ),
                    const SizedBox(height: GainerSpacing.s),
                    button,
                  ],
                )
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: GainerSpacing.s),
                    Expanded(child: text),
                    const SizedBox(width: GainerSpacing.s),
                    button,
                  ],
                ),
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

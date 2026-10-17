import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/models/local/local_mutation.dart';
import '../../../data/repositories/sync/sync_repository.dart';
import '../../../data/services/local/pending_handover_secret_store.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'sync_view_model.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({
    required this.sync,
    required this.isOnline,
    required this.accountId,
    required this.apiOrigin,
    this.isScopeActive,
    super.key,
  });

  final MobileSyncActions sync;
  final bool isOnline;
  final String accountId;
  final String apiOrigin;
  final bool Function()? isScopeActive;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  late final SyncViewModel _model;
  final _handoverId = TextEditingController();
  final _oneTimeCode = TextEditingController();
  final _sourceClientId = TextEditingController();
  final _revision = TextEditingController();
  final _expiresAtUtc = TextEditingController();
  final _transferBundle = TextEditingController();
  bool _showAdvancedHandoverFields = false;
  HandoverTransferBundle? _parsedTransferBundle;

  @override
  void initState() {
    super.initState();
    _model = SyncViewModel(
      sync: widget.sync,
      isOnline: widget.isOnline,
      expectedAccountId: widget.accountId,
      expectedApiOrigin: widget.apiOrigin,
      isScopeActive: widget.isScopeActive,
    )..load();
  }

  @override
  void dispose() {
    _model.dispose();
    _handoverId.dispose();
    _oneTimeCode.dispose();
    _sourceClientId.dispose();
    _revision.dispose();
    _expiresAtUtc.dispose();
    _transferBundle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _model,
    builder: (context, _) {
      final colors = GainerDesign.colorsOf(context);
      return GainerScaffold(
        title: 'Sync & Gerät',
        children: [
          Text(
            widget.isOnline
                ? 'Änderungen werden sicher mit deinem Konto abgeglichen.'
                : 'Offline: lokale Änderungen bleiben auf diesem Gerät gespeichert.',
            style: GainerTypography.body.copyWith(
              color: widget.isOnline ? colors.secondaryText : colors.warning,
            ),
          ),
          if (_model.errorMessage case final message?)
            _Message(message: message, isError: true),
          if (_model.statusMessage case final message?)
            _Message(message: message, isError: false),
          const SizedBox(height: GainerSpacing.l),
          _sectionTitle(context, 'Gerätewechsel'),
          const SizedBox(height: GainerSpacing.xs),
          _handoverPanel(context),
          const SizedBox(height: GainerSpacing.l),
          _sectionTitle(context, 'Sync-Konflikte'),
          const SizedBox(height: GainerSpacing.xs),
          ..._conflictChildren(context),
          const SizedBox(height: GainerSpacing.l),
          GainerPillButton(
            label: 'Status aktualisieren',
            variant: GainerPillVariant.tonal,
            expand: true,
            onPressed: _model.isBusy || _model.isLoading ? null : _model.load,
          ),
        ],
      );
    },
  );

  Widget _handoverPanel(BuildContext context) {
    final pending = _model.pendingHandover;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending == null) ...[
          const _CardText(
            'Starte die Übergabe auf dem bisherigen Gerät. Danach gibst du die angezeigten Übergabedaten auf dem neuen Gerät ein.',
          ),
          const SizedBox(height: GainerSpacing.xs),
          GainerPillButton(
            label: 'Dieses Gerät ablösen',
            expand: true,
            onPressed: !_model.isOnline || _model.isBusy || _model.isLoading
                ? null
                : _confirmAndBegin,
          ),
        ] else
          ..._pendingHandoverChildren(context, pending),
        if (pending == null) ..._receiveHandoverChildren(context),
      ],
    );
  }

  List<Widget> _conflictChildren(BuildContext context) {
    if (_model.isLoading) {
      return const [Center(child: CupertinoActivityIndicator())];
    }
    if (_model.conflicts.isEmpty) {
      return const [_CardText('Keine ungelösten Konflikte.')];
    }
    return [
      for (final conflict in _model.conflicts) _conflictCard(context, conflict),
    ];
  }

  List<Widget> _pendingHandoverChildren(
    BuildContext context,
    PendingHandoverRecord pending,
  ) => switch (pending.phase) {
    'sourceBeginPending' => [
      const _CardText(
        'Die Anfrage wird sicher fortgesetzt. Schreibzugriffe bleiben bis zum Abschluss angehalten.',
      ),
      const SizedBox(height: GainerSpacing.xs),
      GainerPillButton(
        label: 'Übergabe fortsetzen',
        expand: true,
        onPressed: !_model.isOnline || _model.isBusy ? null : _begin,
      ),
    ],
    'sourceBegan' => [
      _handoverCodeCard(context, pending),
      const SizedBox(height: GainerSpacing.xs),
      GainerPillButton(
        label: 'Übergabe abbrechen',
        variant: GainerPillVariant.tonal,
        expand: true,
        onPressed: !_model.isOnline || _model.isBusy ? null : _confirmAndCancel,
      ),
    ],
    'targetCompletePending' => _targetCompletePendingChildren(pending),
    _ => [
      const _CardText(
        'Für dieses Gerät liegt ein Übergabeschritt vor, den die App nicht sicher zuordnen kann. Es wurden keine Schreibrechte geändert.',
        warning: true,
      ),
    ],
  };

  List<Widget> _targetCompletePendingChildren(PendingHandoverRecord pending) {
    final expired =
        pending.expiresAtUtc?.isBefore(DateTime.now().toUtc()) ?? false;
    return [
      _CardText(
        expired
            ? 'Die gespeicherte Übernahme ist abgelaufen. Du kannst sie erneut mit denselben Daten abgleichen oder dieses Gerät nach einer Serverprüfung lokal freigeben.'
            : 'Die Übernahme ist gespeichert und kann nach einem Abbruch oder Neustart wiederholt werden.',
        warning: expired,
      ),
      const SizedBox(height: GainerSpacing.xs),
      GainerPillButton(
        label: 'Übernahme fortsetzen',
        expand: true,
        onPressed: !_model.isOnline || _model.isBusy
            ? null
            : _model.resumeTargetHandover,
      ),
      if (expired) ...[
        const SizedBox(height: GainerSpacing.xs),
        GainerPillButton(
          label: 'Nach Serverprüfung lokal freigeben',
          variant: GainerPillVariant.tonal,
          expand: true,
          onPressed: !_model.isOnline || _model.isBusy
              ? null
              : _model.recoverExpiredTargetHandover,
        ),
      ],
    ];
  }

  List<Widget> _receiveHandoverChildren(BuildContext context) => [
    const SizedBox(height: GainerSpacing.l),
    _sectionTitle(context, 'Übergabe auf diesem Gerät annehmen'),
    const SizedBox(height: GainerSpacing.xs),
    const _CardText(
      'Füge das Übergabepaket vom bisherigen Gerät ein. Es wird gegen dein angemeldetes Konto und diese API geprüft, bevor Schreibrechte wechseln.',
    ),
    const SizedBox(height: GainerSpacing.xs),
    _bundlePasteField(context),
    const SizedBox(height: GainerSpacing.xs),
    GainerPillButton(
      label: 'Übergabedaten einfügen',
      variant: GainerPillVariant.tonal,
      expand: true,
      onPressed: _model.isBusy ? null : _pasteAndParseTransferBundle,
    ),
    if (_parsedTransferBundle case final bundle?)
      Padding(
        padding: const EdgeInsets.only(top: GainerSpacing.xs),
        child: _CardText(
          'Quellgerät ${bundle.sourceClientId} · Revision ${bundle.frozenRevision} · Ablauf ${bundle.expiresAtUtc.toLocal()} · Einmalcode erkannt',
        ),
      ),
    const SizedBox(height: GainerSpacing.xs),
    GainerPillButton(
      label: _showAdvancedHandoverFields
          ? 'Manuelle Eingabe ausblenden'
          : 'Manuell eingeben (erweitert)',
      variant: GainerPillVariant.tonal,
      expand: true,
      onPressed: () => setState(
        () => _showAdvancedHandoverFields = !_showAdvancedHandoverFields,
      ),
    ),
    if (_showAdvancedHandoverFields) ...[
      _field(context, _handoverId, 'Übergabe-ID'),
      _field(context, _oneTimeCode, 'Einmalcode', obscure: true),
      _field(context, _sourceClientId, 'Quellgerät-ID'),
      _field(
        context,
        _revision,
        'Eingefrorene Revision',
        keyboard: TextInputType.number,
      ),
      _field(context, _expiresAtUtc, 'Ablaufzeit (UTC, ISO 8601)'),
    ],
    const SizedBox(height: GainerSpacing.xs),
    GainerPillButton(
      label: 'Gerätewechsel bestätigen',
      expand: true,
      onPressed: !_model.isOnline || _model.isBusy ? null : _confirmAndComplete,
    ),
  ];

  Widget _handoverCodeCard(
    BuildContext context,
    PendingHandoverRecord pending,
  ) {
    final colors = GainerDesign.colorsOf(context);
    final expired =
        pending.expiresAtUtc?.isBefore(DateTime.now().toUtc()) ?? true;
    return GainerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            expired ? 'Übergabe abgelaufen' : 'Übergabe bereit',
            style: GainerTypography.cardTitle.copyWith(
              color: expired ? colors.warning : colors.primaryText,
            ),
          ),
          const SizedBox(height: GainerSpacing.xs),
          Text(
            'Teile diese Daten nur direkt mit deinem neuen Gerät. Der Einmalcode ist ein Geheimnis und wird nach kurzer Zeit ungültig.',
            style: GainerTypography.body.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: GainerSpacing.s),
          _copyValue(context, 'Übergabe-ID', pending.handoverId),
          _copyValue(context, 'Einmalcode', pending.oneTimeCode, secret: true),
          _copyValue(context, 'Quellgerät-ID', pending.sourceClientId),
          _copyValue(
            context,
            'Eingefrorene Revision',
            pending.frozenRevision?.toString(),
          ),
          _copyValue(
            context,
            'Ablaufzeit UTC',
            pending.expiresAtUtc?.toUtc().toIso8601String(),
          ),
          const SizedBox(height: GainerSpacing.s),
          GainerPillButton(
            label: 'Übergabedaten kopieren',
            expand: true,
            onPressed: _model.isBusy ? null : _confirmAndCopyBundle,
          ),
        ],
      ),
    );
  }

  Widget _bundlePasteField(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: GainerSpacing.xs),
      child: CupertinoTextField(
        controller: _transferBundle,
        placeholder: 'Übergabepaket einfügen',
        maxLines: 5,
        minLines: 3,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: GainerTypography.body.copyWith(color: colors.primaryText),
        placeholderStyle: GainerTypography.body.copyWith(
          color: colors.placeholderText,
        ),
        padding: const EdgeInsets.all(GainerSpacing.s),
        decoration: BoxDecoration(
          color: colors.elevatedSurface,
          borderRadius: BorderRadius.circular(GainerRadii.field),
        ),
      ),
    );
  }

  Widget _copyValue(
    BuildContext context,
    String label,
    String? value, {
    bool secret = false,
  }) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: GainerSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GainerTypography.label.copyWith(color: colors.secondaryText),
          ),
          const SizedBox(height: 2),
          Text(
            _copyValueText(value, secret: secret),
            style: GainerTypography.body.copyWith(color: colors.primaryText),
          ),
          if (secret && value != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _model.isBusy ? null : () => _revealCode(value),
              child: const Text('Einmalcode anzeigen'),
            ),
        ],
      ),
    );
  }

  String _copyValueText(String? value, {required bool secret}) {
    if (value == null) return 'Nicht verfügbar';
    return secret ? '••••••••' : value;
  }

  Widget _conflictCard(BuildContext context, LocalConflictRecord conflict) {
    final colors = GainerDesign.colorsOf(context);
    final detail = conflict.detail;
    final detailText = detail is Map<String, Object?>
        ? (detail['message'] ?? detail['reason'] ?? conflict.code).toString()
        : conflict.code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GainerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_aggregateLabel(conflict.aggregateType)} · ${conflict.aggregateId}',
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detailText,
              style: GainerTypography.body.copyWith(color: colors.warning),
            ),
            const SizedBox(height: 4),
            Text(
              'Gemeldet ${conflict.createdAtUtc.toLocal()}',
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: GainerSpacing.s),
            Row(
              children: [
                Expanded(
                  child: GainerPillButton(
                    label: 'Serverstand nutzen',
                    variant: GainerPillVariant.tonal,
                    expand: true,
                    onPressed: _model.isBusy || !widget.isOnline
                        ? null
                        : () => _confirmConflictResolution(
                            conflict,
                            retryLocal: false,
                          ),
                  ),
                ),
                const SizedBox(width: GainerSpacing.xs),
                Expanded(
                  child: GainerPillButton(
                    label: 'Lokale Änderung erneut senden',
                    expand: true,
                    onPressed: _model.isBusy || !widget.isOnline
                        ? null
                        : () => _confirmConflictResolution(
                            conflict,
                            retryLocal: true,
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndBegin() async {
    if (!await _confirm(
          title: 'Dieses Gerät ablösen?',
          message: 'Lokale Schreibzugriffe werden angehalten. Nur das neue Gerät kann nach erfolgreichem Abschluss wieder schreiben.',
          confirmLabel: 'Übergabe starten',
        ) ||
        !mounted) {
      return;
    }
    await _begin();
  }

  Future<void> _begin() async {
    final result = await _model.beginHandover();
    if (!mounted || result == null) return;
    await _showNotice(
      'Übergabedaten',
      'Der Code wird nur einmal angezeigt. Bewahre ihn sicher auf und gib ihn ausschließlich auf deinem neuen Gerät ein.\n\n${result.oneTimeCode}',
    );
  }

  Future<void> _confirmAndCancel() async {
    if (!await _confirm(
          title: 'Übergabe abbrechen?',
          message: 'Das bisherige Gerät erhält nach Bestätigung wieder Schreibzugriff. Der Einmalcode wird ungültig.',
          confirmLabel: 'Abbrechen',
          destructive: true,
        ) ||
        !mounted) {
      return;
    }
    await _model.cancelHandover();
  }

  Future<void> _confirmAndComplete() async {
    if (!await _confirm(
          title: 'Gerätewechsel bestätigen?',
          message: 'Das neue Gerät übernimmt den Schreibzugriff. Das bisherige Gerät wird dabei abgelöst.',
          confirmLabel: 'Übernehmen',
          destructive: true,
        ) ||
        !mounted) {
      return;
    }
    final expiry = DateTime.tryParse(_expiresAtUtc.text.trim());
    if (expiry == null ||
        !RegExp(
          r'(?:Z|\+00:00)$',
          caseSensitive: false,
        ).hasMatch(_expiresAtUtc.text.trim())) {
      _model.reportInputError('Ablaufzeit bitte im ISO-8601-Format eingeben.');
      return;
    }
    await _model.completeHandover(
      handoverId: _handoverId.text,
      oneTimeCode: _oneTimeCode.text,
      sourceClientId: _sourceClientId.text,
      frozenRevision: _revision.text,
      expiresAtUtc: expiry,
    );
  }

  Future<void> _parseTransferBundle() async {
    try {
      final bundle = _model.parseTransferBundle(_transferBundle.text);
      setState(() => _parsedTransferBundle = bundle);
      _handoverId.text = bundle.handoverId;
      _oneTimeCode.text = bundle.oneTimeCode;
      _sourceClientId.text = bundle.sourceClientId;
      _revision.text = bundle.frozenRevision.toString();
      _expiresAtUtc.text = bundle.expiresAtUtc.toIso8601String();
      _model.reportStatus(
        'Übergabedaten sind gültig. Prüfe die Details und bestätige den Gerätewechsel.',
      );
    } catch (_) {
      setState(() => _parsedTransferBundle = null);
      _model.reportInputError(
        'Übergabepaket ungültig, abgelaufen oder für ein anderes Konto beziehungsweise API bestimmt.',
      );
    }
  }

  Future<void> _pasteAndParseTransferBundle() async {
    if (_transferBundle.text.trim().isEmpty) {
      try {
        final clipboard = await Clipboard.getData('text/plain');
        if (!mounted) return;
        final contents = clipboard?.text;
        if (contents == null || contents.isEmpty) {
          _model.reportInputError(
            'In der Zwischenablage wurden keine Übergabedaten gefunden.',
          );
          return;
        }
        _transferBundle.text = contents;
      } catch (_) {
        _model.reportInputError('Zwischenablage kann nicht gelesen werden.');
        return;
      }
    }
    await _parseTransferBundle();
  }

  Future<void> _confirmAndCopyBundle() async {
    if (!await _confirm(
          title: 'Übergabedaten kopieren?',
          message: 'Das Paket enthält einen kurzlebigen Einmalcode. Es wird in die Zwischenablage kopiert und kann dort anderen Apps zugänglich sein.',
          confirmLabel: 'Kopieren',
        ) ||
        !mounted) {
      return;
    }
    final bundle = _model.createTransferBundle();
    if (bundle == null) return;
    await Clipboard.setData(ClipboardData(text: bundle));
    if (!mounted) return;
    _model.reportStatus(
      'Übergabedaten kopiert. Füge sie nur in deinem neuen Gerät ein.',
    );
  }

  Future<void> _confirmConflictResolution(
    LocalConflictRecord conflict, {
    required bool retryLocal,
  }) async {
    final confirmed = await _confirm(
      title: retryLocal
          ? 'Lokale Änderung erneut senden?'
          : 'Serverstand übernehmen?',
      message: retryLocal
          ? 'Die ausstehende lokale Änderung wird mit einer neuen sicheren Änderungs-ID gegen die aktuelle Serverversion gesendet. Der Vorgang kann erneut abgelehnt werden.'
          : 'Die ausstehende lokale Änderung für diesen Eintrag wird verworfen und durch den letzten Serverstand ersetzt.',
      confirmLabel: retryLocal ? 'Erneut senden' : 'Serverstand nutzen',
      destructive: !retryLocal,
    );
    if (!confirmed || !mounted) return;
    if (retryLocal) {
      await _model.retryLocalVersion(conflict.conflictId);
    } else {
      await _model.acceptServerVersion(conflict.conflictId);
    }
  }

  Future<void> _revealCode(String code) => _showNotice(
    'Einmalcode anzeigen',
    'Teile diesen Code nur mit deinem neuen Gerät.\n\n$code',
  );

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async =>
      await showGainerStackedDialog<bool>(
        context: context,
        title: title,
        message: message,
        actions: [
          GainerDialogAction<bool>(
            label: confirmLabel,
            value: true,
            destructive: destructive,
          ),
          const GainerDialogAction<bool>(label: 'Zurück', value: false),
        ],
      ) ??
      false;

  Future<void> _showNotice(String title, String message) async {
    await showGainerStackedDialog<bool>(
      context: context,
      title: title,
      message: message,
      actions: const [
        GainerDialogAction<bool>(label: 'Schließen', value: true),
      ],
    );
  }

  Widget _field(
    BuildContext context,
    TextEditingController controller,
    String label, {
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: GainerSpacing.xs),
      child: CupertinoTextField(
        controller: controller,
        placeholder: label,
        obscureText: obscure,
        keyboardType: keyboard,
        autocorrect: false,
        autofillHints: const [],
        textInputAction: TextInputAction.next,
        style: GainerTypography.body.copyWith(color: colors.primaryText),
        placeholderStyle: GainerTypography.body.copyWith(
          color: colors.placeholderText,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: GainerSpacing.s,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: colors.elevatedSurface,
          borderRadius: BorderRadius.circular(GainerRadii.field),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
    text,
    style: GainerTypography.cardTitle.copyWith(
      color: GainerDesign.colorsOf(context).primaryText,
    ),
  );

  String _aggregateLabel(String type) => switch (type) {
    'workout' => 'Training',
    'daily-check-in' => 'Check-in',
    'nutrition-day' => 'Ernährung',
    'body-goal' => 'Körperziel',
    _ => 'Eintrag',
  };
}

class _CardText extends StatelessWidget {
  const _CardText(this.text, {this.warning = false});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerCard(
      child: Text(
        text,
        style: GainerTypography.body.copyWith(
          color: warning ? colors.warning : colors.primaryText,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: GainerSpacing.s),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GainerTypography.body.copyWith(
          color: isError ? colors.destructive : colors.primaryText,
        ),
      ),
    );
  }
}

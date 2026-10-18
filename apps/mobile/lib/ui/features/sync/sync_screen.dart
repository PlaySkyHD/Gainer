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
    builder: (context, _) => GainerScaffold(
      title: 'Sync & Gerät',
      children: [
        if (_model.errorMessage case final message?)
          _Message(message: message, isError: true),
        if (_model.statusMessage case final message?)
          _Message(message: message, isError: false),
        GainerGroupedSection(
          header: 'Verbindung',
          footer: widget.isOnline
              ? 'Änderungen werden sicher mit deinem Konto abgeglichen.'
              : 'Offline: lokale Änderungen bleiben auf diesem Gerät gespeichert.',
          children: [
            GainerListRow(
              title: 'Status aktualisieren',
              leadingIcon: CupertinoIcons.arrow_clockwise,
              onTap: _model.isBusy || _model.isLoading ? null : _model.load,
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        ..._handoverSections(context),
        const SizedBox(height: GainerSpacing.l),
        ..._conflictSection(context),
      ],
    ),
  );

  List<Widget> _handoverSections(BuildContext context) {
    final pending = _model.pendingHandover;
    if (pending == null) {
      return [
        GainerGroupedSection(
          header: 'Gerätewechsel',
          footer: 'Starte die Übergabe auf dem bisherigen Gerät. Danach gibst du die angezeigten Übergabedaten auf dem neuen Gerät ein.',
          children: [
            GainerListRow(
              title: 'Dieses Gerät ablösen',
              leadingIcon: CupertinoIcons.arrow_2_squarepath,
              showChevron: true,
              onTap: !_model.isOnline || _model.isBusy || _model.isLoading
                  ? null
                  : _confirmAndBegin,
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        ..._receiveHandoverSections(context),
      ];
    }
    return _pendingHandoverSections(context, pending);
  }

  List<Widget> _conflictSection(BuildContext context) {
    if (_model.isLoading) {
      return [
        GainerGroupedSection(
          header: 'Sync-Konflikte',
          children: const [
            Padding(
              padding: EdgeInsets.all(GainerSpacing.m),
              child: Center(child: CupertinoActivityIndicator()),
            ),
          ],
        ),
      ];
    }
    return [
      GainerGroupedSection(
        header: 'Sync-Konflikte',
        children: _model.conflicts.isEmpty
            ? const [GainerListRow(title: 'Keine ungelösten Konflikte')]
            : [
                for (final conflict in _model.conflicts)
                  ..._conflictRows(conflict),
              ],
      ),
    ];
  }

  List<Widget> _pendingHandoverSections(
    BuildContext context,
    PendingHandoverRecord pending,
  ) => switch (pending.phase) {
    'sourceBeginPending' => [
      GainerGroupedSection(
        header: 'Gerätewechsel',
        footer: 'Die Anfrage wird sicher fortgesetzt. Schreibzugriffe bleiben bis zum Abschluss angehalten.',
        children: [
          GainerListRow(
            title: 'Übergabe fortsetzen',
            leadingIcon: CupertinoIcons.arrow_right_circle,
            showChevron: true,
            onTap: !_model.isOnline || _model.isBusy ? null : _begin,
          ),
        ],
      ),
    ],
    'sourceBegan' => [
      ..._handoverCodeSections(context, pending),
      const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        children: [
          GainerListRow(
            title: 'Übergabe abbrechen',
            leadingIcon: CupertinoIcons.xmark_circle,
            showChevron: true,
            onTap: !_model.isOnline || _model.isBusy ? null : _confirmAndCancel,
          ),
        ],
      ),
    ],
    'targetCompletePending' => _targetCompletePendingSections(pending),
    _ => [
      _Footnote(
        'Für dieses Gerät liegt ein Übergabeschritt vor, den die App nicht sicher zuordnen kann. Es wurden keine Schreibrechte geändert.',
        warning: true,
      ),
    ],
  };

  List<Widget> _targetCompletePendingSections(PendingHandoverRecord pending) {
    final expired =
        pending.expiresAtUtc?.isBefore(DateTime.now().toUtc()) ?? false;
    return [
      GainerGroupedSection(
        header: 'Übernahme',
        footer: expired
            ? 'Die gespeicherte Übernahme ist abgelaufen. Du kannst sie erneut mit denselben Daten abgleichen oder dieses Gerät nach einer Serverprüfung lokal freigeben.'
            : 'Die Übernahme ist gespeichert und kann nach einem Abbruch oder Neustart wiederholt werden.',
        children: [
          GainerListRow(
            title: 'Übernahme fortsetzen',
            leadingIcon: CupertinoIcons.arrow_right_circle,
            showChevron: true,
            onTap: !_model.isOnline || _model.isBusy
                ? null
                : _model.resumeTargetHandover,
          ),
          if (expired)
            GainerListRow(
              title: 'Nach Serverprüfung lokal freigeben',
              leadingIcon: CupertinoIcons.checkmark_seal,
              showChevron: true,
              onTap: !_model.isOnline || _model.isBusy
                  ? null
                  : _model.recoverExpiredTargetHandover,
            ),
        ],
      ),
    ];
  }

  List<Widget> _receiveHandoverSections(BuildContext context) => [
    GainerGroupedSection(
      header: 'Übergabe annehmen',
      footer: 'Füge das Übergabepaket vom bisherigen Gerät ein. Es wird gegen dein angemeldetes Konto und diese API geprüft, bevor Schreibrechte wechseln.',
      children: [
        _bundlePasteField(context),
        if (_parsedTransferBundle case final bundle?)
          _Footnote(
            'Quellgerät ${bundle.sourceClientId} · Revision ${bundle.frozenRevision} · Ablauf ${bundle.expiresAtUtc.toLocal()} · Einmalcode erkannt',
          ),
        GainerListRow(
          title: 'Übergabedaten einfügen',
          leadingIcon: CupertinoIcons.doc_on_clipboard,
          showChevron: true,
          onTap: _model.isBusy ? null : _pasteAndParseTransferBundle,
        ),
        GainerListRow(
          title: _showAdvancedHandoverFields
              ? 'Manuelle Eingabe ausblenden'
              : 'Manuell eingeben (erweitert)',
          leadingIcon: CupertinoIcons.pencil,
          onTap: () => setState(
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
      ],
    ),
    const SizedBox(height: GainerSpacing.l),
    GainerPillButton(
      label: 'Gerätewechsel bestätigen',
      expand: true,
      onPressed: !_model.isOnline || _model.isBusy ? null : _confirmAndComplete,
    ),
  ];

  List<Widget> _handoverCodeSections(
    BuildContext context,
    PendingHandoverRecord pending,
  ) {
    final expired =
        pending.expiresAtUtc?.isBefore(DateTime.now().toUtc()) ?? true;
    return [
      GainerGroupedSection(
        header: expired ? 'Übergabe abgelaufen' : 'Übergabe bereit',
        footer: 'Teile diese Daten nur direkt mit deinem neuen Gerät. Der Einmalcode ist ein Geheimnis und wird nach kurzer Zeit ungültig.',
        children: [
          _copyRow('Übergabe-ID', pending.handoverId),
          _copyRow('Einmalcode', pending.oneTimeCode, secret: true),
          _copyRow('Quellgerät-ID', pending.sourceClientId),
          _copyRow('Eingefrorene Revision', pending.frozenRevision?.toString()),
          _copyRow(
            'Ablaufzeit UTC',
            pending.expiresAtUtc?.toUtc().toIso8601String(),
          ),
          GainerListRow(
            title: 'Übergabedaten kopieren',
            leadingIcon: CupertinoIcons.doc_on_doc,
            showChevron: true,
            onTap: _model.isBusy ? null : _confirmAndCopyBundle,
          ),
        ],
      ),
    ];
  }

  Widget _bundlePasteField(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return CupertinoTextField(
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
      padding: const EdgeInsets.all(GainerSpacing.m),
      decoration: const BoxDecoration(),
    );
  }

  GainerListRow _copyRow(String label, String? value, {bool secret = false}) {
    return GainerListRow(
      title: label,
      value: _copyValueText(value, secret: secret),
      showChevron: secret && value != null,
      onTap: secret && value != null && !_model.isBusy
          ? () => _revealCode(value)
          : null,
    );
  }

  String _copyValueText(String? value, {required bool secret}) {
    if (value == null) return 'Nicht verfügbar';
    return secret ? '••••••••' : value;
  }

  List<Widget> _conflictRows(LocalConflictRecord conflict) {
    final detail = conflict.detail;
    final detailText = detail is Map<String, Object?>
        ? (detail['message'] ?? detail['reason'] ?? conflict.code).toString()
        : conflict.code;
    final enabled = !_model.isBusy && widget.isOnline;
    return [
      GainerListRow(
        title:
            '${_aggregateLabel(conflict.aggregateType)} · ${conflict.aggregateId}',
        subtitle: detailText,
        leadingIcon: CupertinoIcons.exclamationmark_triangle,
      ),
      _Footnote('Gemeldet ${conflict.createdAtUtc.toLocal()}'),
      GainerListRow(
        title: 'Serverstand nutzen',
        leadingIcon: CupertinoIcons.cloud_download,
        showChevron: true,
        onTap: enabled
            ? () => _confirmConflictResolution(conflict, retryLocal: false)
            : null,
      ),
      GainerListRow(
        title: 'Lokale Änderung erneut senden',
        leadingIcon: CupertinoIcons.arrow_up_circle,
        showChevron: true,
        onTap: enabled
            ? () => _confirmConflictResolution(conflict, retryLocal: true)
            : null,
      ),
    ];
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
    return CupertinoTextField(
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
        horizontal: GainerSpacing.m,
        vertical: GainerSpacing.s,
      ),
      decoration: const BoxDecoration(),
    );
  }

  String _aggregateLabel(String type) => switch (type) {
    'workout' => 'Training',
    'daily-check-in' => 'Check-in',
    'nutrition-day' => 'Ernährung',
    'body-goal' => 'Körperziel',
    _ => 'Eintrag',
  };
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text, {this.warning = false});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GainerSpacing.m,
        GainerSpacing.xs,
        GainerSpacing.m,
        GainerSpacing.xs,
      ),
      child: Text(
        text,
        style: GainerTypography.label.copyWith(
          color: warning ? colors.warning : colors.secondaryText,
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

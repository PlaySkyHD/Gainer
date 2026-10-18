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
    final enabled = !_model.isBusy && widget.isOnline;
    return [
      GainerGroupedSection(
        header: 'Sync-Konflikte',
        footer: _model.isSelecting
            ? '${_model.selectedConflictIds.length} von ${_model.conflicts.length} ausgewählt'
            : null,
        children: _model.conflicts.isEmpty
            ? const [GainerListRow(title: 'Keine ungelösten Konflikte')]
            : [
                if (_model.isSelecting) ...[
                  GainerListRow(
                    key: const ValueKey('sync-select-all'),
                    title: _model.allSelected
                        ? 'Auswahl aufheben'
                        : 'Alle auswählen',
                    leadingIcon: CupertinoIcons.checkmark_circle,
                    onTap: _model.toggleSelectAll,
                  ),
                  GainerListRow(
                    key: const ValueKey('sync-select-done'),
                    title: 'Auswahl beenden',
                    leadingIcon: CupertinoIcons.xmark_circle,
                    onTap: _model.stopSelecting,
                  ),
                ] else
                  GainerListRow(
                    key: const ValueKey('sync-select-start'),
                    title: 'Auswählen',
                    leadingIcon: CupertinoIcons.checkmark_circle,
                    onTap: _model.isBusy ? null : _model.startSelecting,
                  ),
                for (final conflict in _model.conflicts) _conflictRow(conflict),
              ],
      ),
      if (_model.isSelecting && _model.conflicts.isNotEmpty) ...[
        const SizedBox(height: GainerSpacing.m),
        GainerPillButton(
          key: const ValueKey('sync-force-selected'),
          label: 'Lokalen Stand erzwingen',
          icon: CupertinoIcons.arrow_up_circle,
          expand: true,
          onPressed: enabled && _model.forceableSelection.isNotEmpty
              ? () => _confirmForce(_model.forceableSelection)
              : null,
        ),
        const SizedBox(height: GainerSpacing.s),
        GainerPillButton(
          key: const ValueKey('sync-accept-selected'),
          label: 'Serverstand übernehmen',
          icon: CupertinoIcons.cloud_download,
          variant: GainerPillVariant.tonal,
          expand: true,
          onPressed: enabled && _model.acceptableSelection.isNotEmpty
              ? () => _confirmAccept(_model.acceptableSelection)
              : null,
        ),
      ],
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
    // Erst mit vollständigen Übergabedaten bestätigbar, sonst gäbe es nur
    // einen Formatfehler ohne Hinweis, was fehlt.
    ListenableBuilder(
      listenable: Listenable.merge([
        _handoverId,
        _oneTimeCode,
        _sourceClientId,
        _revision,
        _expiresAtUtc,
      ]),
      builder: (context, _) => GainerPillButton(
        key: const ValueKey('sync-confirm-handover'),
        label: 'Gerätewechsel bestätigen',
        expand: true,
        onPressed: !_model.isOnline || _model.isBusy || !_hasHandoverData
            ? null
            : _confirmAndComplete,
      ),
    ),
  ];

  bool get _hasHandoverData => [
    _handoverId,
    _oneTimeCode,
    _sourceClientId,
    _revision,
    _expiresAtUtc,
  ].every((field) => field.text.trim().isNotEmpty);

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

  Widget _conflictRow(LocalConflictRecord conflict) {
    final info = _model.resourceInfos[conflict.conflictId];
    final selected = _model.selectedConflictIds.contains(conflict.conflictId);
    final enabled = !_model.isBusy && widget.isOnline;
    return GainerListRow(
      key: ValueKey('sync-conflict-${conflict.conflictId}'),
      title: _conflictTitle(conflict, info?.title),
      subtitle:
          '${_conflictReason(conflict)} · ${_formatDate(conflict.createdAtUtc)}',
      leadingIcon: _model.isSelecting
          ? (selected
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.circle)
          : CupertinoIcons.exclamationmark_triangle,
      showChevron: !_model.isSelecting,
      onTap: _model.isSelecting
          ? () => _model.toggleSelection(conflict.conflictId)
          : enabled
          ? () => _showConflictActions(conflict, info?.title)
          : null,
    );
  }

  Future<void> _showConflictActions(
    LocalConflictRecord conflict,
    String? title,
  ) async {
    final id = conflict.conflictId;
    final canRetry =
        _model.hasServerState(id) &&
        !_retryBlockedCodes.contains(conflict.code);
    final action = await showGainerActionSheet<_ConflictAction>(
      context: context,
      title: _conflictTitle(conflict, title),
      groups: [
        [
          if (_model.canForce(id))
            const GainerSheetAction(
              label: 'Lokalen Stand erzwingen',
              icon: CupertinoIcons.arrow_up_circle,
              value: _ConflictAction.force,
              hint: 'Ersetzt wartende Änderungen durch den lokalen Stand',
            ),
          if (_model.hasServerState(id))
            const GainerSheetAction(
              label: 'Serverstand nutzen',
              icon: CupertinoIcons.cloud_download,
              value: _ConflictAction.server,
              destructive: true,
            ),
          if (canRetry)
            const GainerSheetAction(
              label: 'Lokale Änderung erneut senden',
              icon: CupertinoIcons.arrow_up_circle,
              value: _ConflictAction.retry,
            ),
        ],
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _ConflictAction.force:
        await _confirmForce([id]);
      case _ConflictAction.server:
        await _confirmAccept([id]);
      case _ConflictAction.retry:
        await _confirmRetry(conflict);
    }
  }

  String _conflictTitle(LocalConflictRecord conflict, String? title) =>
      '${_aggregateLabel(conflict.aggregateType)} · ${title ?? _shortId(conflict.aggregateId)}';

  String _shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  String _conflictReason(LocalConflictRecord conflict) =>
      switch (conflict.code) {
        'active_workout_exists' => 'Ein anderes Training war noch aktiv',
        'validation_failed' =>
          conflict.aggregateType == 'workout' ||
                  conflict.aggregateType == 'training-plan'
              ? 'Übung oder Plan fehlt auf dem Server'
              : 'Der Server hat die Daten abgelehnt',
        'stale_base_version' ||
        'version_conflict' => 'Auf dem Server gibt es eine neuere Version',
        'resource_not_found' => 'Auf dem Server nicht gefunden',
        _ => 'Der Server hat die Änderung abgelehnt',
      };

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

  Future<void> _confirmForce(List<String> ids) async {
    final many = ids.length > 1;
    final confirmed = await _confirm(
      title: many
          ? 'Lokalen Stand für ${ids.length} Einträge erzwingen?'
          : 'Lokalen Stand erzwingen?',
      message:
          'Wartende Änderungen ${many ? 'dieser Einträge werden' : 'dieses Eintrags werden'} durch den aktuellen lokalen Stand ersetzt und gesendet. Der Serverstand ${many ? 'dieser Einträge wird' : 'dieses Eintrags wird'} dabei überschrieben. Gelöschte Einträge bleiben gelöscht. Danach startet ein Sync.',
      confirmLabel: 'Erzwingen',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _model.forceLocalStates(ids);
  }

  Future<void> _confirmAccept(List<String> ids) async {
    final many = ids.length > 1;
    final confirmed = await _confirm(
      title: many
          ? 'Serverstand für ${ids.length} Einträge übernehmen?'
          : 'Serverstand übernehmen?',
      message:
          'Die ausstehenden lokalen Änderungen ${many ? 'dieser Einträge werden' : 'dieses Eintrags werden'} verworfen und durch den letzten Serverstand ersetzt.',
      confirmLabel: 'Serverstand nutzen',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _model.acceptServerVersions(ids);
  }

  Future<void> _confirmRetry(LocalConflictRecord conflict) async {
    final confirmed = await _confirm(
      title: 'Lokale Änderung erneut senden?',
      message: 'Die ausstehende lokale Änderung wird mit einer neuen sicheren Änderungs-ID gegen die aktuelle Serverversion gesendet. Der Vorgang kann erneut abgelehnt werden.',
      confirmLabel: 'Erneut senden',
    );
    if (!confirmed || !mounted) return;
    await _model.retryLocalVersion(conflict.conflictId);
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
    'training-plan' => 'Plan',
    'workout-rotation' => 'Rotation',
    'custom-exercise' => 'Übung',
    'exercise-category' => 'Kategorie',
    'daily-check-in' => 'Check-in',
    'nutrition-day' => 'Ernährung',
    'body-goal' => 'Körperziel',
    _ => 'Eintrag',
  };
}

enum _ConflictAction { force, server, retry }

/// Diese Codes lassen sich durch erneutes Senden derselben Nutzlast nicht beheben.
const _retryBlockedCodes = {'active_workout_exists', 'validation_failed'};

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

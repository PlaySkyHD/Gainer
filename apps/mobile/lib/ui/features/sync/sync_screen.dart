import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../data/models/local/local_mutation.dart';
import '../../../data/repositories/sync/sync_repository.dart';
import '../../../data/services/local/pending_handover_secret_store.dart';
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
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('Sync & Gerät')),
    child: SafeArea(
      child: AnimatedBuilder(
        animation: _model,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              widget.isOnline
                  ? 'Änderungen werden sicher mit deinem Konto abgeglichen.'
                  : 'Offline: lokale Änderungen bleiben auf diesem Gerät gespeichert.',
              style: CupertinoTheme.of(context).textTheme.textStyle,
            ),
            if (_model.errorMessage case final message?)
              _Message(message: message, isError: true),
            if (_model.statusMessage case final message?)
              _Message(message: message, isError: false),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Gerätewechsel'),
            const SizedBox(height: 8),
            _handoverPanel(context),
            const SizedBox(height: 28),
            _sectionTitle(context, 'Sync-Konflikte'),
            const SizedBox(height: 8),
            if (_model.isLoading)
              const Center(child: CupertinoActivityIndicator())
            else if (_model.conflicts.isEmpty)
              const _CardText('Keine ungelösten Konflikte.')
            else
              for (final conflict in _model.conflicts)
                _conflictCard(context, conflict),
            const SizedBox(height: 24),
            CupertinoButton(
              onPressed: _model.isBusy || _model.isLoading ? null : _model.load,
              child: const Text('Status aktualisieren'),
            ),
          ],
        ),
      ),
    ),
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
          const SizedBox(height: 8),
          CupertinoButton.filled(
            onPressed: !_model.isOnline || _model.isBusy || _model.isLoading
                ? null
                : _confirmAndBegin,
            child: const Text('Dieses Gerät ablösen'),
          ),
        ] else if (pending.phase == 'sourceBeginPending') ...[
          const _CardText(
            'Die Anfrage wird sicher fortgesetzt. Schreibzugriffe bleiben bis zum Abschluss angehalten.',
          ),
          CupertinoButton.filled(
            onPressed: !_model.isOnline || _model.isBusy ? null : _begin,
            child: const Text('Übergabe fortsetzen'),
          ),
        ] else if (pending.phase == 'sourceBegan') ...[
          _handoverCodeCard(context, pending),
          const SizedBox(height: 8),
          CupertinoButton(
            onPressed: !_model.isOnline || _model.isBusy
                ? null
                : _confirmAndCancel,
            child: const Text('Übergabe abbrechen'),
          ),
        ] else if (pending.phase == 'targetCompletePending') ...[
          _CardText(
            pending.expiresAtUtc?.isBefore(DateTime.now().toUtc()) ?? false
                ? 'Die gespeicherte Übernahme ist abgelaufen. Du kannst sie erneut mit denselben Daten abgleichen oder dieses Gerät nach einer Serverprüfung lokal freigeben.'
                : 'Die Übernahme ist gespeichert und kann nach einem Abbruch oder Neustart wiederholt werden.',
          ),
          CupertinoButton.filled(
            onPressed: !_model.isOnline || _model.isBusy
                ? null
                : _model.resumeTargetHandover,
            child: const Text('Übernahme fortsetzen'),
          ),
          if (pending.expiresAtUtc?.isBefore(DateTime.now().toUtc()) ?? false)
            CupertinoButton(
              onPressed: !_model.isOnline || _model.isBusy
                  ? null
                  : _model.recoverExpiredTargetHandover,
              child: const Text('Nach Serverprüfung lokal freigeben'),
            ),
        ] else ...[
          const _CardText(
            'Für dieses Gerät liegt ein Übergabeschritt vor, den die App nicht sicher zuordnen kann. Es wurden keine Schreibrechte geändert.',
          ),
        ],
        if (pending == null) ...[
          const SizedBox(height: 20),
          _sectionTitle(context, 'Übergabe auf diesem Gerät annehmen'),
          const SizedBox(height: 8),
          const _CardText(
            'Füge das Übergabepaket vom bisherigen Gerät ein. Es wird gegen dein angemeldetes Konto und diese API geprüft, bevor Schreibrechte wechseln.',
          ),
          const SizedBox(height: 8),
          _bundlePasteField(),
          const SizedBox(height: 8),
          CupertinoButton(
            onPressed: _model.isBusy ? null : _pasteAndParseTransferBundle,
            child: const Text('Übergabedaten einfügen'),
          ),
          if (_parsedTransferBundle case final bundle?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _CardText(
                'Quellgerät ${bundle.sourceClientId} · Revision ${bundle.frozenRevision} · Ablauf ${bundle.expiresAtUtc.toLocal()} · Einmalcode erkannt',
              ),
            ),
          CupertinoButton(
            onPressed: () => setState(
              () => _showAdvancedHandoverFields = !_showAdvancedHandoverFields,
            ),
            child: Text(
              _showAdvancedHandoverFields
                  ? 'Manuelle Eingabe ausblenden'
                  : 'Manuell eingeben (erweitert)',
            ),
          ),
          if (_showAdvancedHandoverFields) ...[
            _field(_handoverId, 'Übergabe-ID'),
            _field(_oneTimeCode, 'Einmalcode', obscure: true),
            _field(_sourceClientId, 'Quellgerät-ID'),
            _field(
              _revision,
              'Eingefrorene Revision',
              keyboard: TextInputType.number,
            ),
            _field(_expiresAtUtc, 'Ablaufzeit (UTC, ISO 8601)'),
          ],
          const SizedBox(height: 8),
          CupertinoButton.filled(
            onPressed: !_model.isOnline || _model.isBusy
                ? null
                : _confirmAndComplete,
            child: const Text('Gerätewechsel bestätigen'),
          ),
        ],
      ],
    );
  }

  Widget _handoverCodeCard(
    BuildContext context,
    PendingHandoverRecord pending,
  ) {
    final expired =
        pending.expiresAtUtc?.isBefore(DateTime.now().toUtc()) ?? true;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            expired ? 'Übergabe abgelaufen' : 'Übergabe bereit',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
          const SizedBox(height: 8),
          const Text(
            'Teile diese Daten nur direkt mit deinem neuen Gerät. Der Einmalcode ist ein Geheimnis und wird nach kurzer Zeit ungültig.',
          ),
          const SizedBox(height: 12),
          _copyValue('Übergabe-ID', pending.handoverId),
          _copyValue('Einmalcode', pending.oneTimeCode, secret: true),
          _copyValue('Quellgerät-ID', pending.sourceClientId),
          _copyValue(
            'Eingefrorene Revision',
            pending.frozenRevision?.toString(),
          ),
          _copyValue(
            'Ablaufzeit UTC',
            pending.expiresAtUtc?.toUtc().toIso8601String(),
          ),
          const SizedBox(height: 12),
          CupertinoButton.filled(
            onPressed: _model.isBusy ? null : _confirmAndCopyBundle,
            child: const Text('Übergabedaten kopieren'),
          ),
        ],
      ),
    );
  }

  Widget _bundlePasteField() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: CupertinoTextField(
      controller: _transferBundle,
      placeholder: 'Übergabepaket einfügen',
      maxLines: 5,
      minLines: 3,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );

  Widget _copyValue(String label, String? value, {bool secret = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              value == null
                  ? 'Nicht verfügbar'
                  : secret
                  ? '••••••••'
                  : value,
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

  Widget _conflictCard(BuildContext context, LocalConflictRecord conflict) {
    final detail = conflict.detail;
    final detailText = detail is Map<String, Object?>
        ? (detail['message'] ?? detail['reason'] ?? conflict.code).toString()
        : conflict.code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_aggregateLabel(conflict.aggregateType)} · ${conflict.aggregateId}',
              style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
            ),
            const SizedBox(height: 6),
            Text(detailText),
            const SizedBox(height: 4),
            Text(
              'Gemeldet ${conflict.createdAtUtc.toLocal()}',
              style: TextStyle(
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CupertinoButton(
                    onPressed: _model.isBusy || !widget.isOnline
                        ? null
                        : () => _confirmConflictResolution(
                            conflict,
                            retryLocal: false,
                          ),
                    child: const Text('Serverstand nutzen'),
                  ),
                ),
                Expanded(
                  child: CupertinoButton.filled(
                    onPressed: _model.isBusy || !widget.isOnline
                        ? null
                        : () => _confirmConflictResolution(
                            conflict,
                            retryLocal: true,
                          ),
                    child: const Text('Lokale Änderung erneut senden'),
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
      await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Zurück'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: destructive,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _showNotice(String title, String message) =>
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
          ],
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: CupertinoTextField(
      controller: controller,
      placeholder: label,
      obscureText: obscure,
      keyboardType: keyboard,
      autocorrect: false,
      autofillHints: const [],
      textInputAction: TextInputAction.next,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );

  Widget _sectionTitle(BuildContext context, String text) =>
      Text(text, style: CupertinoTheme.of(context).textTheme.navTitleTextStyle);

  String _aggregateLabel(String type) => switch (type) {
    'workout' => 'Training',
    'daily-check-in' => 'Check-in',
    'nutrition-day' => 'Ernährung',
    'body-goal' => 'Körperziel',
    _ => 'Eintrag',
  };
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

class _CardText extends StatelessWidget {
  const _CardText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => _Card(child: Text(text));
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      message,
      style: TextStyle(
        color: isError
            ? CupertinoColors.systemRed.resolveFrom(context)
            : CupertinoColors.systemGreen.resolveFrom(context),
      ),
      textAlign: TextAlign.center,
    ),
  );
}

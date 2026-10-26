import 'package:flutter/cupertino.dart';

import '../../../data/models/api/strava_api_models.dart';
import '../../../data/repositories/strava/strava_service.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Strava verbinden und einstellen, welche Arten automatisch gesendet werden.
class StravaScreen extends StatefulWidget {
  const StravaScreen({required this.service, required this.online, super.key});

  final StravaService service;
  final bool online;

  @override
  State<StravaScreen> createState() => _StravaScreenState();
}

class _StravaScreenState extends State<StravaScreen> {
  ApiStravaStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.online) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.service.status();
      if (mounted) setState(() => _status = status);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Der Strava-Stand konnte nicht geladen werden. Prüfe deine '
              'Verbindung.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service.connect();
      if (!mounted) return;
      switch (result) {
        case StravaConnectResult.connected:
          final status = await widget.service.status();
          if (mounted) setState(() => _status = status);
        case StravaConnectResult.denied:
          setState(
            () => _error = 'Gainer braucht das Recht, Aktivitäten hochzuladen.',
          );
        case StravaConnectResult.failed:
          setState(() => _error = _connectFailed);
        case StravaConnectResult.cancelled:
          break;
      }
    } on Object {
      if (mounted) setState(() => _error = _connectFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _connectFailed =
      'Die Verbindung mit Strava hat nicht geklappt. Versuche es erneut.';

  Future<void> _update({bool? cardio, bool? strength}) async {
    final previous = _status;
    if (previous == null) return;
    final next = ApiStravaStatus(
      configured: previous.configured,
      connected: previous.connected,
      needsReconnect: previous.needsReconnect,
      athleteName: previous.athleteName,
      exportCardio: cardio ?? previous.exportCardio,
      exportStrength: strength ?? previous.exportStrength,
    );
    // Sperrt beide Schalter, bis die Antwort da ist. Sonst setzt ein
    // fehlgeschlagener erster Request auch die Änderung des zweiten zurück.
    setState(() {
      _status = next;
      _error = null;
      _busy = true;
    });
    try {
      final saved = await widget.service.updateSettings(
        exportCardio: next.exportCardio,
        exportStrength: next.exportStrength,
      );
      if (mounted) setState(() => _status = saved);
    } on Object {
      if (mounted) {
        setState(() {
          _status = previous;
          _error = 'Die Einstellung konnte nicht gespeichert werden.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await confirmGainerDelete(
      context,
      title: 'Strava trennen?',
      message:
          'Gainer sendet keine Einheiten mehr an Strava. Bereits gesendete '
          'Aktivitäten bleiben in Strava.',
      deleteLabel: 'Trennen',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.disconnect();
      final status = await widget.service.status();
      if (mounted) setState(() => _status = status);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Strava konnte nicht getrennt werden.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return GainerScaffold(
      title: 'Strava',
      children: [
        ..._sections(colors),
        if (_error case final message?)
          Padding(
            padding: const EdgeInsets.only(top: GainerSpacing.s),
            child: Text(
              message,
              key: const ValueKey('strava-error'),
              textAlign: TextAlign.center,
              style: GainerTypography.body.copyWith(color: colors.destructive),
            ),
          ),
      ],
    );
  }

  List<Widget> _sections(GainerColors colors) {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(GainerSpacing.l),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }
    final status = _status;
    if (!widget.online || status == null) {
      return [
        GainerGroupedSection(
          footer: widget.online
              ? null
              : 'Strava lässt sich nur mit Verbindung verwalten.',
          children: [
            GainerListRow(
              title: widget.online ? 'Erneut laden' : 'Mit Strava verbinden',
              leadingIcon: widget.online
                  ? CupertinoIcons.arrow_clockwise
                  : CupertinoIcons.link,
              onTap: widget.online ? _load : null,
            ),
          ],
        ),
      ];
    }
    if (!status.configured) {
      return const [
        GainerGroupedSection(
          footer:
              'Strava ist auf dem Server noch nicht eingerichtet. Ohne '
              'Strava-App-Zugang lässt sich kein Konto verbinden.',
          children: [
            GainerListRow(
              title: 'Mit Strava verbinden',
              leadingIcon: CupertinoIcons.link,
            ),
          ],
        ),
      ];
    }
    if (!status.connected) {
      return [
        GainerGroupedSection(
          footer:
              'Gainer sendet neue Cardio-Einheiten mit Pulskurve an Strava. '
              'Krafttraining kannst du danach getrennt einschalten.',
          children: [_connectRow('Mit Strava verbinden')],
        ),
      ];
    }
    return [
      GainerGroupedSection(
        footer: status.needsReconnect
            ? 'Strava-Verbindung abgelaufen. Verbinde erneut, damit Gainer '
                  'wieder Einheiten senden kann.'
            : null,
        children: [
          GainerListRow(
            key: const ValueKey('strava-athlete'),
            title: status.athleteName == null
                ? 'Verbunden'
                : 'Verbunden als ${status.athleteName}',
            leadingIcon: status.needsReconnect
                ? CupertinoIcons.exclamationmark_triangle
                : CupertinoIcons.checkmark_circle_fill,
          ),
          if (status.needsReconnect) _connectRow('Erneut verbinden'),
        ],
      ),
      const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        header: 'Automatisch senden',
        footer:
            'Neue Einheiten gehen kurz nach dem Sync an Strava, nur ab dem '
            'Einschalten. Ältere Cardio-Einheiten sendest du in ihrer '
            'Detailansicht.',
        children: [
          GainerListRow(
            title: 'Cardio-Einheiten',
            leadingIcon: CupertinoIcons.heart_circle,
            trailing: CupertinoSwitch(
              key: const ValueKey('strava-export-cardio'),
              value: status.exportCardio,
              onChanged: _busy ? null : (value) => _update(cardio: value),
            ),
          ),
          GainerListRow(
            title: 'Krafttraining',
            leadingIcon: CupertinoIcons.bolt,
            trailing: CupertinoSwitch(
              key: const ValueKey('strava-export-strength'),
              value: status.exportStrength,
              onChanged: _busy ? null : (value) => _update(strength: value),
            ),
          ),
        ],
      ),
      const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        children: [
          GainerListRow(
            key: const ValueKey('strava-disconnect'),
            title: 'Verbindung trennen',
            leadingIcon: CupertinoIcons.xmark_circle,
            onTap: _busy ? null : _disconnect,
          ),
        ],
      ),
    ];
  }

  Widget _connectRow(String title) {
    final colors = GainerDesign.colorsOf(context);
    return GainerListRow(
      key: const ValueKey('strava-connect'),
      title: title,
      leadingIcon: CupertinoIcons.link,
      trailing: _busy
          ? CupertinoActivityIndicator(color: colors.secondaryText)
          : null,
      onTap: _busy ? null : _connect,
    );
  }
}

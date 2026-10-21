import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../data/services/platform/platform_ports.dart';

/// Schreibt das Diktat live in das Beschreibungsfeld der Mahlzeiten-Schätzung.
/// Vorhandener Text bleibt stehen, das Diktat wird angehängt.
class MealDictationController extends ChangeNotifier {
  MealDictationController({
    required this.platform,
    required this.text,
    this.localeId = 'de-DE',
    this.pollInterval = const Duration(milliseconds: 150),
  });

  final DictationPlatform platform;
  final TextEditingController text;
  final String localeId;
  final Duration pollInterval;

  bool isListening = false;
  bool isStarting = false;
  String? message;
  String _prefix = '';
  Timer? _poll;
  bool _reading = false;
  bool _disposed = false;
  Completer<void>? _done;

  Future<void> toggle() => isListening ? stop() : start();

  Future<void> start() async {
    if (isListening || isStarting) return;
    isStarting = true;
    message = null;
    _prefix = text.text.trim();
    _notify();
    DictationState state;
    try {
      state = await platform.startDictation(localeId: localeId);
    } catch (_) {
      state = const DictationState(
        status: DictationStatus.failed,
        transcript: '',
      );
    }
    isStarting = false;
    if (_disposed) {
      if (state.status == DictationStatus.listening) {
        unawaited(platform.cancelDictation());
      }
      return;
    }
    if (state.status != DictationStatus.listening) {
      message = _messageFor(state.status);
      _notify();
      return;
    }
    isListening = true;
    _done = Completer<void>();
    _notify();
    _poll = Timer.periodic(pollInterval, (_) => _read());
  }

  /// Beendet die Aufnahme; der endgültige Text kommt mit dem nächsten Abruf.
  Future<void> stop() async {
    if (!isListening) return;
    try {
      await platform.stopDictation();
    } catch (_) {
      _finish(DictationStatus.failed);
    }
  }

  /// Beendet ein laufendes Diktat und wartet kurz auf den endgültigen Text.
  Future<void> finish({Duration timeout = const Duration(seconds: 2)}) async {
    final done = _done;
    if (!isListening || done == null) return;
    await stop();
    await done.future.timeout(timeout, onTimeout: () {});
  }

  Future<void> _read() async {
    if (_reading || !isListening) return;
    _reading = true;
    try {
      final state = await platform.readDictation();
      if (_disposed || !isListening) return;
      _apply(state.transcript);
      if (state.status != DictationStatus.listening) _finish(state.status);
    } catch (_) {
      if (!_disposed) _finish(DictationStatus.failed);
    } finally {
      _reading = false;
    }
  }

  void _apply(String transcript) {
    final spoken = transcript.trim();
    final value = [_prefix, spoken].where((part) => part.isNotEmpty).join(' ');
    if (value == text.text) return;
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _finish(DictationStatus status) {
    _poll?.cancel();
    _poll = null;
    isListening = false;
    message = status == DictationStatus.failed ? _messageFor(status) : null;
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
    _notify();
  }

  static String? _messageFor(DictationStatus status) => switch (status) {
    DictationStatus.denied => 'Erlaube Mikrofon und Spracherkennung in den iOS-Einstellungen, um zu diktieren.',
    DictationStatus.unavailable => 'Diktat auf dem Gerät ist für Deutsch gerade nicht verfügbar. Prüfe unter Einstellungen › Allgemein › Tastatur, ob Diktieren und Deutsch geladen sind.',
    DictationStatus.failed => 'Das Diktat hat nichts erkannt. Versuche es erneut oder tippe die Mahlzeit ein.',
    _ => null,
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    if (isListening) unawaited(platform.cancelDictation());
    super.dispose();
  }
}

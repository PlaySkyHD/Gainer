import 'cardio_session.dart';
import 'cardio_zones.dart';

/// Aufgelöste Phase einer gespeicherten oder laufenden Einheit. Der Zielbereich
/// ist in bpm gegeben oder fehlt (beide Grenzen oder keine).
class CardioPhase {
  const CardioPhase({
    required this.startOffsetSeconds,
    required this.durationSeconds,
    required this.name,
    this.lowBpm,
    this.highBpm,
  });

  static const maxPhases = 30;
  static const minDurationSeconds = 30;
  static const maxDurationSeconds = 3600;
  static const maxTotalSeconds = 4 * 3600;
  static const maxNameLength = 60;

  factory CardioPhase.fromJson(Map<String, dynamic> json) => CardioPhase(
    startOffsetSeconds: (json['startOffsetSeconds'] as num).toInt(),
    durationSeconds: (json['durationSeconds'] as num).toInt(),
    name: json['name'] as String,
    lowBpm: (json['lowBpm'] as num?)?.toInt(),
    highBpm: (json['highBpm'] as num?)?.toInt(),
  );

  final int startOffsetSeconds;
  final int durationSeconds;
  final String name;
  final int? lowBpm;
  final int? highBpm;

  int get endOffsetSeconds => startOffsetSeconds + durationSeconds;

  /// Zielbereich der Phase; null ohne Ziel.
  CardioTargetZone? get zone => lowBpm == null || highBpm == null
      ? null
      : CardioTargetZone(lowBpm: lowBpm!, highBpm: highBpm!);

  bool coversSecond(int seconds) =>
      seconds >= startOffsetSeconds && seconds < endOffsetSeconds;

  Map<String, Object?> toJson() => {
    'startOffsetSeconds': startOffsetSeconds,
    'durationSeconds': durationSeconds,
    'name': name,
    'lowBpm': ?lowBpm,
    'highBpm': ?highBpm,
  };

  @override
  bool operator ==(Object other) =>
      other is CardioPhase &&
      other.startOffsetSeconds == startOffsetSeconds &&
      other.durationSeconds == durationSeconds &&
      other.name == name &&
      other.lowBpm == lowBpm &&
      other.highBpm == highBpm;

  @override
  int get hashCode =>
      Object.hash(startOffsetSeconds, durationSeconds, name, lowBpm, highBpm);

  /// Phase zum Zeitpunkt [seconds] seit Start; null außerhalb aller Phasen.
  static CardioPhase? at(List<CardioPhase> phases, int seconds) {
    for (final phase in phases) {
      if (phase.coversSecond(seconds)) return phase;
    }
    return null;
  }

  /// Vom Server akzeptierte Phasen: höchstens 30, aufsteigend, ohne Überlappung,
  /// Dauer 30–3600 s, Name 1–60 Zeichen, Zone beide oder keine und gültig,
  /// insgesamt höchstens 4 h.
  static bool isValidList(List<CardioPhase> phases) {
    if (phases.isEmpty || phases.length > maxPhases) return false;
    var cursor = 0;
    for (final phase in phases) {
      final name = phase.name.trim();
      if (name.isEmpty || name.length > maxNameLength) return false;
      if (phase.durationSeconds < minDurationSeconds ||
          phase.durationSeconds > maxDurationSeconds) {
        return false;
      }
      if (phase.startOffsetSeconds < cursor) return false;
      if ((phase.lowBpm == null) != (phase.highBpm == null)) return false;
      final zone = phase.zone;
      if (zone != null && !zone.isValid) return false;
      cursor = phase.endOffsetSeconds;
    }
    return cursor <= maxTotalSeconds;
  }
}

/// Ziel einer Vorlagenphase: Zone 1–5, bpm-Bereich oder keins.
sealed class CardioPhaseTarget {
  const CardioPhaseTarget();

  factory CardioPhaseTarget.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'zone':
        return CardioZoneTarget((json['zone'] as num).toInt());
      case 'bpm':
        return CardioBpmTarget(
          (json['lowBpm'] as num).toInt(),
          (json['highBpm'] as num).toInt(),
        );
      case 'none':
        return const CardioNoTarget();
    }
    throw FormatException('Unbekanntes Phasenziel: ${json['type']}.');
  }

  Map<String, Object?> toJson();
}

final class CardioZoneTarget extends CardioPhaseTarget {
  const CardioZoneTarget(this.number);

  final int number;

  @override
  Map<String, Object?> toJson() => {'type': 'zone', 'zone': number};

  @override
  bool operator ==(Object other) =>
      other is CardioZoneTarget && other.number == number;

  @override
  int get hashCode => Object.hash('zone', number);
}

final class CardioBpmTarget extends CardioPhaseTarget {
  const CardioBpmTarget(this.low, this.high);

  final int low;
  final int high;

  @override
  Map<String, Object?> toJson() => {
    'type': 'bpm',
    'lowBpm': low,
    'highBpm': high,
  };

  @override
  bool operator ==(Object other) =>
      other is CardioBpmTarget && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash('bpm', low, high);
}

final class CardioNoTarget extends CardioPhaseTarget {
  const CardioNoTarget();

  @override
  Map<String, Object?> toJson() => {'type': 'none'};

  @override
  bool operator ==(Object other) => other is CardioNoTarget;

  @override
  int get hashCode => 'none'.hashCode;
}

/// Phase einer Vorlage, noch ohne bpm-Auflösung.
class CardioTemplatePhase {
  const CardioTemplatePhase({
    required this.name,
    required this.durationSeconds,
    this.target = const CardioNoTarget(),
  });

  factory CardioTemplatePhase.fromJson(Map<String, dynamic> json) =>
      CardioTemplatePhase(
        name: json['name'] as String,
        durationSeconds: (json['durationSeconds'] as num).toInt(),
        target: CardioPhaseTarget.fromJson(
          json['target'] as Map<String, dynamic>,
        ),
      );

  final String name;
  final int durationSeconds;
  final CardioPhaseTarget target;

  CardioTemplatePhase copyWith({
    String? name,
    int? durationSeconds,
    CardioPhaseTarget? target,
  }) => CardioTemplatePhase(
    name: name ?? this.name,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    target: target ?? this.target,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'durationSeconds': durationSeconds,
    'target': target.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is CardioTemplatePhase &&
      other.name == name &&
      other.durationSeconds == durationSeconds &&
      other.target == target;

  @override
  int get hashCode => Object.hash(name, durationSeconds, target);
}

/// Die Vorlage braucht Zonen, aber es ist kein Maximalpuls bekannt.
class CardioTemplateResolutionException implements Exception {
  const CardioTemplateResolutionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Intervall-Vorlage aus Phasen. Mitgelieferte Vorlagen haben feste IDs und
/// sind nicht löschbar.
class CardioTemplate {
  const CardioTemplate({
    required this.id,
    required this.name,
    required this.phases,
    this.builtIn = false,
  });

  static const maxNameLength = 100;
  static const zone2Id = 'builtin-zone2-30';
  static const norwegianId = 'builtin-4x4';

  factory CardioTemplate.fromJson(Map<String, dynamic> json) => CardioTemplate(
    id: json['id'] as String,
    name: json['name'] as String,
    phases: [
      for (final phase in json['phases'] as List)
        CardioTemplatePhase.fromJson(phase as Map<String, dynamic>),
    ],
  );

  final String id;
  final String name;
  final List<CardioTemplatePhase> phases;
  final bool builtIn;

  static const zone2 = CardioTemplate(
    id: zone2Id,
    name: 'Zone 2 – 30 min',
    builtIn: true,
    phases: [
      CardioTemplatePhase(
        name: 'Zone 2',
        durationSeconds: 1800,
        target: CardioZoneTarget(2),
      ),
    ],
  );

  static const norwegian = CardioTemplate(
    id: norwegianId,
    name: '4×4 (Norwegisch)',
    builtIn: true,
    phases: [
      CardioTemplatePhase(
        name: 'Aufwärmen',
        durationSeconds: 600,
        target: CardioZoneTarget(2),
      ),
      CardioTemplatePhase(
        name: 'Belastung',
        durationSeconds: 240,
        target: CardioZoneTarget(4),
      ),
      CardioTemplatePhase(
        name: 'Erholung',
        durationSeconds: 180,
        target: CardioZoneTarget(2),
      ),
      CardioTemplatePhase(
        name: 'Belastung',
        durationSeconds: 240,
        target: CardioZoneTarget(4),
      ),
      CardioTemplatePhase(
        name: 'Erholung',
        durationSeconds: 180,
        target: CardioZoneTarget(2),
      ),
      CardioTemplatePhase(
        name: 'Belastung',
        durationSeconds: 240,
        target: CardioZoneTarget(4),
      ),
      CardioTemplatePhase(
        name: 'Erholung',
        durationSeconds: 180,
        target: CardioZoneTarget(2),
      ),
      CardioTemplatePhase(
        name: 'Belastung',
        durationSeconds: 240,
        target: CardioZoneTarget(4),
      ),
      CardioTemplatePhase(
        name: 'Ausfahren',
        durationSeconds: 300,
        target: CardioZoneTarget(1),
      ),
    ],
  );

  static const builtIns = [zone2, norwegian];

  int get totalSeconds =>
      phases.fold(0, (sum, phase) => sum + phase.durationSeconds);

  /// Braucht mindestens eine Phase eine Zone 1–5?
  bool get needsZones => phases.any((p) => p.target is CardioZoneTarget);

  /// Fehlertext, wenn die Vorlage nicht speicherbar ist; sonst null.
  String? validate() {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Der Name fehlt.';
    if (trimmed.length > maxNameLength) {
      return 'Der Name darf höchstens $maxNameLength Zeichen haben.';
    }
    if (phases.isEmpty) return 'Mindestens eine Phase ist nötig.';
    if (phases.length > CardioPhase.maxPhases) {
      return 'Höchstens ${CardioPhase.maxPhases} Phasen sind möglich.';
    }
    for (var i = 0; i < phases.length; i++) {
      final phase = phases[i];
      final label = 'Phase ${i + 1}';
      final phaseName = phase.name.trim();
      if (phaseName.isEmpty) return '$label braucht einen Namen.';
      if (phaseName.length > CardioPhase.maxNameLength) {
        return '$label: Der Name darf höchstens '
            '${CardioPhase.maxNameLength} Zeichen haben.';
      }
      if (phase.durationSeconds < CardioPhase.minDurationSeconds ||
          phase.durationSeconds > CardioPhase.maxDurationSeconds) {
        return '$label: Die Dauer muss zwischen 0:30 und 60:00 liegen.';
      }
      final target = phase.target;
      if (target is CardioZoneTarget &&
          (target.number < 1 || target.number > 5)) {
        return '$label: Zone 1 bis 5 wählen.';
      }
      if (target is CardioBpmTarget &&
          !CardioTargetZone(lowBpm: target.low, highBpm: target.high).isValid) {
        return '$label: Der Pulsbereich muss zwischen '
            '${CardioTargetZone.minBpm} und ${CardioTargetZone.maxBpm} bpm '
            'liegen, unten kleiner als oben.';
      }
    }
    if (totalSeconds > CardioPhase.maxTotalSeconds) {
      return 'Die Vorlage darf höchstens 4 Stunden dauern.';
    }
    return null;
  }

  CardioTemplate copyWith({
    String? id,
    String? name,
    List<CardioTemplatePhase>? phases,
  }) => CardioTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    phases: phases ?? this.phases,
  );

  /// Übersetzt Zonenziele in bpm. Wirft [CardioTemplateResolutionException],
  /// wenn Zonen gebraucht werden, aber [zones] leer ist.
  List<CardioPhase> resolve(List<CardioZone> zones) {
    var offset = 0;
    final result = <CardioPhase>[];
    for (final phase in phases) {
      int? low;
      int? high;
      final target = phase.target;
      if (target is CardioZoneTarget) {
        if (zones.isEmpty) {
          throw const CardioTemplateResolutionException(
            'Für diese Vorlage fehlen die Pulszonen. Maximalpuls oder Alter '
            'in den Cardio-Einstellungen angeben.',
          );
        }
        final zone = zones.firstWhere(
          (z) => z.number == target.number,
          orElse: () => throw CardioTemplateResolutionException(
            'Zone ${target.number} ist unbekannt.',
          ),
        );
        low = zone.lowBpm;
        high = zone.highBpm;
      } else if (target is CardioBpmTarget) {
        low = target.low;
        high = target.high;
      }
      result.add(
        CardioPhase(
          startOffsetSeconds: offset,
          durationSeconds: phase.durationSeconds,
          name: phase.name.trim(),
          lowBpm: low,
          highBpm: high,
        ),
      );
      offset += phase.durationSeconds;
    }
    return result;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'phases': [for (final phase in phases) phase.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is CardioTemplate &&
      other.id == id &&
      other.name == name &&
      _listEquals(other.phases, phases);

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(phases));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Zone der längsten Phase mit Ziel (für `targetZone` einer Vorlagen-Einheit).
CardioTargetZone? longestPhaseZone(List<CardioPhase> phases) {
  CardioPhase? best;
  for (final phase in phases) {
    if (phase.zone == null) continue;
    if (best == null || phase.durationSeconds > best.durationSeconds) {
      best = phase;
    }
  }
  return best?.zone;
}

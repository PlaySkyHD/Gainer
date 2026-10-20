/// Feste Muskelregionen der Körperkarte. Die Schlüssel entsprechen
/// `MuscleKeys` im Backend.
enum Muscle {
  chest('Brust'),
  frontDelts('Vordere Schulter'),
  sideDelts('Seitliche Schulter'),
  rearDelts('Hintere Schulter'),
  biceps('Bizeps'),
  triceps('Trizeps'),
  forearms('Unterarme'),
  abs('Bauch'),
  obliques('Seitliche Bauchmuskeln'),
  lats('Latissimus'),
  traps('Oberer Rücken'),
  lowerBack('Unterer Rücken'),
  glutes('Gesäß'),
  quads('Quadrizeps'),
  hamstrings('Beinbeuger'),
  adductors('Adduktoren'),
  calves('Waden');

  const Muscle(this.label);

  final String label;

  String get wireValue => name;

  static Muscle? fromWireValue(Object? value) {
    for (final muscle in values) {
      if (muscle.name == value) return muscle;
    }
    return null;
  }

  /// Liest eine Schlüsselliste aus dem Sync. Unbekannte Schlüssel einer
  /// neueren Version fallen weg, Wiederholungen ebenso.
  static List<Muscle> listFromJson(Object? value) {
    if (value is! List) return const [];
    final result = <Muscle>[];
    for (final item in value) {
      final muscle = fromWireValue(item);
      if (muscle != null && !result.contains(muscle)) result.add(muscle);
    }
    return List.unmodifiable(result);
  }

  static List<String> listToJson(List<Muscle> muscles) => [
    for (final muscle in muscles) muscle.wireValue,
  ];
}

/// Höchstzahlen je Übung, wie im Backend geprüft.
const maxPrimaryMuscles = 3;
const maxSecondaryMuscles = 6;

/// Muskelgruppen für Auswahllisten, in Anzeigereihenfolge.
const muscleGroups = <(String, List<Muscle>)>[
  ('Oberkörper', [Muscle.chest, Muscle.frontDelts, Muscle.sideDelts]),
  ('Rücken', [Muscle.lats, Muscle.traps, Muscle.rearDelts, Muscle.lowerBack]),
  ('Arme', [Muscle.biceps, Muscle.triceps, Muscle.forearms]),
  ('Rumpf', [Muscle.abs, Muscle.obliques]),
  (
    'Beine',
    [
      Muscle.glutes,
      Muscle.quads,
      Muscle.hamstrings,
      Muscle.adductors,
      Muscle.calves,
    ],
  ),
];

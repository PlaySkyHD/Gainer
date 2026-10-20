import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/exercise_catalog_model.dart';
import 'package:gainer_mobile/domain/models/training/muscle_suggestion.dart';
import 'package:gainer_mobile/domain/models/training/muscles.dart';
import 'package:gainer_mobile/domain/models/training/workout_model.dart';

CatalogExercise _base(String name, List<Muscle> primary) => CatalogExercise(
  id: name,
  name: name,
  exerciseType: ExerciseKind.strength,
  primaryMuscles: primary,
  isBase: true,
);

final _catalog = [
  _base('Bankdrücken (Langhantel)', [Muscle.chest]),
  _base('Bankdrücken (Kurzhantel)', [Muscle.chest]),
  _base('Schrägbankdrücken (Kurzhantel)', [Muscle.chest]),
  _base('Kniebeugen (Langhantel)', [Muscle.quads]),
  _base('Klimmzüge', [Muscle.lats]),
  _base('Rudern sitzend (Kabelzug)', [Muscle.traps]),
  _base('Seitheben (Kurzhantel)', [Muscle.sideDelts]),
  _base('Beinpresse', [Muscle.quads]),
  _base('Ohne Muskeln', const []),
];

String? _suggest(String name) => suggestMuscleSource(name, _catalog)?.name;

void main() {
  test('exakte und leicht abweichende Namen finden die Katalogübung', () {
    expect(
      _suggest('Schrägbankdrücken Kurzhantel'),
      'Schrägbankdrücken (Kurzhantel)',
    );
    expect(
      _suggest('schraegbankdruecken kh'),
      'Schrägbankdrücken (Kurzhantel)',
    );
    expect(_suggest('Klimmzug'), 'Klimmzüge');
    expect(_suggest('Kniebeuge'), 'Kniebeugen (Langhantel)');
  });

  test('Equipment entscheidet zwischen Varianten', () {
    expect(_suggest('Bankdrücken Kurzhantel'), 'Bankdrücken (Kurzhantel)');
    expect(
      _suggest('Bankdrücken mit der Langhantel'),
      'Bankdrücken (Langhantel)',
    );
  });

  test('englische Namen werden übersetzt', () {
    expect(_suggest('Dumbbell Bench Press'), 'Bankdrücken (Kurzhantel)');
    expect(_suggest('Pull-ups'), 'Klimmzüge');
  });

  test('nur Equipment oder Unbekanntes liefert keinen Vorschlag', () {
    expect(_suggest('Kurzhantel'), isNull);
    expect(_suggest('Landmine Rotation'), isNull);
    expect(_suggest(''), isNull);
    expect(_suggest('Ohne Muskeln'), isNull);
  });
}

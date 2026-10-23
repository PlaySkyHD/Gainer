import '../training/training_schedule.dart';
import 'nutrition.dart';

/// Ziel eines Tages mit der Tagesart, aus der es stammt.
class NutritionDayTargetResult {
  const NutritionDayTargetResult({
    required this.version,
    required this.target,
    required this.kind,
    required this.manual,
  });

  /// Zielversion, die an dem Tag gilt (liefert z. B. die Salzgrenze).
  final NutritionTargetVersion version;

  /// kcal und Makros, die an dem Tag gelten.
  final NutritionDayTarget target;

  /// Tagesart; null, wenn die Version kein Ruhetag-Ziel hat und die Tagesart
  /// deshalb keine Rolle spielt.
  final NutritionDayKind? kind;

  /// Hat der Nutzer die Tagesart für den Tag festgelegt?
  final bool manual;

  double get effectiveSaltGrams => version.effectiveSaltGrams;
}

/// Tagesart ohne Festlegung: Trainingstag, wenn ein Krafttraining beendet
/// wurde oder laut Rhythmus eines ansteht (auch erledigt, verpasst oder
/// hierher verschoben). Sonst Ruhetag, auch ohne Rhythmus.
NutritionDayKind automaticDayKind(
  LocalDay date,
  TrainingScheduleProjection projection,
) {
  if (projection.hasFinishedOn(date)) return NutritionDayKind.training;
  if (projection.day(date).effective.isNotEmpty) {
    return NutritionDayKind.training;
  }
  return NutritionDayKind.rest;
}

/// Ziel an [localDate]: das Ruhetag-Ziel, wenn die Version eines hat und der
/// Tag als Ruhetag zählt, sonst das Ziel der Version. Null ohne Ziele.
NutritionDayTargetResult? dayTarget({
  required String localDate,
  required NutritionTargetSchedule? targets,
  required NutritionDayKind? manualKind,
  required TrainingScheduleProjection projection,
}) {
  final version = targets?.targetOn(localDate);
  if (version == null) return null;
  final rest = version.restDay;
  if (rest == null) {
    return NutritionDayTargetResult(
      version: version,
      target: version.trainingDay,
      kind: null,
      manual: false,
    );
  }
  final kind =
      manualKind ?? automaticDayKind(LocalDay.parse(localDate), projection);
  return NutritionDayTargetResult(
    version: version,
    target: kind == NutritionDayKind.rest ? rest : version.trainingDay,
    kind: kind,
    manual: manualKind != null,
  );
}

import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../data/repositories/training/training_preferences.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/muscles.dart';
import '../../../domain/models/training/warmup.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_validation.dart';
import 'exercise_catalog_format.dart';

/// Rohe Eingaben des Übungseditors. Zahlen bleiben Text, bis sie geprüft werden.
class ExerciseEditorInput {
  const ExerciseEditorInput({
    required this.name,
    required this.kind,
    required this.categoryIds,
    this.notes = '',
    this.bodyweightPercent = '',
    this.weightFactor = '',
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
  });

  final String name;
  final ExerciseKind kind;
  final List<String> categoryIds;
  final String notes;

  /// Körpergewichtsanteil in Prozent, leer = Standard des Übungstyps.
  final String bodyweightPercent;

  /// Zusatzgewichtsfaktor, leer = 1.
  final String weightFactor;

  final List<Muscle> primaryMuscles;
  final List<Muscle> secondaryMuscles;
}

/// Hält eine eigene oder Basisübung für den Editor und prüft Eingaben.
class ExerciseEditorViewModel extends ChangeNotifier {
  ExerciseEditorViewModel({required this.repository, this.exercise});

  final TrainingLogRepository repository;

  /// Bestehende Übung; null beim Anlegen.
  final CatalogExercise? exercise;

  /// Nicht archivierte Kategorien, die zugeordnet werden können.
  List<CatalogCategory> categories = const [];

  /// True, wenn Trainings oder Pläne auf die Übung verweisen.
  bool isUsed = false;

  /// Trainingseinstellungen des Kontos; hier nur für den Abschnitt „Aufwärmen“.
  TrainingPreferenceValues settings = const TrainingPreferenceValues();

  bool isLoading = false;
  bool isSaving = false;
  String? errorMessage;
  Map<String, String> fieldErrors = const {};
  bool _disposed = false;

  bool get isNew => exercise == null;
  bool get isBase => exercise?.isBase ?? false;
  bool get isArchived => exercise?.isArchived ?? false;

  /// Basisübungen sind nur lesbar. Archivierte bleiben lesbar, damit ein
  /// Speichern sie nicht still wieder aktiviert.
  bool get readOnly => isBase || isArchived;

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    _notify();
    try {
      final loadedCategories = await repository.readCategories();
      final used = await _isUsed();
      final loadedSettings = await repository.preferences.read().catchError(
        (_) => const TrainingPreferenceValues(),
      );
      if (_disposed) return;
      categories = loadedCategories;
      isUsed = used;
      settings = loadedSettings;
    } catch (_) {
      if (!_disposed) errorMessage = 'Die Übung konnte nicht geladen werden.';
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  /// Aufwärm-Abweichungen dieser Übung; `null` erbt alles.
  ExerciseWarmupOverride? get warmupOverride =>
      exercise == null ? null : settings.warmupOverrides[exercise!.id];

  /// Ändert die Aufwärm-Abweichungen der Übung und speichert sie lokal. Ein
  /// leeres Ergebnis entfernt den Eintrag.
  Future<void> updateWarmupOverride(
    ExerciseWarmupOverride Function(ExerciseWarmupOverride current) change,
  ) async {
    final id = exercise?.id;
    if (id == null) return;
    TrainingPreferenceValues apply(TrainingPreferenceValues values) {
      final next = change(
        values.warmupOverrides[id] ?? ExerciseWarmupOverride(exerciseId: id),
      );
      final overrides = {...values.warmupOverrides};
      if (next.isEmpty) {
        overrides.remove(id);
      } else {
        overrides[id] = next;
      }
      return values.copyWith(warmupOverrides: overrides);
    }

    settings = apply(settings);
    _notify();
    try {
      await repository.preferences.update(apply);
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Die Einstellung konnte nicht gespeichert werden.';
        _notify();
      }
    }
  }

  /// Kategorien der Übung, die noch angeboten werden. Archivierte fallen weg.
  List<String> activeCategoryIds(Iterable<String> ids) {
    final active = {for (final category in categories) category.id};
    return [
      for (final id in ids)
        if (active.contains(id)) id,
    ];
  }

  /// Typwechsel einer bereits verwendeten Übung braucht eine Bestätigung.
  bool needsTypeChangeConfirmation(ExerciseKind kind) {
    final original = exercise;
    return original != null && isUsed && kind != original.exerciseType;
  }

  /// Speichert die Übung. Liefert true bei Erfolg; sonst stehen Fehler in
  /// [fieldErrors] oder [errorMessage].
  Future<bool> save(ExerciseEditorInput input) async {
    final original = exercise;
    final fields = <String, String>{};
    final bodyweightFactor = _parseBodyweight(input.bodyweightPercent, fields);
    final weightFactor = _parseWeight(input.weightFactor, fields);
    if (fields.isNotEmpty) {
      _setErrors(fields, null);
      return false;
    }

    final draft = CatalogExercise(
      id: original?.id ?? repository.newId(),
      name: input.name.trim(),
      exerciseType: input.kind,
      notes: input.notes.trim().isEmpty ? null : input.notes.trim(),
      bodyweightFactor: bodyweightFactor,
      weightFactor: weightFactor,
      categoryIds: activeCategoryIds(input.categoryIds),
      primaryMuscles: input.primaryMuscles,
      secondaryMuscles: input.secondaryMuscles,
      isBase: false,
      isArchived: original?.isArchived ?? false,
    );

    _startSaving();
    try {
      if (original == null) {
        await repository.createCustomExercise(draft);
      } else {
        await repository.updateCustomExercise(draft);
      }
    } catch (error) {
      if (error is WorkoutValidationException) {
        _setErrors(error.fields, null);
      } else {
        _setErrors(
          const {},
          catalogErrorMessage(
            error,
            'Die Übung konnte nicht gespeichert werden.',
          ),
        );
      }
      return false;
    }
    if (!_disposed) {
      isSaving = false;
      _notify();
    }
    return true;
  }

  /// Archiviert die eigene Übung. Liefert true bei Erfolg.
  Future<bool> archive() async {
    final original = exercise;
    if (original == null || original.isBase) return false;
    _startSaving();
    try {
      await repository.archiveCustomExercise(original.id);
    } catch (error) {
      _setErrors(
        const {},
        catalogErrorMessage(error, 'Die Übung konnte nicht archiviert werden.'),
      );
      return false;
    }
    if (!_disposed) {
      isSaving = false;
      _notify();
    }
    return true;
  }

  /// Prozent-Eingabe: „64“ entspricht 0,64. Leer ergibt null (Standard).
  double? _parseBodyweight(String raw, Map<String, String> fields) {
    final value = _parseNumber(raw);
    if (value == null) {
      if (raw.trim().isNotEmpty) fields['bodyweightFactor'] = _notANumber;
      return null;
    }
    if (value < 0 || value > 100) {
      fields['bodyweightFactor'] =
          'Der Körpergewichtsfaktor muss zwischen 0 und 100 % liegen.';
      return null;
    }
    return value / 100;
  }

  double? _parseWeight(String raw, Map<String, String> fields) {
    final value = _parseNumber(raw);
    if (value == null) {
      if (raw.trim().isNotEmpty) fields['weightFactor'] = _notANumber;
      return null;
    }
    if (value <= 0 || value > 10) {
      fields['weightFactor'] =
          'Der Zusatzgewichtsfaktor muss größer 0 und höchstens 10 sein.';
      return null;
    }
    return value;
  }

  static const _notANumber = 'Bitte eine Zahl eingeben.';

  static double? _parseNumber(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) return null;
    return value;
  }

  Future<bool> _isUsed() async {
    final id = exercise?.id;
    if (id == null) return false;
    for (final workout in await repository.readDiary()) {
      if (workout.exercises.any((block) => block.sourceExerciseId == id)) {
        return true;
      }
    }
    for (final plan in await repository.readPlans(includeArchived: true)) {
      if (plan.entries.any((entry) => entry.exerciseId == id)) return true;
    }
    return false;
  }

  void _startSaving() {
    isSaving = true;
    errorMessage = null;
    fieldErrors = const {};
    _notify();
  }

  void _setErrors(Map<String, String> fields, String? message) {
    if (_disposed) return;
    isSaving = false;
    fieldErrors = Map.unmodifiable(fields);
    errorMessage = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../data/repositories/training/training_preferences.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import '../../../domain/models/training/previous_values.dart';
import '../../../domain/models/training/workout_input.dart';
import '../../../domain/models/training/workout_model.dart';
import '../../../domain/models/training/workout_rules.dart';
import '../../../domain/models/training/workout_validation.dart';
import 'active_workout_controller.dart';

enum WorkoutFinishOutcome { finished, failed }

const _maxTitleLength = 160;

/// Zustand eines Trainings im Trainingsscreen. Jede Änderung wird sofort
/// lokal angezeigt und über [TrainingLogRepository.saveWorkout] gespeichert.
/// Schlägt das Speichern fehl, bleibt die Änderung in der Ansicht erhalten und
/// kann mit [retrySave] erneut gesendet werden.
///
/// Feldänderungen rufen die Methoden auf, die jeweils eine vollständige
/// Workout-Fassung über [edit] speichern. Ungültige Eingaben kommen nicht bis
/// hierher; die Ansicht prüft sie vorher und ruft dann nichts auf.
class WorkoutViewModel extends ChangeNotifier {
  WorkoutViewModel({
    required this.repository,
    required this.activeWorkout,
    required this.workoutId,
  }) : _preferences = repository.preferences;

  final TrainingLogRepository repository;
  final ActiveWorkoutController activeWorkout;
  final String workoutId;

  final TrainingPreferences _preferences;
  Workout? _workout;
  List<Workout> _diary = const [];
  Map<String, String?> _exerciseNotes = const {};
  TrainingPreferenceValues _settings = const TrainingPreferenceValues();
  bool isLoading = false;
  String? errorMessage;
  bool _hasUnsavedChanges = false;
  bool _disposed = false;

  /// Serialisiert Speichervorgänge, damit sich Schreibzugriffe nicht überholen.
  Future<void> _queue = Future.value();

  Workout? get workout => _workout;

  bool get isActive => _workout?.isActive ?? false;

  bool get hasUnsavedChanges => _hasUnsavedChanges;

  /// Anzeigeeinheit und RIR-Sichtbarkeit des Kontos.
  TrainingPreferenceValues get settings => _settings;

  WeightUnit get weightUnit => _settings.weightUnit;

  bool get showRir => _settings.showRir;

  /// Details auf dem Sperrbildschirm freigegeben (Training, Übung, Satzposition).
  bool get liveActivityDetails => _settings.liveActivityDetails;

  /// Vorwerte je Block-ID, eine Position je Satz. `null` ohne Vorwert.
  Map<String, List<LoggedSet?>> get previousValues {
    final current = _workout;
    if (current == null) return const {};
    return previousValuesFor(current, _diary);
  }

  /// Übungsstammnotiz aus dem Katalog; nur lesend.
  String? exerciseNoteFor(WorkoutBlock block) =>
      _exerciseNotes[block.sourceExerciseId];

  /// Block direkt nach [workoutExerciseId] in der Reihenfolge, falls vorhanden.
  WorkoutBlock? blockAfter(String workoutExerciseId) {
    final exercises = _workout?.exercises;
    if (exercises == null) return null;
    final index = exercises.indexWhere(
      (block) => block.workoutExerciseId == workoutExerciseId,
    );
    if (index < 0 || index + 1 >= exercises.length) return null;
    return exercises[index + 1];
  }

  String newId() => repository.newId();

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    _notify();
    try {
      final loaded = await repository.readWorkout(workoutId);
      if (_disposed) return;
      _workout = loaded;
      errorMessage = loaded == null
          ? 'Das Training ist nicht mehr verfügbar.'
          : null;
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Das Training konnte nicht geladen werden.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
    await _loadSupportData();
  }

  /// Verlauf, Stammnotizen und Einstellungen. Fehler lassen das Training
  /// bedienbar, nur die jeweilige Zusatzinformation fehlt.
  Future<void> _loadSupportData() async {
    try {
      final diary = await repository.readDiary();
      if (!_disposed) _diary = diary;
    } catch (_) {
      // Zusatzdaten fehlen nur in der Anzeige; das Training bleibt bedienbar.
    }
    try {
      final exercises = await repository.readExercises(includeArchived: true);
      if (!_disposed) {
        _exerciseNotes = {
          for (final exercise in exercises) exercise.id: exercise.notes,
        };
      }
    } catch (_) {
      // Zusatzdaten fehlen nur in der Anzeige; das Training bleibt bedienbar.
    }
    try {
      final settings = await _preferences.read();
      if (!_disposed) _settings = settings;
    } catch (_) {
      // Zusatzdaten fehlen nur in der Anzeige; das Training bleibt bedienbar.
    }
    _notify();
  }

  Future<void> setWeightUnit(WeightUnit unit) =>
      _updateSettings(_settings.copyWith(weightUnit: unit));

  Future<void> setShowRir(bool showRir) =>
      _updateSettings(_settings.copyWith(showRir: showRir));

  Future<void> setLiveActivityDetails(bool enabled) =>
      _updateSettings(_settings.copyWith(liveActivityDetails: enabled));

  Future<void> _updateSettings(TrainingPreferenceValues values) async {
    if (values == _settings) return;
    _settings = values;
    _notify();
    try {
      await _preferences.write(values);
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Die Einstellung konnte nicht gespeichert werden.';
        _notify();
      }
    }
  }

  /// Wendet [change] auf das angezeigte Training an und speichert es.
  /// Das Future endet, wenn dieser Stand gespeichert oder der Fehler gemeldet ist.
  Future<void> edit(Workout Function(Workout current) change) {
    final current = _workout;
    if (current == null) return Future.value();
    _workout = change(current);
    _hasUnsavedChanges = true;
    _notify();
    return _enqueueSave();
  }

  /// Sendet eine nach einem Fehler verbliebene Änderung erneut.
  Future<void> retrySave() => _enqueueSave();

  // Metadaten

  /// Fehlermeldung für einen ungültigen Titel, sonst `null`.
  String? validateTitle(String title) {
    final length = title.trim().length;
    if (length < 1 || length > _maxTitleLength) {
      return 'Der Titel muss zwischen 1 und $_maxTitleLength Zeichen lang sein.';
    }
    return null;
  }

  Future<void> setTitle(String title) {
    final trimmed = title.trim();
    if (validateTitle(trimmed) != null) return Future.value();
    return edit((w) => w.copyWith(title: trimmed));
  }

  Future<void> setNotes(String? notes) {
    final normalized = notes == null || notes.isEmpty ? null : notes;
    return edit((w) => w.copyWith(notes: () => normalized));
  }

  /// Fehlermeldung, wenn die Startzeit nicht vor der Endzeit liegt.
  String? validateStartedAt(DateTime startedAt) {
    final endedAt = _workout?.endedAtUtc;
    if (endedAt != null && !startedAt.isBefore(endedAt)) {
      return 'Die Startzeit muss vor der Endzeit liegen.';
    }
    return null;
  }

  /// Fehlermeldung, wenn die Endzeit nicht nach der Startzeit liegt.
  String? validateEndedAt(DateTime endedAt) {
    final startedAt = _workout?.startedAtUtc;
    if (startedAt != null && !endedAt.isAfter(startedAt)) {
      return 'Die Endzeit muss nach der Startzeit liegen.';
    }
    return null;
  }

  /// Ungültige Zeiten bleiben unverändert; die Ansicht zeigt dann den Feldfehler.
  Future<void> setStartedAt(DateTime startedAt) {
    final utc = startedAt.toUtc();
    if (validateStartedAt(utc) != null) return Future.value();
    return edit((w) => w.copyWith(startedAtUtc: utc));
  }

  Future<void> setEndedAt(DateTime endedAt) {
    final utc = endedAt.toUtc();
    if (validateEndedAt(utc) != null) return Future.value();
    return edit((w) => w.copyWith(endedAtUtc: () => utc));
  }

  // Blöcke

  Future<void> setBlockNotes(String blockId, String? notes) {
    final normalized = notes == null || notes.isEmpty ? null : notes;
    return _editBlock(
      blockId,
      (block) => block.copyWith(notes: () => normalized),
    );
  }

  /// Verbindet den Block mit dem nächsten zu einem Superset. Hat der Block
  /// noch keine Superset-ID, bekommt er eine neue.
  Future<void> connectWithNextBlock(String blockId) {
    final next = blockAfter(blockId);
    final block = _blockById(blockId);
    if (next == null || block == null) return Future.value();
    final supersetId = block.supersetId ?? newId();
    if (block.supersetId == supersetId && next.supersetId == supersetId) {
      return Future.value();
    }
    return edit(
      (w) => w.copyWith(
        exercises: [
          for (final exercise in w.exercises)
            if (exercise.workoutExerciseId == blockId ||
                exercise.workoutExerciseId == next.workoutExerciseId)
              exercise.copyWith(supersetId: () => supersetId)
            else
              exercise,
        ],
      ),
    );
  }

  Future<void> detachFromSuperset(String blockId) => _editBlock(
    blockId,
    (block) => block.supersetId == null
        ? block
        : block.copyWith(supersetId: () => null),
  );

  /// Hängt je Übung einen Block mit einem leeren normalen Satz an. Mit
  /// [asSuperset] teilen die Blöcke eine neue Superset-ID.
  Future<void> addExercises(
    List<CatalogExercise> exercises, {
    bool asSuperset = false,
  }) {
    if (_workout == null || exercises.isEmpty) return Future.value();
    final supersetId = asSuperset && exercises.length > 1 ? newId() : null;
    final blocks = [
      for (final exercise in exercises)
        WorkoutBlock(
          workoutExerciseId: newId(),
          sourceExerciseId: exercise.id,
          exerciseNameSnapshot: exercise.name,
          exerciseTypeSnapshot: exercise.exerciseType,
          supersetId: supersetId,
          sets: [LoggedSet(setId: newId(), setType: SetType.normal)],
        ),
    ];
    return edit((w) => w.copyWith(exercises: [...w.exercises, ...blocks]));
  }

  /// Ersetzt die Übung eines Blocks. Satzwerte und Blocknotiz bleiben; Vorwerte
  /// beziehen sich danach auf die neue Übung.
  Future<void> replaceExercise(String blockId, CatalogExercise exercise) =>
      _editBlock(
        blockId,
        (block) => block.copyWith(
          sourceExerciseId: exercise.id,
          exerciseNameSnapshot: exercise.name,
          exerciseTypeSnapshot: exercise.exerciseType,
        ),
      );

  /// Ordnet die Blöcke in der gegebenen Reihenfolge neu. Blöcke, die nicht in
  /// [orderedBlockIds] stehen, entfallen. Ein Superset, das durch das Entfernen
  /// oder Verschieben nicht mehr zusammenhängt, wird aufgelöst.
  Future<void> arrangeBlocks(List<String> orderedBlockIds) {
    final current = _workout;
    if (current == null) return Future.value();
    final byId = {
      for (final block in current.exercises) block.workoutExerciseId: block,
    };
    final kept = [
      for (final id in orderedBlockIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (listEquals(
      [for (final block in current.exercises) block.workoutExerciseId],
      [for (final block in kept) block.workoutExerciseId],
    )) {
      return Future.value();
    }

    final arranged = [
      for (var i = 0; i < kept.length; i++)
        if (kept[i].supersetId != null &&
            !_connected(kept, i, kept[i].supersetId!))
          kept[i].copyWith(supersetId: () => null)
        else
          kept[i],
    ];
    return edit((w) => w.copyWith(exercises: arranged));
  }

  bool _connected(List<WorkoutBlock> blocks, int index, String supersetId) =>
      (index > 0 && blocks[index - 1].supersetId == supersetId) ||
      (index + 1 < blocks.length && blocks[index + 1].supersetId == supersetId);

  Future<void> removeBlock(String blockId) => arrangeBlocks([
    for (final block in _workout?.exercises ?? const <WorkoutBlock>[])
      if (block.workoutExerciseId != blockId) block.workoutExerciseId,
  ]);

  // Sätze

  Future<void> setWeight(String blockId, String setId, double? kg) =>
      _editSet(blockId, setId, (set) => set.copyWith(weightKg: () => kg));

  Future<void> setRepetitions(String blockId, String setId, int? repetitions) =>
      _editSet(
        blockId,
        setId,
        (set) => set.copyWith(repetitions: () => repetitions),
      );

  Future<void> setRir(String blockId, String setId, int? rir) =>
      _editSet(blockId, setId, (set) => set.copyWith(rir: () => rir));

  Future<void> setSetNotes(String blockId, String setId, String? notes) {
    final normalized = notes == null || notes.isEmpty ? null : notes;
    return _editSet(
      blockId,
      setId,
      (set) => set.copyWith(notes: () => normalized),
    );
  }

  Future<void> setSetType(String blockId, String setId, SetType type) =>
      _editSet(blockId, setId, (set) => set.copyWith(setType: type));

  /// Übernimmt Vorwert-Gewicht und -Wiederholungen in die leeren Felder des Satzes.
  Future<void> applyPreviousValues(String blockId, String setId) {
    final index = _setIndex(blockId, setId);
    if (index < 0) return Future.value();
    final previous = _at(previousValues[blockId], index);
    if (previous == null) return Future.value();
    return _editSet(
      blockId,
      setId,
      (set) => set.copyWith(
        weightKg: () => set.weightKg ?? previous.weightKg,
        repetitions: () => set.repetitions ?? previous.repetitions,
      ),
    );
  }

  /// Neuer leerer Satz am Ende. Er übernimmt den Typ des letzten Satzes.
  Future<void> addSet(String blockId) {
    final block = _blockById(blockId);
    if (block == null) return Future.value();
    final type = block.sets.isEmpty ? SetType.normal : block.sets.last.setType;
    final set = LoggedSet(setId: newId(), setType: type);
    return _editBlock(
      blockId,
      (block) => block.copyWith(sets: [...block.sets, set]),
    );
  }

  /// Kopie des Satzes direkt dahinter mit neuer ID.
  Future<void> duplicateSet(String blockId, String setId) {
    final index = _setIndex(blockId, setId);
    if (index < 0) return Future.value();
    final copy = _blockById(blockId)!.sets[index].copyWith(setId: newId());
    return _editBlock(blockId, (block) {
      final sets = [...block.sets]..insert(index + 1, copy);
      return block.copyWith(sets: sets);
    });
  }

  /// Entfernt den Satz; der Block bleibt auch ohne Sätze bestehen.
  Future<void> removeSet(String blockId, String setId) => _editBlock(
    blockId,
    (block) => block.copyWith(
      sets: [
        for (final set in block.sets)
          if (set.setId != setId) set,
      ],
    ),
  );

  /// Verschiebt den Satz um [delta] Positionen innerhalb des Blocks.
  Future<void> moveSet(String blockId, String setId, int delta) {
    final index = _setIndex(blockId, setId);
    final block = _blockById(blockId);
    if (index < 0 || block == null) return Future.value();
    final target = index + delta;
    if (target < 0 || target >= block.sets.length) return Future.value();
    return _editBlock(blockId, (block) {
      final sets = [...block.sets];
      final moved = sets.removeAt(index);
      sets.insert(target, moved);
      return block.copyWith(sets: sets);
    });
  }

  Future<void> _editBlock(
    String blockId,
    WorkoutBlock Function(WorkoutBlock block) change,
  ) {
    final block = _blockById(blockId);
    if (block == null) return Future.value();
    final updated = change(block);
    if (updated == block) return Future.value();
    return edit(
      (w) => w.copyWith(
        exercises: [
          for (final exercise in w.exercises)
            if (exercise.workoutExerciseId == blockId)
              change(exercise)
            else
              exercise,
        ],
      ),
    );
  }

  Future<void> _editSet(
    String blockId,
    String setId,
    LoggedSet Function(LoggedSet set) change,
  ) {
    final index = _setIndex(blockId, setId);
    if (index < 0) return Future.value();
    final block = _blockById(blockId)!;
    final set = block.sets[index];
    final updated = change(set);
    if (updated == set) return Future.value();
    final wasRecorded = isSetRecorded(set, block.exerciseTypeSnapshot);
    final edited = _editBlock(
      blockId,
      (block) => block.copyWith(
        sets: [
          for (final candidate in block.sets)
            if (candidate.setId == setId) change(candidate) else candidate,
        ],
      ),
    );
    if (!wasRecorded && isSetRecorded(updated, block.exerciseTypeSnapshot)) {
      // Ein abgelaufener Pausentimer kehrt erst zur Trainingszeit zurück, wenn
      // ein Satz vollständig ist; Teileingaben tun das nicht.
      final timer = activeWorkout.restTimer;
      if (timer != null && timer.workoutId == workoutId) {
        unawaited(timer.onSetRecorded());
      }
    }
    return edited;
  }

  WorkoutBlock? _blockById(String blockId) {
    for (final block in _workout?.exercises ?? const <WorkoutBlock>[]) {
      if (block.workoutExerciseId == blockId) return block;
    }
    return null;
  }

  int _setIndex(String blockId, String setId) {
    final block = _blockById(blockId);
    if (block == null) return -1;
    return block.sets.indexWhere((set) => set.setId == setId);
  }

  LoggedSet? _at(List<LoggedSet?>? sets, int index) =>
      sets == null || index >= sets.length ? null : sets[index];

  // Training beenden und löschen

  /// Anzahl der Sätze mit fehlenden Pflichtwerten. Die Ansicht fragt nur bei
  /// Werten größer null nach, bevor sie beendet.
  int get missingValueCount {
    final current = _workout;
    return current == null ? 0 : missingValueSets(current).length;
  }

  /// Beendet das Training. Mit [applyPreviousValues] füllen Vorwerte die leeren
  /// Felder; sonst bleiben fehlende Werte leer.
  Future<WorkoutFinishOutcome> requestFinish({
    bool applyPreviousValues = false,
  }) async {
    await _enqueueSave();
    if (_hasUnsavedChanges) return WorkoutFinishOutcome.failed;
    try {
      await repository.finishWorkout(
        workoutId,
        applyPreviousValues: applyPreviousValues,
      );
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Das Training konnte nicht beendet werden.';
        _notify();
      }
      return WorkoutFinishOutcome.failed;
    }
    await activeWorkout.endRestTimer(workoutId);
    await activeWorkout.load();
    await _reloadSilently();
    return WorkoutFinishOutcome.finished;
  }

  /// Löscht das Training nach Bestätigung durch die Ansicht.
  Future<bool> deleteWorkout() async {
    await _queue;
    try {
      await repository.deleteWorkout(workoutId);
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Das Training konnte nicht gelöscht werden.';
        _notify();
      }
      return false;
    }
    await activeWorkout.endRestTimer(workoutId);
    await activeWorkout.load();
    return true;
  }

  Future<void> _enqueueSave() {
    _queue = _queue.then((_) => _saveIfChanged());
    return _queue;
  }

  Future<void> _saveIfChanged() async {
    final snapshot = _workout;
    if (snapshot == null || !_hasUnsavedChanges) return;
    _hasUnsavedChanges = false;
    try {
      await repository.saveWorkout(snapshot);
      if (_disposed) return;
      errorMessage = null;
    } catch (error) {
      _hasUnsavedChanges = true;
      if (!_disposed) {
        errorMessage = _saveErrorMessage(error);
      }
    }
    await activeWorkout.load();
    _notify();
  }

  Future<void> _reloadSilently() async {
    final loaded = await repository.readWorkout(workoutId);
    if (_disposed) return;
    _workout = loaded ?? _workout;
    _notify();
  }

  String _saveErrorMessage(Object error) {
    if (error is WorkoutValidationException && error.fields.isNotEmpty) {
      return error.fields.values.first;
    }
    return 'Speichern fehlgeschlagen. Deine Änderung bleibt auf dem Bildschirm und kann erneut gespeichert werden.';
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

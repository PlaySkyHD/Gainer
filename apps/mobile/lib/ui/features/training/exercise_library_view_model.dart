import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import 'exercise_catalog_format.dart';

/// Hält Übungen und Kategorien für die Übungsverwaltung mit Suche und Filter.
class ExerciseLibraryViewModel extends ChangeNotifier {
  ExerciseLibraryViewModel({required this.repository});

  final TrainingLogRepository repository;

  /// Alle Übungen inklusive archivierter, nach Name sortiert.
  List<CatalogExercise> exercises = const [];

  /// Nicht archivierte Kategorien, für Filter und Zuordnung.
  List<CatalogCategory> categories = const [];

  bool isLoading = false;
  String? errorMessage;
  String query = '';
  String? categoryId;
  bool showArchived = false;
  bool _disposed = false;

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final loadedExercises = await repository.readExercises(
        includeArchived: true,
      );
      final loadedCategories = await repository.readCategories();
      if (_disposed) return;
      exercises = loadedExercises;
      categories = loadedCategories;
      if (categoryId != null && categoryById(categoryId!) == null) {
        categoryId = null;
      }
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Die Übungen konnten nicht geladen werden.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  void setQuery(String value) {
    query = value;
    _notify();
  }

  void setCategory(String? id) {
    categoryId = id;
    _notify();
  }

  void setShowArchived(bool value) {
    showArchived = value;
    _notify();
  }

  CatalogCategory? categoryById(String id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  /// Übungen nach Suche, Kategorie und Archiv-Schalter gefiltert.
  List<CatalogExercise> get visibleExercises {
    final needle = foldCatalogSearch(query.trim());
    final category = categoryId;
    return [
      for (final exercise in exercises)
        if ((showArchived || !exercise.isArchived) &&
            (category == null || exercise.categoryIds.contains(category)) &&
            (needle.isEmpty ||
                foldCatalogSearch(exercise.name).contains(needle)))
          exercise,
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

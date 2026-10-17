import 'package:flutter/foundation.dart';

import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/training/exercise_catalog_model.dart';
import 'exercise_catalog_format.dart';

/// Hält Basis- und eigene Kategorien für die Kategorienverwaltung.
class CategoryLibraryViewModel extends ChangeNotifier {
  CategoryLibraryViewModel({required this.repository});

  final TrainingLogRepository repository;

  /// Basiskategorien, nur lesbar.
  List<CatalogCategory> baseCategories = const [];

  /// Eigene, nicht archivierte Kategorien.
  List<CatalogCategory> ownCategories = const [];

  bool isLoading = false;
  String? errorMessage;
  bool _disposed = false;

  Future<void> load() async {
    if (_disposed) return;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final all = await repository.readCategories();
      if (_disposed) return;
      baseCategories = [
        for (final category in all)
          if (category.isBase) category,
      ];
      ownCategories = [
        for (final category in all)
          if (!category.isBase) category,
      ];
    } catch (_) {
      if (!_disposed) {
        errorMessage = 'Die Kategorien konnten nicht geladen werden.';
      }
    } finally {
      if (!_disposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  /// Legt eine Kategorie an oder benennt sie um (bei [categoryId]). Liefert
  /// eine Fehlermeldung oder null bei Erfolg.
  Future<String?> save({required String name, String? categoryId}) async {
    try {
      if (categoryId == null) {
        await repository.createCategory(
          CatalogCategory(
            id: repository.newId(),
            name: name.trim(),
            isBase: false,
          ),
        );
      } else {
        await repository.updateCategory(
          CatalogCategory(id: categoryId, name: name.trim(), isBase: false),
        );
      }
    } catch (error) {
      return catalogErrorMessage(
        error,
        'Die Kategorie konnte nicht gespeichert werden.',
      );
    }
    await load();
    return null;
  }

  /// Archiviert eine eigene Kategorie. Zugeordnete Übungen bleiben unverändert.
  Future<String?> archive(String categoryId) async {
    try {
      await repository.archiveCategory(categoryId);
    } catch (error) {
      return catalogErrorMessage(
        error,
        'Die Kategorie konnte nicht archiviert werden.',
      );
    }
    await load();
    return null;
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

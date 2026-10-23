import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/nutrition/nutrition.dart';

class NutritionViewModel extends ChangeNotifier {
  NutritionViewModel({
    required this.repository,
    required this.localDate,
    this.dictation,
  }) {
    if (!isValidLocalDate(localDate)) {
      throw ArgumentError.value(localDate, 'localDate');
    }
  }

  final NutritionRepository repository;

  /// Diktat für die Mahlzeiten-Schätzung; ohne Plattform kein Diktat-Button.
  final DictationPlatform? dictation;
  String localDate;
  NutritionMeal selectedMeal = NutritionMeal.breakfast;
  NutritionSnapshot? snapshot;
  NutritionLabelScanDraft? labelDraft;
  MealEstimateDraft? mealEstimateDraft;
  List<NutritionFood> searchResults = const [];

  /// Treffer aus dem lokalen Katalog (BLS), schon beim Tippen.
  List<NutritionFood> localResults = const [];
  bool localResultsPartial = false;
  int _localSearchGeneration = 0;
  NutritionFood? barcodeFood;
  bool isLoading = false;
  bool isSaving = false;
  bool isOnlineOperation = false;
  String? errorMessage;
  NutritionErrorOperation? errorOperation;
  String? statusMessage;
  bool _disposed = false;
  int _dayLoadGeneration = 0;
  String? _failedDate;

  Future<void> load() => _loadDay(_failedDate ?? localDate);

  Future<void> selectDate(String value) {
    if (!isValidLocalDate(value)) {
      reportInputError('Bitte ein gültiges Datum im Format JJJJ-MM-TT wählen.');
      return Future.value();
    }
    return _loadDay(value);
  }

  Future<void> _loadDay(String date) async {
    final generation = ++_dayLoadGeneration;
    isLoading = true;
    errorMessage = null;
    errorOperation = null;
    statusMessage = null;
    _notify();
    try {
      final next = await repository.read(date);
      if (_disposed || generation != _dayLoadGeneration) return;
      localDate = date;
      snapshot = next;
      _failedDate = null;
    } catch (error) {
      if (!_disposed && generation == _dayLoadGeneration) {
        _failedDate = date;
        errorMessage = _messageFor(error);
        errorOperation = NutritionErrorOperation.day;
      }
    } finally {
      if (!_disposed && generation == _dayLoadGeneration) {
        isLoading = false;
        _notify();
      }
    }
  }

  void dismissActionError() {
    if (errorOperation == null ||
        errorOperation == NutritionErrorOperation.day) {
      return;
    }
    errorMessage = null;
    errorOperation = null;
    _notify();
  }

  void reportInputError(
    String message, {
    NutritionErrorOperation operation = NutritionErrorOperation.entry,
  }) {
    if (_disposed) return;
    errorMessage = message;
    errorOperation = operation;
    _notify();
  }

  void selectMeal(NutritionMeal meal) {
    selectedMeal = meal;
    _notify();
  }

  Future<void> addManualEntry({
    required String productName,
    String? brand,
    required double amountGrams,
    required double kilocaloriesPer100Grams,
    double? proteinGramsPer100,
    double? carbohydrateGramsPer100,
    double? fatGramsPer100,
    double? saltGramsPer100,
    double? fiberGramsPer100,
    double? pieceGrams,
    double? pieceCount,
  }) => _run(() async {
    final current = snapshot ?? await repository.read(localDate);
    final position =
        current.day.entries
            .where((item) => item.meal == selectedMeal)
            .fold<int>(
              0,
              (max, item) => item.position > max ? item.position : max,
            ) +
        1;
    await repository.saveEntry(
      localDate,
      NutritionEntry(
        entryId: repository.ids(),
        meal: selectedMeal,
        position: position,
        productName: productName,
        brand: brand,
        amountGrams: amountGrams,
        per100Grams: NutritionTotals(
          kilocalories: kilocaloriesPer100Grams,
          proteinGrams: proteinGramsPer100,
          carbohydrateGrams: carbohydrateGramsPer100,
          fatGrams: fatGramsPer100,
          saltGrams: saltGramsPer100,
          fiberGrams: fiberGramsPer100,
        ),
        source: null,
        pieceGrams: pieceGrams,
        pieceCount: pieceCount,
      ),
    );
    snapshot = await repository.read(localDate);
    statusMessage = 'Eintrag lokal gespeichert und für den Sync vorgemerkt.';
  }, saving: true);

  Future<void> removeEntry(String entryId) => _run(
    () async {
      await repository.removeEntry(localDate, entryId);
      snapshot = await repository.read(localDate);
      statusMessage = 'Eintrag entfernt.';
    },
    saving: true,
    operation: NutritionErrorOperation.diary,
  );

  Future<void> updateEntry({
    required NutritionEntry original,
    required NutritionMeal meal,
    required String productName,
    String? brand,
    required double amountGrams,
    required NutritionTotals per100Grams,
    double? pieceGrams,
    double? pieceCount,
  }) => _run(
    () async {
      await repository.saveEntry(
        localDate,
        original.copyWith(
          meal: meal,
          productName: productName,
          brand: brand,
          clearBrand: brand == null,
          amountGrams: amountGrams,
          per100Grams: per100Grams,
          pieceGrams: pieceGrams,
          pieceCount: pieceCount,
          clearPieces: true,
        ),
      );
      snapshot = await repository.read(localDate);
      statusMessage =
          'Eintrag aktualisiert; Quelle und Nährwertsnapshot bleiben erhalten.';
    },
    saving: true,
    operation: NutritionErrorOperation.diary,
  );

  Future<void> moveEntry(String entryId, NutritionMeal meal, int position) =>
      _run(
        () async {
          await repository.moveEntry(localDate, entryId, meal, position);
          snapshot = await repository.read(localDate);
        },
        saving: true,
        operation: NutritionErrorOperation.diary,
      );

  Future<void> addReusableMeal(
    String id,
    NutritionMeal meal, {
    double? portionScale,
  }) => _run(() async {
    await repository.copyReusableMealToDay(
      mealId: id,
      localDate: localDate,
      meal: meal,
      portionScale: portionScale,
    );
    snapshot = await repository.read(localDate);
    statusMessage = 'Gericht als unabhängige Mahlzeit übernommen.';
  }, saving: true);

  Future<void> saveReusableMeal({
    String? id,
    required ReusableMeal meal,
    NutritionErrorOperation operation = NutritionErrorOperation.planning,
  }) => _run(
    () async {
      await repository.saveReusableMeal(meal, id: id);
      snapshot = await repository.read(localDate);
      statusMessage = 'Gespeichertes Gericht lokal aktualisiert.';
    },
    saving: true,
    operation: operation,
  );

  Future<void> archiveReusableMeal(String id) => _run(
    () async {
      await repository.archiveReusableMeal(id);
      snapshot = await repository.read(localDate);
      statusMessage = 'Gericht archiviert. Bereits gespeicherte Tages-Snapshots bleiben unverändert.';
    },
    saving: true,
    operation: NutritionErrorOperation.planning,
  );

  /// Speichert die Ziele mit Wirkung ab heute.
  Future<void> saveTargets({
    required NutritionDayTarget training,
    required NutritionDayTarget? restDay,
    required double? saltGrams,
    required double? fiberGrams,
  }) => _run(
    () async {
      await repository.saveTargets(
        training: training,
        restDay: restDay,
        saltGrams: saltGrams,
        fiberGrams: fiberGrams,
      );
      snapshot = await repository.read(localDate);
      statusMessage = 'Ziele gespeichert. Sie gelten ab heute.';
    },
    saving: true,
    operation: NutritionErrorOperation.planning,
  );

  /// Legt die Tagesart des geöffneten Tages fest; null heißt automatisch.
  Future<void> setDayKind(NutritionDayKind? kind) => _run(
    () async {
      await repository.setDayKind(localDate, kind);
      snapshot = await repository.read(localDate);
    },
    saving: true,
    operation: NutritionErrorOperation.diary,
  );

  /// Speichert den geöffneten Tag als neue Vorlage oder überschreibt eine.
  Future<void> saveDayAsTemplate({
    String? overwriteId,
    String? name,
    NutritionDayKind? dayKind,
  }) => _run(
    () async {
      await repository.saveDayAsTemplate(
        localDate,
        overwriteId: overwriteId,
        name: name,
        dayKind: dayKind,
      );
      snapshot = await repository.read(localDate);
      statusMessage = overwriteId == null
          ? 'Tag als Vorlage gespeichert.'
          : 'Vorlage überschrieben.';
    },
    saving: true,
    operation: NutritionErrorOperation.planning,
  );

  /// Übernimmt die Einträge der Vorlage in den geöffneten Tag.
  Future<void> applyTemplate(
    String templateId, {
    TemplateApplyMode mode = TemplateApplyMode.append,
  }) => _run(
    () async {
      await repository.applyTemplate(templateId, localDate, mode: mode);
      snapshot = await repository.read(localDate);
      statusMessage = 'Vorlage übernommen.';
    },
    saving: true,
    operation: NutritionErrorOperation.diary,
  );

  Future<void> updateTemplate(
    String templateId, {
    required String name,
    required NutritionDayKind? dayKind,
    required List<NutritionEntry> entries,
  }) => _run(
    () async {
      await repository.updateTemplate(
        templateId,
        name: name,
        dayKind: dayKind,
        entries: entries,
      );
      snapshot = await repository.read(localDate);
      statusMessage = 'Vorlage gespeichert.';
    },
    saving: true,
    operation: NutritionErrorOperation.planning,
  );

  Future<void> deleteTemplate(String templateId) => _run(
    () async {
      await repository.deleteTemplate(templateId);
      snapshot = await repository.read(localDate);
      statusMessage = 'Vorlage gelöscht. Befüllte Tage bleiben unverändert.';
    },
    saving: true,
    operation: NutritionErrorOperation.planning,
  );

  /// Gibt es eine Produktsuche online (Open Food Facts)?
  bool get canSearchOnline => repository.canSearchOnline;

  /// Sucht beim Tippen im lokalen Katalog. Ältere Online-Treffer passen nicht
  /// mehr zur Eingabe und entfallen; spätere Antworten überholen frühere nicht.
  Future<void> searchLocalFoods(String query) async {
    final generation = ++_localSearchGeneration;
    if (searchResults.isNotEmpty) {
      searchResults = const [];
      _notify();
    }
    LocalFoodSearch result;
    try {
      result = await repository.searchLocalFoods(query);
    } catch (_) {
      result = LocalFoodSearch.empty;
    }
    if (_disposed || generation != _localSearchGeneration) return;
    localResults = result.foods;
    localResultsPartial = result.partial;
    _notify();
  }

  Future<void> searchFoods(String query) => _run(
    () async {
      isOnlineOperation = true;
      searchResults = await repository.searchFoods(query);
      statusMessage = searchResults.isEmpty
          ? 'Keine Lebensmittel gefunden.'
          : '${searchResults.length} Lebensmittel gefunden.';
    },
    saving: false,
    operation: NutritionErrorOperation.search,
  );

  Future<void> lookupBarcode() => _run(
    () async {
      isOnlineOperation = true;
      final barcode = await repository.scanBarcode();
      if (barcode == null) return;
      barcodeFood = await repository.lookupBarcode(barcode);
      statusMessage = barcodeFood == null
          ? 'Kein Produkt zu diesem Barcode gefunden.'
          : 'Produkt gefunden: ${barcodeFood!.name}. Bitte Menge prüfen und eintragen.';
    },
    saving: false,
    operation: NutritionErrorOperation.barcode,
  );

  Future<void> estimateMeal(String description) => _run(
    () async {
      isOnlineOperation = true;
      mealEstimateDraft = await repository.estimateMeal(description);
      statusMessage = mealEstimateDraft!.components.isEmpty
          ? 'Keine Bestandteile erkannt.'
          : 'Schätzung prüfen. Es wurde noch nichts gespeichert.';
    },
    saving: false,
    operation: NutritionErrorOperation.estimate,
  );

  Future<void> estimateMealFromImage({
    required bool photoConsentConfirmed,
    required bool uploadConsentConfirmed,
    required bool useCamera,
  }) => _run(() async {
    isOnlineOperation = true;
    final image = await repository.captureLabelImage(
      photoConsentConfirmed: photoConsentConfirmed,
      useCamera: useCamera,
    );
    if (image == null) {
      statusMessage = 'Aufnahme abgebrochen.';
      return;
    }
    mealEstimateDraft = await repository.estimateCapturedMeal(
      review: image,
      uploadConsentConfirmed: uploadConsentConfirmed,
    );
    statusMessage = 'Schätzung prüfen. Es wurde noch nichts gespeichert.';
  }, operation: NutritionErrorOperation.estimate);

  /// [pieceCount] gesetzt: Menge wurde in Stück eingegeben ([amountGrams] ist
  /// dann Stückzahl × Stückgewicht des Lebensmittels).
  Future<void> addFood(
    NutritionFood food, {
    required double amountGrams,
    double? pieceCount,
  }) => _run(() async {
    final current = snapshot ?? await repository.read(localDate);
    final position =
        current.day.entries
            .where((item) => item.meal == selectedMeal)
            .fold<int>(
              0,
              (max, item) => item.position > max ? item.position : max,
            ) +
        1;
    await repository.saveEntry(
      localDate,
      NutritionEntry(
        entryId: repository.ids(),
        meal: selectedMeal,
        position: position,
        productName: food.name,
        brand: food.brand,
        amountGrams: amountGrams,
        per100Grams: food.per100Grams,
        source: food.source,
        pieceGrams: food.pieceGrams,
        pieceCount: pieceCount,
      ),
    );
    snapshot = await repository.read(localDate);
    statusMessage =
        'Lebensmittel-Snapshot gespeichert und für den Sync vorgemerkt.';
  }, saving: true);

  Future<void> confirmEstimatedComponent(int componentIndex) async {
    final draft = mealEstimateDraft;
    if (draft == null ||
        componentIndex < 0 ||
        componentIndex >= draft.components.length) {
      throw StateError('Die Schätzung ist nicht verfügbar.');
    }
    final item = draft.components[componentIndex];
    // 0 kcal ist gültig, z. B. für den Bestandteil „Salz“.
    if (item.amountGrams <= 0 || item.totals.kilocalories < 0) {
      throw StateError(
        'Der Schätzwert ist nicht gültig und muss manuell ergänzt werden.',
      );
    }
    final per100 = calculatePer100Totals(
      amountGrams: item.amountGrams,
      totals: item.totals,
    );
    await _run(() async {
      final current = snapshot ?? await repository.read(localDate);
      final position =
          current.day.entries
              .where((entry) => entry.meal == selectedMeal)
              .fold<int>(
                0,
                (max, entry) => entry.position > max ? entry.position : max,
              ) +
          1;
      await repository.saveEntry(
        localDate,
        NutritionEntry(
          entryId: repository.ids(),
          meal: selectedMeal,
          position: position,
          productName: item.name,
          brand: null,
          amountGrams: item.amountGrams,
          per100Grams: per100,
          source: NutritionSource(
            // Mit Websuche steht die Fundstelle dabei, z. B. „OpenAI · fddb.info“.
            provider: switch (item.sourceHost) {
              final host? => '${draft.provider} · $host',
              null => draft.provider,
            },
            retrievedAtUtc: draft.estimatedAtUtc,
            basisGrams: item.amountGrams,
          ),
          pieceGrams: item.pieceCount == null ? null : item.pieceGrams,
          pieceCount: item.pieceGrams == null ? null : item.pieceCount,
        ),
      );
      snapshot = await repository.read(localDate);
      // Nur den übernommenen Bestandteil entfernen; die übrigen bleiben
      // zum Prüfen stehen.
      final remaining = [
        for (var i = 0; i < draft.components.length; i++)
          if (i != componentIndex) draft.components[i],
      ];
      mealEstimateDraft = remaining.isEmpty
          ? null
          : MealEstimateDraft(
              components: List.unmodifiable(remaining),
              provider: draft.provider,
              schemaVersion: draft.schemaVersion,
              estimatedAtUtc: draft.estimatedAtUtc,
            );
      statusMessage = 'Geprüfte Schätzung als Eintrag gespeichert.';
      _notify();
    }, saving: true);
  }

  /// Verwirft einen offenen Vorschlag ohne Statusmeldung, z. B. beim Schließen.
  void clearEstimateDraft() {
    if (mealEstimateDraft == null) return;
    mealEstimateDraft = null;
    _notify();
  }

  void discardEstimate() {
    mealEstimateDraft = null;
    statusMessage = 'Schätzung verworfen; es wurde nichts gespeichert.';
    _notify();
  }

  Future<void> scanLabel({
    required bool photoConsentConfirmed,
    required bool uploadConsentConfirmed,
    required bool useCamera,
  }) => _run(() async {
    isOnlineOperation = true;
    final image = await repository.captureLabelImage(
      photoConsentConfirmed: photoConsentConfirmed,
      useCamera: useCamera,
    );
    if (image == null) {
      statusMessage = 'Aufnahme abgebrochen.';
      return;
    }
    labelDraft = await repository.scanCapturedLabel(
      review: image,
      uploadConsentConfirmed: uploadConsentConfirmed,
    );
    statusMessage =
        'Nährwertvorschlag prüfen. Es wurde noch nichts gespeichert.';
  }, operation: NutritionErrorOperation.label);

  Future<void> confirmLabelDraft({
    required String productName,
    required double amountGrams,
    String? brand,
  }) async {
    final draft = labelDraft;
    final nutrients = draft?.confirmedPer100Grams;
    if (draft == null || nutrients == null) {
      throw StateError('Der Labelscan kann nicht bestätigt werden.');
    }
    await _run(() async {
      final current = snapshot ?? await repository.read(localDate);
      final position =
          current.day.entries
              .where((item) => item.meal == selectedMeal)
              .fold<int>(
                0,
                (max, item) => item.position > max ? item.position : max,
              ) +
          1;
      await repository.saveEntry(
        localDate,
        NutritionEntry(
          entryId: repository.ids(),
          meal: selectedMeal,
          position: position,
          productName: productName,
          brand: brand,
          amountGrams: amountGrams,
          per100Grams: nutrients,
          source: NutritionSource(
            provider: draft.provider,
            retrievedAtUtc: draft.scannedAtUtc,
            basisGrams: 100,
          ),
        ),
      );
      snapshot = await repository.read(localDate);
      labelDraft = null;
      statusMessage = 'Eintrag lokal gespeichert und für den Sync vorgemerkt.';
    }, saving: true);
  }

  Future<String?> confirmLabelAsReusableMeal({
    required String productName,
    required double amountGrams,
    required String mealName,
  }) async {
    final draft = labelDraft;
    final per100 = draft?.confirmedPer100Grams;
    if (draft == null || per100 == null) {
      throw StateError('Der Labelscan kann nicht bestätigt werden.');
    }
    String? id;
    await _run(() async {
      final source = NutritionSource(
        provider: draft.provider,
        retrievedAtUtc: draft.scannedAtUtc,
        basisGrams: 100,
      );
      id = await repository.saveReusableMeal(
        ReusableMeal(
          name: mealName,
          description: 'Aus geprüftem Nährwertetikett',
          standardPortion: 1,
          components: [
            ReusableMealComponent(
              componentId: repository.ids(),
              position: 0,
              name: productName,
              brand: null,
              amountGrams: amountGrams,
              per100Grams: per100,
              source: source,
            ),
          ],
        ),
      );
      snapshot = await repository.read(localDate);
      labelDraft = null;
      statusMessage =
          'Gericht lokal gespeichert. Es wurde kein Ernährungstag geändert.';
    }, saving: true);
    return id;
  }

  void discardLabelDraft() {
    labelDraft = null;
    statusMessage = 'Vorschlag verworfen; es wurde nichts gespeichert.';
    _notify();
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool saving = false,
    NutritionErrorOperation operation = NutritionErrorOperation.entry,
  }) async {
    if (_disposed) return;
    isLoading = !saving;
    isSaving = saving;
    isOnlineOperation = false;
    errorMessage = null;
    errorOperation = null;
    statusMessage = null;
    _notify();
    try {
      await action();
    } catch (error) {
      if (!_disposed) {
        errorMessage = _messageFor(error);
        errorOperation = operation;
      }
    } finally {
      isLoading = false;
      isSaving = false;
      isOnlineOperation = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String _messageFor(Object error) => switch (error) {
    StateError(:final message) when message.contains('Onlineverbindung') =>
      '$message Bitte später erneut versuchen.',
    PlatformException() => _captureMessage(error),
    NutritionValidationException(:final fields) when fields.isNotEmpty =>
      fields.values.first,
    _ => error.toString(),
  };

  /// Fehler von Kamera, Barcode-Scanner und Fotoauswahl verständlich.
  static String _captureMessage(PlatformException error) =>
      switch (error.code) {
        'capture_in_progress' =>
          'Die Kamera ist noch geöffnet. Schließe sie und versuche es erneut.',
        'camera_permission_denied' || 'camera_permission_unavailable' => 'Gainer darf die Kamera nicht nutzen. Erlaube den Zugriff in den iOS-Einstellungen oder gib die Werte manuell ein.',
        'camera_unavailable' || 'capture_unavailable' =>
          'Die Kamera ist gerade nicht verfügbar. Gib die Werte manuell ein.',
        'unsupported_image' || 'capture_failed' => 'Das Bild konnte nicht gelesen werden. Versuche es mit einem anderen Foto.',
        'image_too_large' => 'Das Bild ist zu groß. Wähle ein kleineres Foto.',
        _ => 'Die Aufnahme ist fehlgeschlagen. Versuche es erneut.',
      };
}

enum NutritionErrorOperation {
  day,
  diary,
  entry,
  planning,
  search,
  barcode,
  estimate,
  label,
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../data/repositories/nutrition/nutrition_preferences.dart';
import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../data/repositories/sync/local_sync_store.dart'
    show LocalResourceChangedException;
import '../../../data/services/platform/platform_ports.dart';
import '../../../domain/models/nutrition/nutrition.dart';

class NutritionViewModel extends ChangeNotifier {
  NutritionViewModel({
    required this.repository,
    required this.localDate,
    this.dictation,
  }) : _today = localDateOf(repository.clock()) {
    if (!isValidLocalDate(localDate)) {
      throw ArgumentError.value(localDate, 'localDate');
    }
    repository.preferences.values.addListener(_notify);
  }

  final NutritionRepository repository;

  /// Gerätelokale Einstellungen (Wasser erfassen, Tagesziel).
  NutritionPreferenceValues get preferences =>
      repository.preferences.values.value;

  /// Getrunkenes Wasser des angezeigten Tages in ml.
  int get waterMl => snapshot?.waterMl ?? 0;

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

  /// Eingabe, zu der [searchResults] gehören; null ohne Online-Suche.
  String? onlineSearchQuery;

  /// Quelle, auf die die Trefferliste beschränkt ist.
  FoodSourceFilter searchSource = FoodSourceFilter.all;
  int _localSearchGeneration = 0;
  NutritionFood? barcodeFood;

  /// Tag oder Suche/Schätzung laden gerade.
  bool get isLoading => _dayLoading || _reading;
  bool isSaving = false;
  bool isOnlineOperation = false;

  /// Wechselt der Tag gerade? Währenddessen würde ein Speichern auf dem alten
  /// Tag landen.
  bool _dayLoading = false;

  /// Läuft eine Suche, Schätzung oder Aufnahme? Sie blockiert kein Speichern.
  bool _reading = false;

  /// Läuft ein Speichern, das ein Tipp starten dürfte? Sonst sind Zeilen, die
  /// speichern würden, deaktiviert.
  bool get canSave => !_disposed && !isSaving && !_dayLoading;

  /// Zählt übernommene Tagesstände; ein Laden, das davor gelesen hat, liest
  /// neu, statt einen älteren Stand über einen gespeicherten zu legen.
  int _dayRevision = 0;
  String? errorMessage;
  NutritionErrorOperation? errorOperation;
  String? statusMessage;
  bool _disposed = false;
  int _dayLoadGeneration = 0;
  String? _failedDate;

  /// Tag, der gerade geladen wird. Ein Neuladen währenddessen (etwa weil der
  /// Tab sichtbar wird) übernimmt ihn, statt auf [localDate] zurückzufallen.
  String? _pendingDate;

  /// Kalendertag, der zuletzt „heute“ war; daran erkennt [checkToday] einen
  /// neuen Tag.
  String _today;

  Future<void> load() => _loadDay(_pendingDate ?? _failedDate ?? localDate);

  /// Hat ein neuer Tag begonnen (über Nacht geöffnet oder Rückkehr in die
  /// App) und zeigt die Ansicht noch den alten Tag als „heute“, wechselt sie
  /// auf den neuen. Ein bewusst gewählter anderer Tag bleibt stehen. Liefert
  /// true, wenn sie wechselt; dann braucht es kein zusätzliches [load].
  bool checkToday() {
    final today = localDateOf(repository.clock());
    if (today == _today) return false;
    final showedToday = (_pendingDate ?? localDate) == _today;
    _today = today;
    if (!showedToday) return false;
    _loadDay(today);
    return true;
  }

  Future<void> selectDate(String value) {
    if (!isValidLocalDate(value)) {
      reportInputError('Bitte ein gültiges Datum im Format JJJJ-MM-TT wählen.');
      return Future.value();
    }
    return _loadDay(value);
  }

  Future<void> _loadDay(String date) async {
    final generation = ++_dayLoadGeneration;
    _pendingDate = date;
    _dayLoading = true;
    errorMessage = null;
    errorOperation = null;
    statusMessage = null;
    _notify();
    final waterRevision = _waterRevision;
    try {
      var dayRevision = _dayRevision;
      var next = await repository.read(date);
      // Ein Speichern, das während des Lesens fertig wurde, ist neuer als
      // dieser Stand.
      while (dayRevision != _dayRevision && !_disposed) {
        dayRevision = _dayRevision;
        next = await repository.read(date);
      }
      await repository.preferences.read();
      if (_disposed || generation != _dayLoadGeneration) return;
      // Kam während des Ladens eine Wasseränderung für diesen Tag an, ist ihr
      // Stand neuer als der gelesene.
      final current = snapshot;
      if (_waterRevision != waterRevision &&
          current != null &&
          current.day.localDate == date) {
        next = next.withWater(current.waterMl);
      }
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
        _pendingDate = null;
        _dayLoading = false;
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

  /// Liefert true, wenn der Eintrag gespeichert wurde.
  Future<bool> addManualEntry({
    required String productName,
    String? brand,
    required double amountGrams,
    required NutritionTotals per100Grams,
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
        per100Grams: per100Grams,
        source: null,
        pieceGrams: pieceGrams,
        pieceCount: pieceCount,
      ),
    );
    await _refresh();
    statusMessage = '„$productName“ hinzugefügt.';
  }, saving: true);

  Future<void> removeEntry(String entryId) => _run(
    () async {
      await repository.removeEntry(localDate, entryId);
      await _refresh();
      statusMessage = 'Eintrag entfernt.';
    },
    saving: true,
    operation: NutritionErrorOperation.diary,
  );

  /// Speichert den bearbeiteten Eintrag; Quelle und Nährwertsnapshot bleiben
  /// die des Originals.
  Future<void> updateEntry(NutritionEntry updated) => _run(
    () async {
      await repository.saveEntry(localDate, updated);
      await _refresh();
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
          await _refresh();
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
    await _refresh();
    statusMessage = 'Gericht als unabhängige Mahlzeit übernommen.';
  }, saving: true);

  Future<void> saveReusableMeal({
    String? id,
    required ReusableMeal meal,
    NutritionErrorOperation operation = NutritionErrorOperation.planning,
  }) => _run(
    () async {
      await repository.saveReusableMeal(meal, id: id);
      await _refresh();
      statusMessage = 'Gespeichertes Gericht lokal aktualisiert.';
    },
    saving: true,
    operation: operation,
  );

  Future<void> archiveReusableMeal(String id) => _run(
    () async {
      await repository.archiveReusableMeal(id);
      await _refresh();
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
      await _refresh();
      statusMessage = 'Ziele gespeichert. Sie gelten ab heute.';
    },
    saving: true,
    operation: NutritionErrorOperation.planning,
  );

  /// Legt die Tagesart des geöffneten Tages fest; null heißt automatisch.
  Future<void> setDayKind(NutritionDayKind? kind) => _run(
    () async {
      await repository.setDayKind(localDate, kind);
      await _refresh();
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
      await _refresh();
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
      await _refresh();
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
      await _refresh();
      statusMessage = 'Vorlage gespeichert.';
    },
    saving: true,
    operation: NutritionErrorOperation.planning,
  );

  Future<void> deleteTemplate(String templateId) => _run(
    () async {
      await repository.deleteTemplate(templateId);
      await _refresh();
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
    if (onlineSearchQuery != null && onlineSearchQuery != query.trim()) {
      searchResults = const [];
      onlineSearchQuery = null;
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
      onlineSearchQuery = query.trim();
      statusMessage = searchResults.isEmpty
          ? 'Keine Produkte bei Open Food Facts gefunden.'
          : '${searchResults.length} Produkte von Open Food Facts gefunden.';
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
  /// Liefert true, wenn der Eintrag gespeichert wurde.
  Future<bool> addFood(
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
    await _refresh();
    statusMessage = '„${food.name}“ hinzugefügt.';
  }, saving: true);

  /// Übernimmt [item] aus dem Schätzvorschlag. Das Objekt statt eines Index
  /// zu nehmen verhindert, dass ein später Tipp nach dem Entfernen einen
  /// anderen Bestandteil bucht; ist [item] nicht mehr im Vorschlag, passiert
  /// nichts. Liefert true, wenn der Bestandteil gespeichert wurde.
  Future<bool> confirmEstimatedComponent(
    NutritionEstimateComponent item,
  ) async {
    final draft = mealEstimateDraft;
    if (draft == null || !draft.components.contains(item)) return false;
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
    var saved = false;
    final ran = await _run(() async {
      final open = mealEstimateDraft;
      if (open == null || !open.components.contains(item)) return;
      final position = await _nextPosition();
      await repository.saveEntry(
        localDate,
        _estimatedEntry(item, draft, per100, position),
      );
      saved = true;
      await _refresh();
      // Nur den übernommenen Bestandteil entfernen; die übrigen bleiben
      // zum Prüfen stehen. Eine inzwischen neue Schätzung bleibt unberührt.
      if (identical(mealEstimateDraft, open)) {
        mealEstimateDraft = _withoutComponent(open, item, draft);
      }
      statusMessage = 'Geprüfte Schätzung als Eintrag gespeichert.';
      _notify();
    }, saving: true);
    return ran && saved;
  }

  NutritionEntry _estimatedEntry(
    NutritionEstimateComponent item,
    MealEstimateDraft draft,
    NutritionTotals per100,
    int position,
  ) => NutritionEntry(
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
  );

  /// Nächste freie Position in der gewählten Mahlzeit.
  Future<int> _nextPosition() async {
    final current = snapshot ?? await repository.read(localDate);
    return current.day.entries
            .where((entry) => entry.meal == selectedMeal)
            .fold<int>(
              0,
              (max, entry) => entry.position > max ? entry.position : max,
            ) +
        1;
  }

  /// Der offene Vorschlag [open] ohne [item] (Kopfdaten aus [draft]); null, wenn
  /// nichts übrig bleibt.
  MealEstimateDraft? _withoutComponent(
    MealEstimateDraft open,
    NutritionEstimateComponent item,
    MealEstimateDraft draft,
  ) {
    final remaining = [
      for (final component in open.components)
        if (!identical(component, item)) component,
    ];
    if (remaining.isEmpty) return null;
    return MealEstimateDraft(
      components: List.unmodifiable(remaining),
      provider: draft.provider,
      schemaVersion: draft.schemaVersion,
      estimatedAtUtc: draft.estimatedAtUtc,
    );
  }

  /// Verwirft einen offenen Vorschlag ohne Statusmeldung, z. B. beim Schließen.
  void setSearchSource(FoodSourceFilter value) {
    if (searchSource == value) return;
    searchSource = value;
    _notify();
  }

  /// Leert Suche, Treffer und Barcode-Ergebnis für das nächste Öffnen.
  void resetFoodSearch() {
    _localSearchGeneration++;
    localResults = const [];
    localResultsPartial = false;
    searchResults = const [];
    onlineSearchQuery = null;
    barcodeFood = null;
    searchSource = FoodSourceFilter.all;
    _notify();
  }

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
      await _refresh();
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
      await _refresh();
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

  /// Führt [action] aus und liefert true, wenn sie lief und ohne Fehler
  /// endete. Eine abgewiesene Aktion (zweiter Tipp, Speichern während des
  /// Tageswechsels) liefert false; Aufrufer schließen oder leeren Eingaben nur
  /// bei true.
  ///
  /// Speichernde Aktionen schließen sich gegenseitig und den Tageswechsel
  /// aus. Suche, Schätzung und Aufnahme laufen unabhängig davon parallel zu
  /// einem Speichern.
  Future<bool> _run(
    Future<void> Function() action, {
    bool saving = false,
    NutritionErrorOperation operation = NutritionErrorOperation.entry,
  }) async {
    if (_disposed) return false;
    if (saving ? !canSave : _reading) return false;
    if (saving) {
      isSaving = true;
    } else {
      _reading = true;
      isOnlineOperation = false;
    }
    errorMessage = null;
    errorOperation = null;
    statusMessage = null;
    _notify();
    var succeeded = false;
    try {
      await action();
      succeeded = true;
    } catch (error) {
      if (!_disposed) {
        errorMessage = _messageFor(error);
        errorOperation = operation;
      }
    } finally {
      if (saving) {
        isSaving = false;
      } else {
        _reading = false;
        isOnlineOperation = false;
      }
      _notify();
    }
    return succeeded && !_disposed;
  }

  /// Liest den angezeigten Tag neu und übernimmt ihn, solange er noch
  /// angezeigt wird; sonst stünde der Stand von Tag A unter Tag B. Ein
  /// Neuladen desselben Tages währenddessen verwirft ihn nicht: Das Laden
  /// liest bei einem übernommenen Stand selbst neu ([_dayRevision]). Eine
  /// inzwischen gespeicherte Wasseränderung bleibt erhalten.
  Future<void> _refresh() async {
    final date = localDate;
    final waterRevision = _waterRevision;
    var next = await repository.read(date);
    if (_disposed || date != localDate) return;
    final current = snapshot;
    if (_waterRevision != waterRevision &&
        current != null &&
        current.day.localDate == date) {
      next = next.withWater(current.waterMl);
    }
    snapshot = next;
    _dayRevision++;
  }

  /// Addiert [addedMl] Wasser zum angezeigten Tag (Schnellknöpfe).
  Future<bool> addWater(int addedMl) =>
      _changeWater((date) => repository.water.add(date, addedMl));

  /// Setzt die Wassermenge des angezeigten Tages (Korrektur, Rückgängig).
  /// Liefert false, wenn nichts gespeichert wurde.
  Future<bool> setWater(int amountMl) =>
      _changeWater((date) => repository.water.setAmount(date, amountMl));

  /// Zählt gespeicherte Wasseränderungen; ein laufendes Laden erkennt daran,
  /// dass sein gelesener Wasserstand veraltet ist.
  int _waterRevision = 0;

  /// Ohne Ladeanzeige, damit schnelle Tipps nicht flackern; die Warteschlange
  /// im Repository hält die Reihenfolge. Löscht nur eigene Wasserfehler.
  Future<bool> _changeWater(Future<int> Function(String date) change) async {
    if (_disposed) return false;
    final date = localDate;
    if (errorOperation == NutritionErrorOperation.water) {
      errorMessage = null;
      errorOperation = null;
    }
    try {
      final total = await change(date);
      _waterRevision++;
      final current = snapshot;
      if (current != null && current.day.localDate == date) {
        snapshot = current.withWater(total);
      }
      return true;
    } catch (error) {
      if (!_disposed) {
        errorMessage = _messageFor(error);
        errorOperation = NutritionErrorOperation.water;
      }
      return false;
    } finally {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    repository.preferences.values.removeListener(_notify);
    super.dispose();
  }

  String _messageFor(Object error) => switch (error) {
    StateError(:final message) when message.contains('Onlineverbindung') =>
      '$message Bitte später erneut versuchen.',
    PlatformException() => _captureMessage(error),
    LocalResourceChangedException() =>
      'Der Tag hat sich gerade beim Synchronisieren geändert. '
          'Bitte versuche es noch einmal.',
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

/// Quellen der Lebensmittelsuche.
enum FoodSourceFilter { all, bls, openFoodFacts }

enum NutritionErrorOperation {
  day,
  diary,

  /// Wasser-Karte und Korrektur-Sheet.
  water,
  entry,
  planning,
  search,
  barcode,
  estimate,
  label,
}

/// `JJJJ-MM-TT` des Kalendertags von [date].
String localDateOf(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

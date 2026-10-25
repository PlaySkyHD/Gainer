import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../data/repositories/training/training_log_repository.dart';
import '../../../domain/models/nutrition/day_target.dart';
import '../../../domain/models/nutrition/nutrition.dart';
import '../../../domain/models/training/training_schedule.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import '../training/training_schedule_sheet.dart';
import 'food_add_target.dart';
import 'meal_dictation_controller.dart';
import 'nutrition_averages_view.dart';
import 'nutrition_day_kind.dart';
import 'nutrition_day_templates.dart';
import 'nutrition_settings_screen.dart';
import 'nutrition_targets_editor.dart';
import 'nutrition_view_model.dart';
import 'nutrition_water_card.dart';

const _notRecognizedLabel = 'nicht erkannt';

const _confidenceNames = {
  'low': 'unsicher',
  'medium': 'mittel',
  'high': 'sicher',
};

const _saltName = 'Salz';
const _saltPer100 = NutritionTotals(
  kilocalories: 0,
  proteinGrams: 0,
  carbohydrateGrams: 0,
  fatGrams: 0,
  saltGrams: 100,
  fiberGrams: 0,
);

/// Übliche Mengen beim Selbstsalzen; 1 Teelöffel Salz wiegt etwa 6 g.
const _saltPresets = [
  (label: 'Prise', grams: 0.5),
  (label: 'Halber Teelöffel', grams: 3.0),
  (label: 'Teelöffel', grams: 6.0),
];

enum _NutritionEntryMode {
  choices,
  recent,
  meals,
  manual,
  salt,
  search,
  barcode,
  estimate,
  label,
}

extension on _NutritionEntryMode {
  String get title => switch (this) {
    _NutritionEntryMode.choices => 'Lebensmittel hinzufügen',
    _NutritionEntryMode.recent => 'Zuletzt verwendet',
    _NutritionEntryMode.meals => 'Gespeicherte Gerichte',
    _NutritionEntryMode.manual => 'Manuell erfassen',
    _NutritionEntryMode.salt => 'Salz hinzufügen',
    _NutritionEntryMode.search => 'Lebensmittel suchen',
    _NutritionEntryMode.barcode => 'Barcode',
    _NutritionEntryMode.estimate => 'Mahlzeit schätzen',
    _NutritionEntryMode.label => 'Etikett erfassen',
  };

  String get description => switch (this) {
    _NutritionEntryMode.choices => 'Erfassungsart auswählen',
    _NutritionEntryMode.recent => 'Lebensmittel von früheren Einträgen',
    _NutritionEntryMode.meals => 'Ein gespeichertes Gericht übernehmen',
    _NutritionEntryMode.manual => 'Nährwerte selbst eingeben',
    _NutritionEntryMode.salt => 'Selbst gesalzen, z. B. eine Prise',
    _NutritionEntryMode.search => 'BLS-Lebensmittel und Produkte',
    _NutritionEntryMode.barcode => 'Produkt über den Barcode finden',
    _NutritionEntryMode.estimate => 'Text oder Foto als Vorschlag prüfen',
    _NutritionEntryMode.label => 'Nährwertetikett fotografieren und prüfen',
  };

  IconData get icon => switch (this) {
    _NutritionEntryMode.choices => CupertinoIcons.add,
    _NutritionEntryMode.recent => CupertinoIcons.clock,
    _NutritionEntryMode.meals => CupertinoIcons.book,
    _NutritionEntryMode.manual => CupertinoIcons.pencil,
    _NutritionEntryMode.salt => CupertinoIcons.circle_grid_hex,
    _NutritionEntryMode.search => CupertinoIcons.search,
    _NutritionEntryMode.barcode => CupertinoIcons.barcode_viewfinder,
    _NutritionEntryMode.estimate => CupertinoIcons.sparkles,
    _NutritionEntryMode.label => CupertinoIcons.doc_text_viewfinder,
  };
}

/// Erfassungswege je Ziel, gruppiert: finden, mit KI erfassen, selbst
/// eintragen. Mehrteilige Schätzung, Etikettenscan und das Übernehmen
/// gespeicherter Gerichte sind nur für Tagesmahlzeiten verfügbar.
List<({String title, List<_NutritionEntryMode> modes})> _modeGroupsFor(
  FoodAddTarget target,
) {
  final day = target is DayMealTarget;
  return [
    (
      title: 'Finden',
      modes: const [
        _NutritionEntryMode.search,
        _NutritionEntryMode.recent,
        _NutritionEntryMode.barcode,
      ],
    ),
    if (day)
      (
        title: 'Mit KI',
        modes: const [_NutritionEntryMode.estimate, _NutritionEntryMode.label],
      ),
    (
      title: 'Selbst eintragen',
      modes: [
        if (day) _NutritionEntryMode.meals,
        _NutritionEntryMode.manual,
        _NutritionEntryMode.salt,
      ],
    ),
  ];
}

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({
    super.key,
    required this.viewModel,
    this.training,
    this.visibility,
    this.isVisible,
    this.refresh,
  });
  final NutritionViewModel viewModel;

  /// Für „Rhythmus einrichten“ im Ziel-Editor; ohne fehlt der Link.
  final TrainingLogRepository? training;

  /// Meldet Tab-Wechsel; zusammen mit [isVisible] lädt der Tag neu, wenn der
  /// Tab sichtbar wird (Training beendet, Rhythmus geändert).
  final Listenable? visibility;
  final bool Function()? isVisible;

  /// Löst Neuladen aus, solange der Tab sichtbar ist (z. B. Sync-Ende).
  final Listenable? refresh;

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _amount = TextEditingController(text: '100');
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _salt = TextEditingController();
  final _fiber = TextEditingController();
  final _pieceGrams = TextEditingController();
  final _pieceCount = TextEditingController();
  final _addPieces = TextEditingController();
  final _search = TextEditingController();
  final _estimateText = TextEditingController();
  final _saltAmount = TextEditingController();
  MealDictationController? _dictation;
  Timer? _localSearch;
  late final AppLifecycleListener _lifecycle;
  Timer? _midnight;

  /// Schließt das offene Hinzufügen-Sheet; null, wenn keines offen ist.
  VoidCallback? _closeEntrySheet;

  /// „Mehrere hinzufügen“: Das Sheet bleibt nach jedem Eintrag offen.
  bool _addingMultiple = false;
  bool _wasVisible = true;

  bool get _visible => widget.isVisible?.call() ?? true;

  void _onVisibility() {
    final visible = _visible;
    if (visible && !_wasVisible) _reload();
    _wasVisible = visible;
  }

  void _onRefresh() {
    if (_visible) _reload();
  }

  /// Lädt neu; hat inzwischen ein neuer Tag begonnen, wandert „heute“ mit.
  void _reload() {
    if (!widget.viewModel.checkToday()) widget.viewModel.load();
  }

  void _onResume() {
    // Nach der Rückkehr in die App kann ein neuer Tag begonnen haben.
    if (_visible) {
      _reload();
    } else {
      widget.viewModel.checkToday();
    }
    _scheduleMidnight();
  }

  /// Weckt kurz nach Mitternacht, damit „heute“ mitwandert, auch wenn die App
  /// über Nacht geöffnet bleibt.
  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight = Timer(next.difference(now), () {
      if (!mounted) return;
      widget.viewModel.checkToday();
      _scheduleMidnight();
    });
  }

  @override
  void didUpdateWidget(NutritionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.visibility, widget.visibility)) {
      oldWidget.visibility?.removeListener(_onVisibility);
      widget.visibility?.addListener(_onVisibility);
    }
    if (!identical(oldWidget.refresh, widget.refresh)) {
      oldWidget.refresh?.removeListener(_onRefresh);
      widget.refresh?.addListener(_onRefresh);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.visibility?.addListener(_onVisibility);
    widget.refresh?.addListener(_onRefresh);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _wasVisible = _visible;
    _scheduleMidnight();
    widget.viewModel.load();
    if (widget.viewModel.dictation case final platform?) {
      _dictation = MealDictationController(
        platform: platform,
        text: _estimateText,
      );
    }
  }

  @override
  void dispose() {
    widget.visibility?.removeListener(_onVisibility);
    widget.refresh?.removeListener(_onRefresh);
    _dictation?.dispose();
    _localSearch?.cancel();
    _lifecycle.dispose();
    _midnight?.cancel();
    for (final controller in [
      _name,
      _brand,
      _amount,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _salt,
      _fiber,
      _pieceGrams,
      _pieceCount,
      _addPieces,
      _search,
      _estimateText,
      _saltAmount,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      final snapshot = vm.snapshot;
      final dayView = GainerScaffold(
        title: 'Ernährung',
        leading: GainerDayNavigator(
          pillKey: const ValueKey('nutrition-date-pill'),
          label: gainerDayLabel(
            DateTime.parse(vm.localDate),
            DateTime.parse(_dateString(vm.repository.clock())),
          ),
          onPrevious: () => _shiftDay(-1),
          onNext: () => _shiftDay(1),
          onPick: () => _pickDay(context),
        ),
        trailing: [
          GestureDetector(
            onLongPress: () => _offerMultipleAdd(null),
            child: GainerToolbarButton(
              key: const ValueKey('nutrition-add-food'),
              icon: CupertinoIcons.add,
              semanticLabel: 'Lebensmittel hinzufügen',
              onPressed: _openEntry,
            ),
          ),
          GainerToolbarButton(
            key: const ValueKey('nutrition-more-menu'),
            icon: CupertinoIcons.ellipsis,
            semanticLabel: 'Weitere Aktionen',
            onPressed: _showMenu,
          ),
        ],
        children: [
          if (vm.errorMessage != null &&
              vm.errorOperation == NutritionErrorOperation.day) ...[
            _notice(context, vm.errorMessage!, isError: true),
            GainerPillButton(
              label: 'Tagebuch erneut laden',
              icon: CupertinoIcons.refresh,
              variant: GainerPillVariant.tonal,
              expand: true,
              onPressed: vm.load,
            ),
          ],
          if (snapshot == null && vm.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CupertinoActivityIndicator()),
            ),
          if (snapshot != null) ..._dayChildren(context, vm, snapshot),
          if (vm.isSaving || vm.isOnlineOperation)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CupertinoActivityIndicator()),
            ),
        ],
      );
      if (vm.errorMessage == null ||
          vm.errorOperation != NutritionErrorOperation.diary) {
        return dayView;
      }
      // Fehler des Tagebuchs bleiben oberhalb der Liste sichtbar, auch wenn
      // der Nutzer nach unten scrollt.
      return Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _notice(context, vm.errorMessage!, isError: true),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: dayView,
            ),
          ),
        ],
      );
    },
  );

  List<Widget> _dayChildren(
    BuildContext context,
    NutritionViewModel vm,
    NutritionSnapshot snapshot,
  ) => [
    _DayCard(
      totals: snapshot.day.totals,
      target: snapshot.dayTarget,
      onManage: _editTargets,
      onDayKind: () => _chooseDayKind(snapshot),
    ),
    if (vm.preferences.waterEnabled)
      Padding(
        padding: const EdgeInsets.only(top: GainerSpacing.s),
        child: NutritionWaterCard(
          amountMl: vm.waterMl,
          goalMl: vm.preferences.waterGoalMl,
          onAdd: vm.addWater,
          error: vm.errorOperation == NutritionErrorOperation.water
              ? vm.errorMessage
              : null,
          onEdit: () => showWaterAmountSheet(
            context,
            currentMl: vm.waterMl,
            onSave: (amountMl) async => await vm.setWater(amountMl)
                ? null
                : vm.errorMessage ?? 'Speichern nicht möglich.',
          ),
        ),
      ),
    if (snapshot.suggestedTemplate case final template?)
      Padding(
        padding: const EdgeInsets.only(top: GainerSpacing.s),
        child: GainerGroupedSection(
          children: [
            GainerListRow(
              key: const ValueKey('nutrition-template-suggestion'),
              title: 'Vorlage „${template.name}“ übernehmen',
              subtitle: templateSummary(template),
              leadingIcon: CupertinoIcons.doc_on_doc,
              trailing: GainerPillButton(
                label: _applyLabel,
                variant: GainerPillVariant.tonal,
                onPressed: vm.isSaving
                    ? null
                    : () => vm.applyTemplate(template.templateId),
              ),
            ),
          ],
        ),
      ),
    NutritionAveragesEntry(repository: vm.repository, refreshKey: snapshot),
    if (vm.statusMessage != null)
      Semantics(liveRegion: true, child: _notice(context, vm.statusMessage!)),
    for (final meal in NutritionMeal.values)
      Padding(
        padding: const EdgeInsets.only(top: GainerSpacing.l),
        child: _MealSection(
          key: ValueKey('meal-${meal.name}'),
          meal: meal,
          entries: snapshot.day.entries
              .where((entry) => entry.meal == meal)
              .toList(),
          onAdd: () {
            vm.selectMeal(meal);
            _openEntry();
          },
          onAddMultiple: () => _offerMultipleAdd(meal),
          onEdit: _editEntry,
          onRemove: (entry) => vm.removeEntry(entry.entryId),
          onConfirmRemove: (entry) => confirmGainerDelete(
            context,
            title: 'Eintrag löschen?',
            message: '„${entry.productName}“ wird aus dem Tagebuch entfernt.',
          ),
          onMoveTo: (entries, orderedIds) =>
              _applyEntryOrder(meal, entries, orderedIds),
        ),
      ),
  ];

  /// Ordnet die Einträge einer Mahlzeit per Einzelschritten in [targetIds]
  /// um. Jeder Schritt ist ein `moveEntry` wie bisher beim Nach-oben-Schieben.
  Future<void> _applyEntryOrder(
    NutritionMeal meal,
    List<NutritionEntry> entries,
    List<String> targetIds,
  ) async {
    final current = [for (final entry in entries) entry.entryId];
    for (var target = 0; target < targetIds.length; target++) {
      final id = targetIds[target];
      final from = current.indexOf(id);
      if (from == target) continue;
      current
        ..removeAt(from)
        ..insert(target, id);
      await widget.viewModel.moveEntry(id, meal, target);
      if (!mounted) return;
    }
  }

  /// Menü der Seitenaktionen (…): Vorlagen, Ziele und Gerichte.
  Future<void> _showMenu() async {
    final snapshot = widget.viewModel.snapshot;
    final hasEntries = snapshot?.day.entries.isNotEmpty ?? false;
    final hasTemplates = snapshot?.templates.isNotEmpty ?? false;
    final choice = await showGainerActionSheet<_NutritionMenuAction>(
      context: context,
      title: 'Ernährung',
      groups: [
        [
          GainerSheetAction(
            label: 'Tag als Vorlage speichern',
            icon: CupertinoIcons.square_arrow_down,
            hint: hasEntries ? null : 'Der Tag hat noch keine Einträge.',
            enabled: hasEntries,
            value: _NutritionMenuAction.saveTemplate,
          ),
          GainerSheetAction(
            label: 'Aus Vorlage befüllen',
            icon: CupertinoIcons.doc_on_doc,
            hint: hasTemplates ? null : 'Noch keine Vorlage gespeichert.',
            enabled: hasTemplates,
            value: _NutritionMenuAction.applyTemplate,
          ),
        ],
        const [
          GainerSheetAction(
            label: 'Ziele',
            icon: CupertinoIcons.scope,
            value: _NutritionMenuAction.targets,
          ),
          GainerSheetAction(
            label: 'Gerichte und Vorlagen verwalten',
            icon: CupertinoIcons.slider_horizontal_3,
            value: _NutritionMenuAction.planning,
          ),
          GainerSheetAction(
            label: 'Einstellungen',
            icon: CupertinoIcons.gear,
            hint: 'Wasser erfassen',
            value: _NutritionMenuAction.settings,
          ),
        ],
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case _NutritionMenuAction.saveTemplate:
        await _saveDayAsTemplate();
      case _NutritionMenuAction.applyTemplate:
        await _applyTemplate();
      case _NutritionMenuAction.targets:
        await _editTargets();
      case _NutritionMenuAction.planning:
        await _openPlanning();
      case _NutritionMenuAction.settings:
        await openNutritionSettings(
          context,
          preferences: widget.viewModel.repository.preferences,
        );
      case null:
    }
  }

  /// Öffnet den Ziel-Editor; gespeichert wird mit Wirkung ab heute.
  Future<void> _editTargets() async {
    final vm = widget.viewModel;
    vm.dismissActionError();
    final current = await vm.repository.currentTargets();
    final projection = await vm.repository.readProjection();
    if (!mounted) return;
    final training = widget.training;
    final input = await showNutritionTargetsEditor(
      context,
      current: current,
      hasSchedule: projection.schedule != null,
      onSetUpSchedule: training == null
          ? null
          : () => showTrainingScheduleSheet(context, repository: training),
    );
    if (input == null || !mounted) return;
    await vm.saveTargets(
      training: input.training,
      restDay: input.restDay,
      saltGrams: input.saltGrams,
      fiberGrams: input.fiberGrams,
    );
  }

  Future<void> _chooseDayKind(NutritionSnapshot snapshot) async {
    final result = await showDayKindSheet(
      context,
      automatic: snapshot.automaticDayKind,
      current: snapshot.day.dayKind,
    );
    if (!result.changed || !mounted) return;
    await widget.viewModel.setDayKind(result.kind);
  }

  Future<void> _saveDayAsTemplate() async {
    final vm = widget.viewModel;
    final templates = vm.snapshot?.templates ?? const <NutritionDayTemplate>[];
    final choice = await showSaveTemplateSheet(context, templates: templates);
    if (!mounted) return;
    switch (choice) {
      case SaveAsNewTemplate(:final name, :final dayKind):
        await vm.saveDayAsTemplate(name: name, dayKind: dayKind);
      case OverwriteTemplate(:final templateId):
        await vm.saveDayAsTemplate(overwriteId: templateId);
      case null:
    }
  }

  Future<void> _applyTemplate() async {
    final vm = widget.viewModel;
    final snapshot = vm.snapshot;
    if (snapshot == null || snapshot.templates.isEmpty) return;
    final template = await showChooseTemplateSheet(
      context,
      templates: snapshot.templates,
    );
    if (template == null || !mounted) return;
    var mode = TemplateApplyMode.append;
    if (snapshot.day.entries.isNotEmpty) {
      final chosen = await askTemplateApplyMode(context);
      if (chosen == null || !mounted) return;
      mode = chosen;
    }
    await vm.applyTemplate(template.templateId, mode: mode);
  }

  /// Öffnet den gemeinsamen Hinzufügen-Dialog als Sheet. Für [DayMealTarget]
  /// schreibt er Einträge in die gewählte Mahlzeit und liefert `null`. Für
  /// [MealDraftTarget] liefert er das bestätigte Lebensmittel als Draft zurück
  /// und verändert keinen Ernährungstag; Abbrechen liefert `null`.
  Future<FoodComponentDraft?> _openEntry({
    FoodAddTarget target = const DayMealTarget(),
    bool multiple = false,
  }) {
    final vm = widget.viewModel;
    vm.dismissActionError();
    _addingMultiple = multiple && target is DayMealTarget;
    var mode = _NutritionEntryMode.choices;
    return showGainerSheet<FoodComponentDraft>(
      context: context,
      heightFactor: 0.9,
      builder: (sheetContext) {
        _closeEntrySheet = () => Navigator.of(sheetContext).pop();
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) => AnimatedBuilder(
            animation: vm,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _entryHeader(
                  sheetContext,
                  target,
                  mode,
                  multiple: _addingMultiple,
                  onBack: () => setSheetState(() {
                    vm.dismissActionError();
                    mode = _NutritionEntryMode.choices;
                  }),
                ),
                // Die Mahlzeit wird auf der Startseite gewählt; Unterseiten
                // zeigen nur ihr Werkzeug.
                if (target is DayMealTarget &&
                    mode == _NutritionEntryMode.choices)
                  _mealSegment(vm),
                Expanded(
                  child: ListView(
                    // Jede Seite beginnt oben, auch nach Scrollen auf der Startseite.
                    key: ValueKey('nutrition-entry-page-${mode.name}'),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      GainerSpacing.m,
                      GainerSpacing.m,
                      GainerSpacing.m,
                      GainerSpacing.l,
                    ),
                    children: mode == _NutritionEntryMode.choices
                        ? _choiceChildren(
                            target,
                            (option) => setSheetState(() => mode = option),
                          )
                        : _entryChildren(
                            context,
                            vm,
                            mode,
                            target,
                            (draft) => Navigator.of(sheetContext).pop(draft),
                            (option) => setSheetState(() => mode = option),
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(_resetEntrySheet);
  }

  /// Beim Schließen des Sheets beginnt das nächste Öffnen leer: Startseite,
  /// leere Suche ohne alte Treffer, 100 g und eine neue Schätzung.
  void _resetEntrySheet() {
    _closeEntrySheet = null;
    _addingMultiple = false;
    if (!mounted) return;
    _localSearch?.cancel();
    _dictation?.cancel();
    _estimateText.clear();
    _saltAmount.clear();
    _search.clear();
    _amount.text = '100';
    _addPieces.clear();
    widget.viewModel
      ..clearEstimateDraft()
      ..resetFoodSearch();
  }

  /// Nach erfolgreichem Speichern in eine Mahlzeit schließt das Sheet. Beim
  /// Hinzufügen mehrerer bleibt es offen und ist bereit für das nächste.
  void _closeAfterSave() {
    if (widget.viewModel.errorMessage != null) return;
    if (!_addingMultiple) {
      _closeEntrySheet?.call();
      return;
    }
    _localSearch?.cancel();
    _search.clear();
    _amount.text = '100';
    _addPieces.clear();
    widget.viewModel.resetFoodSearch();
  }

  /// Langes Drücken auf „Hinzufügen“: mehrere Einträge nacheinander, ohne
  /// dass das Sheet jedes Mal schließt.
  Future<void> _offerMultipleAdd(NutritionMeal? meal) async {
    final choice = await showGainerActionSheet<bool>(
      context: context,
      title: meal == null ? 'Hinzufügen' : _mealName(meal),
      groups: const [
        [
          GainerSheetAction(
            label: 'Mehrere hinzufügen',
            icon: CupertinoIcons.square_stack,
            value: true,
            hint: 'Das Fenster bleibt nach jedem Eintrag offen.',
          ),
        ],
      ],
    );
    if (choice != true || !mounted) return;
    if (meal != null) widget.viewModel.selectMeal(meal);
    await _openEntry(multiple: true);
  }

  Widget _entryHeader(
    BuildContext sheetContext,
    FoodAddTarget target,
    _NutritionEntryMode mode, {
    required VoidCallback onBack,
    bool multiple = false,
  }) {
    final atChoices = mode == _NutritionEntryMode.choices;
    return GainerSheetHeader(
      title: atChoices
          ? (target is MealDraftTarget
                ? 'Bestandteil hinzufügen'
                : multiple
                ? 'Mehrere hinzufügen'
                : 'Hinzufügen')
          : mode.title,
      compactTrailing: true,
      trailing: multiple
          ? GainerToolbarButton(
              key: const ValueKey('nutrition-entry-done'),
              icon: CupertinoIcons.checkmark,
              semanticLabel: 'Fertig',
              onPressed: () => Navigator.of(sheetContext).pop(),
            )
          : null,
      leading: GainerToolbarButton(
        key: ValueKey(
          atChoices ? 'nutrition-entry-close' : 'nutrition-entry-options',
        ),
        icon: atChoices ? CupertinoIcons.xmark : CupertinoIcons.chevron_left,
        semanticLabel: atChoices ? 'Schließen' : 'Optionen',
        onPressed: atChoices ? () => Navigator.of(sheetContext).pop() : onBack,
      ),
    );
  }

  Widget _mealSegment(NutritionViewModel vm) => Padding(
    padding: const EdgeInsets.fromLTRB(
      GainerSpacing.m,
      GainerSpacing.s,
      GainerSpacing.m,
      0,
    ),
    child: GainerSegmentedControl<NutritionMeal>(
      options: {
        for (final meal in NutritionMeal.values) meal: _mealShortName(meal),
      },
      value: vm.selectedMeal,
      onChanged: vm.selectMeal,
    ),
  );

  List<Widget> _choiceChildren(
    FoodAddTarget target,
    ValueChanged<_NutritionEntryMode> onSelectMode,
  ) => [
    for (final (index, group) in _modeGroupsFor(target).indexed) ...[
      if (index > 0) const SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        header: group.title,
        children: [
          for (final option in group.modes)
            GainerListRow(
              key: ValueKey('nutrition-mode-${option.name}'),
              leadingIcon: option.icon,
              title: option.title,
              subtitle: option.description,
              showChevron: true,
              onTap: () => onSelectMode(option),
            ),
        ],
      ),
    ],
  ];

  List<Widget> _entryChildren(
    BuildContext context,
    NutritionViewModel vm,
    _NutritionEntryMode mode,
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
    ValueChanged<_NutritionEntryMode> onSelectMode,
  ) => [
    if (vm.errorMessage != null &&
        vm.errorOperation != null &&
        vm.errorOperation != NutritionErrorOperation.day)
      _notice(context, vm.errorMessage!, isError: true),
    if (vm.statusMessage != null && target is DayMealTarget)
      Semantics(liveRegion: true, child: _notice(context, vm.statusMessage!)),
    ..._entryTools(context, vm, mode, target, onDraft, onSelectMode),
    if (vm.isSaving || vm.isOnlineOperation)
      const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CupertinoActivityIndicator()),
      ),
  ];

  /// Menge in Gramm oder als Anzahl. Die Anzahl gilt für Lebensmittel mit
  /// bekanntem Stückgewicht („1 Stk = 50 g“) und hat dann Vorrang.
  Widget _amountGroup() => GainerGroupedSection(
    footer: 'Anzahl gilt für Lebensmittel mit Stückgewicht, z. B. Eier.',
    children: [
      GainerTextFieldRow(
        label: 'Menge',
        unit: 'g',
        controller: _amount,
        keyboardType: _decimalKeyboard,
        fieldKey: const ValueKey('nutrition-entry-amount'),
        onChanged: (_) => _addPieces.clear(),
      ),
      _PieceCountRow(
        key: const ValueKey('nutrition-entry-pieces'),
        controller: _addPieces,
      ),
    ],
  );

  List<Widget> _entryTools(
    BuildContext context,
    NutritionViewModel vm,
    _NutritionEntryMode mode,
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
    ValueChanged<_NutritionEntryMode> onSelectMode,
  ) {
    void submit(NutritionFood food) => _submitFood(food, target, onDraft);
    return switch (mode) {
      _NutritionEntryMode.manual => [
        ..._foodFormGroups(
          name: _name,
          brand: _brand,
          amount: _amount,
          kcal: _kcal,
          protein: _protein,
          carbs: _carbs,
          fat: _fat,
          salt: _salt,
          fiber: _fiber,
          pieceGrams: _pieceGrams,
          pieceCount: _pieceCount,
          nameKey: const ValueKey('nutrition-entry-name'),
          brandKey: const ValueKey('nutrition-entry-brand'),
          amountKey: const ValueKey('nutrition-entry-amount'),
          kcalKey: const ValueKey('nutrition-entry-kcal'),
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerPillButton(
          key: const ValueKey('nutrition-entry-save'),
          label: target is DayMealTarget ? 'Manuell speichern' : _applyLabel,
          expand: true,
          onPressed: vm.isSaving ? null : () => _addManual(target, onDraft),
        ),
      ],
      _NutritionEntryMode.recent => _recentTools(vm, submit),
      _NutritionEntryMode.meals => _mealTools(vm),
      _NutritionEntryMode.search => _searchTools(vm, submit),
      _NutritionEntryMode.barcode => _barcodeTools(vm, submit),
      _NutritionEntryMode.estimate => _estimateTools(vm, onSelectMode),
      _NutritionEntryMode.salt => _saltTools(target, onDraft),
      _NutritionEntryMode.label => [
        GainerGroupedSection(
          footer: 'Du prüfst alle Werte, bevor etwas gespeichert wird.',
          children: [
            GainerListRow(
              leadingIcon: CupertinoIcons.doc_text_viewfinder,
              title: 'Nährwerttabelle fotografieren',
              subtitle: 'Gerade und gut lesbar, mit Kalorien und Makros.',
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerPillButton(
          label: 'Etikett fotografieren',
          icon: CupertinoIcons.camera,
          expand: true,
          isLoading: vm.isOnlineOperation,
          onPressed: vm.isOnlineOperation ? null : _scanLabel,
        ),
      ],
      _NutritionEntryMode.choices => const [],
    };
  }

  /// Ergebniszeilen von „Zuletzt“, Suche und Barcode. Antippen übernimmt das
  /// Lebensmittel mit der eingegebenen Menge.
  Widget _foodResults(
    List<NutritionFood> foods,
    String fallback,
    ValueChanged<NutritionFood> onSelect, {
    String? header,
  }) => GainerGroupedSection(
    header: header,
    children: [
      for (final food in foods)
        GainerListRow(
          title: food.name,
          // Quelle zuerst, damit gemischte Treffer unterscheidbar sind.
          subtitle: [
            food.source.provider ?? fallback,
            ?food.brand,
            '${_fmtKcal(food.per100Grams.kilocalories)} kcal / 100 g',
            if (food.pieceGrams case final grams?)
              '1 Stk = ${_fmtGrams(grams)} g',
          ].join(' · '),
          trailing: const _AddGlyph(),
          onTap: () => onSelect(food),
        ),
    ],
  );

  List<Widget> _recentTools(
    NutritionViewModel vm,
    ValueChanged<NutritionFood> onSelect,
  ) {
    final foods = vm.snapshot?.recentFoods ?? const <NutritionFood>[];
    return [
      _amountGroup(),
      const SizedBox(height: GainerSpacing.m),
      if (foods.isEmpty)
        _hint('Noch keine zuletzt verwendeten Lebensmittel.')
      else
        _foodResults(foods, 'Lebensmittel', onSelect),
    ];
  }

  List<Widget> _mealTools(NutritionViewModel vm) {
    final meals = [
      for (final meal in vm.snapshot?.meals ?? const [])
        if (meal.value.status == 'Active') meal,
    ];
    if (meals.isEmpty) return [_hint('Noch keine gespeicherten Gerichte.')];
    return [
      GainerGroupedSection(
        children: [
          for (final meal in meals)
            _ReusableMealRow(
              meal: meal.value,
              onAdd: () => _addReusableMeal(meal.id, meal.value),
              onEdit: null,
              onArchive: null,
            ),
        ],
      ),
    ];
  }

  /// Eine Trefferliste für BLS und Open Food Facts. Der Filter beschränkt sie
  /// auf eine Quelle; Produkte kommen erst auf ausdrücklichen Wunsch dazu,
  /// weil Open Food Facts Suchanfragen begrenzt.
  List<Widget> _searchTools(
    NutritionViewModel vm,
    ValueChanged<NutritionFood> onSelect,
  ) {
    final query = _search.text.trim();
    final source = vm.searchSource;
    final showLocal = source != FoodSourceFilter.openFoodFacts;
    final showOnline = source != FoodSourceFilter.bls;
    final onlineCurrent = vm.onlineSearchQuery == query;
    final foods = [
      if (showLocal) ...vm.localResults,
      if (showOnline && onlineCurrent) ...vm.searchResults,
    ];
    final canStartOnline =
        showOnline &&
        vm.canSearchOnline &&
        !onlineCurrent &&
        !vm.isOnlineOperation;
    // Nur der Filter „Open Food Facts“ braucht den Hinweis; in „Alle“
    // genügen die BLS-Treffer.
    final needsInternet =
        source == FoodSourceFilter.openFoodFacts && !vm.canSearchOnline;
    return [
      GainerSearchField(
        key: const ValueKey('nutrition-entry-search'),
        controller: _search,
        placeholder: 'Lebensmittel, Produkt oder Marke',
        onChanged: (query) => _scheduleLocalSearch(vm, query),
        onSubmitted: (query) => _searchFoods(vm, query),
      ),
      const SizedBox(height: GainerSpacing.m),
      _amountGroup(),
      if (query.length >= 2) ...[
        const SizedBox(height: GainerSpacing.m),
        GainerSegmentedControl<FoodSourceFilter>(
          key: const ValueKey('nutrition-search-source'),
          options: const {
            FoodSourceFilter.all: 'Alle',
            FoodSourceFilter.bls: 'BLS',
            // Ausgeschrieben passt „Open Food Facts“ nicht ins Segment;
            // die Zeilen nennen die Quelle.
            FoodSourceFilter.openFoodFacts: 'Produkte',
          },
          value: source,
          onChanged: (value) => _selectSearchSource(vm, value, query),
        ),
        // Über der Liste, damit sie nicht hinter 20 Treffern verschwindet.
        if (needsInternet) ...[
          const SizedBox(height: GainerSpacing.m),
          _hint('Produktsuche braucht Internet.'),
        ] else if (canStartOnline) ...[
          const SizedBox(height: GainerSpacing.m),
          GainerPillButton(
            key: const ValueKey('nutrition-search-online'),
            label: 'In Open Food Facts suchen',
            icon: CupertinoIcons.globe,
            variant: GainerPillVariant.tonal,
            expand: true,
            onPressed: () => _searchFoods(vm, query),
          ),
        ],
        if (foods.isNotEmpty) ...[
          const SizedBox(height: GainerSpacing.m),
          _foodResults(
            foods,
            'Lebensmittel',
            onSelect,
            header: showLocal && vm.localResultsPartial ? 'Teiltreffer' : null,
          ),
        ] else if (!canStartOnline &&
            !vm.isOnlineOperation &&
            !needsInternet) ...[
          const SizedBox(height: GainerSpacing.m),
          _hint('Keine Treffer.'),
        ],
      ],
    ];
  }

  /// „Produkte“ heißt: Open Food Facts zeigen. Für die aktuelle Eingabe wird
  /// dann online gesucht, falls das noch nicht geschehen ist.
  void _selectSearchSource(
    NutritionViewModel vm,
    FoodSourceFilter value,
    String query,
  ) {
    vm.setSearchSource(value);
    if (value == FoodSourceFilter.openFoodFacts &&
        vm.canSearchOnline &&
        vm.onlineSearchQuery != query &&
        query.length >= 2) {
      _searchFoods(vm, query);
    }
  }

  /// Lokale Treffer folgen der Eingabe mit kurzer Pause, damit nicht jeder
  /// Tastendruck eine Suche startet.
  void _scheduleLocalSearch(NutritionViewModel vm, String query) {
    _localSearch?.cancel();
    _localSearch = Timer(
      const Duration(milliseconds: 150),
      () => vm.searchLocalFoods(query),
    );
  }

  List<Widget> _barcodeTools(
    NutritionViewModel vm,
    ValueChanged<NutritionFood> onSelect,
  ) => [
    _amountGroup(),
    const SizedBox(height: GainerSpacing.m),
    GainerPillButton(
      label: 'Barcode scannen',
      icon: CupertinoIcons.barcode_viewfinder,
      variant: GainerPillVariant.tonal,
      expand: true,
      onPressed: vm.isOnlineOperation ? null : vm.lookupBarcode,
    ),
    if (vm.barcodeFood case final food?) ...[
      const SizedBox(height: GainerSpacing.m),
      _foodResults([food], 'Barcode', onSelect),
    ],
  ];

  /// Selbst gesalzen: Schnellwahl oder eigene Menge. Salz ist ein Eintrag mit
  /// 0 kcal und 100 g Salz pro 100 g, zählt also nur zum Tagessalz.
  List<Widget> _saltTools(
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
  ) => [
    ValueListenableBuilder<TextEditingValue>(
      valueListenable: _saltAmount,
      builder: (context, value, _) {
        final colors = GainerDesign.colorsOf(context);
        final grams = _parse(value.text);
        final valid = grams != null && grams > 0 && grams <= 100;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GainerGroupedSection(
              footer: 'Zählt zum Salz des Tages, nicht zu den Kalorien.',
              children: [
                for (final preset in _saltPresets)
                  GainerListRow(
                    key: ValueKey('nutrition-salt-${preset.grams}'),
                    title: preset.label,
                    subtitle: '${_fmtGrams(preset.grams)} g',
                    trailing: grams == preset.grams
                        ? Icon(
                            CupertinoIcons.checkmark,
                            size: 18,
                            color: colors.accent,
                          )
                        : null,
                    onTap: () => _saltAmount.text = _grams(preset.grams),
                  ),
                GainerTextFieldRow(
                  label: 'Eigene Menge',
                  unit: 'g',
                  controller: _saltAmount,
                  keyboardType: _decimalKeyboard,
                  fieldKey: const ValueKey('nutrition-salt-amount'),
                ),
              ],
            ),
            const SizedBox(height: GainerSpacing.m),
            GainerPillButton(
              key: const ValueKey('nutrition-salt-add'),
              label: 'Salz hinzufügen',
              expand: true,
              onPressed: valid ? () => _addSalt(grams, target, onDraft) : null,
            ),
          ],
        );
      },
    ),
  ];

  Future<void> _addSalt(
    double grams,
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
  ) async {
    switch (target) {
      case DayMealTarget():
        await widget.viewModel.addManualEntry(
          productName: _saltName,
          amountGrams: grams,
          kilocaloriesPer100Grams: _saltPer100.kilocalories,
          proteinGramsPer100: _saltPer100.proteinGrams,
          carbohydrateGramsPer100: _saltPer100.carbohydrateGrams,
          fatGramsPer100: _saltPer100.fatGrams,
          saltGramsPer100: _saltPer100.saltGrams,
        );
        if (widget.viewModel.errorMessage == null) _saltAmount.clear();
        _closeAfterSave();
      case MealDraftTarget():
        final accepted = _commitDraft(
          FoodComponentDraft(
            name: _saltName,
            brand: null,
            amountGrams: grams,
            per100Grams: _saltPer100,
            source: null,
          ),
          onDraft,
        );
        if (accepted) _saltAmount.clear();
    }
  }

  /// Baut neu, sobald sich das Diktat ändert; ohne Diktat einmal mit null.
  Widget _withDictation(
    Widget Function(MealDictationController? dictation) builder,
  ) {
    final dictation = _dictation;
    if (dictation == null) return builder(null);
    return ListenableBuilder(
      listenable: dictation,
      builder: (context, _) => builder(dictation),
    );
  }

  List<Widget> _estimateTools(
    NutritionViewModel vm,
    ValueChanged<_NutritionEntryMode> onSelectMode,
  ) => [
    _withDictation(
      (dictation) => GainerGroupedSection(
        footer: switch (dictation) {
          MealDictationController(isListening: true) => 'Ich höre zu. Nenne Lebensmittel und Mengen und tippe dann auf Stopp.',
          MealDictationController(:final message?) => message,
          _ => 'Vorschläge werden erst nach deiner Bestätigung gespeichert.',
        },
        children: [
          _MealDescriptionInput(
            controller: _estimateText,
            dictation: dictation,
            dictationEnabled: !vm.isOnlineOperation,
            onPhoto: vm.isOnlineOperation ? null : _captureMealEstimate,
          ),
        ],
      ),
    ),
    const SizedBox(height: GainerSpacing.m),
    ValueListenableBuilder<TextEditingValue>(
      valueListenable: _estimateText,
      builder: (context, value, _) => GainerPillButton(
        label: 'Mahlzeit schätzen',
        icon: CupertinoIcons.sparkles,
        expand: true,
        isLoading: vm.isOnlineOperation,
        onPressed: vm.isOnlineOperation || value.text.trim().isEmpty
            ? null
            : () async {
                await _dictation?.finish();
                await vm.estimateMeal(_estimateText.text);
              },
      ),
    ),
    if (vm.mealEstimateDraft case final estimate?) ...[
      const SizedBox(height: GainerSpacing.l),
      GainerSectionHeader(title: 'Vorschlag prüfen · ${estimate.provider}'),
      const SizedBox(height: GainerSpacing.xs),
      GainerGroupedSection(
        children: [
          for (var index = 0; index < estimate.components.length; index++)
            GainerListRow(
              title: estimate.components[index].name,
              subtitle: _estimateSubtitle(estimate.components[index]),
              trailing: const _AddGlyph(),
              onTap: () => vm.confirmEstimatedComponent(index),
            ),
        ],
      ),
      // Selbst gesalzenes Essen schätzt die KI nicht; hier geht es direkt
      // zur Salz-Schnellwahl.
      if (!estimate.components.any((item) => item.name == _saltName)) ...[
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          children: [
            GainerListRow(
              key: const ValueKey('nutrition-estimate-add-salt'),
              leadingIcon: _NutritionEntryMode.salt.icon,
              title: 'Selbst gesalzen?',
              subtitle: 'Salz hinzufügen',
              showChevron: true,
              onTap: () => onSelectMode(_NutritionEntryMode.salt),
            ),
          ],
        ),
      ],
      const SizedBox(height: GainerSpacing.m),
      GainerPillButton(
        label: 'Schätzung verwerfen',
        variant: GainerPillVariant.tonal,
        expand: true,
        onPressed: vm.discardEstimate,
      ),
    ],
  ];

  /// „350 g · 890 kcal · ~12 g Ballaststoffe · ~3,5 g Salz · mittel“;
  /// Ballaststoffe und Salz nur, wenn geschätzt.
  String _estimateSubtitle(NutritionEstimateComponent item) {
    final salt = item.totals.saltGrams;
    final fiber = item.totals.fiberGrams;
    return [
      if (item.pieceCount case final count?)
        '${_formatNumber(count, decimals: 2)} Stk',
      '${_fmtGrams(item.amountGrams)} g',
      '${_fmtKcal(item.totals.kilocalories)} kcal',
      if (fiber != null && item.name != _saltName)
        '~${_fmtGrams(fiber)} g Ballaststoffe',
      if (salt != null && item.name != _saltName) '~${_fmtGrams(salt)} g Salz',
      _confidenceNames[item.confidence.toLowerCase()] ?? item.confidence,
      ?item.sourceHost,
    ].join(' · ');
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: GainerSpacing.s),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: GainerTypography.label.copyWith(
        color: GainerDesign.colorsOf(context).secondaryText,
      ),
    ),
  );

  /// Übernimmt ein gefundenes Lebensmittel in das [target].
  Future<void> _submitFood(
    NutritionFood food,
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
  ) async {
    final pieces = _parse(_addPieces.text);
    final pieceGrams = food.pieceGrams;
    if (pieces != null && pieceGrams == null) {
      widget.viewModel.reportInputError(
        'Für „${food.name}“ ist kein Stückgewicht bekannt. Gib die Menge in g ein.',
        operation: NutritionErrorOperation.entry,
      );
      return;
    }
    final amount = pieces != null && pieceGrams != null
        ? gramsForPieces(pieces, pieceGrams)
        : _parse(_amount.text) ?? 100;
    switch (target) {
      case DayMealTarget():
        await widget.viewModel.addFood(
          food,
          amountGrams: amount,
          pieceCount: pieces,
        );
        _closeAfterSave();
      case MealDraftTarget():
        _commitDraft(
          FoodComponentDraft(
            name: food.name,
            brand: food.brand,
            amountGrams: amount,
            per100Grams: food.per100Grams,
            source: food.source,
            pieceGrams: pieceGrams,
            pieceCount: pieces,
          ),
          onDraft,
        );
    }
  }

  /// Gibt einen gültigen Draft an den Aufrufer zurück. Bei ungültigen Werten
  /// bleibt der Dialog offen und zeigt den Fehler; der Entwurf bleibt
  /// unverändert.
  bool _commitDraft(
    FoodComponentDraft draft,
    ValueChanged<FoodComponentDraft> onDraft,
  ) {
    final problem = draft.validate();
    if (problem != null) {
      widget.viewModel.reportInputError(
        problem,
        operation: NutritionErrorOperation.entry,
      );
      return false;
    }
    onDraft(draft);
    return true;
  }

  void _searchFoods(NutritionViewModel vm, String query) {
    final value = query.trim();
    // Absenden zeigt die lokalen Treffer sofort, ohne auf die Pause zu warten.
    _localSearch?.cancel();
    vm.searchLocalFoods(value);
    if (!vm.canSearchOnline) return;
    if (value.length < 2) {
      vm.reportInputError(
        'Bitte mindestens zwei Zeichen eingeben.',
        operation: NutritionErrorOperation.search,
      );
      return;
    }
    vm.searchFoods(value);
  }

  Future<void> _openPlanning() {
    final vm = widget.viewModel;
    vm.dismissActionError();
    return Navigator.of(context).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => AnimatedBuilder(
          animation: vm,
          builder: (context, _) => GainerScaffold(
            title: 'Gerichte und Vorlagen',
            leading: GainerToolbarButton(
              key: const ValueKey('nutrition-planning-back'),
              icon: CupertinoIcons.chevron_left,
              semanticLabel: 'Zurück',
              onPressed: () => Navigator.of(context).pop(),
            ),
            children: [
              if (vm.errorMessage != null &&
                  vm.errorOperation == NutritionErrorOperation.planning)
                _notice(context, vm.errorMessage!, isError: true),
              const GainerSectionHeader(title: 'Gespeicherte Gerichte'),
              const SizedBox(height: GainerSpacing.xs),
              GainerGroupedSection(
                children: [
                  GainerListRow(
                    title: 'Neues Gericht anlegen',
                    leadingIcon: CupertinoIcons.add,
                    showChevron: true,
                    onTap: () => _editReusableMeal(),
                  ),
                  ..._mealRows(vm),
                ],
              ),
              const SizedBox(height: GainerSpacing.l),
              const GainerSectionHeader(title: 'Tagesvorlagen'),
              const SizedBox(height: GainerSpacing.xs),
              GainerGroupedSection(
                footer: vm.snapshot?.templates.isEmpty ?? true
                    ? 'Speichere einen Tag über „…“ → „Tag als Vorlage speichern“.'
                    : null,
                children: [
                  for (final template
                      in vm.snapshot?.templates ??
                          const <NutritionDayTemplate>[])
                    NutritionDayTemplateRow(
                      key: ValueKey('day-template-row-${template.templateId}'),
                      template: template,
                      onOpen: () => _openTemplate(template),
                      onDelete: () => vm.deleteTemplate(template.templateId),
                    ),
                  if (vm.snapshot?.templates.isEmpty ?? true)
                    const GainerListRow(title: 'Noch keine Vorlagen'),
                ],
              ),
              const SizedBox(height: GainerSpacing.l),
              const GainerSectionHeader(title: 'Ziele'),
              const SizedBox(height: GainerSpacing.xs),
              _TargetsSummary(
                target: vm.snapshot?.targetSchedule?.targetOn(
                  _dateString(vm.repository.clock()),
                ),
                onEdit: _editTargets,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _mealRows(NutritionViewModel vm) => [
    for (final meal in vm.snapshot?.meals ?? const [])
      _ReusableMealRow(
        meal: meal.value,
        onAdd: () => _addReusableMeal(meal.id, meal.value),
        onEdit: meal.value.status == 'Active'
            ? () => _editReusableMeal(id: meal.id, existing: meal.value)
            : null,
        onArchive: meal.value.status == 'Active'
            ? () => vm.archiveReusableMeal(meal.id)
            : null,
      ),
  ];

  /// Bearbeitet eine Vorlage: Name, Tagesart und Einträge je Mahlzeit. Der
  /// Entwurf bleibt lokal, bis „Sichern“ ihn speichert.
  Future<void> _openTemplate(NutritionDayTemplate template) async {
    final draft = _TemplateDraft(template);
    try {
      final save = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (context) => StatefulBuilder(
            builder: (context, setPageState) =>
                _templateEditorPage(context, setPageState, draft),
          ),
        ),
      );
      if (save != true || !mounted) return;
      await widget.viewModel.updateTemplate(
        template.templateId,
        name: draft.name.text.trim(),
        dayKind: draft.dayKind,
        entries: draft.entries,
      );
    } finally {
      draft.dispose();
    }
  }

  Widget _templateEditorPage(
    BuildContext context,
    StateSetter setPageState,
    _TemplateDraft draft,
  ) => _FormPage(
    title: 'Vorlage bearbeiten',
    closeKey: const ValueKey('day-template-close'),
    onSave: draft.canSave ? () => Navigator.pop(context, true) : null,
    children: [
      GainerGroupedSection(
        children: [
          GainerTextFieldRow(
            label: 'Name',
            controller: draft.name,
            fieldKey: const ValueKey('day-template-name'),
            onChanged: (_) => setPageState(() {}),
          ),
        ],
      ),
      const SizedBox(height: GainerSpacing.m),
      GainerSegmentedControl<String>(
        key: const ValueKey('day-template-kind'),
        options: const {
          'none': 'Jeder Tag',
          'training': 'Training',
          'rest': 'Ruhe',
        },
        value: draft.dayKind?.name ?? 'none',
        onChanged: (value) => setPageState(
          () => draft.dayKind = switch (value) {
            'training' => NutritionDayKind.training,
            'rest' => NutritionDayKind.rest,
            _ => null,
          },
        ),
      ),
      for (final meal in NutritionMeal.values) ...[
        const SizedBox(height: GainerSpacing.l),
        GainerSectionHeader(
          title: _mealName(meal),
          trailing: '${_fmtKcal(draft.kilocaloriesOf(meal))} kcal',
        ),
        const SizedBox(height: GainerSpacing.xs),
        GainerGroupedSection(
          children: [
            for (final entry in draft.entriesOf(meal))
              _templateEntryRow(context, setPageState, draft, entry),
            _AddRow(
              key: ValueKey('day-template-add-${meal.name}'),
              label: 'Hinzufügen',
              onPressed: draft.entries.length >= maxEntriesPerDay
                  ? null
                  : () => _addTemplateEntry(draft, meal, setPageState),
            ),
          ],
        ),
      ],
      const SizedBox(height: GainerSpacing.m),
      Text(
        draft.entries.isEmpty
            ? 'Eine Vorlage braucht mindestens einen Eintrag.'
            : 'Änderungen ändern keine Tage, auf die die Vorlage schon angewendet wurde.',
        textAlign: TextAlign.center,
        style: GainerTypography.caption.copyWith(
          color: GainerDesign.colorsOf(context).secondaryText,
        ),
      ),
    ],
  );

  Widget _templateEntryRow(
    BuildContext context,
    StateSetter setPageState,
    _TemplateDraft draft,
    NutritionEntry entry,
  ) {
    void remove() => setPageState(() => draft.remove(entry.entryId));
    Future<bool> confirmRemove() => confirmGainerDelete(
      context,
      title: 'Eintrag entfernen?',
      message: '„${entry.productName}“ wird aus der Vorlage entfernt.',
      deleteLabel: 'Entfernen',
    );
    return GainerSwipeToDelete(
      dismissKey: ValueKey('day-template-entry-swipe-${entry.entryId}'),
      label: 'Entfernen',
      confirm: confirmRemove,
      onDeleted: remove,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () async {
          final action = await showGainerActionSheet<_EntryAction>(
            context: context,
            title: entry.productName,
            groups: const [
              [
                GainerSheetAction(
                  label: 'Andere Mahlzeit',
                  icon: CupertinoIcons.arrow_up_arrow_down,
                  value: _EntryAction.move,
                ),
              ],
              [
                GainerSheetAction(
                  label: 'Entfernen',
                  icon: CupertinoIcons.trash,
                  value: _EntryAction.remove,
                  destructive: true,
                ),
              ],
            ],
          );
          if (!context.mounted) return;
          switch (action) {
            case _EntryAction.move:
              final meal = await _chooseMealValue();
              if (meal != null) {
                setPageState(() => draft.moveTo(entry.entryId, meal));
              }
            case _EntryAction.remove:
              if (await confirmRemove()) remove();
            case null:
          }
        },
        child: GainerListRow(
          key: ValueKey('day-template-entry-${entry.entryId}'),
          title: entry.productName,
          subtitle: entry.brand,
          value:
              '${_amountLabel(entry.amountGrams, entry.pieceCount)} · ${_fmtKcal(entry.totals.kilocalories)} kcal',
          onTap: () => _editTemplateEntry(draft, entry, setPageState),
        ),
      ),
    );
  }

  /// Gleicher Dialog wie bei Mahlzeiten, Ergebnis landet nur im Entwurf.
  Future<void> _addTemplateEntry(
    _TemplateDraft draft,
    NutritionMeal meal,
    StateSetter setPageState,
  ) async {
    final food = await _openEntry(target: const MealDraftTarget());
    if (food == null || !mounted) return;
    try {
      final entry = food.toEntry(
        entryId: widget.viewModel.repository.ids(),
        meal: meal,
        position: draft.entriesOf(meal).length,
      );
      setPageState(() => draft.add(entry));
    } catch (error) {
      widget.viewModel.reportInputError(
        error.toString(),
        operation: NutritionErrorOperation.planning,
      );
    }
  }

  Future<void> _editTemplateEntry(
    _TemplateDraft draft,
    NutritionEntry entry,
    StateSetter setPageState,
  ) async {
    try {
      final updated = await _editFoodSheet(
        ReusableMealComponent(
          componentId: entry.entryId,
          position: entry.position,
          name: entry.productName,
          brand: entry.brand,
          amountGrams: entry.amountGrams,
          per100Grams: entry.per100Grams,
          source: entry.source,
          pieceGrams: entry.pieceGrams,
          pieceCount: entry.pieceCount,
        ),
        'Eintrag bearbeiten',
      );
      if (updated == null || !mounted) return;
      setPageState(
        () => draft.replace(
          updated.toEntry(
            entryId: entry.entryId,
            meal: entry.meal,
            position: entry.position,
          ),
        ),
      );
    } catch (error) {
      widget.viewModel.reportInputError(
        error.toString(),
        operation: NutritionErrorOperation.planning,
      );
    }
  }

  /// Kalendertage statt 24 Stunden, sonst bleibt der Tag der Zeitumstellung
  /// hängen.
  Future<void> _shiftDay(int days) => widget.viewModel.selectDate(
    LocalDay.parse(widget.viewModel.localDate).addDays(days).toIso(),
  );

  Future<void> _pickDay(BuildContext context) async {
    final initial = DateTime.parse(widget.viewModel.localDate);
    final date = await showGainerDatePicker(
      context: context,
      title: 'Tag auswählen',
      initial: initial,
      maximum: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null && mounted) {
      await widget.viewModel.selectDate(_dateString(date));
    }
  }

  Future<void> _editEntry(NutritionEntry entry) async {
    final c = _EntryEditControllers(entry);
    var meal = entry.meal;
    try {
      await Navigator.of(context).push<({NutritionMeal meal})>(
        CupertinoPageRoute<({NutritionMeal meal})>(
          builder: (routeContext) => AnimatedBuilder(
            animation: widget.viewModel,
            builder: (routeContext, _) => StatefulBuilder(
              builder: (routeContext, setRouteState) => _FormPage(
                title: 'Eintrag bearbeiten',
                closeKey: const ValueKey('nutrition-edit-close'),
                onSave: _isEntryEditBlocked(c)
                    ? null
                    : () => _saveEntryEdit(routeContext, c, entry, meal),
                children: _entryEditFields(
                  routeContext,
                  c,
                  entry,
                  meal,
                  refresh: () => setRouteState(() {}),
                  onMealChanged: (selected) =>
                      setRouteState(() => meal = selected),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      c.dispose();
    }
  }

  bool _isEntryEditBlocked(_EntryEditControllers c) =>
      _parse(c.amount.text) == null ||
      _parse(c.kcal.text) == null ||
      c.name.text.trim().isEmpty ||
      widget.viewModel.isSaving;

  Future<void> _saveEntryEdit(
    BuildContext routeContext,
    _EntryEditControllers c,
    NutritionEntry entry,
    NutritionMeal meal,
  ) async {
    await widget.viewModel.updateEntry(
      original: entry,
      meal: meal,
      productName: c.name.text,
      brand: c.brand.text.trim().isEmpty ? null : c.brand.text,
      amountGrams: _parse(c.amount.text)!,
      per100Grams: NutritionTotals(
        kilocalories: _parse(c.kcal.text)!,
        proteinGrams: _nullable(c.protein.text),
        carbohydrateGrams: _nullable(c.carbs.text),
        fatGrams: _nullable(c.fat.text),
        saltGrams: _nullable(c.salt.text),
        fiberGrams: _nullable(c.fiber.text),
      ),
      pieceGrams: _nullable(c.pieceGrams.text),
      pieceCount: _nullable(c.pieceCount.text),
    );
    if (widget.viewModel.errorMessage == null &&
        routeContext.mounted &&
        ModalRoute.of(routeContext)?.isCurrent == true) {
      Navigator.pop(routeContext, (meal: meal));
    }
  }

  List<Widget> _entryEditFields(
    BuildContext routeContext,
    _EntryEditControllers c,
    NutritionEntry entry,
    NutritionMeal meal, {
    required VoidCallback refresh,
    required ValueChanged<NutritionMeal> onMealChanged,
  }) => [
    if (widget.viewModel.errorMessage != null &&
        widget.viewModel.errorOperation == NutritionErrorOperation.diary)
      _notice(routeContext, widget.viewModel.errorMessage!, isError: true),
    if (widget.viewModel.isSaving)
      const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CupertinoActivityIndicator()),
      ),
    ..._foodFormGroups(
      name: c.name,
      brand: c.brand,
      amount: c.amount,
      kcal: c.kcal,
      protein: c.protein,
      carbs: c.carbs,
      fat: c.fat,
      salt: c.salt,
      fiber: c.fiber,
      pieceGrams: c.pieceGrams,
      pieceCount: c.pieceCount,
      nameKey: const ValueKey('nutrition-edit-name'),
      amountKey: const ValueKey('nutrition-edit-amount'),
      kcalKey: const ValueKey('nutrition-edit-kcal'),
      onChanged: (_) => refresh(),
    ),
    const SizedBox(height: GainerSpacing.m),
    GainerGroupedSection(
      footer: entry.source == null
          ? 'Manueller Eintrag'
          : 'Quelle ${entry.source!.provider ?? entry.source!.barcode ?? 'Lebensmittelkatalog'} bleibt erhalten.',
      children: [
        GainerListRow(
          title: 'Mahlzeit',
          value: _mealName(meal),
          showChevron: true,
          onTap: () async {
            final selected = await _chooseMealValue();
            if (selected != null) onMealChanged(selected);
          },
        ),
      ],
    ),
  ];

  Future<NutritionMeal?> _chooseMealValue() => _chooseFromSheet<NutritionMeal>(
    title: 'Mahlzeit auswählen',
    options: [
      for (final item in NutritionMeal.values)
        (label: _mealName(item), icon: _mealIcon(item), value: item),
    ],
  );

  Future<void> _editReusableMeal({String? id, ReusableMeal? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(
      text: existing?.description ?? '',
    );
    final portion = TextEditingController(
      text: _grams(existing?.standardPortion ?? 1),
    );
    // Lokaler Entwurf: bleibt bis „Sichern“ unverändert gegenüber dem
    // gespeicherten Gericht und berührt nie einen Ernährungstag.
    final components = <ReusableMealComponent>[...?existing?.components];
    try {
      final save = await Navigator.of(context).push<bool>(
        CupertinoPageRoute<bool>(
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => _recipeEditorPage(
              context,
              setDialogState,
              existing: existing,
              name: name,
              description: description,
              portion: portion,
              components: components,
            ),
          ),
        ),
      );
      if (save != true || !mounted) return;
      final value = _reusableMealFromDraft(
        name: name,
        description: description,
        portion: portion,
        components: components,
      );
      await widget.viewModel.saveReusableMeal(
        id: id,
        meal: value,
        operation: NutritionErrorOperation.planning,
      );
    } catch (error) {
      widget.viewModel.reportInputError(
        error.toString(),
        operation: NutritionErrorOperation.planning,
      );
    } finally {
      name.dispose();
      description.dispose();
      portion.dispose();
    }
  }

  Widget _recipeEditorPage(
    BuildContext context,
    StateSetter setDialogState, {
    required ReusableMeal? existing,
    required TextEditingController name,
    required TextEditingController description,
    required TextEditingController portion,
    required List<ReusableMealComponent> components,
  }) {
    void refresh() => setDialogState(() {});
    final totalKcal = components.fold<double>(
      0,
      (sum, item) => sum + item.totals.kilocalories,
    );
    return _FormPage(
      title: existing == null ? 'Neues Gericht' : 'Gericht bearbeiten',
      closeKey: const ValueKey('nutrition-recipe-close'),
      onSave: _canSaveRecipe(name, portion, components)
          ? () => Navigator.pop(context, true)
          : null,
      children: [
        GainerGroupedSection(
          children: [
            GainerTextFieldRow(
              label: 'Name',
              placeholder: 'Gerichtsname',
              controller: name,
              fieldKey: const ValueKey('nutrition-recipe-name'),
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Beschreibung',
              placeholder: 'Optional',
              controller: description,
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Standardportion',
              unit: '×',
              controller: portion,
              keyboardType: _decimalKeyboard,
              onChanged: (_) => refresh(),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.l),
        GainerSectionHeader(
          title: 'Bestandteile',
          trailing: components.isEmpty ? null : '${_fmtKcal(totalKcal)} kcal',
        ),
        const SizedBox(height: GainerSpacing.xs),
        GainerGroupedSection(
          footer: 'Änderungen ändern keine bereits eingetragenen Mahlzeiten.',
          children: [
            for (final component in components)
              _componentRow(context, setDialogState, components, component),
            _addComponentRow(setDialogState, components),
          ],
        ),
      ],
    );
  }

  Widget _componentRow(
    BuildContext context,
    StateSetter setDialogState,
    List<ReusableMealComponent> components,
    ReusableMealComponent component,
  ) {
    void remove() => setDialogState(
      () => components.removeWhere(
        (item) => item.componentId == component.componentId,
      ),
    );
    Future<bool> confirmRemove() => confirmGainerDelete(
      context,
      title: 'Bestandteil entfernen?',
      message: '„${component.name}“ wird aus dem Gericht entfernt.',
      deleteLabel: 'Entfernen',
    );
    return GainerSwipeToDelete(
      dismissKey: ValueKey('meal-component-swipe-${component.componentId}'),
      label: 'Entfernen',
      confirm: confirmRemove,
      onDeleted: remove,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () async {
          final action = await showGainerActionSheet<_EntryAction>(
            context: context,
            title: component.name,
            groups: [
              if (components.length > 1)
                const [
                  GainerSheetAction(
                    label: 'Verschieben',
                    icon: CupertinoIcons.arrow_up_arrow_down,
                    value: _EntryAction.move,
                  ),
                ],
              const [
                GainerSheetAction(
                  label: 'Entfernen',
                  icon: CupertinoIcons.trash,
                  value: _EntryAction.remove,
                  destructive: true,
                ),
              ],
            ],
          );
          if (!context.mounted) return;
          switch (action) {
            case _EntryAction.move:
              final ids = await showGainerSheet<List<String>>(
                context: context,
                builder: (_) => _ReorderSheet(
                  title: 'Bestandteile anordnen',
                  items: [
                    for (final item in components)
                      (id: item.componentId, title: item.name),
                  ],
                ),
              );
              if (ids == null) return;
              final byId = {
                for (final item in components) item.componentId: item,
              };
              setDialogState(() {
                final ordered = [for (final id in ids) byId[id]!];
                components
                  ..clear()
                  ..addAll(ordered);
              });
            case _EntryAction.remove:
              if (await confirmRemove()) remove();
            case null:
          }
        },
        child: GainerListRow(
          key: ValueKey('meal-component-${component.componentId}'),
          title: component.name,
          value:
              '${_amountLabel(component.amountGrams, component.pieceCount)} · ${_fmtKcal(component.totals.kilocalories)} kcal',
          onTap: () => _editComponent(component, components, setDialogState),
        ),
      ),
    );
  }

  Widget _addComponentRow(
    StateSetter setDialogState,
    List<ReusableMealComponent> components,
  ) => _AddRow(
    key: const ValueKey('meal-component-add'),
    label: 'Bestandteil hinzufügen',
    onPressed: components.length >= 50
        ? null
        : () => _addComponent(components, setDialogState),
  );

  /// Öffnet denselben Dialog wie bei Mahlzeiten, aber mit Ziel Gerichtsentwurf.
  Future<void> _addComponent(
    List<ReusableMealComponent> components,
    StateSetter setDialogState,
  ) async {
    final draft = await _openEntry(target: const MealDraftTarget());
    if (draft == null || !mounted) return;
    try {
      final component = draft.toComponent(
        componentId: widget.viewModel.repository.ids(),
        position: components.length,
      );
      setDialogState(() => components.add(component));
    } catch (error) {
      widget.viewModel.reportInputError(
        error.toString(),
        operation: NutritionErrorOperation.planning,
      );
    }
  }

  /// Bearbeitet einen Bestandteil des Entwurfs in einem Sheet mit denselben
  /// Feldern wie die manuelle Erfassung.
  Future<void> _editComponent(
    ReusableMealComponent component,
    List<ReusableMealComponent> components,
    StateSetter setDialogState,
  ) async {
    try {
      final updated = await _editFoodSheet(component, 'Bestandteil bearbeiten');
      if (updated == null || !mounted) return;
      final index = components.indexWhere(
        (item) => item.componentId == component.componentId,
      );
      if (index < 0) return;
      setDialogState(
        () => components[index] = updated.toComponent(
          componentId: component.componentId,
          position: index,
        ),
      );
    } catch (error) {
      widget.viewModel.reportInputError(
        error.toString(),
        operation: NutritionErrorOperation.planning,
      );
    }
  }

  /// Sheet mit denselben Feldern wie die manuelle Erfassung; liefert die
  /// geänderten Werte oder null bei Abbruch.
  Future<FoodComponentDraft?> _editFoodSheet(
    ReusableMealComponent component,
    String title,
  ) async {
    final c = _IngredientControllers.fromComponent(component);
    try {
      return await showGainerSheet<FoodComponentDraft>(
        context: context,
        heightFactor: 0.9,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final draft = _draftFrom(c, source: component.source);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GainerSheetHeader(
                  title: title,
                  trailing: GainerPillButton(
                    label: 'Sichern',
                    onPressed: draft.validate() == null
                        ? () => Navigator.of(sheetContext).pop(draft)
                        : null,
                  ),
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      GainerSpacing.m,
                      GainerSpacing.m,
                      GainerSpacing.m,
                      GainerSpacing.l,
                    ),
                    children: _foodFormGroups(
                      name: c.name,
                      brand: c.brand,
                      amount: c.amount,
                      kcal: c.kcal,
                      protein: c.protein,
                      carbs: c.carbs,
                      fat: c.fat,
                      salt: c.salt,
                      fiber: c.fiber,
                      pieceGrams: c.pieceGrams,
                      pieceCount: c.pieceCount,
                      nameKey: const ValueKey('meal-component-name'),
                      amountKey: const ValueKey('meal-component-amount'),
                      kcalKey: const ValueKey('meal-component-kcal'),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      c.dispose();
    }
  }

  ReusableMeal _reusableMealFromDraft({
    required TextEditingController name,
    required TextEditingController description,
    required TextEditingController portion,
    required List<ReusableMealComponent> components,
  }) => ReusableMeal(
    name: name.text,
    description: description.text.trim().isEmpty ? null : description.text,
    standardPortion: _parse(portion.text)!,
    components: [
      for (var index = 0; index < components.length; index++)
        ReusableMealComponent(
          componentId: components[index].componentId,
          position: index,
          name: components[index].name,
          brand: components[index].brand,
          amountGrams: components[index].amountGrams,
          per100Grams: components[index].per100Grams,
          source: components[index].source,
          pieceGrams: components[index].pieceGrams,
          pieceCount: components[index].pieceCount,
        ),
    ],
  );

  bool _canSaveRecipe(
    TextEditingController name,
    TextEditingController portion,
    List<ReusableMealComponent> components,
  ) =>
      name.text.trim().isNotEmpty &&
      (_parse(portion.text) ?? 0) >= .01 &&
      (_parse(portion.text) ?? 101) <= 100 &&
      components.isNotEmpty &&
      components.length <= 50;

  Future<void> _addReusableMeal(String id, ReusableMeal meal) async {
    final scale = TextEditingController(text: _grams(meal.standardPortion));
    try {
      final accepted = await showGainerSheet<bool>(
        context: context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            final portion = _parse(scale.text);
            final valid = (portion ?? 0) >= .01 && (portion ?? 101) <= 100;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GainerSheetHeader(title: '${meal.name} übernehmen'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    GainerSpacing.m,
                    GainerSpacing.m,
                    GainerSpacing.m,
                    0,
                  ),
                  child: GainerGroupedSection(
                    children: [
                      GainerTextFieldRow(
                        label: 'Portionen',
                        unit: '×',
                        controller: scale,
                        keyboardType: _decimalKeyboard,
                        onChanged: (_) => setSheetState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: GainerSpacing.m),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GainerSpacing.m,
                  ),
                  child: GainerPillButton(
                    label: _applyLabel,
                    expand: true,
                    onPressed: valid
                        ? () => Navigator.of(sheetContext).pop(true)
                        : null,
                  ),
                ),
                const SizedBox(height: GainerSpacing.m),
              ],
            );
          },
        ),
      );
      if (accepted == true && mounted) {
        await widget.viewModel.addReusableMeal(
          id,
          widget.viewModel.selectedMeal,
          portionScale: _parse(scale.text),
        );
      }
    } finally {
      scale.dispose();
    }
  }

  Future<T?> _chooseFromSheet<T>({
    required String title,
    required List<({String label, IconData icon, T value})> options,
  }) => showGainerActionSheet<T>(
    context: context,
    title: title,
    groups: [
      [
        for (final option in options)
          GainerSheetAction<T>(
            label: option.label,
            icon: option.icon,
            value: option.value,
          ),
      ],
    ],
  );

  Future<void> _addManual(
    FoodAddTarget target,
    ValueChanged<FoodComponentDraft> onDraft,
  ) async {
    final amount = _parse(_amount.text);
    final kcal = _parse(_kcal.text);
    if (amount == null || kcal == null) {
      widget.viewModel.reportInputError(
        'Menge und Kalorien müssen gültige Zahlen sein.',
        operation: NutritionErrorOperation.entry,
      );
      return;
    }
    switch (target) {
      case DayMealTarget():
        await widget.viewModel.addManualEntry(
          productName: _name.text,
          brand: _brand.text.trim().isEmpty ? null : _brand.text,
          amountGrams: amount,
          kilocaloriesPer100Grams: kcal,
          proteinGramsPer100: _nullable(_protein.text),
          carbohydrateGramsPer100: _nullable(_carbs.text),
          fatGramsPer100: _nullable(_fat.text),
          saltGramsPer100: _nullable(_salt.text),
          fiberGramsPer100: _nullable(_fiber.text),
          pieceGrams: _nullable(_pieceGrams.text),
          pieceCount: _nullable(_pieceCount.text),
        );
        if (widget.viewModel.errorMessage == null) {
          _name.clear();
          _brand.clear();
          _pieceGrams.clear();
          _pieceCount.clear();
        }
        _closeAfterSave();
      case MealDraftTarget():
        final accepted = _commitDraft(
          FoodComponentDraft(
            name: _name.text,
            brand: _brand.text.trim().isEmpty ? null : _brand.text,
            amountGrams: amount,
            per100Grams: NutritionTotals(
              kilocalories: kcal,
              proteinGrams: _nullable(_protein.text),
              carbohydrateGrams: _nullable(_carbs.text),
              fatGrams: _nullable(_fat.text),
              saltGrams: _nullable(_salt.text),
              fiberGrams: _nullable(_fiber.text),
            ),
            source: null,
            pieceGrams: _nullable(_pieceGrams.text),
            pieceCount: _nullable(_pieceCount.text),
          ),
          onDraft,
        );
        if (accepted) {
          for (final controller in [
            _name,
            _brand,
            _kcal,
            _protein,
            _carbs,
            _fat,
            _salt,
            _fiber,
            _pieceGrams,
            _pieceCount,
          ]) {
            controller.clear();
          }
        }
    }
  }

  Future<void> _scanLabel() async {
    final consent = await _confirm(
      title: 'Etikett fotografieren',
      message: 'Das Bild wird zur Nährwerterkennung an den Gainer-Dienst gesendet. Es wird nicht lokal gespeichert. Du kannst den Vorschlag danach prüfen oder verwerfen.',
      accept: 'Fortfahren',
    );
    if (consent != true || !mounted) return;
    final useCamera = await _chooseCaptureSource();
    if (useCamera == null || !mounted) return;
    final upload = await _confirm(
      title: 'Nährwerte online erkennen',
      message: 'Das Etikettbild wird einmalig hochgeladen. Nichts wird automatisch ins Tagebuch übernommen.',
      accept: 'Einmalig hochladen',
    );
    if (upload != true || !mounted) return;
    await widget.viewModel.scanLabel(
      photoConsentConfirmed: true,
      uploadConsentConfirmed: true,
      useCamera: useCamera,
    );
    if (mounted && widget.viewModel.labelDraft != null) {
      await _reviewLabelDraft();
    }
  }

  Future<void> _reviewLabelDraft() async {
    final draft = widget.viewModel.labelDraft!;
    final name = TextEditingController();
    final amount = TextEditingController(text: '100');
    final recipeName = TextEditingController();
    final target = _LabelTargetDraft();
    try {
      // Über dem Hinzufügen-Sheet, das auf dem Root-Navigator liegt.
      final accepted = await Navigator.of(context, rootNavigator: true)
          .push<String>(
            CupertinoPageRoute<String>(
              builder: (context) => StatefulBuilder(
                builder: (context, setDialogState) => _labelDraftPage(
                  context,
                  setDialogState,
                  draft,
                  name: name,
                  amount: amount,
                  recipeName: recipeName,
                  target: target,
                ),
              ),
            ),
          );
      if (accepted == 'diary' && mounted) {
        await widget.viewModel.confirmLabelDraft(
          productName: name.text,
          amountGrams: _parse(amount.text) ?? 0,
        );
      } else if (accepted == 'meal' && mounted) {
        await widget.viewModel.confirmLabelAsReusableMeal(
          productName: name.text,
          amountGrams: _parse(amount.text) ?? 0,
          mealName: recipeName.text.trim().isEmpty
              ? name.text
              : recipeName.text,
        );
      } else {
        widget.viewModel.discardLabelDraft();
      }
    } finally {
      name.dispose();
      amount.dispose();
      recipeName.dispose();
    }
  }

  Widget _labelDraftPage(
    BuildContext context,
    StateSetter setDialogState,
    NutritionLabelScanDraft draft, {
    required TextEditingController name,
    required TextEditingController amount,
    required TextEditingController recipeName,
    required _LabelTargetDraft target,
  }) {
    void refresh() => setDialogState(() {});
    return _FormPage(
      title: 'Vorschlag prüfen',
      closeKey: const ValueKey('nutrition-label-close'),
      closeLabel: 'Verwerfen',
      onSave:
          draft.confirmedPer100Grams == null ||
              name.text.trim().isEmpty ||
              _parse(amount.text) == null
          ? null
          : () => Navigator.pop(context, target.value),
      children: [
        GainerGroupedSection(
          header:
              'Erkannt${draft.servingMassGrams == null ? '' : ' · ${_fmtGrams(draft.servingMassGrams!)} g pro Portion'}',
          footer: 'Werte pro 100 g. Prüfe alle Werte. Der Scan allein speichert nichts.',
          children: [
            GainerListRow(title: 'Gelesen', value: _labelBasis(draft.basis)),
            GainerListRow(
              title: 'Kalorien',
              value: _labelValue(draft.kilocalories, _fmtKcal, 'kcal'),
            ),
            GainerListRow(
              title: 'Protein',
              value: _labelValue(draft.proteinGrams, _fmtGrams, 'g'),
            ),
            GainerListRow(
              title: 'Kohlenhydrate',
              value: _labelValue(draft.carbohydrateGrams, _fmtGrams, 'g'),
            ),
            GainerListRow(
              title: 'Fett',
              value: _labelValue(draft.fatGrams, _fmtGrams, 'g'),
            ),
            GainerListRow(
              title: 'Ballaststoffe',
              value: _labelValue(draft.fiberGrams, _fmtGrams, 'g'),
            ),
            GainerListRow(
              title: 'Salz',
              value: _labelValue(draft.saltGrams, _fmtGrams, 'g'),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          children: [
            GainerTextFieldRow(
              label: 'Produktname',
              controller: name,
              onChanged: (_) => refresh(),
            ),
            GainerTextFieldRow(
              label: 'Menge',
              unit: 'g',
              controller: amount,
              keyboardType: _decimalKeyboard,
              onChanged: (_) => refresh(),
            ),
          ],
        ),
        const SizedBox(height: GainerSpacing.m),
        GainerGroupedSection(
          children: [
            GainerListRow(
              title: 'Speicherziel',
              value: target.value == 'diary'
                  ? 'Tagebucheintrag'
                  : 'Gespeichertes Gericht',
              showChevron: true,
              onTap: () async {
                final choice = await _chooseTarget();
                if (choice != null) {
                  setDialogState(() => target.value = choice);
                }
              },
            ),
            if (target.value == 'meal')
              GainerTextFieldRow(
                label: 'Gerichtsname',
                placeholder: 'Optional',
                controller: recipeName,
              ),
          ],
        ),
      ],
    );
  }

  Future<String?> _chooseTarget() => _chooseFromSheet<String>(
    title: 'Speicherziel auswählen',
    options: const [
      (label: 'Tagebucheintrag', icon: CupertinoIcons.book, value: 'diary'),
      (
        label: 'Neues gespeichertes Gericht',
        icon: CupertinoIcons.square_stack_3d_up,
        value: 'meal',
      ),
    ],
  );

  Future<void> _captureMealEstimate() async {
    final consent = await _confirm(
      title: 'Mahlzeit fotografieren',
      message: 'Das Bild wird einmalig zur Schätzung an den Gainer-Dienst gesendet. Es wird nicht lokal gespeichert. Der Vorschlag landet erst nach deiner Prüfung im Tagebuch.',
      accept: 'Fortfahren',
    );
    if (consent != true || !mounted) return;
    final useCamera = await _chooseCaptureSource();
    if (useCamera == null || !mounted) return;
    final upload = await _confirm(
      title: 'Bild einmalig hochladen',
      message: 'Die Bildanalyse ist unverbindlich. Prüfe jeden erkannten Bestandteil.',
      accept: 'Hochladen',
    );
    if (upload != true || !mounted) return;
    await widget.viewModel.estimateMealFromImage(
      photoConsentConfirmed: true,
      uploadConsentConfirmed: true,
      useCamera: useCamera,
    );
  }

  Future<bool?> _chooseCaptureSource() => _chooseFromSheet<bool>(
    title: 'Bild auswählen',
    options: const [
      (
        label: 'Fotomediathek',
        icon: CupertinoIcons.photo_on_rectangle,
        value: false,
      ),
      (label: 'Kamera', icon: CupertinoIcons.camera, value: true),
    ],
  );

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String accept,
    bool destructive = false,
  }) => showGainerStackedDialog<bool>(
    context: context,
    title: title,
    message: message,
    actions: [
      const GainerDialogAction(label: 'Abbrechen', value: false),
      GainerDialogAction(label: accept, value: true, destructive: destructive),
    ],
  );
}

IconData _mealIcon(NutritionMeal meal) => switch (meal) {
  NutritionMeal.breakfast => CupertinoIcons.sunrise,
  NutritionMeal.lunch => CupertinoIcons.sun_max,
  NutritionMeal.dinner => CupertinoIcons.moon,
  NutritionMeal.snacks => CupertinoIcons.square_grid_2x2,
};

const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);
const _applyLabel = 'Übernehmen';

Widget _notice(BuildContext context, String text, {bool isError = false}) {
  final colors = GainerDesign.colorsOf(context);
  final tone = isError ? colors.destructive : colors.accent;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(GainerRadii.field),
    ),
    child: Text(
      text,
      style: GainerTypography.body.copyWith(
        color: isError ? colors.destructive : colors.primaryText,
      ),
    ),
  );
}

/// Felder eines Lebensmittels als zwei gruppierte Karten (Stammdaten und
/// Nährwerte pro 100 g). Gemeinsam genutzt von manueller Erfassung, Eintrags-
/// und Bestandteilbearbeitung.
List<Widget> _foodFormGroups({
  required TextEditingController name,
  required TextEditingController brand,
  required TextEditingController amount,
  required TextEditingController kcal,
  required TextEditingController protein,
  required TextEditingController carbs,
  required TextEditingController fat,
  required TextEditingController salt,
  required TextEditingController fiber,
  required TextEditingController pieceGrams,
  required TextEditingController pieceCount,
  Key? nameKey,
  Key? brandKey,
  Key? amountKey,
  Key? kcalKey,
  ValueChanged<String>? onChanged,
}) => [
  GainerGroupedSection(
    children: [
      GainerTextFieldRow(
        label: 'Name',
        placeholder: 'Lebensmittel',
        controller: name,
        fieldKey: nameKey,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Marke',
        placeholder: 'Optional',
        controller: brand,
        fieldKey: brandKey,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Menge',
        unit: 'g',
        controller: amount,
        keyboardType: _decimalKeyboard,
        fieldKey: amountKey,
        onChanged: (value) {
          // Wer Gramm tippt, gibt die Menge nicht mehr in Stück an.
          pieceCount.clear();
          onChanged?.call(value);
        },
      ),
    ],
  ),
  const SizedBox(height: GainerSpacing.m),
  GainerGroupedSection(
    header: 'Stück (optional)',
    footer: 'Mit Gewicht pro Stück und Anzahl wird die Menge berechnet.',
    children: [
      GainerTextFieldRow(
        label: 'Gewicht pro Stück',
        unit: 'g',
        controller: pieceGrams,
        keyboardType: _decimalKeyboard,
        fieldKey: const ValueKey('nutrition-piece-grams'),
        onChanged: (value) {
          _syncPieceAmount(amount, pieceGrams, pieceCount);
          onChanged?.call(value);
        },
      ),
      _PieceCountRow(
        key: const ValueKey('nutrition-piece-count'),
        controller: pieceCount,
        onChanged: (value) {
          _syncPieceAmount(amount, pieceGrams, pieceCount);
          onChanged?.call(value);
        },
      ),
    ],
  ),
  const SizedBox(height: GainerSpacing.m),
  GainerGroupedSection(
    header: 'Nährwerte pro 100 g',
    children: [
      GainerTextFieldRow(
        label: 'Kalorien',
        unit: 'kcal',
        controller: kcal,
        keyboardType: _decimalKeyboard,
        fieldKey: kcalKey,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Protein',
        unit: 'g',
        controller: protein,
        keyboardType: _decimalKeyboard,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Kohlenhydrate',
        unit: 'g',
        controller: carbs,
        keyboardType: _decimalKeyboard,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Ballaststoffe',
        unit: 'g',
        controller: fiber,
        keyboardType: _decimalKeyboard,
        fieldKey: const ValueKey('nutrition-entry-fiber'),
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Fett',
        unit: 'g',
        controller: fat,
        keyboardType: _decimalKeyboard,
        onChanged: onChanged,
      ),
      GainerTextFieldRow(
        label: 'Salz',
        unit: 'g',
        controller: salt,
        keyboardType: _decimalKeyboard,
        fieldKey: const ValueKey('nutrition-entry-salt'),
        onChanged: onChanged,
      ),
    ],
  ),
];

/// Setzt die Menge auf Anzahl × Gewicht pro Stück, sobald beides gültig ist.
void _syncPieceAmount(
  TextEditingController amount,
  TextEditingController pieceGrams,
  TextEditingController pieceCount,
) {
  final grams = _parse(pieceGrams.text);
  final count = _parse(pieceCount.text);
  if (grams == null || count == null || grams <= 0 || count <= 0) return;
  amount.text = _grams(gramsForPieces(count, grams));
}

/// Baut aus den Bearbeitungsfeldern einen (noch ungeprüften) Draft.
FoodComponentDraft _draftFrom(
  _IngredientControllers c, {
  NutritionSource? source,
}) => FoodComponentDraft(
  name: c.name.text,
  brand: c.brand.text.trim().isEmpty ? null : c.brand.text,
  amountGrams: _parse(c.amount.text) ?? 0,
  per100Grams: NutritionTotals(
    kilocalories: _parse(c.kcal.text) ?? 0,
    proteinGrams: _nullable(c.protein.text),
    carbohydrateGrams: _nullable(c.carbs.text),
    fatGrams: _nullable(c.fat.text),
    saltGrams: _nullable(c.salt.text),
    fiberGrams: _nullable(c.fiber.text),
  ),
  source: source,
  pieceGrams: _nullable(c.pieceGrams.text),
  pieceCount: _nullable(c.pieceCount.text),
);

/// Formularseite im Look der Sheets: X links, Titel, „Sichern“-Pille rechts
/// (aktiv, sobald [onSave] gesetzt ist). Das X schließt ohne Ergebnis.
class _FormPage extends StatelessWidget {
  const _FormPage({
    required this.title,
    required this.children,
    required this.onSave,
    this.closeKey,
    this.closeLabel = 'Schließen',
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onSave;
  final Key? closeKey;
  final String closeLabel;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: GainerDesign.colorsOf(context).background,
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GainerSheetHeader(
                title: title,
                leading: GainerToolbarButton(
                  key: closeKey,
                  icon: CupertinoIcons.xmark,
                  semanticLabel: closeLabel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                trailing: GainerPillButton(label: 'Sichern', onPressed: onSave),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    GainerSpacing.m,
                    GainerSpacing.m,
                    GainerSpacing.m,
                    GainerSpacing.l,
                  ),
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Plus-Symbol am Zeilenende, das „Antippen übernimmt“ anzeigt.
class _AddGlyph extends StatelessWidget {
  const _AddGlyph();

  @override
  Widget build(BuildContext context) => Icon(
    CupertinoIcons.add_circled,
    size: 22,
    color: GainerDesign.colorsOf(context).accent,
  );
}

/// Zeile „+ Beschriftung“ in Akzentfarbe am Ende einer Karte.
class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.label,
    required this.onPressed,
    this.onLongPress,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final color = onPressed == null ? colors.placeholderText : colors.accent;
    // Bei großer Schrift Symbol über der Beschriftung stapeln, die dann
    // umbrechen darf, statt die Zeile zu sprengen.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final icon = Icon(CupertinoIcons.add, size: 18, color: color);
    final text = Text(
      label,
      style: GainerTypography.label.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        onLongPress: onPressed == null ? null : onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.m),
            child: stacked
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: GainerSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(height: GainerSpacing.xxs),
                        text,
                      ],
                    ),
                  )
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: GainerSpacing.xxs),
                      text,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _EntryEditControllers {
  _EntryEditControllers(NutritionEntry entry)
    : name = TextEditingController(text: entry.productName),
      brand = TextEditingController(text: entry.brand ?? ''),
      amount = TextEditingController(text: _grams(entry.amountGrams)),
      kcal = TextEditingController(
        text: _grams(entry.per100Grams.kilocalories),
      ),
      protein = TextEditingController(
        text: _optionalGrams(entry.per100Grams.proteinGrams),
      ),
      carbs = TextEditingController(
        text: _optionalGrams(entry.per100Grams.carbohydrateGrams),
      ),
      fat = TextEditingController(
        text: _optionalGrams(entry.per100Grams.fatGrams),
      ),
      salt = TextEditingController(
        text: _optionalGrams(entry.per100Grams.saltGrams),
      ),
      fiber = TextEditingController(
        text: _optionalGrams(entry.per100Grams.fiberGrams),
      ),
      pieceGrams = TextEditingController(
        text: _optionalGrams(entry.pieceGrams),
      ),
      pieceCount = TextEditingController(
        text: _optionalGrams(entry.pieceCount),
      );

  final TextEditingController name;
  final TextEditingController brand;
  final TextEditingController amount;
  final TextEditingController kcal;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;
  final TextEditingController salt;
  final TextEditingController fiber;
  final TextEditingController pieceGrams;
  final TextEditingController pieceCount;

  void dispose() {
    for (final controller in [
      name,
      brand,
      amount,
      kcal,
      protein,
      carbs,
      fat,
      salt,
      fiber,
      pieceGrams,
      pieceCount,
    ]) {
      controller.dispose();
    }
  }
}

/// Lokaler Entwurf einer Tagesvorlage im Editor.
class _TemplateDraft {
  _TemplateDraft(NutritionDayTemplate template)
    : name = TextEditingController(text: template.name),
      dayKind = template.dayKind,
      entries = [...template.entries],
      _original = template;

  final NutritionDayTemplate _original;
  final TextEditingController name;
  NutritionDayKind? dayKind;
  final List<NutritionEntry> entries;
  bool _entriesChanged = false;

  List<NutritionEntry> entriesOf(NutritionMeal meal) => [
    for (final entry in entries)
      if (entry.meal == meal) entry,
  ];

  double kilocaloriesOf(NutritionMeal meal) =>
      entriesOf(meal)
          .fold<double>(0, (sum, entry) => sum + entry.totals.kilocalories);

  bool get canSave {
    final trimmed = name.text.trim();
    final changed =
        _entriesChanged ||
        trimmed != _original.name ||
        dayKind != _original.dayKind;
    return changed &&
        trimmed.isNotEmpty &&
        trimmed.length <= NutritionDayTemplate.maxNameLength &&
        entries.isNotEmpty &&
        entries.length <= maxEntriesPerDay;
  }

  void add(NutritionEntry entry) {
    entries.add(entry);
    _entriesChanged = true;
  }

  void replace(NutritionEntry entry) {
    final index = entries.indexWhere((item) => item.entryId == entry.entryId);
    if (index < 0) return;
    entries[index] = entry;
    _entriesChanged = true;
  }

  void remove(String entryId) {
    entries.removeWhere((item) => item.entryId == entryId);
    _entriesChanged = true;
  }

  /// Verschiebt den Eintrag ans Ende der Mahlzeit [meal].
  void moveTo(String entryId, NutritionMeal meal) {
    final index = entries.indexWhere((item) => item.entryId == entryId);
    if (index < 0 || entries[index].meal == meal) return;
    final moved = entries.removeAt(index);
    entries.add(moved.copyWith(meal: meal, position: entriesOf(meal).length));
    _entriesChanged = true;
  }

  void dispose() => name.dispose();
}

class _LabelTargetDraft {
  String value = 'diary';
}

/// Tageswechsel in der Toolbar: ‹ [Datum] › in einer gemeinsamen Pille. Das
/// Datum öffnet die Datumsauswahl.
/// Eine Tageskarte: Kalorien groß mit Fortschritt, darunter drei kompakte
/// Makro-Spalten. Ohne Ziele nur die Ist-Werte und der Weg zu den Zielen.
/// Aktuelle Ziele im Bereich „Ziele“; Antippen öffnet den Editor.
class _TargetsSummary extends StatelessWidget {
  const _TargetsSummary({required this.target, required this.onEdit});

  final NutritionTargetVersion? target;
  final VoidCallback onEdit;

  String _line(NutritionDayTarget value) =>
      '${_fmtKcal(value.kilocalories)} kcal · P ${_fmtGrams(value.proteinGrams)} g · KH ${_fmtGrams(value.carbohydrateGrams)} g · F ${_fmtGrams(value.fatGrams)} g';

  @override
  Widget build(BuildContext context) {
    final current = target;
    return GainerGroupedSection(
      footer: current == null
          ? null
          : 'Änderungen gelten ab heute. Vergangene Tage behalten ihr Ziel.',
      children: current == null
          ? [
              GainerListRow(
                key: const ValueKey('nutrition-targets-set'),
                title: 'Ziele festlegen',
                leadingIcon: CupertinoIcons.add,
                showChevron: true,
                onTap: onEdit,
              ),
            ]
          : [
              GainerListRow(
                key: const ValueKey('nutrition-targets-training'),
                title: current.restDay == null ? 'Pro Tag' : 'Trainingstag',
                subtitle: _line(current.trainingDay),
                showChevron: true,
                onTap: onEdit,
              ),
              if (current.restDay case final rest?)
                GainerListRow(
                  key: const ValueKey('nutrition-targets-rest'),
                  title: 'Ruhetag',
                  subtitle: _line(rest),
                  showChevron: true,
                  onTap: onEdit,
                ),
              GainerListRow(
                title: 'Ballaststoffe',
                value: '≥ ${_fmtGrams(current.effectiveFiberGrams)} g',
                onTap: onEdit,
              ),
              GainerListRow(
                title: 'Salz',
                value: '≤ ${_fmtGrams(current.effectiveSaltGrams)} g',
                onTap: onEdit,
              ),
            ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.totals,
    required this.target,
    required this.onManage,
    required this.onDayKind,
  });

  final NutritionTotals totals;
  final NutritionDayTargetResult? target;
  final VoidCallback onManage;
  final VoidCallback onDayKind;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final goal = target?.target;
    final kind = target?.kind;
    final kcal = totals.kilocalories;
    final remaining = goal == null ? null : goal.kilocalories - kcal;
    return Semantics(
      button: true,
      label: goal == null ? 'Tagesziele festlegen' : 'Tagesziele verwalten',
      child: GestureDetector(
        key: const ValueKey('nutrition-target-card'),
        behavior: HitTestBehavior.opaque,
        onTap: onManage,
        child: GainerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tagesart nur, wenn es ein Ruhetag-Ziel gibt.
              if (kind != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: NutritionDayKindChip(
                    kind: kind,
                    manual: target!.manual,
                    onTap: onDayKind,
                  ),
                ),
                const SizedBox(height: GainerSpacing.xs),
              ],
              Semantics(
                label: 'Tageskalorien ${_fmtKcal(kcal)} Kilokalorien',
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _fmtKcal(kcal),
                        style: GainerTypography.largeTitle.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                      ),
                      TextSpan(
                        text: goal == null
                            ? ' kcal'
                            : ' von ${_fmtKcal(goal.kilocalories)} kcal',
                        style: GainerTypography.body.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (goal != null && remaining != null) ...[
                const SizedBox(height: GainerSpacing.xs),
                GainerProgressBar(consumed: kcal, target: goal.kilocalories),
                const SizedBox(height: GainerSpacing.xs),
                Text(
                  remaining >= 0
                      ? '${_fmtKcal(remaining)} übrig'
                      : '${_fmtKcal(-remaining)} über',
                  style: GainerTypography.label.copyWith(
                    color: remaining >= 0
                        ? colors.secondaryText
                        : colors.warning,
                  ),
                ),
              ],
              const SizedBox(height: GainerSpacing.m),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _macro(
                    colors,
                    'Protein',
                    totals.proteinGrams,
                    goal?.proteinGrams,
                    tint: colors.protein,
                  ),
                  const SizedBox(width: GainerSpacing.s),
                  _macro(
                    colors,
                    'Kohlenhydrate',
                    totals.carbohydrateGrams,
                    goal?.carbohydrateGrams,
                    tint: colors.carbohydrate,
                  ),
                  const SizedBox(width: GainerSpacing.s),
                  _macro(
                    colors,
                    'Fett',
                    totals.fatGrams,
                    goal?.fatGrams,
                    tint: colors.fat,
                  ),
                ],
              ),
              const SizedBox(height: GainerSpacing.s),
              // Ballaststoffe (Mindestziel) und Salz (Obergrenze) zentriert in
              // eigener Zeile, je so breit wie eine Makrospalte.
              LayoutBuilder(
                builder: (context, constraints) {
                  final column =
                      (constraints.maxWidth - 2 * GainerSpacing.s) / 3;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: column,
                        child: _macroBody(
                          colors,
                          'Ballaststoffe',
                          totals.fiberGrams,
                          target?.effectiveFiberGrams,
                          minimum: true,
                        ),
                      ),
                      const SizedBox(width: GainerSpacing.s),
                      SizedBox(
                        width: column,
                        child: _macroBody(
                          colors,
                          'Salz',
                          totals.saltGrams,
                          target?.effectiveSaltGrams,
                          barColor: colors.secondaryText,
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (goal == null) ...[
                const SizedBox(height: GainerSpacing.m),
                Text(
                  'Tagesziele festlegen',
                  style: GainerTypography.body.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _macro(
    GainerColors colors,
    String name,
    double? consumed,
    double? goal, {
    Color? tint,
  }) => Expanded(child: _macroBody(colors, name, consumed, goal, tint: tint));

  /// [minimum] markiert Mindestziele: Über dem Ziel gibt es keine Warnfarbe.
  /// [tint] färbt Punkt und Balken eines Makros; der Text bleibt in
  /// Textfarbe. [barColor] färbt nur den Balken (z. B. Salz neutral).
  Widget _macroBody(
    GainerColors colors,
    String name,
    double? consumed,
    double? goal, {
    bool minimum = false,
    Color? tint,
    Color? barColor,
  }) {
    final actual = consumed == null ? '–' : _fmtGrams(consumed);
    return Semantics(
      label: goal == null
          ? '$name, $actual g'
          : '$name, $actual von ${_fmtGrams(goal)} g',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (tint != null) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox.square(dimension: 7),
                ),
                const SizedBox(width: GainerSpacing.xxs),
              ],
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GainerTypography.caption.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              goal == null ? '$actual g' : '$actual / ${_fmtGrams(goal)} g',
              maxLines: 1,
              style: GainerTypography.value.copyWith(color: colors.primaryText),
            ),
          ),
          if (goal != null) ...[
            const SizedBox(height: GainerSpacing.xxs),
            GainerProgressBar(
              consumed: consumed,
              target: goal,
              height: 4,
              warnWhenExceeded: !minimum,
              color: tint ?? barColor,
            ),
          ],
        ],
      ),
    );
  }
}

enum _EntryAction { move, remove }

enum _NutritionMenuAction {
  saveTemplate,
  applyTemplate,
  targets,
  planning,
  settings,
}

/// Mahlzeit: Abschnittsüberschrift mit kcal rechts, darunter eine gruppierte
/// Karte mit einer Zeile je Eintrag. Wischen nach links löscht nach
/// Bestätigung, langes Drücken öffnet das Kontext-Sheet. Ohne Einträge zeigt
/// die Karte nur „+ Hinzufügen“.
class _MealSection extends StatelessWidget {
  const _MealSection({
    super.key,
    required this.meal,
    required this.entries,
    required this.onAdd,
    required this.onAddMultiple,
    required this.onEdit,
    required this.onRemove,
    required this.onConfirmRemove,
    required this.onMoveTo,
  });
  final NutritionMeal meal;
  final List<NutritionEntry> entries;
  final VoidCallback onAdd;

  /// Langes Drücken auf „Hinzufügen“.
  final VoidCallback onAddMultiple;
  final ValueChanged<NutritionEntry> onEdit;
  final ValueChanged<NutritionEntry> onRemove;
  final Future<bool> Function(NutritionEntry entry) onConfirmRemove;
  final Future<void> Function(
    List<NutritionEntry> ordered,
    List<String> orderedIds,
  )
  onMoveTo;

  @override
  Widget build(BuildContext context) {
    final ordered = [...entries]
      ..sort((a, b) => a.position.compareTo(b.position));
    final calories = entries.fold<double>(
      0,
      (sum, entry) => sum + entry.totals.kilocalories,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerSectionHeader(
          title: _mealName(meal),
          trailing: '${_fmtKcal(calories)} kcal',
        ),
        const SizedBox(height: GainerSpacing.xs),
        GainerGroupedSection(
          children: [
            for (final entry in ordered) _entryRow(context, ordered, entry),
            _AddRow(
              key: ValueKey('meal-add-${meal.name}'),
              label: 'Hinzufügen',
              onPressed: onAdd,
              onLongPress: onAddMultiple,
            ),
          ],
        ),
      ],
    );
  }

  Widget _entryRow(
    BuildContext context,
    List<NutritionEntry> ordered,
    NutritionEntry entry,
  ) => GainerSwipeToDelete(
    dismissKey: ValueKey('nutrition-swipe-${entry.entryId}'),
    confirm: () => onConfirmRemove(entry),
    onDeleted: () => onRemove(entry),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showEntryActions(context, ordered, entry),
      child: GainerListRow(
        key: ValueKey('nutrition-entry-${entry.entryId}'),
        title: entry.productName,
        value:
            '${_amountLabel(entry.amountGrams, entry.pieceCount)} · ${_fmtKcal(entry.totals.kilocalories)} kcal',
        onTap: () => onEdit(entry),
      ),
    ),
  );

  /// Kontext-Sheet eines Eintrags: Verschieben (ab zwei Einträgen) und Entfernen.
  Future<void> _showEntryActions(
    BuildContext context,
    List<NutritionEntry> ordered,
    NutritionEntry entry,
  ) async {
    final action = await showGainerActionSheet<_EntryAction>(
      context: context,
      title: entry.productName,
      groups: [
        if (ordered.length > 1)
          const [
            GainerSheetAction(
              label: 'Verschieben',
              icon: CupertinoIcons.arrow_up_arrow_down,
              value: _EntryAction.move,
            ),
          ],
        const [
          GainerSheetAction(
            label: 'Entfernen',
            icon: CupertinoIcons.trash,
            value: _EntryAction.remove,
            destructive: true,
          ),
        ],
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case _EntryAction.move:
        final ids = await showGainerSheet<List<String>>(
          context: context,
          builder: (_) => _ReorderSheet(
            title: 'Einträge anordnen',
            items: [
              for (final item in ordered)
                (id: item.entryId, title: item.productName),
            ],
          ),
        );
        if (ids != null) await onMoveTo(ordered, ids);
      case _EntryAction.remove:
        if (await onConfirmRemove(entry)) onRemove(entry);
      case null:
    }
  }
}

/// Sheet zum Umordnen einer Liste mit Ziehgriffen. Liefert die IDs in neuer
/// Reihenfolge, bei Schließen `null`.
class _ReorderSheet extends StatefulWidget {
  const _ReorderSheet({required this.title, required this.items});

  final String title;
  final List<({String id, String title})> items;

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late final List<({String id, String title})> _items = [...widget.items];

  void _move(int oldIndex, int newIndex) {
    setState(() => _items.insert(newIndex, _items.removeAt(oldIndex)));
  }

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.6;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerSheetHeader(
          title: widget.title,
          trailing: GainerPillButton(
            label: 'Fertig',
            onPressed: () =>
                Navigator.of(context).pop([for (final item in _items) item.id]),
          ),
        ),
        const SizedBox(height: GainerSpacing.s),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: CustomScrollView(
            shrinkWrap: true,
            slivers: [
              SliverReorderableList(
                itemCount: _items.length,
                onReorderItem: _move,
                itemBuilder: (context, index) =>
                    _row(context, _items[index], index),
              ),
            ],
          ),
        ),
        const SizedBox(height: GainerSpacing.m),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    ({String id, String title}) item,
    int index,
  ) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
      child: GainerCard(
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Ziehen zum Umordnen',
                child: Padding(
                  padding: const EdgeInsets.all(GainerSpacing.xxs),
                  child: Icon(
                    CupertinoIcons.line_horizontal_3,
                    size: 22,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ReusableMealAction { add, edit, archive }

/// Gespeichertes Gericht als Listenzeile. Antippen öffnet die Bearbeitung
/// (oder übernimmt das Gericht, wenn nur [onAdd] gesetzt ist). Langes Drücken
/// öffnet das Kontext-Sheet mit Übernehmen, Bearbeiten und Archivieren.
class _ReusableMealRow extends StatelessWidget {
  const _ReusableMealRow({
    required this.meal,
    required this.onAdd,
    required this.onEdit,
    required this.onArchive,
  });

  final ReusableMeal meal;
  final VoidCallback onAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  bool get _active => meal.status == 'Active';

  @override
  Widget build(BuildContext context) {
    final tap = onEdit ?? (_active ? onAdd : null);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showActions(context),
      child: GainerListRow(
        key: ValueKey('reusable-meal-${meal.name}'),
        title: meal.name,
        subtitle:
            '${meal.components.length} Bestandteile · Portion ${_fmtGrams(meal.standardPortion)}× · ${_active ? 'Aktiv' : 'Archiviert'}',
        showChevron: onEdit != null,
        onTap: tap,
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showGainerActionSheet<_ReusableMealAction>(
      context: context,
      title: meal.name,
      groups: [
        [
          if (_active)
            const GainerSheetAction(
              label: _applyLabel,
              icon: CupertinoIcons.plus_square,
              value: _ReusableMealAction.add,
            ),
          if (onEdit != null)
            const GainerSheetAction(
              label: 'Bearbeiten',
              icon: CupertinoIcons.pencil,
              value: _ReusableMealAction.edit,
            ),
        ],
        [
          if (onArchive != null)
            const GainerSheetAction(
              label: 'Archivieren',
              icon: CupertinoIcons.archivebox,
              value: _ReusableMealAction.archive,
              destructive: true,
            ),
        ],
      ].where((group) => group.isNotEmpty).toList(),
    );
    if (!context.mounted) return;
    switch (action) {
      case _ReusableMealAction.add:
        onAdd();
      case _ReusableMealAction.edit:
        onEdit?.call();
      case _ReusableMealAction.archive:
        onArchive?.call();
      case null:
    }
  }
}

class _IngredientControllers {
  _IngredientControllers()
    : componentId = null,
      source = null,
      name = TextEditingController(),
      brand = TextEditingController(),
      amount = TextEditingController(text: '100'),
      kcal = TextEditingController(),
      protein = TextEditingController(),
      carbs = TextEditingController(),
      fat = TextEditingController(),
      salt = TextEditingController(),
      fiber = TextEditingController(),
      pieceGrams = TextEditingController(),
      pieceCount = TextEditingController();

  _IngredientControllers.fromComponent(ReusableMealComponent component)
    : componentId = component.componentId,
      source = component.source,
      name = TextEditingController(text: component.name),
      brand = TextEditingController(text: component.brand ?? ''),
      amount = TextEditingController(text: _grams(component.amountGrams)),
      kcal = TextEditingController(
        text: _grams(component.per100Grams.kilocalories),
      ),
      protein = TextEditingController(
        text: _optionalGrams(component.per100Grams.proteinGrams),
      ),
      carbs = TextEditingController(
        text: _optionalGrams(component.per100Grams.carbohydrateGrams),
      ),
      fat = TextEditingController(
        text: _optionalGrams(component.per100Grams.fatGrams),
      ),
      salt = TextEditingController(
        text: _optionalGrams(component.per100Grams.saltGrams),
      ),
      fiber = TextEditingController(
        text: _optionalGrams(component.per100Grams.fiberGrams),
      ),
      pieceGrams = TextEditingController(
        text: _optionalGrams(component.pieceGrams),
      ),
      pieceCount = TextEditingController(
        text: _optionalGrams(component.pieceCount),
      );

  final String? componentId;
  final NutritionSource? source;
  final TextEditingController name;
  final TextEditingController brand;
  final TextEditingController amount;
  final TextEditingController kcal;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;
  final TextEditingController salt;
  final TextEditingController fiber;
  final TextEditingController pieceGrams;
  final TextEditingController pieceCount;

  void dispose() {
    name.dispose();
    brand.dispose();
    amount.dispose();
    kcal.dispose();
    protein.dispose();
    carbs.dispose();
    fat.dispose();
    salt.dispose();
    fiber.dispose();
    pieceGrams.dispose();
    pieceCount.dispose();
  }
}

String _mealName(NutritionMeal meal) => switch (meal) {
  NutritionMeal.breakfast => 'Frühstück',
  NutritionMeal.lunch => 'Mittagessen',
  NutritionMeal.dinner => 'Abendessen',
  NutritionMeal.snacks => 'Snacks',
};
double? _parse(String input) =>
    double.tryParse(input.trim().replaceAll(',', '.'));
double? _nullable(String input) => input.trim().isEmpty ? null : _parse(input);
String _grams(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');

/// Anzeige-Format: deutsches Komma, Tausenderpunkt, keine Nullen am Ende.
/// „4 Stk“, wenn in Stück erfasst, sonst „200 g“.
String _amountLabel(double amountGrams, double? pieceCount) =>
    pieceCount == null
    ? '${_fmtGrams(amountGrams)} g'
    : '${_formatNumber(pieceCount, decimals: 2)} Stk';

String _formatNumber(double value, {int decimals = 0}) =>
    formatNutritionNumber(value, decimals: decimals);

/// Kilokalorien als ganze Zahl, z. B. `1.240`.
String _fmtKcal(double value) => _formatNumber(value);

/// Gramm mit höchstens einer Nachkommastelle, z. B. `12,5`.
String _fmtGrams(double value) => _formatNumber(value, decimals: 1);

const _labelBasisNames = {
  'Per100Grams': 'pro 100 g',
  'Per100Milliliters': 'pro 100 ml (1 ml ≈ 1 g)',
  'PerServing': 'pro Portion',
};

String _labelBasis(String basis) => _labelBasisNames[basis] ?? basis;

String _labelValue(
  NutritionLabelFieldDraft field,
  String Function(double) format,
  String unit,
) {
  final value = field.per100Grams;
  if (value != null) return '${format(value)} $unit';
  return field.status == 'Implausible' ? 'unplausibel' : _notRecognizedLabel;
}

String _mealShortName(NutritionMeal meal) => switch (meal) {
  NutritionMeal.breakfast => 'Frühstück',
  NutritionMeal.lunch => 'Mittag',
  NutritionMeal.dinner => 'Abend',
  NutritionMeal.snacks => 'Snacks',
};
String _optionalGrams(double? value) => value == null ? '' : _grams(value);
String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Beschreibung der Mahlzeit mit Foto- und Diktat-Button im selben Feld.
class _MealDescriptionInput extends StatelessWidget {
  const _MealDescriptionInput({
    required this.controller,
    required this.dictation,
    required this.dictationEnabled,
    required this.onPhoto,
  });

  final TextEditingController controller;
  final MealDictationController? dictation;
  final bool dictationEnabled;
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final dictation = this.dictation;
    final listening = dictation?.isListening ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GainerSpacing.m,
        GainerSpacing.xs,
        GainerSpacing.xs,
        GainerSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoTextField.borderless(
            key: const ValueKey('nutrition-estimate-text'),
            controller: controller,
            placeholder: 'Was hast du gegessen? z. B. Haferflocken mit Banane',
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            padding: const EdgeInsets.only(
              top: GainerSpacing.xs,
              right: GainerSpacing.xs,
            ),
            style: GainerTypography.body.copyWith(color: colors.primaryText),
            placeholderStyle: GainerTypography.body.copyWith(
              color: colors.placeholderText,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _RoundIconButton(
                key: const ValueKey('nutrition-estimate-photo'),
                icon: CupertinoIcons.camera,
                semanticLabel: 'Foto aufnehmen',
                onPressed: onPhoto,
              ),
              if (dictation != null) ...[
                const SizedBox(width: GainerSpacing.xs),
                _RoundIconButton(
                  key: const ValueKey('nutrition-dictation'),
                  icon: listening
                      ? CupertinoIcons.stop_fill
                      : CupertinoIcons.mic_fill,
                  semanticLabel: listening ? 'Diktat beenden' : 'Diktieren',
                  prominent: listening,
                  onPressed: dictation.isStarting || !dictationEnabled
                      ? null
                      : dictation.toggle,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.prominent = false,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  /// Gefüllt in Akzentfarbe, z. B. während einer laufenden Aufnahme.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final enabled = onPressed != null;
    final background = prominent
        ? colors.accent
        : colors.accent.withValues(alpha: 0.14);
    final foreground = !enabled
        ? colors.placeholderText
        : prominent
        ? colors.onAccent
        : colors.accent;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: CupertinoButton(
        minimumSize: const Size.square(GainerRadii.iconButtonDiameter),
        padding: EdgeInsets.zero,
        borderRadius: GainerRadii.pill,
        color: background,
        disabledColor: colors.accent.withValues(alpha: 0.06),
        onPressed: onPressed,
        child: ExcludeSemantics(child: Icon(icon, size: 20, color: foreground)),
      ),
    );
  }
}

/// „Anzahl“ mit Minus/Plus und Eingabefeld; ganze Schritte, Eingabe auch
/// halb („0,5“). Leer bedeutet: keine Stückangabe.
class _PieceCountRow extends StatelessWidget {
  const _PieceCountRow({required this.controller, this.onChanged, super.key});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  void _step(double delta) {
    final current = _parse(controller.text) ?? 0;
    final next = current + delta;
    final value = next < 1 ? (delta > 0 ? 1.0 : 0.5) : next;
    if (delta < 0 && current <= 0.5) {
      controller.clear();
    } else {
      controller.text = _formatNumber(value, decimals: 2);
    }
    onChanged?.call(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final style = GainerTypography.body.copyWith(color: colors.primaryText);
    // Bei sehr großer Schrift steht die Beschriftung über den Knöpfen.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final label = Text('Anzahl', style: style);
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundIconButton(
          key: const ValueKey('piece-minus'),
          icon: CupertinoIcons.minus,
          semanticLabel: 'Ein Stück weniger',
          onPressed: () => _step(-1),
        ),
        SizedBox(
          width: stacked ? 96 : 64,
          child: CupertinoTextField.borderless(
            key: const ValueKey('piece-count-field'),
            controller: controller,
            textAlign: TextAlign.center,
            placeholder: '–',
            keyboardType: _decimalKeyboard,
            onChanged: onChanged,
            style: style,
            placeholderStyle: style.copyWith(color: colors.placeholderText),
          ),
        ),
        _RoundIconButton(
          key: const ValueKey('piece-plus'),
          icon: CupertinoIcons.plus,
          semanticLabel: 'Ein Stück mehr',
          onPressed: () => _step(1),
        ),
        const SizedBox(width: GainerSpacing.xs),
        Text('Stk', style: style.copyWith(color: colors.secondaryText)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: GainerSpacing.m,
        vertical: GainerSpacing.xxs,
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, controls],
            )
          : Row(
              children: [
                Expanded(child: label),
                controls,
              ],
            ),
    );
  }
}

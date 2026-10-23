import 'package:flutter/cupertino.dart';

import '../../../data/repositories/nutrition/nutrition_repository.dart';
import '../../../domain/models/nutrition/nutrition.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'nutrition_averages_view.dart';
import 'nutrition_day_kind.dart';

/// Ergebnis von „Als Vorlage speichern“: neue Vorlage oder überschreiben.
sealed class SaveTemplateChoice {
  const SaveTemplateChoice();
}

final class SaveAsNewTemplate extends SaveTemplateChoice {
  const SaveAsNewTemplate(this.name, this.dayKind);
  final String name;
  final NutritionDayKind? dayKind;
}

final class OverwriteTemplate extends SaveTemplateChoice {
  const OverwriteTemplate(this.templateId);
  final String templateId;
}

/// Kurzbeschreibung: „Ruhetag · 2.180 kcal · P 175 g“.
String templateSummary(NutritionDayTemplate template) {
  final totals = template.totals;
  return [
    if (template.dayKind case final kind?) dayKindLabel(kind),
    '${formatNutritionNumber(totals.kilocalories)} kcal',
    if (totals.proteinGrams case final protein?)
      'P ${formatNutritionNumber(protein)} g',
  ].join(' · ');
}

/// Sheet „Als Vorlage speichern“. Bei 50 Vorlagen ist nur Überschreiben
/// möglich; Überschreiben fragt vorher nach.
Future<SaveTemplateChoice?> showSaveTemplateSheet(
  BuildContext context, {
  required List<NutritionDayTemplate> templates,
}) => showGainerSheet<SaveTemplateChoice>(
  context: context,
  heightFactor: 0.75,
  builder: (_) => SaveTemplateSheet(templates: templates),
);

/// Inhalt von „Als Vorlage speichern“; öffentlich für Tests und Vorschauen.
class SaveTemplateSheet extends StatefulWidget {
  const SaveTemplateSheet({required this.templates, super.key});

  final List<NutritionDayTemplate> templates;

  @override
  State<SaveTemplateSheet> createState() => _SaveTemplateSheetState();
}

enum _SaveMode { create, overwrite }

class _SaveTemplateSheetState extends State<SaveTemplateSheet> {
  final _name = TextEditingController();
  NutritionDayKind? _kind;
  late _SaveMode _mode = _full ? _SaveMode.overwrite : _SaveMode.create;

  bool get _full =>
      widget.templates.length >= NutritionDayTemplate.maxTemplates;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _mode == _SaveMode.create &&
      !_full &&
      _name.text.trim().isNotEmpty &&
      _name.text.trim().length <= NutritionDayTemplate.maxNameLength;

  Future<void> _overwrite(NutritionDayTemplate template) async {
    final confirmed = await confirmGainerDelete(
      context,
      title: '„${template.name}“ überschreiben?',
      message: 'Die Vorlage bekommt die Einträge dieses Tages. Tage, auf die sie schon angewendet wurde, bleiben unverändert.',
      deleteLabel: 'Überschreiben',
    );
    if (!confirmed || !mounted) return;
    Navigator.of(context)
        .pop<SaveTemplateChoice>(OverwriteTemplate(template.templateId));
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerSheetHeader(
          title: 'Als Vorlage speichern',
          trailing: _mode == _SaveMode.create
              ? GainerPillButton(
                  key: const ValueKey('template-save'),
                  label: 'Sichern',
                  onPressed: _canSave
                      ? () => Navigator.of(context).pop<SaveTemplateChoice>(
                          SaveAsNewTemplate(_name.text.trim(), _kind),
                        )
                      : null,
                )
              : null,
        ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              GainerSpacing.m,
              GainerSpacing.s,
              GainerSpacing.m,
              GainerSpacing.l,
            ),
            children: [
              if (widget.templates.isNotEmpty) ...[
                GainerSegmentedControl<_SaveMode>(
                  key: const ValueKey('template-save-mode'),
                  options: const {
                    _SaveMode.create: 'Neu',
                    _SaveMode.overwrite: 'Überschreiben',
                  },
                  value: _mode,
                  onChanged: (mode) => setState(() => _mode = mode),
                ),
                const SizedBox(height: GainerSpacing.m),
              ],
              ...(_mode == _SaveMode.create
                  ? _createFields(colors)
                  : [_overwriteList()]),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _createFields(GainerColors colors) {
    if (_full) {
      return [
        Text(
          'Es sind höchstens ${NutritionDayTemplate.maxTemplates} Vorlagen möglich. Überschreibe eine bestehende oder lösche eine.',
          style: GainerTypography.body.copyWith(color: colors.secondaryText),
        ),
      ];
    }
    return [
      GainerGroupedSection(
        children: [
          GainerTextFieldRow(
            label: 'Name',
            placeholder: 'z. B. Trainingstag',
            controller: _name,
            fieldKey: const ValueKey('template-name'),
            textAlign: TextAlign.left,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      const SizedBox(height: GainerSpacing.m),
      GainerGroupedSection(
        header: 'Für',
        footer: 'Passt die Tagesart, schlägt die App die Vorlage an leeren Tagen vor.',
        children: [
          for (final (kind, label) in const [
            (null, 'Jeden Tag'),
            (NutritionDayKind.training, 'Trainingstage'),
            (NutritionDayKind.rest, 'Ruhetage'),
          ])
            GainerListRow(
              key: ValueKey('template-kind-${kind?.name ?? 'none'}'),
              title: label,
              trailing: _kind == kind
                  ? Icon(
                      CupertinoIcons.checkmark,
                      color: colors.accent,
                      size: 18,
                    )
                  : null,
              onTap: () => setState(() => _kind = kind),
            ),
        ],
      ),
    ];
  }

  Widget _overwriteList() => GainerGroupedSection(
    footer: 'Name und Tagesart der Vorlage bleiben erhalten.',
    children: [
      for (final template in widget.templates)
        GainerListRow(
          key: ValueKey('template-overwrite-${template.name}'),
          title: template.name,
          subtitle: templateSummary(template),
          showChevron: true,
          onTap: () => _overwrite(template),
        ),
    ],
  );
}

/// Sheet „Aus Vorlage befüllen“. Liefert die gewählte Vorlage.
Future<NutritionDayTemplate?> showChooseTemplateSheet(
  BuildContext context, {
  required List<NutritionDayTemplate> templates,
}) => showGainerSheet<NutritionDayTemplate>(
  context: context,
  heightFactor: 0.7,
  builder: (sheetContext) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const GainerSheetHeader(title: 'Aus Vorlage befüllen'),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            GainerSpacing.m,
            GainerSpacing.s,
            GainerSpacing.m,
            GainerSpacing.l,
          ),
          children: [
            GainerGroupedSection(
              footer: 'Die Einträge werden kopiert. Spätere Änderungen an der Vorlage ändern diesen Tag nicht.',
              children: [
                for (final template in templates)
                  GainerListRow(
                    key: ValueKey('template-choose-${template.name}'),
                    title: template.name,
                    subtitle: templateSummary(template),
                    showChevron: true,
                    onTap: () => Navigator.of(sheetContext).pop(template),
                  ),
              ],
            ),
          ],
        ),
      ),
    ],
  ),
);

enum _ApplyChoice { replace, append }

/// Fragt bei einem Tag mit Einträgen, ob ersetzt oder hinzugefügt wird.
/// Null heißt Abbrechen.
Future<TemplateApplyMode?> askTemplateApplyMode(BuildContext context) async {
  final choice = await showGainerActionSheet<_ApplyChoice>(
    context: context,
    title: 'Der Tag hat schon Einträge',
    groups: const [
      [
        GainerSheetAction(
          label: 'Hinzufügen',
          icon: CupertinoIcons.plus_square_on_square,
          hint: 'Einträge der Vorlage hinten anhängen',
          value: _ApplyChoice.append,
        ),
        GainerSheetAction(
          label: 'Ersetzen',
          icon: CupertinoIcons.arrow_2_squarepath,
          hint: 'Bisherige Einträge entfernen',
          value: _ApplyChoice.replace,
          destructive: true,
        ),
      ],
    ],
  );
  return switch (choice) {
    _ApplyChoice.replace => TemplateApplyMode.replace,
    _ApplyChoice.append => TemplateApplyMode.append,
    null => null,
  };
}

/// Zeile im Bereich „Tagesvorlagen“; Wischen löscht nach Bestätigung.
class NutritionDayTemplateRow extends StatelessWidget {
  const NutritionDayTemplateRow({
    required this.template,
    required this.onOpen,
    required this.onDelete,
    super.key,
  });

  final NutritionDayTemplate template;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => GainerSwipeToDelete(
    dismissKey: ValueKey('day-template-swipe-${template.templateId}'),
    confirm: () => confirmGainerDelete(
      context,
      title: 'Vorlage löschen?',
      message:
          '„${template.name}“ wird gelöscht. Tage, auf die sie angewendet wurde, behalten ihre Einträge.',
    ),
    onDeleted: onDelete,
    child: GainerListRow(
      key: ValueKey('day-template-${template.name}'),
      title: template.name,
      subtitle: templateSummary(template),
      showChevron: true,
      onTap: onOpen,
    ),
  );
}

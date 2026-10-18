import 'package:flutter/cupertino.dart';
import 'package:gainer_mobile/ui/core/components/components.dart';

import 'component_harness.dart';

void main() {
  expectGoldenVariants(
    'gainer_scaffold',
    () => GainerScaffold(
      title: 'Tagebuch',
      trailing: [
        GainerToolbarButton(
          icon: CupertinoIcons.add,
          semanticLabel: 'Hinzufügen',
          onPressed: () {},
        ),
        GainerToolbarButton(
          icon: CupertinoIcons.ellipsis,
          semanticLabel: 'Mehr',
          onPressed: () {},
        ),
      ],
      children: const [
        Text('Ein Eintrag auf dem Hintergrund'),
        SizedBox(height: 12),
        Text('Zweiter Eintrag'),
      ],
    ),
  );

  expectGoldenVariants(
    'gainer_card',
    () => const GainerCard(child: Text('Kniebeuge · 3 × 8 · 100 kg')),
  );

  expectGoldenVariants(
    'gainer_grouped_section',
    () => GainerGroupedSection(
      header: 'Konto & Geräte',
      children: [
        GainerListRow(
          title: 'Sync & Gerätewechsel',
          value: 'Aktiv',
          showChevron: true,
          onTap: () {},
        ),
        GainerListRow(title: 'Apple Health', showChevron: true, onTap: () {}),
      ],
    ),
  );

  expectGoldenVariants(
    'gainer_list_row',
    () => GainerListRow(title: 'Gewichtseinheit', value: 'kg', onTap: () {}),
  );

  expectGoldenVariants(
    'gainer_list_row_states',
    () => Column(
      children: [
        GainerListRow(
          title: 'Sync & Gerätewechsel',
          leadingIcon: CupertinoIcons.arrow_2_squarepath,
          value: 'Aktiv',
          showChevron: true,
          onTap: () {},
        ),
        GainerListRow(
          title: 'member@example.test',
          subtitle: 'Aktiv',
          leadingIcon: CupertinoIcons.person_2,
          leadingIconBackground: const Color(0xFF34C759),
          trailing: CupertinoSwitch(value: true, onChanged: (_) {}),
        ),
        GainerListRow(
          title: 'Kontoverwaltung',
          subtitle: 'Deaktiviert',
          leadingIcon: CupertinoIcons.person_2,
          trailing: CupertinoSwitch(value: false, onChanged: null),
        ),
      ],
    ),
  );

  expectGoldenVariants(
    'gainer_toolbar_button',
    () => Row(
      children: [
        GainerToolbarButton(
          icon: CupertinoIcons.pencil,
          semanticLabel: 'Bearbeiten',
          onPressed: () {},
        ),
        const SizedBox(width: 12),
        GainerToolbarGroup(
          actions: [
            GainerToolbarAction(
              icon: CupertinoIcons.timer,
              semanticLabel: 'Timer',
              onPressed: () {},
            ),
            GainerToolbarAction(
              icon: CupertinoIcons.ellipsis,
              semanticLabel: 'Menü',
              onPressed: () {},
            ),
          ],
        ),
      ],
    ),
  );

  expectGoldenVariants(
    'gainer_pill_button',
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GainerPillButton(label: 'Beenden', onPressed: () {}),
        const SizedBox(height: 12),
        GainerPillButton(
          label: 'Training fortsetzen',
          variant: GainerPillVariant.tonal,
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        GainerPillButton(
          label: 'Löschen',
          variant: GainerPillVariant.destructive,
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        const GainerPillButton(label: 'Deaktiviert', onPressed: null),
        const SizedBox(height: 12),
        GainerPillButton(
          label: 'Hinzufügen',
          icon: CupertinoIcons.add,
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        GainerPillButton(label: 'Speichern', isLoading: true, onPressed: () {}),
      ],
    ),
    animated: true,
  );

  expectGoldenVariants(
    'gainer_action_sheet',
    () => GainerActionSheet<String>(
      title: 'Bankdrücken',
      quickActions: const [
        GainerSheetAction(
          label: 'Verschieben',
          icon: CupertinoIcons.arrow_up_arrow_down,
          value: 'move',
        ),
        GainerSheetAction(
          label: 'Ersetzen',
          icon: CupertinoIcons.arrow_2_squarepath,
          value: 'replace',
        ),
        GainerSheetAction(
          label: 'Löschen',
          icon: CupertinoIcons.trash,
          value: 'delete',
          destructive: true,
        ),
      ],
      groups: const [
        [
          GainerSheetAction(
            label: 'Notiz',
            icon: CupertinoIcons.pencil,
            value: 'note',
          ),
          GainerSheetAction(
            label: 'Verlauf',
            icon: CupertinoIcons.clock,
            value: 'history',
          ),
          GainerSheetAction(
            label: 'Graphen',
            icon: CupertinoIcons.chart_bar,
            value: 'chart',
          ),
        ],
        [
          GainerSheetAction(
            label: 'Rekorde',
            icon: CupertinoIcons.star,
            value: 'records',
          ),
          GainerSheetAction(
            label: 'Gewichtseinheit',
            icon: CupertinoIcons.drop,
            value: 'unit',
          ),
        ],
      ],
    ),
  );

  expectGoldenVariants(
    'gainer_stacked_dialog',
    () => GainerStackedDialog<String>(
      title: 'Gewicht oder Wiederholungen fehlen',
      message: 'Einige Sätze haben kein Gewicht oder keine Wiederholungen. Vorwerte können übernommen werden.',
      actions: const [
        GainerDialogAction(label: 'Ja, Vorwerte verwenden', value: 'prefill'),
        GainerDialogAction(
          label: 'Trotzdem beenden',
          value: 'finish',
          destructive: true,
        ),
        GainerDialogAction(label: 'Weitertrainieren', value: 'continue'),
      ],
    ),
  );

  expectGoldenVariants(
    'gainer_sheet',
    () => GainerSheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GainerSheetHeader(
            title: 'Mahlzeit bearbeiten',
            trailing: GainerPillButton(label: 'Speichern', onPressed: () {}),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: GainerGroupedSection(
              children: [
                GainerDateRow(
                  title: 'Datum',
                  value: DateTime(2026, 10, 12),
                  format: (_) => 'Mo. 12. Okt.',
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  expectGoldenVariants(
    'gainer_section_header',
    () => const GainerSectionHeader(
      title: 'Oktober 2026',
      trailing: '2 Trainings',
    ),
  );

  expectGoldenVariants(
    'gainer_text_field_row',
    () => GainerGroupedSection(
      header: 'Gewicht',
      children: [
        GainerTextFieldRow(label: 'Startgewicht', unit: 'kg', placeholder: '0'),
        GainerTextFieldRow(
          label: 'Zielgewicht',
          unit: 'kg',
          placeholder: '0',
          errorText: 'Bitte eine Zahl eingeben.',
        ),
      ],
    ),
  );

  expectGoldenVariants(
    'gainer_search_field',
    () => GainerSearchField(placeholder: 'Übung suchen', onChanged: (_) {}),
  );

  expectGoldenVariants(
    'gainer_segmented_control',
    () => GainerSegmentedControl<int>(
      options: const {0: 'Tagebuch', 1: 'Pläne', 2: 'Statistik'},
      value: 0,
      onChanged: (_) {},
    ),
  );

  expectGoldenVariants(
    'gainer_numeric_accessory_bar',
    () => GainerNumericAccessoryBar(
      onPrevious: () {},
      onNext: () {},
      onDone: () {},
      onHideKeyboard: () {},
    ),
    size: const Size(390, 120),
  );

  expectGoldenVariants(
    'gainer_floating_tab_bar',
    () => GainerFloatingTabBar(
      items: const [
        GainerTabItem(label: 'Heute', icon: CupertinoIcons.chart_bar),
        GainerTabItem(label: 'Check-in', icon: CupertinoIcons.heart),
        GainerTabItem(label: 'Essen', icon: CupertinoIcons.drop),
        GainerTabItem(label: 'Training', icon: CupertinoIcons.sportscourt),
        GainerTabItem(label: 'Mehr', icon: CupertinoIcons.ellipsis),
      ],
      currentIndex: 3,
      onTap: (_) {},
    ),
    size: const Size(390, 140),
  );
}

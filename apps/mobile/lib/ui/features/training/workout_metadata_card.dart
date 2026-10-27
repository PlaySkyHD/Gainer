import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/workout_model.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'training_format.dart';
import 'workout_text_sheet.dart';
import 'workout_view_model.dart';

/// Datum mit Uhrzeit wie „Do. 15. Okt., 17:41“.
String formatWorkoutDateTime(DateTime local) =>
    '${formatWeekdayShort(local)}. ${formatShortDate(local)}, ${formatClockTime(local)}';

/// Karte oberhalb der Übungen: Titel, Start- und Endzeit sowie Notizen.
/// Die Zeiten werden nur über den Zeitwähler geändert; ungültige Werte
/// lehnt das Sheet ab und lassen den bisherigen Stand stehen.
class WorkoutMetadataCard extends StatelessWidget {
  const WorkoutMetadataCard({
    required this.viewModel,
    required this.workout,
    super.key,
  });

  final WorkoutViewModel viewModel;
  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final endedAt = workout.endedAtUtc;
    return GainerCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'Titel bearbeiten',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _editTitle(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GainerSpacing.m,
                  GainerSpacing.m,
                  GainerSpacing.m,
                  GainerSpacing.s,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        workout.title,
                        style: GainerTypography.cardTitle.copyWith(
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.pencil,
                      size: 18,
                      color: colors.secondaryText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _Separator(color: colors.separator),
          GainerListRow(
            title: 'Startzeit',
            value: formatWorkoutDateTime(workout.startedAtUtc.toLocal()),
            onTap: () => _editStart(context),
          ),
          _Separator(color: colors.separator),
          GainerListRow(
            title: 'Endzeit',
            value: endedAt == null
                ? 'läuft'
                : formatWorkoutDateTime(endedAt.toLocal()),
            onTap: endedAt == null ? null : () => _editEnd(context),
          ),
          _Separator(color: colors.separator),
          GainerListRow(
            title: 'Notizen',
            subtitle: _preview(workout.notes),
            showChevron: true,
            onTap: () => _editNotes(context),
          ),
        ],
      ),
    );
  }

  Future<void> _editTitle(BuildContext context) async {
    final text = await showWorkoutTextSheet(
      context: context,
      title: 'Titel',
      initialText: workout.title,
      placeholder: 'Trainingstitel',
      validate: viewModel.validateTitle,
    );
    if (text != null) await viewModel.setTitle(text);
  }

  Future<void> _editStart(BuildContext context) async {
    final value = await showWorkoutTimeSheet(
      context: context,
      title: 'Startzeit',
      initial: workout.startedAtUtc,
      validate: viewModel.validateStartedAt,
    );
    if (value != null) await viewModel.setStartedAt(value);
  }

  Future<void> _editEnd(BuildContext context) async {
    final endedAt = workout.endedAtUtc;
    if (endedAt == null) return;
    final value = await showWorkoutTimeSheet(
      context: context,
      title: 'Endzeit',
      initial: endedAt,
      validate: viewModel.validateEndedAt,
    );
    if (value != null) await viewModel.setEndedAt(value);
  }

  Future<void> _editNotes(BuildContext context) async {
    final text = await showWorkoutTextSheet(
      context: context,
      title: 'Notizen',
      initialText: workout.notes ?? '',
      placeholder: 'Notiz zum Training',
      multiline: true,
    );
    if (text != null) await viewModel.setNotes(text);
  }
}

/// Erste Zeile der Notiz, gekürzt; ohne Notiz kein Untertitel.
String? _preview(String? notes) {
  final text = notes?.trim() ?? '';
  if (text.isEmpty) return null;
  final firstLine = text.split('\n').first;
  return firstLine.length > 60 ? '${firstLine.substring(0, 60)}…' : firstLine;
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: GainerSpacing.m),
      color: color,
    );
  }
}

/// Zeitwähler im Sheet. Liefert die gewählte Zeit in UTC (minutengenau) oder `null` bei
/// Abbruch und bei unveränderter Zeit; `initial` behält so seine Sekunden. Ungültige Zeiten zeigen einen Feldfehler und lassen
/// „Fertig“ wirkungslos.
Future<DateTime?> showWorkoutTimeSheet({
  required BuildContext context,
  required String title,
  required DateTime initial,
  required String? Function(DateTime value) validate,
}) {
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (_) =>
        _WorkoutTimeSheet(title: title, initial: initial, validate: validate),
  );
}

class _WorkoutTimeSheet extends StatefulWidget {
  const _WorkoutTimeSheet({
    required this.title,
    required this.initial,
    required this.validate,
  });

  final String title;
  final DateTime initial;
  final String? Function(DateTime value) validate;

  @override
  State<_WorkoutTimeSheet> createState() => _WorkoutTimeSheetState();
}

class _WorkoutTimeSheetState extends State<_WorkoutTimeSheet> {
  late final DateTime _initial = widget.initial.toLocal();

  /// Aktuelle Wählerzeit (lokal).
  late DateTime _value = _initial;
  late String? _error = widget.validate(_result());

  static DateTime _toMinute(DateTime local) =>
      DateTime(local.year, local.month, local.day, local.hour, local.minute);

  /// Zeigt der Wähler dieselbe Minute wie `initial`, bleibt `initial` samt
  /// Sekunden und Millisekunden erhalten. Sonst gelten Datum, Stunde und
  /// Minute des Wählers, Sekunden und Millisekunden sind dann 0.
  DateTime _result() {
    final picked = _toMinute(_value);
    if (picked == _toMinute(_initial)) return widget.initial.toUtc();
    return picked.toUtc();
  }

  void _changed(DateTime value) {
    setState(() {
      _value = value;
      _error = widget.validate(_result());
    });
  }

  /// Unveränderte Zeit schließt wie „Abbrechen“ mit `null`, damit kein
  /// überflüssiger Speicher- und Sync-Eintrag entsteht.
  void _save() {
    if (_error != null) return;
    final result = _result();
    Navigator.of(context).pop(result == widget.initial.toUtc() ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(GainerRadii.card),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(GainerSpacing.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Abbrechen',
                      style: GainerTypography.body.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: GainerTypography.title.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 72),
                ],
              ),
              SizedBox(
                height: 216,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  initialDateTime: _initial,
                  use24hFormat: true,
                  minuteInterval: 1,
                  onDateTimeChanged: _changed,
                ),
              ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(bottom: GainerSpacing.xs),
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: GainerTypography.label.copyWith(
                      color: colors.destructive,
                    ),
                  ),
                ),
              GainerPillButton(
                label: 'Fertig',
                expand: true,
                onPressed: _error == null ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

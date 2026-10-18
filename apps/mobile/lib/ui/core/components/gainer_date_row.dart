import 'package:flutter/cupertino.dart';

import '../theme.dart';
import 'gainer_list_row.dart';
import 'gainer_pill_button.dart';
import 'gainer_sheet.dart';

/// Öffnet eine Datumsauswahl im Sheet. Liefert den gewählten Wert oder `null`
/// bei Abbruch.
Future<DateTime?> showGainerDatePicker({
  required BuildContext context,
  required String title,
  required DateTime initial,
  CupertinoDatePickerMode mode = CupertinoDatePickerMode.date,
  DateTime? minimum,
  DateTime? maximum,
}) {
  var value = initial;
  return showGainerSheet<DateTime>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GainerSheetHeader(
          title: title,
          trailing: GainerPillButton(
            label: 'Fertig',
            onPressed: () => Navigator.of(sheetContext).pop(value),
          ),
        ),
        SizedBox(
          height: 216,
          child: CupertinoDatePicker(
            mode: mode,
            initialDateTime: initial,
            minimumDate: minimum,
            maximumDate: maximum,
            use24hFormat: true,
            onDateTimeChanged: (picked) => value = picked,
          ),
        ),
        const SizedBox(height: GainerSpacing.m),
      ],
    ),
  );
}

/// Zeile mit Datum rechts; Antippen öffnet die Datumsauswahl.
class GainerDateRow extends StatelessWidget {
  const GainerDateRow({
    required this.title,
    required this.value,
    required this.format,
    required this.onChanged,
    this.mode = CupertinoDatePickerMode.date,
    this.minimum,
    this.maximum,
    super.key,
  });

  final String title;
  final DateTime value;
  final String Function(DateTime value) format;
  final ValueChanged<DateTime>? onChanged;
  final CupertinoDatePickerMode mode;
  final DateTime? minimum;
  final DateTime? maximum;

  Future<void> _pick(BuildContext context) async {
    final picked = await showGainerDatePicker(
      context: context,
      title: title,
      initial: value,
      mode: mode,
      minimum: minimum,
      maximum: maximum,
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    return GainerListRow(
      title: title,
      value: format(value),
      onTap: onChanged == null ? null : () => _pick(context),
    );
  }
}

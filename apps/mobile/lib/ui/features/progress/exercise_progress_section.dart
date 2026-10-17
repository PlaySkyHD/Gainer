import 'package:flutter/cupertino.dart';

import '../../../data/models/api/api_models.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';
import 'progress_view_model.dart';

const _chooseExerciseLabel = 'Übung auswählen';

class ExerciseProgressSection extends StatefulWidget {
  const ExerciseProgressSection({required this.viewModel, super.key});
  final ProgressViewModel viewModel;

  @override
  State<ExerciseProgressSection> createState() =>
      _ExerciseProgressSectionState();
}

class _ExerciseProgressSectionState extends State<ExerciseProgressSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.viewModel.loadExerciseOptions(),
    );
  }

  @override
  void didUpdateWidget(covariant ExerciseProgressSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.viewModel.loadExerciseOptions(),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.viewModel,
    builder: (context, _) => _buildCard(context, widget.viewModel),
  );

  Widget _buildCard(BuildContext context, ProgressViewModel model) {
    final selected = model.exerciseOptions.where(
      (item) => item.id == model.selectedExerciseId,
    );
    final selectedName = selected.isEmpty ? null : selected.first.name;
    final data = model.exerciseProgress;
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: GainerSpacing.s),
      child: GainerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Übungsfortschritt',
              style: GainerTypography.cardTitle.copyWith(
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Geschätztes 1RM aus deinen abgeschlossenen Sätzen',
              style: GainerTypography.label.copyWith(
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 14),
            _exercisePicker(context, model, selectedName),
            if (model.isExerciseCatalogStale ||
                model.exerciseOptionsErrorMessage != null) ...[
              const SizedBox(height: 8),
              _StatusLine(
                text:
                    model.exerciseOptionsErrorMessage ??
                    'Gespeicherte Übungsliste · möglicherweise veraltet',
              ),
              if (model.exerciseOptionsErrorMessage != null)
                GainerPillButton(
                  label: 'Übungsliste erneut laden',
                  variant: GainerPillVariant.tonal,
                  expand: true,
                  onPressed: model.isLoadingExerciseOptions
                      ? null
                      : () => model.loadExerciseOptions(refresh: true),
                ),
            ],
            const SizedBox(height: 12),
            _WindowPicker(
              selected: model.selectedProgressWindow,
              onChanged: model.selectProgressWindow,
            ),
            const SizedBox(height: 14),
            if (model.isExerciseProgressStale)
              _StatusLine(
                text: model.exerciseProgressCachedAtUtc == null
                    ? 'Gespeicherter Stand · möglicherweise veraltet'
                    : 'Gespeicherter Stand vom ${_formatDate(model.exerciseProgressCachedAtUtc!)} · möglicherweise veraltet',
              ),
            if (model.exerciseProgressErrorMessage case final error?)
              _StatusLine(text: error),
            ..._progressBody(context, model, selectedName),
            if (model.isLoadingExerciseProgress && data != null)
              const Align(
                alignment: Alignment.centerRight,
                child: CupertinoActivityIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _exercisePicker(
    BuildContext context,
    ProgressViewModel model,
    String? selectedName,
  ) => Semantics(
    button: true,
    label: selectedName == null
        ? _chooseExerciseLabel
        : 'Übung: $selectedName. Übung auswählen',
    child: CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      minimumSize: const Size(double.infinity, 48),
      color: GainerDesign.colorsOf(context).elevatedSurface,
      borderRadius: GainerRadii.pill,
      onPressed: model.isLoadingExerciseOptions || model.exerciseOptions.isEmpty
          ? null
          : _chooseExercise,
      child: Row(
        children: [
          Expanded(
            child: Text(
              model.isLoadingExerciseOptions
                  ? 'Übungen laden …'
                  : selectedName ?? _chooseExerciseLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GainerTypography.body.copyWith(
                color: GainerDesign.colorsOf(context).primaryText,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            CupertinoIcons.chevron_down,
            size: 14,
            color: GainerDesign.colorsOf(context).secondaryText,
          ),
        ],
      ),
    ),
  );

  List<Widget> _progressBody(
    BuildContext context,
    ProgressViewModel model,
    String? selectedName,
  ) {
    final data = model.exerciseProgress;
    if (model.isLoadingExerciseProgress && data == null) {
      return const [
        SizedBox(
          height: 132,
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }
    if (data == null &&
        model.exerciseProgressErrorMessage == null &&
        model.selectedExerciseId == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('Wähle eine Übung aus, um den Verlauf zu sehen.'),
        ),
      ];
    }
    final points = _estimatedPoints(data);
    final minimumEstimate = _minimumEstimate(points);
    final bestEstimate = _bestEstimate(points);
    if (data != null &&
        points.isNotEmpty &&
        minimumEstimate != null &&
        bestEstimate != null) {
      return _chartChildren(
        context,
        data,
        points,
        minimumEstimate,
        bestEstimate,
      );
    }
    if (data != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'Für ${selectedName ?? 'diese Übung'} gibt es in diesem Zeitraum noch keine berechenbaren 1RM-Werte.',
          ),
        ),
      ];
    }
    if (model.exerciseProgressErrorMessage != null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('Verlauf ist offline nicht gespeichert.'),
        ),
      ];
    }
    return const [];
  }

  List<Widget> _chartChildren(
    BuildContext context,
    ApiExerciseProgress data,
    List<ApiExerciseProgressPoint> points,
    double minimumEstimate,
    double bestEstimate,
  ) => [
    const SizedBox(height: 8),
    Row(
      children: [
        Expanded(
          child: Text(
            'Min. ${minimumEstimate.toStringAsFixed(1)} kg',
            softWrap: true,
            style: TextStyle(
              color: GainerDesign.colorsOf(context).secondaryText,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            'Max. ${bestEstimate.toStringAsFixed(1)} kg',
            softWrap: true,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: GainerDesign.colorsOf(context).secondaryText,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
    Semantics(
      label: _chartDescription(points),
      child: SizedBox(
        height: 136,
        width: double.infinity,
        child: CustomPaint(
          painter: _OneRepMaxChartPainter(
            points,
            GainerDesign.colorsOf(context).accent,
            GainerDesign.colorsOf(context).secondaryText,
          ),
        ),
      ),
    ),
    Row(
      children: [
        Expanded(
          child: Text(
            _formatDate(points.first.completedAtUtc),
            softWrap: true,
            style: TextStyle(
              color: GainerDesign.colorsOf(context).secondaryText,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            _formatDate(points.last.completedAtUtc),
            softWrap: true,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: GainerDesign.colorsOf(context).secondaryText,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    Text(
      'Bestes geschätztes 1RM · ${bestEstimate.toStringAsFixed(1)} kg',
      style: GainerTypography.body.copyWith(
        fontWeight: FontWeight.w600,
        color: GainerDesign.colorsOf(context).primaryText,
      ),
    ),
    if (data.bestSet case final best?)
      Text(
        'Bestleistung am ${_formatDate(best.completedAtUtc)} · ${best.weightKg.toStringAsFixed(1)} kg × ${best.repetitions}',
        style: TextStyle(color: GainerDesign.colorsOf(context).secondaryText),
      ),
  ];

  Future<void> _chooseExercise() async {
    final chosen = await Navigator.of(context).push<String>(
      CupertinoPageRoute<String>(
        builder: (_) => _ExercisePickerPage(
          options: widget.viewModel.exerciseOptions,
          selectedId: widget.viewModel.selectedExerciseId,
        ),
      ),
    );
    if (chosen != null && mounted) {
      await widget.viewModel.selectExercise(chosen);
    }
  }
}

List<ApiExerciseProgressPoint> _estimatedPoints(ApiExerciseProgress? data) =>
    data?.points
        .where((item) => item.estimatedOneRepMaxKg != null)
        .toList(growable: false) ??
    const <ApiExerciseProgressPoint>[];

double? _minimumEstimate(List<ApiExerciseProgressPoint> points) =>
    points.isEmpty
    ? null
    : points
          .map((item) => item.estimatedOneRepMaxKg!)
          .reduce((a, b) => a < b ? a : b);

double? _bestEstimate(List<ApiExerciseProgressPoint> points) => points.isEmpty
    ? null
    : points
          .map((item) => item.estimatedOneRepMaxKg!)
          .reduce((a, b) => a > b ? a : b);

class _ExercisePickerPage extends StatefulWidget {
  const _ExercisePickerPage({required this.options, required this.selectedId});
  final List<ExerciseProgressOption> options;
  final String? selectedId;
  @override
  State<_ExercisePickerPage> createState() => _ExercisePickerPageState();
}

class _ExercisePickerPageState extends State<_ExercisePickerPage> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final colors = GainerDesign.colorsOf(context);
    final options = widget.options
        .where((item) => item.name.toLowerCase().contains(query))
        .toList(growable: false);
    return GainerScaffold(
      title: _chooseExerciseLabel,
      trailing: [
        GainerPillButton(
          label: 'Abbrechen',
          variant: GainerPillVariant.tonal,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      children: [
        GainerSearchField(
          controller: _search,
          placeholder: 'Übung suchen',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: GainerSpacing.s),
        if (options.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Keine passende Übung gefunden.'),
          )
        else
          GainerGroupedSection(
            children: [
              for (final option in options)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GainerSpacing.m,
                    vertical: 12,
                  ),
                  minimumSize: const Size(double.infinity, 44),
                  onPressed: () => Navigator.of(context).pop(option.id),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.name,
                          textAlign: TextAlign.left,
                          style: GainerTypography.body.copyWith(
                            color: colors.primaryText,
                          ),
                        ),
                      ),
                      if (option.isCustom)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            'Eigene',
                            style: TextStyle(color: colors.secondaryText),
                          ),
                        ),
                      if (option.id == widget.selectedId)
                        Icon(CupertinoIcons.check_mark, color: colors.accent),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _WindowPicker extends StatelessWidget {
  const _WindowPicker({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;
  static const _labels = <String, String>{
    '7': '7 T.',
    '30': '30 T.',
    '90': '90 T.',
    'all': 'Gesamt',
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 360 ||
          MediaQuery.textScalerOf(context).scale(14) > 19;
      if (compact) {
        return _compactPicker(context);
      }
      return _segmentedPicker();
    },
  );

  Widget _compactPicker(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final entry in _labels.entries) _compactButton(context, entry),
    ],
  );

  Widget _compactButton(BuildContext context, MapEntry<String, String> entry) {
    final isSelected = selected == entry.key;
    final colors = GainerDesign.colorsOf(context);
    return CupertinoButton(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: isSelected ? colors.accent : colors.elevatedSurface,
      borderRadius: GainerRadii.pill,
      onPressed: () => onChanged(entry.key),
      child: Text(
        entry.value,
        style: TextStyle(
          color: isSelected ? colors.onAccent : colors.primaryText,
          fontWeight: isSelected ? FontWeight.w600 : null,
        ),
      ),
    );
  }

  Widget _segmentedPicker() => GainerSegmentedControl<String>(
    value: selected,
    options: _labels,
    onChanged: onChanged,
  );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        color: GainerDesign.colorsOf(context).secondaryText,
        fontSize: 13,
      ),
      semanticsLabel: text,
    ),
  );
}

class _OneRepMaxChartPainter extends CustomPainter {
  const _OneRepMaxChartPainter(this.points, this.color, this.labelColor);
  final List<ApiExerciseProgressPoint> points;
  final Color color;
  final Color labelColor;
  @override
  void paint(Canvas canvas, Size size) {
    final values = points
        .map((point) => point.estimatedOneRepMaxKg!)
        .toList(growable: false);
    if (values.isEmpty || size.isEmpty) return;
    const inset = 12.0;
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;
    final height = size.height - inset * 2;
    final offsets = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          values.length == 1
              ? size.width / 2
              : size.width * i / (values.length - 1),
          inset +
              height * (range == 0 ? .5 : 1 - (values[i] - minValue) / range),
        ),
    ];
    final grid = Paint()
      ..color = labelColor.withValues(alpha: .16)
      ..strokeWidth = 1;
    for (final fraction in [.25, .5, .75]) {
      final y = size.height * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = color;
    if (offsets.length == 1) {
      canvas.drawCircle(offsets.single, 4, dot);
      return;
    }
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final point in offsets.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, line);
    for (final point in offsets) {
      canvas.drawCircle(point, 4, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _OneRepMaxChartPainter old) =>
      old.points != points ||
      old.color != color ||
      old.labelColor != labelColor;
}

String _chartDescription(List<ApiExerciseProgressPoint> points) =>
    'Geschätzter Einwiederholungswert im Verlauf. ${points.map((point) => '${_formatDate(point.completedAtUtc)}: ${point.estimatedOneRepMaxKg!.toStringAsFixed(1)} kg').join(', ')}';
String _formatDate(DateTime date) {
  final localDate = date.toLocal();
  return '${localDate.day.toString().padLeft(2, '0')}.${localDate.month.toString().padLeft(2, '0')}.${localDate.year}';
}

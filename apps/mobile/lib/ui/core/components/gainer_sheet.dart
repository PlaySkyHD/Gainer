import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../theme.dart';
import 'gainer_toolbar_button.dart';

/// Öffnet ein Bottom-Sheet mit Griff. Wischen nach unten, X oder Tippen auf den
/// Hintergrund schließen es. Mit [heightFactor] hat es eine feste Höhe relativ
/// zum Bildschirm, sonst passt es sich dem Inhalt an.
Future<T?> showGainerSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double? heightFactor,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (sheetContext) => GainerSwipeToDismiss(
      child: GainerSheetFrame(
        heightFactor: heightFactor,
        child: Builder(builder: builder),
      ),
    ),
  );
}

/// Gerundete Sheet-Fläche mit Griff oben.
class GainerSheetFrame extends StatelessWidget {
  const GainerSheetFrame({required this.child, this.heightFactor, super.key});

  final Widget child;
  final double? heightFactor;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final factor = heightFactor;
    return GainerKeyboardInset(
      child: SafeArea(
        top: false,
        child: Container(
          height: factor == null ? null : gainerSheetHeight(context, factor),
          margin: const EdgeInsets.all(GainerSpacing.xs),
          decoration: BoxDecoration(
            color: colors.elevatedSurface,
            borderRadius: BorderRadius.circular(GainerRadii.card),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: GainerSpacing.xs),
                child: GainerSheetGrabber(),
              ),
              if (factor == null)
                Flexible(child: child)
              else
                Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Höhe eines Sheets mit fester Höhe; bei offener Tastatur schrumpft es, damit
/// es vollständig über der Tastatur bleibt.
double gainerSheetHeight(BuildContext context, double factor) {
  final screen = MediaQuery.sizeOf(context).height;
  final keyboard = MediaQuery.viewInsetsOf(context).bottom;
  return math.max(240, screen * factor - keyboard);
}

/// Schiebt ein Sheet über die eingeblendete Tastatur, damit Eingabefelder
/// sichtbar bleiben.
class GainerKeyboardInset extends StatelessWidget {
  const GainerKeyboardInset({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}

/// Griff am oberen Rand eines Sheets.
class GainerSheetGrabber extends StatelessWidget {
  const GainerSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Container(
      width: 36,
      height: 5,
      decoration: BoxDecoration(
        color: colors.separator,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// Kopfzeile eines Sheets: links standardmäßig X, Titel mittig, rechts eine
/// optionale Aktion wie „Speichern“.
class GainerSheetHeader extends StatelessWidget {
  const GainerSheetHeader({
    required this.title,
    this.leading,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GainerSpacing.xs,
        GainerSpacing.xs,
        GainerSpacing.xs,
        0,
      ),
      child: Row(
        children: [
          leading ??
              GainerToolbarButton(
                icon: CupertinoIcons.xmark,
                semanticLabel: 'Schließen',
                onPressed: () => Navigator.of(context).pop(),
              ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: GainerSpacing.xs),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GainerTypography.cardTitle.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
          ),
          if (trailing case final action?)
            // Bei großer Schrift darf die Aktion umbrechen statt überzulaufen.
            Flexible(child: action)
          else
            const SizedBox.square(dimension: GainerRadii.iconButtonDiameter),
        ],
      ),
    );
  }
}

/// Lässt ein Sheet dem Finger nach unten folgen. Weit genug oder schnell
/// genug gewischt schließt es, sonst federt es zurück. Scrollbare Inhalte
/// behalten ihre eigene Scrollgeste.
class GainerSwipeToDismiss extends StatefulWidget {
  const GainerSwipeToDismiss({required this.child, super.key});

  final Widget child;

  @override
  State<GainerSwipeToDismiss> createState() => _GainerSwipeToDismissState();
}

class _GainerSwipeToDismissState extends State<GainerSwipeToDismiss>
    with SingleTickerProviderStateMixin {
  static const _dismissVelocity = 700.0;
  static const _dismissFraction = 0.25;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(() => setState(() => _offset = _settleFrom * _settle.value));

  double _offset = 0;
  double _settleFrom = 0;
  var _dismissed = false;

  void _onUpdate(DragUpdateDetails details) {
    _settle.stop();
    setState(() => _offset = math.max(0, _offset + details.delta.dy));
  }

  void _onEnd(DragEndDetails details) {
    final height = context.size?.height ?? 1;
    final velocity = details.primaryVelocity ?? 0;
    if (!_dismissed &&
        (velocity > _dismissVelocity || _offset > height * _dismissFraction)) {
      _dismissed = true;
      Navigator.of(context).pop();
      return;
    }
    _settleFrom = _offset;
    _settle.reverse(from: 1);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onUpdate,
      onVerticalDragEnd: _onEnd,
      child: Transform.translate(
        offset: Offset(0, _offset),
        child: widget.child,
      ),
    );
  }
}

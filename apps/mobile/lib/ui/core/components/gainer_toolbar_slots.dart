import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Verbindet die linke und die rechte Toolbar-Aktion einer Seite.
///
/// `CupertinoSliverNavigationBar` legt `leading` und `trailing` unabhängig
/// voneinander mit der vollen Breite aus. Eine breite linke Aktion kann so
/// unter die rechten Aktionen ragen und deren Tap-Fläche verdecken. Über diese
/// Verbindung fragt die linke Aktion die echte Breite der rechten ab und nimmt
/// nur den Rest.
class GainerToolbarLink {
  RenderBox? _leading;
  RenderBox? _trailing;
}

/// Markiert die rechten Toolbar-Aktionen, damit die linke Aktion ihre Breite
/// kennt. Das Layout bleibt unverändert. Die Breite kommt aus den
/// Intrinsic-Maßen; `LayoutBuilder` darin ist deshalb nicht erlaubt.
class GainerToolbarTrailingSlot extends SingleChildRenderObjectWidget {
  const GainerToolbarTrailingSlot({
    required this.link,
    required Widget super.child,
    super.key,
  });

  final GainerToolbarLink link;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTrailingSlot(link);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderTrailingSlot).link = link;
  }
}

/// Linke Toolbar-Aktion: bekommt höchstens den Platz links von den rechten
/// Aktionen, abzüglich Lücke und Rand der Navigationsleiste.
class GainerToolbarLeadingSlot extends SingleChildRenderObjectWidget {
  const GainerToolbarLeadingSlot({
    required this.link,
    required Widget super.child,
    super.key,
  });

  final GainerToolbarLink link;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLeadingSlot(link);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLeadingSlot).link = link;
  }
}

class _RenderTrailingSlot extends RenderProxyBox {
  _RenderTrailingSlot(this._link);

  GainerToolbarLink _link;

  set link(GainerToolbarLink value) {
    if (identical(_link, value)) return;
    if (identical(_link._trailing, this)) _link._trailing = null;
    _link = value;
    if (attached) _link._trailing = this;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _link._trailing = this;
  }

  @override
  void detach() {
    if (identical(_link._trailing, this)) _link._trailing = null;
    super.detach();
  }

  @override
  void markNeedsLayout() {
    super.markNeedsLayout();
    // Ändert sich die Breite der rechten Aktionen, muss die linke neu messen.
    _link._leading?.markNeedsLayout();
  }
}

class _RenderLeadingSlot extends RenderProxyBox {
  _RenderLeadingSlot(this._link);

  GainerToolbarLink _link;

  set link(GainerToolbarLink value) {
    if (identical(_link, value)) return;
    if (identical(_link._leading, this)) _link._leading = null;
    _link = value;
    if (attached) _link._leading = this;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _link._leading = this;
  }

  @override
  void detach() {
    if (identical(_link._leading, this)) _link._leading = null;
    super.detach();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    var maxWidth = constraints.maxWidth;
    final trailing = _link._trailing;
    if (maxWidth.isFinite && trailing != null) {
      // Rechts bleiben Aktionsbreite, Lücke und der Rand der Navigationsleiste
      // (gleich dem linken Rand, den diese Aktion bereits abgezogen hat).
      final reserved =
          trailing.getMaxIntrinsicWidth(double.infinity) +
          GainerSpacing.xs +
          GainerSpacing.m;
      maxWidth = math.max(constraints.minWidth, maxWidth - reserved);
    }
    child.layout(
      constraints.copyWith(maxWidth: maxWidth),
      parentUsesSize: true,
    );
    size = child.size;
  }
}

import 'package:flutter/cupertino.dart';

import '../theme.dart';

/// Seite mit großem Titel am Listenanfang, der beim Scrollen in eine kompakte Titelleiste übergeht.
class GainerScaffold extends StatelessWidget {
  const GainerScaffold({
    required this.title,
    required this.children,
    this.leading,
    this.trailing = const [],
    this.onRefresh,
    super.key,
  });

  final String title;
  final List<Widget> children;

  /// Linke Toolbar-Aktion, z. B. ein Zurück-Button.
  final Widget? leading;

  /// Rechte Toolbar-Aktionen in Reihenfolge von links nach rechts.
  final List<Widget> trailing;

  /// Aktiviert Ziehen zum Aktualisieren am Listenanfang.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = GainerDesign.colorsOf(context);
    final theme = CupertinoTheme.of(context);
    final media = MediaQuery.of(context);
    // Die linke Aktion darf die rechten nicht überdecken: Sie bekommt nur den
    // Platz zwischen Rand und Aktionsgruppe.
    final trailingWidth = trailing.isEmpty
        ? 0.0
        : trailing.length * GainerRadii.iconButtonDiameter +
              (trailing.length - 1) * GainerSpacing.xs;
    final leadingMaxWidth =
        media.size.width -
        media.padding.horizontal -
        2 * GainerSpacing.m -
        trailingWidth -
        (trailing.isEmpty ? 0 : GainerSpacing.xs);
    return CupertinoTheme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          navLargeTitleTextStyle: GainerTypography.largeTitle.copyWith(
            color: colors.primaryText,
          ),
          navTitleTextStyle: GainerTypography.title.copyWith(
            color: colors.primaryText,
          ),
        ),
      ),
      child: CupertinoPageScaffold(
        backgroundColor: colors.background,
        child: CustomScrollView(
          slivers: [
            CupertinoSliverNavigationBar(
              backgroundColor: colors.background,
              largeTitle: Text(title),
              leading: leading == null
                  ? null
                  : ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: leadingMaxWidth.clamp(
                          GainerRadii.iconButtonDiameter,
                          double.infinity,
                        ),
                      ),
                      child: leading,
                    ),
              trailing: trailing.isEmpty
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < trailing.length; i++) ...[
                          if (i > 0) const SizedBox(width: GainerSpacing.xs),
                          trailing[i],
                        ],
                      ],
                    ),
            ),
            if (onRefresh case final refresh?)
              CupertinoSliverRefreshControl(onRefresh: refresh),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                GainerSpacing.m,
                GainerSpacing.xs,
                GainerSpacing.m,
                GainerSpacing.l,
              ),
              sliver: SliverList(delegate: SliverChildListDelegate(children)),
            ),
          ],
        ),
      ),
    );
  }
}

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
              leading: leading,
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

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../view_models/mobile_shell_view_model.dart';

class MobileShell extends StatelessWidget {
  const MobileShell({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<MobileShellViewModel>();

    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        currentIndex: model.selectedIndex,
        onTap: model.selectTab,
        items: [
          for (final area in MobileArea.values)
            BottomNavigationBarItem(
              icon: Icon(area.icon),
              label: area.label,
              tooltip: area.label,
            ),
        ],
      ),
      tabBuilder: (context, index) =>
          _MobileAreaPage(area: MobileArea.values[index]),
    );
  }
}

class _MobileAreaPage extends StatelessWidget {
  const _MobileAreaPage({required this.area});

  final MobileArea area;

  @override
  Widget build(BuildContext context) {
    final colors = CupertinoTheme.of(context);

    return CupertinoPageScaffold(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              children: [
                Text(
                  area.label,
                  key: const ValueKey<String>('area-title'),
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .navLargeTitleTextStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.barBackgroundColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colors.primaryColor.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(area.icon, color: colors.primaryColor, size: 24),
                      const SizedBox(height: 12),
                      Text(
                        'Dieser Bereich wird vorbereitet.',
                        style: CupertinoTheme.of(context).textTheme.textStyle
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Die Funktionen für ${area.label.toLowerCase()} '
                        'werden in einem späteren Schritt ergänzt.',
                        style: CupertinoTheme.of(context).textTheme.textStyle
                            .copyWith(color: CupertinoColors.secondaryLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';

import '../../../data/repositories/nutrition/bls_food_catalog.dart';
import '../../core/components/components.dart';
import '../../core/theme.dart';

/// Quellen und Lizenzen der mitgelieferten und abgefragten Lebensmitteldaten.
class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) => GainerScaffold(
    title: 'Lizenzen',
    children: const [
      GainerGroupedSection(
        header: 'Lebensmittel (BLS)',
        footer: BlsFoodCatalog.attribution,
        children: [
          GainerListRow(
            key: ValueKey('licenses-bls'),
            title: 'Bundeslebensmittelschlüssel 4.0',
            subtitle: 'Max Rubner-Institut · CC BY 4.0',
          ),
        ],
      ),
      SizedBox(height: GainerSpacing.l),
      GainerGroupedSection(
        header: 'Produkte (Open Food Facts)',
        footer:
            'Produktdaten von Open Food Facts (openfoodfacts.org), '
            'Open Database License (ODbL); einzelne Inhalte unter der '
            'Database Contents License.',
        children: [
          GainerListRow(
            key: ValueKey('licenses-open-food-facts'),
            title: 'Open Food Facts',
            subtitle: 'ODbL 1.0',
          ),
        ],
      ),
    ],
  );
}

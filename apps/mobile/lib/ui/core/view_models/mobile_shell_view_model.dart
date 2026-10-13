import 'package:flutter/cupertino.dart';

enum MobileArea {
  training('Training', CupertinoIcons.sportscourt),
  nutrition('Ernährung', CupertinoIcons.drop),
  body('Körper', CupertinoIcons.heart),
  progress('Fortschritt', CupertinoIcons.chart_bar),
  more('Mehr', CupertinoIcons.ellipsis);

  const MobileArea(this.label, this.icon);

  final String label;
  final IconData icon;
}

class MobileShellViewModel extends ChangeNotifier {
  int _selectedIndex = 0;

  int get selectedIndex => _selectedIndex;
  MobileArea get selectedArea => MobileArea.values[_selectedIndex];

  void selectTab(int index) {
    if (index < 0 ||
        index >= MobileArea.values.length ||
        index == _selectedIndex) {
      return;
    }
    _selectedIndex = index;
    notifyListeners();
  }
}

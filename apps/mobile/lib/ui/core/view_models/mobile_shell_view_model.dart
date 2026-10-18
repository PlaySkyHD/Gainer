import 'package:flutter/cupertino.dart';

enum MobileArea {
  progress('Heute', CupertinoIcons.chart_bar),
  body('Check-in', CupertinoIcons.heart),
  nutrition('Essen', CupertinoIcons.drop),
  training('Training', CupertinoIcons.sportscourt),
  more('Mehr', CupertinoIcons.ellipsis);

  const MobileArea(this.label, this.icon);

  final String label;
  final IconData icon;
}

class MobileShellViewModel extends ChangeNotifier {
  MobileShellViewModel() {
    _tabController = CupertinoTabController(
      initialIndex: MobileArea.progress.index,
    )..addListener(_syncSelectedIndex);
  }

  late final CupertinoTabController _tabController;
  int _selectedIndex = MobileArea.progress.index;
  String? _requestedWorkoutId;
  bool _requestedCardio = false;

  int get selectedIndex => _selectedIndex;
  MobileArea get selectedArea => MobileArea.values[_selectedIndex];
  CupertinoTabController get tabController => _tabController;

  void _syncSelectedIndex() {
    if (_tabController.index == _selectedIndex) return;
    _selectedIndex = _tabController.index;
    notifyListeners();
  }

  void selectTab(int index) {
    if (index < 0 ||
        index >= MobileArea.values.length ||
        index == _selectedIndex) {
      return;
    }
    _tabController.index = index;
  }

  /// Bittet darum, nach dem Tab-Wechsel das Training mit dieser ID zu öffnen.
  void requestOpenWorkout(String workoutId) {
    _requestedWorkoutId = workoutId;
    notifyListeners();
  }

  /// Liefert die offene Training-Anfrage einmal und löscht sie danach.
  String? takeRequestedWorkout() {
    final workoutId = _requestedWorkoutId;
    _requestedWorkoutId = null;
    return workoutId;
  }

  /// Bittet darum, nach dem Tab-Wechsel die Live-Ansicht der Cardio-Einheit
  /// zu öffnen.
  void requestOpenCardio() {
    _requestedCardio = true;
    notifyListeners();
  }

  /// Liefert die offene Cardio-Anfrage einmal und löscht sie danach.
  bool takeRequestedCardio() {
    final requested = _requestedCardio;
    _requestedCardio = false;
    return requested;
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_syncSelectedIndex)
      ..dispose();
    super.dispose();
  }
}

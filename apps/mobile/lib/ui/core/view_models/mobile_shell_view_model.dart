import 'package:flutter/cupertino.dart';

import '../../../domain/models/training/training_schedule.dart';

enum MobileArea {
  calendar('Übersicht', CupertinoIcons.square_grid_2x2),
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
      initialIndex: MobileArea.calendar.index,
    )..addListener(_syncSelectedIndex);
  }

  late final CupertinoTabController _tabController;
  int _selectedIndex = MobileArea.calendar.index;
  String? _requestedWorkoutId;
  bool _requestedCardio = false;
  bool _requestedCloseOverlays = false;
  LocalDay? _requestedCalendarDay;

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

  /// Bittet darum, offene Vollbilder und Sheets zu schließen, damit ein von
  /// außen (Widget, Kurzbefehl) gewählter Tab auch sichtbar wird.
  void requestCloseOverlays() {
    _requestedCloseOverlays = true;
    notifyListeners();
  }

  /// Liefert die Anfrage zum Schließen einmal und löscht sie danach.
  bool takeRequestedCloseOverlays() {
    final requested = _requestedCloseOverlays;
    _requestedCloseOverlays = false;
    return requested;
  }

  /// Wechselt in den Kalender und bittet ihn danach, [day] zu zeigen. Der
  /// Kalender holt den Tag erst nach dem nächsten Bild ab, wenn der Tab
  /// sichtbar ist und seine Ticker laufen.
  void openCalendarDay(LocalDay day) {
    selectTab(MobileArea.calendar.index);
    _requestedCalendarDay = day;
    notifyListeners();
  }

  /// Liefert den angefragten Kalendertag einmal und löscht ihn danach.
  LocalDay? takeRequestedCalendarDay() {
    final day = _requestedCalendarDay;
    _requestedCalendarDay = null;
    return day;
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

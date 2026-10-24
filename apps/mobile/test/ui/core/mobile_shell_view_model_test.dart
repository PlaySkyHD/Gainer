import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/domain/models/training/training_schedule.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';

void main() {
  test(
    'starts on Übersicht and keeps feature names attached to their routes',
    () {
      final model = MobileShellViewModel();

      expect(model.selectedArea, MobileArea.calendar);
      expect(MobileArea.values.map((area) => area.label), [
        'Übersicht',
        'Check-in',
        'Essen',
        'Training',
        'Mehr',
      ]);
      expect(MobileArea.values[MobileArea.training.index], MobileArea.training);
      expect(MobileArea.values[MobileArea.body.index], MobileArea.body);
      expect(
        MobileArea.values[MobileArea.nutrition.index],
        MobileArea.nutrition,
      );
      model.dispose();
    },
  );

  test('an open workout request is delivered exactly once', () {
    final model = MobileShellViewModel();
    var notifications = 0;
    model.addListener(() => notifications++);

    expect(model.takeRequestedWorkout(), isNull);
    model.requestOpenWorkout('workout-1');
    expect(notifications, 1);
    expect(model.takeRequestedWorkout(), 'workout-1');
    expect(model.takeRequestedWorkout(), isNull);
    model.dispose();
  });

  test('opening a calendar day switches the tab and delivers it once', () {
    final model = MobileShellViewModel();
    model.selectTab(MobileArea.training.index);
    var notifications = 0;
    model.addListener(() => notifications++);

    expect(model.takeRequestedCalendarDay(), isNull);
    model.openCalendarDay(LocalDay(2026, 9, 15));
    expect(model.selectedArea, MobileArea.calendar);
    expect(notifications, 2);
    expect(model.takeRequestedCalendarDay(), LocalDay(2026, 9, 15));
    expect(model.takeRequestedCalendarDay(), isNull);
    model.dispose();
  });

  test('an open cardio request is delivered exactly once', () {
    final model = MobileShellViewModel();
    var notifications = 0;
    model.addListener(() => notifications++);

    expect(model.takeRequestedCardio(), isFalse);
    model.requestOpenCardio();
    expect(notifications, 1);
    expect(model.takeRequestedCardio(), isTrue);
    expect(model.takeRequestedCardio(), isFalse);
    model.dispose();
  });
}

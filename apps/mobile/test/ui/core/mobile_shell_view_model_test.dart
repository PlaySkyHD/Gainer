import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/view_models/mobile_shell_view_model.dart';

void main() {
  test('starts on Heute and keeps feature names attached to their routes', () {
    final model = MobileShellViewModel();

    expect(model.selectedArea, MobileArea.progress);
    expect(MobileArea.values.map((area) => area.label), [
      'Heute',
      'Check-in',
      'Essen',
      'Training',
      'Mehr',
    ]);
    expect(MobileArea.values[MobileArea.training.index], MobileArea.training);
    expect(MobileArea.values[MobileArea.body.index], MobileArea.body);
    expect(MobileArea.values[MobileArea.nutrition.index], MobileArea.nutrition);
    model.dispose();
  });

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
}

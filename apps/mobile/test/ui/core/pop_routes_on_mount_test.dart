import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/navigation/pop_routes_on_mount.dart';

void main() {
  testWidgets('offene Root-Routen verschwinden, wenn der Login erscheint', (
    tester,
  ) async {
    final signedIn = ValueNotifier(true);
    addTearDown(signedIn.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: signedIn,
          builder: (context, value, _) => value
              ? Builder(
                  builder: (context) => CupertinoButton(
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute<void>(
                            builder: (_) => const Text('Training'),
                          ),
                        ),
                    child: const Text('Shell'),
                  ),
                )
              : const PopRoutesOnMount(child: Text('Login')),
        ),
      ),
    );
    await tester.tap(find.text('Shell'));
    await tester.pumpAndSettle();
    expect(find.text('Training'), findsOneWidget);

    signedIn.value = false;
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Training'), findsNothing);
  });
}

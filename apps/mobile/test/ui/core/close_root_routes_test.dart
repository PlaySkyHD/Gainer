import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gainer_mobile/ui/core/navigation/close_root_routes.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.onDispose);

  final VoidCallback onDispose;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('Training');
}

void main() {
  testWidgets('closeAll entsorgt offene Root-Routen vor der Rückkehr', (
    tester,
  ) async {
    final closer = RootRouteCloser();
    var disposed = false;
    await tester.pumpWidget(
      CupertinoApp(
        navigatorObservers: [closer],
        home: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute<void>(
                builder: (_) => _Probe(() => disposed = true),
              ),
            ),
            child: const Text('Shell'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Shell'));
    await tester.pumpAndSettle();
    expect(find.text('Training'), findsOneWidget);

    var done = false;
    final future = closer.closeAll().then((_) => done = true);
    await tester.pump();
    await tester.pump();
    await future;

    expect(done, isTrue);
    expect(disposed, isTrue);
    expect(find.text('Training'), findsNothing);
    expect(find.text('Shell'), findsOneWidget);
  });

  testWidgets('closeAll ohne offene Routen kehrt sofort zurück', (
    tester,
  ) async {
    final closer = RootRouteCloser();
    await tester.pumpWidget(
      CupertinoApp(navigatorObservers: [closer], home: const Text('Shell')),
    );

    await closer.closeAll();

    expect(find.text('Shell'), findsOneWidget);
  });
}

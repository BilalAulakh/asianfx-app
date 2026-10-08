import 'package:asianfxapp/presentation/common/widgets/double_back_to_exit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
  });

  bool exited() => platformCalls.any((c) => c.method == 'SystemNavigator.pop');

  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
  }

  testWidgets('first back shows a hint, second back within 2s exits', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DoubleBackToExit(child: Scaffold())));

    await pressBack(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(exited(), isFalse);

    await pressBack(tester);
    expect(exited(), isTrue);
  });

  testWidgets('a slow second press only shows the hint again', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DoubleBackToExit(child: Scaffold())));

    await pressBack(tester);
    // The widget reads the wall clock, so wait for real.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2100)));
    await tester.pump(const Duration(seconds: 3));
    await pressBack(tester);
    expect(exited(), isFalse);
  });

  testWidgets('onBack handles the press (e.g. previous tab) without exiting', (tester) async {
    var handled = 0;
    await tester.pumpWidget(MaterialApp(
      home: DoubleBackToExit(
        onBack: () => ++handled <= 2,
        child: const Scaffold(),
      ),
    ));

    await pressBack(tester);
    await pressBack(tester);
    expect(handled, 2);
    expect(find.text('Press back again to exit'), findsNothing);

    await pressBack(tester); // nothing left to go back to
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(exited(), isFalse);
  });

  testWidgets('pushed on top of another page: back simply returns', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const Text('home')));
    key.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const DoubleBackToExit(child: Scaffold(body: Text('admin'))),
    ));
    await tester.pumpAndSettle();

    await pressBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(exited(), isFalse);
  });
}

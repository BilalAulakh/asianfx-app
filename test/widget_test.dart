import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asianfxapp/main.dart';

void main() {
  testWidgets('FXAsianApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: FXAsianApp(),
      ),
    );
    expect(find.byType(FXAsianApp), findsOneWidget);
  });
}

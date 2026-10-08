import 'package:asianfxapp/blocs/blocs.dart';
import 'package:asianfxapp/presentation/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('Android back walks back through visited tabs, then asks before exiting', (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });

    const tabs = ['/app/vault', '/app/markets', '/app/terminal', '/app/positions', '/app/profile'];
    final router = GoRouter(
      initialLocation: tabs.first,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(navigationShell: shell),
          branches: [
            for (final t in tabs)
              StatefulShellBranch(routes: [
                GoRoute(path: t, builder: (_, _) => Center(child: Text('page $t'))),
              ]),
          ],
        ),
      ],
    );

    // Real timers (market feed singleton) must not run on the fake test clock.
    final engine = (await tester.runAsync(() async => TradingEngineCubit()))!;
    final auth = (await tester.runAsync(
        () async => AuthCubit(tradingEngineCubit: engine, adminCubit: AdminCubit())))!;
    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: auth),
        BlocProvider<TradingEngineCubit>.value(value: engine),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    expect(find.text('page /app/vault'), findsOneWidget);

    // Accounts -> Trade -> Chart via the bottom bar.
    await tester.tap(find.text('Trade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chart'));
    await tester.pumpAndSettle();
    expect(find.text('page /app/terminal'), findsOneWidget);

    await back();
    expect(find.text('page /app/markets'), findsOneWidget);
    await back();
    expect(find.text('page /app/vault'), findsOneWidget);
    expect(calls.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);

    // On the first tab: hint first, exit on the second press.
    await back();
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(calls.where((c) => c.method == 'SystemNavigator.pop'), isEmpty);
    await tester.binding.handlePopRoute();
    expect(calls.where((c) => c.method == 'SystemNavigator.pop'), isNotEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() async {
      await auth.close();
      await engine.close();
    });
  });
}

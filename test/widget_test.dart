import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asianfxapp/blocs/blocs.dart';
import 'package:asianfxapp/core/router/app_router.dart';
import 'package:asianfxapp/data/datasources/market_feed_service.dart';
import 'package:asianfxapp/main.dart';

void main() {
  testWidgets('FXAsianApp smoke test', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final feedService = MarketFeedService();
      final tradingEngineCubit = TradingEngineCubit();
      final adminCubit = AdminCubit();
      final authCubit = AuthCubit(
        tradingEngineCubit: tradingEngineCubit,
        adminCubit: adminCubit,
      );
      final themeCubit = ThemeCubit();
      final connectivityCubit = ConnectivityCubit();
      final marketBloc = MarketBloc(feedService: feedService);
      final walletCubit = WalletCubit();
      final ledgerCubit = LedgerCubit();
      final kycCubit = KycCubit();
      final dealingDeskCubit = DealingDeskCubit(
        feedService: feedService,
        tradingEngineCubit: tradingEngineCubit,
      );
      final router = createAppRouter(authCubit);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ThemeCubit>.value(value: themeCubit),
            BlocProvider<ConnectivityCubit>.value(value: connectivityCubit),
            BlocProvider<AuthCubit>.value(value: authCubit),
            BlocProvider<TradingEngineCubit>.value(value: tradingEngineCubit),
            BlocProvider<AdminCubit>.value(value: adminCubit),
            BlocProvider<MarketBloc>.value(value: marketBloc),
            BlocProvider<WalletCubit>.value(value: walletCubit),
            BlocProvider<LedgerCubit>.value(value: ledgerCubit),
            BlocProvider<KycCubit>.value(value: kycCubit),
            BlocProvider<DealingDeskCubit>.value(value: dealingDeskCubit),
          ],
          child: FXAsianApp(router: router),
        ),
      );
      expect(find.byType(FXAsianApp), findsOneWidget);
    });
    await tester.pumpWidget(const SizedBox());
  });
}

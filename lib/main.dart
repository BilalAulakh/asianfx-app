import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'blocs/blocs.dart';
import 'core/constants/feature_flags.dart';
import 'core/router/app_router.dart';
import 'core/security/app_lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'data/datasources/market_feed_service.dart';
import 'presentation/common/widgets/network_status_overlay.dart';
import 'presentation/common/widgets/update_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase Backend
  await Supabase.initialize(
    url: 'https://jrdyiqjejhkescsrircn.supabase.co',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpyZHlpcWplamhrZXNjc3JpcmNuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg1MTI1NjIsImV4cCI6MjEwNDA4ODU2Mn0.o0Orm6Km_G0cSYh8osjWSJIEIBTqQm40ZtCST-WDzhQ',
  );

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Transparent status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

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

  runApp(
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
}

class FXAsianApp extends StatelessWidget {
  final GoRouter router;
  const FXAsianApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, bool>(
      builder: (context, isDark) {
        return MaterialApp.router(
          title: 'FXAsianApp',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          routerConfig: router,
          builder: (context, child) {
            return MediaQuery(
              // Prevent text scaling above 1.2x for consistent layout
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
                ),
              ),
              child: UpdateGate(
                child: NetworkStatusOverlay(
                  child: kDemoMode
                      // Simulated prices must be unmistakable on every screen.
                      ? Banner(
                          message: 'DEMO PRICES',
                          location: BannerLocation.topEnd,
                          color: const Color(0xFFFF9F43),
                          child: AppLockGate(child: child!),
                        )
                      : AppLockGate(child: child!),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

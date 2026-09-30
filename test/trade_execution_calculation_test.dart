import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asianfxapp/core/constants/app_constants.dart';
import 'package:asianfxapp/core/math/money_math.dart';
import 'package:asianfxapp/data/datasources/market_feed_service.dart';
import 'package:asianfxapp/domain/entities/trading_entities.dart';
import 'package:asianfxapp/blocs/trading_engine_bloc.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('1. Trade Calculation & Precision Math (MoneyMath)', () {
    test('Margin Calculation: Gold (XAU/USD) with 100x & 500x leverage', () {
      final lots = MoneyMath.toDec(1.0); // 1.0 lot
      final contractSize = AppConstants.contractSizeGold; // 100 oz
      final openPrice = MoneyMath.toDec(2850.00);

      // 100x leverage: (1 * 100 * 2850) / 100 = $2850.00
      final margin100x = MoneyMath.calcRequiredMargin(
        lots: lots,
        contractSize: contractSize,
        openPrice: openPrice,
        leverage: Decimal.fromInt(100),
      );
      expect(margin100x.toDouble(), equals(2850.00));

      // 500x leverage: (1 * 100 * 2850) / 500 = $570.00
      final margin500x = MoneyMath.calcRequiredMargin(
        lots: lots,
        contractSize: contractSize,
        openPrice: openPrice,
        leverage: Decimal.fromInt(500),
      );
      expect(margin500x.toDouble(), equals(570.00));
    });

    test('Margin Calculation: Forex EUR/USD with standard contract size', () {
      final lots = MoneyMath.toDec(0.5); // 0.5 lot
      final contractSize = AppConstants.contractSizeForex; // 100,000 units
      final openPrice = MoneyMath.toDec(1.1600);
      final leverage = Decimal.fromInt(100);

      // (0.5 * 100,000 * 1.1600) / 100 = $580.00
      final margin = MoneyMath.calcRequiredMargin(
        lots: lots,
        contractSize: contractSize,
        openPrice: openPrice,
        leverage: leverage,
      );
      expect(margin.toDouble(), equals(580.00));
    });

    test('Unrealized PnL Calculation: Long & Short Positions', () {
      final lots = MoneyMath.toDec(2.0);
      final contractSize = AppConstants.contractSizeGold; // 100 oz

      // Long Position: Open @ 2850.00, Current Bid @ 2875.00 -> Profit +$5,000
      final pnlLongProfit = MoneyMath.calcUnrealizedPnL(
        isBuy: true,
        openPrice: MoneyMath.toDec(2850.00),
        currentPrice: MoneyMath.toDec(2875.00),
        lots: lots,
        contractSize: contractSize,
      );
      expect(pnlLongProfit.toDouble(), equals(5000.00));

      // Long Position: Open @ 2850.00, Current Bid @ 2830.00 -> Loss -$4,000
      final pnlLongLoss = MoneyMath.calcUnrealizedPnL(
        isBuy: true,
        openPrice: MoneyMath.toDec(2850.00),
        currentPrice: MoneyMath.toDec(2830.00),
        lots: lots,
        contractSize: contractSize,
      );
      expect(pnlLongLoss.toDouble(), equals(-4000.00));

      // Short Position: Open @ 2850.00, Current Ask @ 2835.00 -> Profit +$3,000
      final pnlShortProfit = MoneyMath.calcUnrealizedPnL(
        isBuy: false,
        openPrice: MoneyMath.toDec(2850.00),
        currentPrice: MoneyMath.toDec(2835.00),
        lots: lots,
        contractSize: contractSize,
      );
      expect(pnlShortProfit.toDouble(), equals(3000.00));

      // Short Position: Open @ 2850.00, Current Ask @ 2865.00 -> Loss -$3,000
      final pnlShortLoss = MoneyMath.calcUnrealizedPnL(
        isBuy: false,
        openPrice: MoneyMath.toDec(2850.00),
        currentPrice: MoneyMath.toDec(2865.00),
        lots: lots,
        contractSize: contractSize,
      );
      expect(pnlShortLoss.toDouble(), equals(-3000.00));
    });

    test('Free Margin & Margin Level % Accuracy', () {
      final equity = MoneyMath.toDec(10500.00);
      final usedMargin = MoneyMath.toDec(3000.00);

      // Free Margin = 10500 - 3000 = 7500.00
      final freeMargin = MoneyMath.calcFreeMargin(equity: equity, usedMargin: usedMargin);
      expect(freeMargin.toDouble(), equals(7500.00));

      // Margin Level % = (10500 / 3000) * 100 = 350.0%
      final marginLevel = MoneyMath.calcMarginLevel(equity: equity, usedMargin: usedMargin);
      expect(marginLevel.toDouble(), equals(350.0));
    });

    test('Spread Markup Calculation for Client Bid & Ask', () {
      final rawBid = MoneyMath.toDec(2850.00);
      final rawAsk = MoneyMath.toDec(2850.30);
      const markupPips = 10;
      const pipDecimals = 2; // factor = 0.01; markup = 10 * 0.01 = 0.10

      final offeredBid = MoneyMath.applySpreadMarkup(
        rawPrice: rawBid,
        markupPips: markupPips,
        pipDecimals: pipDecimals,
        isAsk: false,
      );
      final offeredAsk = MoneyMath.applySpreadMarkup(
        rawPrice: rawAsk,
        markupPips: markupPips,
        pipDecimals: pipDecimals,
        isAsk: true,
      );

      expect(offeredBid.toDouble(), equals(2849.90));
      expect(offeredAsk.toDouble(), equals(2850.40));
    });

    test('Risk Thresholds: Margin Call (<50%) and Stop-Out (<=10%)', () {
      final accountSafe = TradingAccountState(
        accountId: 'ACT-001',
        userId: 'usr_test',
        ledgerBalance: MoneyMath.toDec(10000.00),
        unrealizedPnl: MoneyMath.toDec(-1000.00), // Equity = 9000
        usedMargin: MoneyMath.toDec(2000.00),     // Margin Level = 450%
        leverage: Decimal.fromInt(100),
      );
      expect(accountSafe.isMarginCall, isFalse);
      expect(accountSafe.isStopOutLiquidation, isFalse);

      // Margin Call: Equity = 900, Used Margin = 2000 -> 45% (< 50% margin call threshold)
      final accountMarginCall = TradingAccountState(
        accountId: 'ACT-001',
        userId: 'usr_test',
        ledgerBalance: MoneyMath.toDec(5000.00),
        unrealizedPnl: MoneyMath.toDec(-4100.00), // Equity = 900
        usedMargin: MoneyMath.toDec(2000.00),     // Margin Level = 45%
        leverage: Decimal.fromInt(100),
      );
      expect(accountMarginCall.isMarginCall, isTrue);
      expect(accountMarginCall.isStopOutLiquidation, isFalse);

      // Stop-Out Liquidation: Equity = 160, Used Margin = 2000 -> 8% (<= 10% stop-out threshold)
      final accountLiquidate = TradingAccountState(
        accountId: 'ACT-001',
        userId: 'usr_test',
        ledgerBalance: MoneyMath.toDec(5000.00),
        unrealizedPnl: MoneyMath.toDec(-4840.00), // Equity = 160
        usedMargin: MoneyMath.toDec(2000.00),     // Margin Level = 8%
        leverage: Decimal.fromInt(100),
      );
      expect(accountLiquidate.isMarginCall, isTrue);
      expect(accountLiquidate.isStopOutLiquidation, isTrue);
    });
  });

  group('2. Trade Placement Validation & Rejections', () {
    late TradingEngineCubit cubit;
    late InstrumentEntity goldInst;

    setUp(() {
      cubit = TradingEngineCubit();
      cubit.setBalance('test_trader_1', MoneyMath.toDec(1000.00));
      cubit.switchUser('test_trader_1', initialBalance: MoneyMath.toDec(1000.00));

      goldInst = InstrumentEntity(
        symbol: 'XAU/USD',
        name: 'Gold vs US Dollar',
        category: 'forex',
        rawBid: MoneyMath.toDec(2850.00),
        rawAsk: MoneyMath.toDec(2850.20),
        decimals: 2,
        contractSize: AppConstants.contractSizeGold,
        spreadMarkupPips: 10,
        change24h: 0.5,
        high24h: MoneyMath.toDec(2860.00),
        low24h: MoneyMath.toDec(2840.00),
        volume24h: MoneyMath.toDec(100000),
      );
    });

    tearDown(() {
      cubit.close();
    });

    test('Trade placement is rejected when KYC is not verified', () async {
      expect(
        () => cubit.placeOrder(
          instrument: goldInst,
          side: OrderSide.buy,
          type: OrderType.market,
          lots: MoneyMath.toDec(0.1),
          canTrade: false, // KYC unverified
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('KYC Verification required'),
        )),
      );
    });

    test('Trade placement is rejected when free margin is insufficient', () async {
      // With $1000 balance and 100x leverage, 1 lot gold requires $2850 margin
      // Free margin is $1000 < $2850, so order must throw Insufficient Free Margin!
      expect(
        () => cubit.placeOrder(
          instrument: goldInst,
          side: OrderSide.buy,
          type: OrderType.market,
          lots: MoneyMath.toDec(1.0),
          canTrade: true,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Insufficient Free Margin'),
        )),
      );
    });
  });

  group('3. Trade Execution Engine: Placement, Calculations & Closing', () {
    late TradingEngineCubit cubit;
    late InstrumentEntity goldInst;

    setUp(() {
      cubit = TradingEngineCubit();
      // Provide ample initial balance
      cubit.setBalance('test_trader_2', MoneyMath.toDec(10000.00));
      cubit.switchUser('test_trader_2', initialBalance: MoneyMath.toDec(10000.00));

      goldInst = InstrumentEntity(
        symbol: 'XAU/USD',
        name: 'Gold vs US Dollar',
        category: 'forex',
        rawBid: MoneyMath.toDec(2850.00),
        rawAsk: MoneyMath.toDec(2850.20),
        decimals: 2,
        contractSize: AppConstants.contractSizeGold,
        spreadMarkupPips: 10,
        change24h: 0.5,
        high24h: MoneyMath.toDec(2860.00),
        low24h: MoneyMath.toDec(2840.00),
        volume24h: MoneyMath.toDec(100000),
      );
    });

    tearDown(() {
      cubit.close();
    });

    test('Market BUY Order Execution & Margin Deduction', () async {
      final success = await cubit.placeOrder(
        instrument: goldInst,
        side: OrderSide.buy,
        type: OrderType.market,
        lots: MoneyMath.toDec(0.5), // 0.5 lot = 50 oz
        canTrade: true,
      );

      expect(success, isTrue);
      expect(cubit.state.openPositions.length, equals(1));

      final position = cubit.state.openPositions.first;
      expect(position.symbol, equals('XAU/USD'));
      expect(position.side, equals(OrderSide.buy));
      expect(position.status, equals(OrderStatus.open));
      expect(position.lots.toDouble(), equals(0.5));
      expect(position.openPrice, equals(goldInst.ask));

      // Expected Margin: (0.5 * 100 * askPrice) / 100 = 0.5 * askPrice
      final expectedMargin = (MoneyMath.toDec(0.5) * AppConstants.contractSizeGold * goldInst.ask) / Decimal.fromInt(AppConstants.defaultLeverage);
      expect(position.requiredMargin.toDouble(), equals(expectedMargin.toDouble()));

      // Verify Account State: used margin updated and free margin reduced
      expect(cubit.state.accountState.usedMargin.toDouble(), equals(position.requiredMargin.toDouble()));
      expect(
        cubit.state.accountState.freeMargin.toDouble(),
        equals((cubit.state.accountState.equity - position.requiredMargin).toDouble()),
      );
    });

    test('Live Market Tick updates Unrealized PnL', () async {
      await cubit.placeOrder(
        instrument: goldInst,
        side: OrderSide.buy,
        type: OrderType.market,
        lots: MoneyMath.toDec(1.0), // 1 lot = 100 oz
        canTrade: true,
      );

      final openPrice = cubit.state.openPositions.first.openPrice;

      // Price moves UP by $15.00
      final higherBid = openPrice + MoneyMath.toDec(15.00);
      final higherAsk = higherBid + MoneyMath.toDec(0.30);
      final updatedGold = goldInst.copyWith(
        rawBid: higherBid,
        rawAsk: higherAsk,
      );

      // Emit new tick
      MarketFeedService().emitTick(updatedGold);
      await Future.delayed(const Duration(milliseconds: 50));

      final posAfterTick = cubit.state.openPositions.first;
      // Expected PnL: (bid - openPrice) * 1.0 * 100
      final expectedPnl = (posAfterTick.currentPrice - openPrice) * MoneyMath.toDec(1.0) * AppConstants.contractSizeGold;
      expect(posAfterTick.unrealizedPnl.toDouble(), equals(expectedPnl.toDouble()));
      expect(posAfterTick.unrealizedPnl.toDouble(), greaterThan(0));
    });

    test('Automated Take-Profit (TP) Trigger Execution', () async {
      final openAsk = goldInst.ask;
      final targetTp = openAsk + MoneyMath.toDec(10.00);

      await cubit.placeOrder(
        instrument: goldInst,
        side: OrderSide.buy,
        type: OrderType.market,
        lots: MoneyMath.toDec(1.0),
        takeProfit: targetTp,
        canTrade: true,
      );

      expect(cubit.state.openPositions.length, equals(1));

      // Market moves to hit TP
      final tpTick = goldInst.copyWith(
        rawBid: targetTp + MoneyMath.toDec(1.00),
        rawAsk: targetTp + MoneyMath.toDec(1.20),
      );

      MarketFeedService().emitTick(tpTick);
      await Future.delayed(const Duration(milliseconds: 50));

      // Open positions should be empty, closed trades should have 1 trade
      expect(cubit.state.openPositions.isEmpty, isTrue);
      expect(cubit.state.closedTrades.length, equals(1));

      final closedTrade = cubit.state.closedTrades.first;
      expect(closedTrade.status, equals(OrderStatus.closed));
      expect(closedTrade.closeReason, equals('take_profit'));
      expect(closedTrade.realizedPnl.toDouble(), greaterThan(0));
    });

    test('Automated Stop-Loss (SL) Trigger Execution', () async {
      final openAsk = goldInst.ask;
      final targetSl = openAsk - MoneyMath.toDec(10.00);

      await cubit.placeOrder(
        instrument: goldInst,
        side: OrderSide.buy,
        type: OrderType.market,
        lots: MoneyMath.toDec(1.0),
        stopLoss: targetSl,
        canTrade: true,
      );

      expect(cubit.state.openPositions.length, equals(1));

      // Market price drops to hit SL
      final slTick = goldInst.copyWith(
        rawBid: targetSl - MoneyMath.toDec(0.50),
        rawAsk: targetSl - MoneyMath.toDec(0.20),
      );

      MarketFeedService().emitTick(slTick);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.openPositions.isEmpty, isTrue);
      expect(cubit.state.closedTrades.length, equals(1));

      final closedTrade = cubit.state.closedTrades.first;
      expect(closedTrade.status, equals(OrderStatus.closed));
      expect(closedTrade.closeReason, equals('stop_loss'));
      expect(closedTrade.realizedPnl.toDouble(), lessThan(0));
    });

    test('Manual Position Close releases Margin & settles Realized PnL', () async {
      await cubit.placeOrder(
        instrument: goldInst,
        side: OrderSide.buy,
        type: OrderType.market,
        lots: MoneyMath.toDec(0.5),
        canTrade: true,
      );

      final tradeId = cubit.state.openPositions.first.id;
      final usedMarginBefore = cubit.state.accountState.usedMargin;
      expect(usedMarginBefore.toDouble(), greaterThan(0));

      // Close manually
      await cubit.closePosition(tradeId);

      // Verify position moved to closed
      expect(cubit.state.openPositions.isEmpty, isTrue);
      expect(cubit.state.closedTrades.length, equals(1));

      final closed = cubit.state.closedTrades.first;
      expect(closed.id, equals(tradeId));
      expect(closed.status, equals(OrderStatus.closed));
      expect(closed.closeReason, equals('manual'));

      // Used margin must be released back to 0
      expect(cubit.state.accountState.usedMargin, equals(Decimal.zero));
    });
  });
}

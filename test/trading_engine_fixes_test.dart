import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:asianfxapp/blocs/trading_engine_bloc.dart';
import 'package:asianfxapp/core/constants/app_constants.dart';
import 'package:asianfxapp/core/math/money_math.dart';
import 'package:asianfxapp/data/datasources/market_feed_service.dart';
import 'package:asianfxapp/data/datasources/supabase_trade_service.dart';
import 'package:asianfxapp/domain/entities/trading_entities.dart';

/// Regression tests for the trading-engine defects found during the audit.
/// Each group names the bug it pins down.
void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  InstrumentEntity gold({
    double bid = 2850.00,
    double ask = 2850.20,
    int markup = 10,
  }) =>
      InstrumentEntity(
        symbol: 'XAU/USD',
        name: 'Gold vs US Dollar',
        category: 'forex',
        rawBid: MoneyMath.toDec(bid),
        rawAsk: MoneyMath.toDec(ask),
        decimals: 2,
        spreadMarkupPips: markup,
        contractSize: AppConstants.contractSizeGold,
        change24h: 0.5,
        high24h: MoneyMath.toDec(bid + 20),
        low24h: MoneyMath.toDec(bid - 20),
        volume24h: MoneyMath.toDec(100000),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  group('BUG: margin & PnL were left in the instrument quote currency', () {
    test('USD/JPY margin is denominated in USD, not yen', () {
      final lots = Decimal.one;
      final contract = AppConstants.contractSizeForex; // 100,000
      final price = MoneyMath.toDec(153.60);
      final leverage = Decimal.fromInt(100);

      // Old behaviour: (1 * 100000 * 153.60) / 100 = 153,600 "USD".
      final unconverted = MoneyMath.calcRequiredMargin(
        lots: lots, contractSize: contract, openPrice: price, leverage: leverage,
      );
      expect(unconverted.toDouble(), closeTo(153600.0, 0.01));

      // Correct: the notional is in JPY, so convert with USD-per-JPY (1/153.60).
      final rate = MoneyMath.divide(Decimal.one, price);
      final converted = MoneyMath.calcRequiredMargin(
        lots: lots, contractSize: contract, openPrice: price,
        leverage: leverage, quoteToUsdRate: rate,
      );
      expect(converted.toDouble(), closeTo(1000.0, 0.01));
    });

    test('USD/JPY profit converts yen into USD', () {
      // 1 lot long USD/JPY from 153.60 to 154.60 = 100,000 JPY profit.
      final rate = MoneyMath.divide(Decimal.one, MoneyMath.toDec(154.60));
      final pnl = MoneyMath.calcUnrealizedPnL(
        isBuy: true,
        openPrice: MoneyMath.toDec(153.60),
        currentPrice: MoneyMath.toDec(154.60),
        lots: Decimal.one,
        contractSize: AppConstants.contractSizeForex,
        quoteToUsdRate: rate,
      );
      // 100,000 JPY / 154.60 = $646.83
      expect(pnl.toDouble(), closeTo(646.83, 0.01));
    });

    test('cross pair EUR/GBP margin uses the GBP/USD rate', () {
      // 1 lot EUR/GBP @ 0.8585 with GBP/USD @ 1.3549 and 1:100 leverage
      // => 100000 * 0.8585 * 1.3549 / 100 = $1163.1817, i.e. the EUR notional in
      // USD — within a cent of the same trade expressed as EUR/USD @ 1.1633.
      final margin = MoneyMath.calcRequiredMargin(
        lots: Decimal.one,
        contractSize: AppConstants.contractSizeForex,
        openPrice: MoneyMath.toDec(0.8585),
        leverage: Decimal.fromInt(100),
        quoteToUsdRate: MoneyMath.toDec(1.3549),
      );
      expect(margin.toDouble(), closeTo(1163.1817, 0.0001));

      final viaEurUsd = MoneyMath.calcRequiredMargin(
        lots: Decimal.one,
        contractSize: AppConstants.contractSizeForex,
        openPrice: MoneyMath.toDec(1.1633),
        leverage: Decimal.fromInt(100),
      );
      expect(margin.toDouble(), closeTo(viaEurUsd.toDouble(), 0.5));
    });

    test('feed resolves USD-per-quote-currency for both pair directions', () {
      final feed = MarketFeedService();

      expect(feed.usdPerCurrency('USD'), Decimal.one);

      // GBP is quoted directly as GBP/USD.
      final gbpUsd = feed.getInstrument('GBP/USD')!;
      expect(feed.usdPerCurrency('GBP').toDouble(),
          closeTo(gbpUsd.midPrice.toDouble(), 0.0001));

      // JPY only exists as USD/JPY, so the rate must be inverted.
      final usdJpy = feed.getInstrument('USD/JPY')!;
      expect(feed.usdPerCurrency('JPY').toDouble(),
          closeTo(1 / usdJpy.midPrice.toDouble(), 0.000001));

      // An unknown currency degrades to 1:1 instead of zeroing the position.
      expect(feed.usdPerCurrency('ZZZ'), Decimal.one);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('BUG: pip size was wrong for 1-, 3- and 5-digit instruments', () {
    test('pointSize follows 10^-digits for every digit count', () {
      expect(MoneyMath.pointSize(1).toString(), '0.1');
      expect(MoneyMath.pointSize(2).toString(), '0.01');
      expect(MoneyMath.pointSize(3).toString(), '0.001');
      expect(MoneyMath.pointSize(4).toString(), '0.0001');
      expect(MoneyMath.pointSize(5).toString(), '0.00001');
    });

    test('index spread is applied in index points, not thousandths', () {
      // US30: 1 digit, 25 points of markup -> 2.5 price units of total spread.
      final us30 = InstrumentEntity(
        symbol: 'US30/USD',
        name: 'Wall Street 30',
        category: 'indices',
        rawBid: MoneyMath.toDec(44250.00),
        rawAsk: MoneyMath.toDec(44250.00),
        decimals: 1,
        spreadMarkupPips: 25,
        contractSize: Decimal.one,
        change24h: 0,
        high24h: MoneyMath.toDec(44300),
        low24h: MoneyMath.toDec(44200),
        volume24h: MoneyMath.toDec(1000),
      );
      expect(us30.spread.toDouble(), closeTo(2.5, 0.0001));
      expect(us30.spreadPoints, closeTo(25.0, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('BUG: half-spread markup was rounded per side', () {
    test('an odd markup keeps the configured total spread exact', () {
      // 15 points on a 2-digit symbol = 0.15 total. The old code did
      // (15 / 2).round() = 8 per side, producing 0.16.
      final inst = gold(bid: 2850.00, ask: 2850.00, markup: 15);
      expect(inst.spread.toDouble(), closeTo(0.15, 0.000001));
      expect(inst.bid.toDouble(), closeTo(2849.925, 0.000001));
      expect(inst.ask.toDouble(), closeTo(2850.075, 0.000001));
    });

    test('a 3-point silver markup is not inflated to 4 points', () {
      final silver = InstrumentEntity(
        symbol: 'XAG/USD',
        name: 'Silver',
        category: 'forex',
        rawBid: MoneyMath.toDec(63.80),
        rawAsk: MoneyMath.toDec(63.80),
        decimals: 2,
        spreadMarkupPips: 3,
        contractSize: AppConstants.contractSizeSilver,
        change24h: 0,
        high24h: MoneyMath.toDec(64),
        low24h: MoneyMath.toDec(63),
        volume24h: MoneyMath.toDec(1000),
      );
      expect(silver.spread.toDouble(), closeTo(0.03, 0.000001));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('BUG: closing a trade replaced the balance with the ledger aggregate', () {
    late TradingEngineCubit cubit;

    setUp(() {
      cubit = TradingEngineCubit();
      cubit.setBalance('bal_user', MoneyMath.toDec(10000));
      cubit.switchUser('bal_user', initialBalance: MoneyMath.toDec(10000));
    });
    tearDown(() => cubit.close());

    test('a profitable close adds PnL to the deposit instead of overwriting it', () async {
      final inst = gold();
      await cubit.placeOrder(
        instrument: inst,
        side: OrderSide.buy,
        type: OrderType.market,
        lots: MoneyMath.toDec(0.10),
        canTrade: true,
      );

      final openPrice = cubit.state.openPositions.first.openPrice;

      // +$10 on gold, 0.10 lots x 100 oz = +$100 realized.
      MarketFeedService().emitTick(inst.copyWith(
        rawBid: openPrice + MoneyMath.toDec(10.00),
        rawAsk: openPrice + MoneyMath.toDec(10.20),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final realized = cubit.state.openPositions.first.unrealizedPnl;
      expect(realized.toDouble(), greaterThan(0));

      await cubit.closePosition(cubit.state.openPositions.first.id);

      // The old code did `postLedger > 0 ? postLedger : ...`, which set the
      // balance to the cumulative realized PnL and destroyed the $10,000.
      expect(cubit.state.accountState.ledgerBalance.toDouble(),
          closeTo(10000 + realized.toDouble(), 0.01));
      expect(cubit.state.accountState.usedMargin, Decimal.zero);
    });

    test('closing the same position twice settles it only once', () async {
      final inst = gold();
      await cubit.placeOrder(
        instrument: inst,
        side: OrderSide.buy,
        type: OrderType.market,
        lots: MoneyMath.toDec(0.10),
        canTrade: true,
      );
      final id = cubit.state.openPositions.first.id;

      await Future.wait([cubit.closePosition(id), cubit.closePosition(id)]);

      expect(cubit.state.openPositions, isEmpty);
      expect(cubit.state.closedTrades.where((t) => t.id == id).length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('BUG: orders had no validation at all', () {
    late TradingEngineCubit cubit;

    setUp(() {
      cubit = TradingEngineCubit();
      cubit.setBalance('val_user', MoneyMath.toDec(100000));
      cubit.switchUser('val_user', initialBalance: MoneyMath.toDec(100000));
    });
    tearDown(() => cubit.close());

    Future<void> expectRejected(Future<bool> Function() action, String fragment) async {
      await expectLater(
        action(),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains(fragment))),
      );
    }

    test('zero and sub-minimum volume is rejected', () async {
      await expectRejected(
        () => cubit.placeOrder(
          instrument: gold(), side: OrderSide.buy, type: OrderType.market,
          lots: Decimal.zero, canTrade: true,
        ),
        'greater than zero',
      );
    });

    test('volume off the lot step is rejected', () async {
      await expectRejected(
        () => cubit.placeOrder(
          instrument: gold(), side: OrderSide.buy, type: OrderType.market,
          lots: MoneyMath.toDec(0.015), canTrade: true,
        ),
        'multiple of',
      );
    });

    test('volume above the maximum is rejected', () async {
      await expectRejected(
        () => cubit.placeOrder(
          instrument: gold(), side: OrderSide.buy, type: OrderType.market,
          lots: MoneyMath.toDec(500), canTrade: true,
        ),
        'between',
      );
    });

    test('an unsupported leverage is rejected', () async {
      await expectRejected(
        () => cubit.placeOrder(
          instrument: gold(), side: OrderSide.buy, type: OrderType.market,
          lots: MoneyMath.toDec(0.01), leverage: Decimal.fromInt(9999), canTrade: true,
        ),
        'not offered',
      );
    });

    test('a BUY take profit below the entry is rejected', () async {
      final inst = gold();
      await expectRejected(
        () => cubit.placeOrder(
          instrument: inst, side: OrderSide.buy, type: OrderType.market,
          lots: MoneyMath.toDec(0.01),
          takeProfit: inst.ask - MoneyMath.toDec(5),
          canTrade: true,
        ),
        'take profit must be above the entry',
      );
    });

    test('a BUY stop loss above the entry is rejected', () async {
      final inst = gold();
      await expectRejected(
        () => cubit.placeOrder(
          instrument: inst, side: OrderSide.buy, type: OrderType.market,
          lots: MoneyMath.toDec(0.01),
          stopLoss: inst.ask + MoneyMath.toDec(5),
          canTrade: true,
        ),
        'stop loss must be below the entry',
      );
    });

    test('a BUY LIMIT above the ask is rejected', () async {
      final inst = gold();
      await expectRejected(
        () => cubit.placeOrder(
          instrument: inst, side: OrderSide.buy, type: OrderType.limit,
          lots: MoneyMath.toDec(0.01),
          targetPrice: inst.ask + MoneyMath.toDec(5),
          canTrade: true,
        ),
        'BUY LIMIT must be below the current ask',
      );
    });

    test('a BUY STOP below the ask is rejected', () async {
      final inst = gold();
      await expectRejected(
        () => cubit.placeOrder(
          instrument: inst, side: OrderSide.buy, type: OrderType.stop,
          lots: MoneyMath.toDec(0.01),
          targetPrice: inst.ask - MoneyMath.toDec(5),
          canTrade: true,
        ),
        'BUY STOP must be above the current ask',
      );
    });

    test('a valid BUY LIMIT below the ask is accepted and rests', () async {
      final inst = gold();
      final ok = await cubit.placeOrder(
        instrument: inst, side: OrderSide.buy, type: OrderType.limit,
        lots: MoneyMath.toDec(0.01),
        targetPrice: inst.ask - MoneyMath.toDec(5),
        canTrade: true,
      );
      expect(ok, isTrue);
      expect(cubit.state.pendingOrders.length, 1);
      expect(cubit.state.pendingOrders.first.type, OrderType.limit);
      // A resting order must not reserve margin until it triggers.
      expect(cubit.state.accountState.usedMargin, Decimal.zero);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('BUG: stop-out closed only one position per tick', () {
    test('liquidation loops until the margin level recovers', () async {
      final cubit = TradingEngineCubit();
      addTearDown(cubit.close);

      cubit.setBalance('so_user', MoneyMath.toDec(1000));
      cubit.switchUser('so_user', initialBalance: MoneyMath.toDec(1000));

      final inst = gold();
      for (var i = 0; i < 2; i++) {
        await cubit.placeOrder(
          instrument: inst, side: OrderSide.buy, type: OrderType.market,
          lots: MoneyMath.toDec(0.10), leverage: Decimal.fromInt(500), canTrade: true,
        );
      }
      expect(cubit.state.openPositions.length, 2);

      // Crash the price: each 0.10-lot position loses ~$500, wiping the equity.
      final crash = inst.copyWith(
        rawBid: MoneyMath.toDec(2800.00),
        rawAsk: MoneyMath.toDec(2800.20),
      );
      MarketFeedService().emitTick(crash);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(cubit.state.openPositions, isEmpty,
          reason: 'both positions must liquidate in the same evaluation cycle');
      expect(cubit.state.closedTrades.length, 2);
      for (final t in cubit.state.closedTrades) {
        expect(t.closeReason, AppConstants.closeReasonStopOut);
        expect(t.status, OrderStatus.liquidated);
      }
      expect(cubit.state.accountState.usedMargin, Decimal.zero);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('BUG: pending orders re-validate margin at trigger time', () {
    test('a trigger with no free margin is rejected, not silently opened', () async {
      final cubit = TradingEngineCubit();
      addTearDown(cubit.close);

      cubit.setBalance('pm_user', MoneyMath.toDec(20));
      cubit.switchUser('pm_user', initialBalance: MoneyMath.toDec(20));

      final inst = gold();
      // 1 lot of gold needs $2,850 of margin at 1:100 — far beyond this account.
      await cubit.placeOrder(
        instrument: inst, side: OrderSide.buy, type: OrderType.limit,
        lots: Decimal.one,
        targetPrice: inst.ask - MoneyMath.toDec(5),
        canTrade: true,
      );
      expect(cubit.state.pendingOrders.length, 1);

      // Drop the ask through the limit level so the order triggers.
      MarketFeedService().emitTick(inst.copyWith(
        rawBid: inst.rawBid - MoneyMath.toDec(10),
        rawAsk: inst.rawAsk - MoneyMath.toDec(10),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(cubit.state.openPositions, isEmpty);
      expect(cubit.state.accountState.usedMargin, Decimal.zero);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('BUG: fetchUserTrades forced every row to OrderType.market', () {
    test('row mapping preserves type, status and every audit field', () {
      final trade = SupabaseTradeService.tradeFromRow({
        'id': 'POS-ABC',
        'order_id': 'ORD-ABC',
        'user_id': 'u1',
        'symbol': 'XAU/USD',
        'side': 'sell',
        'type': 'limit',
        'status': 'pending',
        'lots': 0.25,
        'contract_size': 100,
        'open_price': 2851.5,
        'current_price': 2852.0,
        'target_price': 2860.0,
        'stop_loss': 2870.0,
        'take_profit': 2830.0,
        'required_margin': 712.88,
        'leverage': 200,
        'commission': 1.25,
        'swap': -0.40,
        'realized_pnl': 0,
        'quote_to_usd_rate': 1,
        'requested_price': 2851.4,
        'spread_at_open': 0.15,
        'client_request_id': 'ord-123',
        'open_time': '2026-09-30T10:00:00Z',
      });

      expect(trade.type, OrderType.limit, reason: 'order type must survive the round trip');
      expect(trade.status, OrderStatus.pending);
      expect(trade.side, OrderSide.sell);
      expect(trade.lots.toDouble(), 0.25);
      expect(trade.targetPrice!.toDouble(), 2860.0);
      expect(trade.stopLoss!.toDouble(), 2870.0);
      expect(trade.takeProfit!.toDouble(), 2830.0);
      expect(trade.commission.toDouble(), 1.25);
      expect(trade.swap.toDouble(), -0.40);
      expect(trade.leverage.toDouble(), 200);
      expect(trade.currentPrice.toDouble(), 2852.0);
      expect(trade.requestedPrice!.toDouble(), 2851.4);
      expect(trade.clientRequestId, 'ord-123');
    });

    test('new terminal states map instead of crashing', () {
      expect(SupabaseTradeService.orderStatusFrom('rejected'), OrderStatus.rejected);
      expect(SupabaseTradeService.orderStatusFrom('expired'), OrderStatus.expired);
      expect(SupabaseTradeService.orderStatusFrom('cancelled'), OrderStatus.cancelled);
      expect(SupabaseTradeService.orderStatusFrom('liquidated'), OrderStatus.liquidated);
    });

    test('unknown / null enum values fall back instead of throwing', () {
      expect(SupabaseTradeService.orderTypeFrom(null), OrderType.market);
      expect(SupabaseTradeService.orderTypeFrom('something_new'), OrderType.market);
      expect(SupabaseTradeService.orderTypeFrom('stopLimit'), OrderType.stopLimit);
      expect(SupabaseTradeService.orderTypeFrom('stop_limit'), OrderType.stopLimit);
      expect(SupabaseTradeService.orderStatusFrom('who_knows'), OrderStatus.open);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Decimal arithmetic no longer detours through double', () {
    test('division is exact for terminating quotients', () {
      expect(MoneyMath.divide(MoneyMath.toDec(1), MoneyMath.toDec(8)).toString(), '0.125');
      // 1/3 has no finite representation: capped at the requested scale.
      expect(MoneyMath.divide(Decimal.one, Decimal.fromInt(3), scale: 6).toString(), '0.333333');
    });

    test('monetary results are rounded to the stored 4-dp scale', () {
      final pnl = MoneyMath.calcUnrealizedPnL(
        isBuy: true,
        openPrice: MoneyMath.toDec(1.123456789),
        currentPrice: MoneyMath.toDec(1.223456789),
        lots: MoneyMath.toDec(0.01),
        contractSize: AppConstants.contractSizeForex,
      );
      expect(pnl.scale, lessThanOrEqualTo(MoneyMath.moneyScale));
      expect(pnl.toDouble(), closeTo(100.0, 0.0001));
    });
  });
}

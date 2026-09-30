import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asianfxapp/core/constants/app_constants.dart';
import 'package:asianfxapp/core/math/money_math.dart';
import 'package:asianfxapp/data/repositories/ledger_repository.dart';

void main() {
  group('1. MoneyMath Precision & Risk Calculations', () {
    test('Gold (XAU/USD) Margin Calculation with 100x leverage', () {
      final lots = MoneyMath.toDec(1.5); // 1.5 lots
      final contractSize = AppConstants.contractSizeGold; // 100 oz
      final openPrice = MoneyMath.toDec(2850.00);
      final leverage = Decimal.fromInt(100);

      final margin = MoneyMath.calcRequiredMargin(
        lots: lots,
        contractSize: contractSize,
        openPrice: openPrice,
        leverage: leverage,
      );

      // (1.5 * 100 * 2850) / 100 = 4275.00
      expect(margin.toDouble(), equals(4275.00));
    });

    test('Gold (XAU/USD) Unrealized PnL Calculation', () {
      // Long 2.0 lots bought at 2850.00, current bid is 2865.50
      final pnlLong = MoneyMath.calcUnrealizedPnL(
        isBuy: true,
        openPrice: MoneyMath.toDec(2850.00),
        currentPrice: MoneyMath.toDec(2865.50),
        lots: MoneyMath.toDec(2.0),
        contractSize: AppConstants.contractSizeGold,
      );
      // (2865.50 - 2850.00) * 2.0 * 100 = 3100.00
      expect(pnlLong.toDouble(), equals(3100.00));

      // Short 1.0 lot sold at 2860.00, current ask is 2870.00 (Loss)
      final pnlShort = MoneyMath.calcUnrealizedPnL(
        isBuy: false,
        openPrice: MoneyMath.toDec(2860.00),
        currentPrice: MoneyMath.toDec(2870.00),
        lots: MoneyMath.toDec(1.0),
        contractSize: AppConstants.contractSizeGold,
      );
      // (2860 - 2870) * 1.0 * 100 = -1000.00
      expect(pnlShort.toDouble(), equals(-1000.00));
    });

    test('Margin Level & Stop-Out Thresholds', () {
      final equity = MoneyMath.toDec(2000.00);
      final usedMargin = MoneyMath.toDec(4000.00);

      final marginLevel = MoneyMath.calcMarginLevel(
        equity: equity,
        usedMargin: usedMargin,
      );

      // (2000 / 4000) * 100 = 50.0%
      expect(marginLevel.toDouble(), equals(50.0));
      expect(marginLevel.toDouble() <= AppConstants.marginCallLevelPercent, isTrue);
    });

    test('Small Account (\$100) Micro-Lot (0.01) Gold & Forex Margin with 100x and 500x leverage', () {
      final accountBalance = MoneyMath.toDec(100.00);
      final lots = MoneyMath.toDec(0.01);
      final goldPrice = MoneyMath.toDec(4362.00);

      // Gold at 1:100 leverage
      final margin100 = MoneyMath.calcRequiredMargin(
        lots: lots,
        contractSize: AppConstants.contractSizeGold,
        openPrice: goldPrice,
        leverage: Decimal.fromInt(100),
      );
      // (0.01 * 100 * 4362) / 100 = 43.62
      expect(margin100.toDouble(), equals(43.62));
      expect(margin100 <= accountBalance, isTrue, reason: '43.62 fits comfortably in 100 balance');

      // Gold at 1:500 leverage
      final margin500 = MoneyMath.calcRequiredMargin(
        lots: lots,
        contractSize: AppConstants.contractSizeGold,
        openPrice: goldPrice,
        leverage: Decimal.fromInt(500),
      );
      // (0.01 * 100 * 4362) / 500 = 8.724
      expect(margin500.toDouble(), closeTo(8.72, 0.01));
      expect(margin500 <= accountBalance, isTrue);

      // EUR/USD at 1:100 leverage
      final eurusdPrice = MoneyMath.toDec(1.16);
      final marginForex = MoneyMath.calcRequiredMargin(
        lots: lots,
        contractSize: AppConstants.contractSizeForex,
        openPrice: eurusdPrice,
        leverage: Decimal.fromInt(100),
      );
      // (0.01 * 100000 * 1.16) / 100 = 11.60
      expect(marginForex.toDouble(), equals(11.60));
      expect(marginForex <= accountBalance, isTrue, reason: '11.60 fits easily in 100 balance');
    });
  });

  group('2. High-Precision Double-Entry Ledger Invariant Tests', () {
    late LedgerRepository repo;

    setUp(() {
      repo = LedgerRepository();
    });

    test('Initial Seed Ledger is perfectly balanced with 0.00 drift', () {
      final proof = repo.generateTreasuryProof();
      expect(proof.isProofValid, isTrue);
      expect(proof.accountingDrift, equals(Decimal.zero));
      expect(proof.totalSystemDebits, equals(proof.totalSystemCredits));
    });

    test('Deposit increases Segregated Assets and Client Equity identically', () {
      final depositAmount = MoneyMath.toDec(10000.00);
      repo.recordDeposit(
        userId: 'usr_test_01',
        amount: depositAmount,
        method: 'USDT (TRC-20)',
      );

      final proof = repo.generateTreasuryProof();
      expect(proof.isProofValid, isTrue);
      expect(proof.accountingDrift, equals(Decimal.zero));
    });

    test('Margin Lock & Margin Release maintain zero ledger drift', () {
      final marginAmt = MoneyMath.toDec(3500.00);

      // 1. Lock Margin
      final lockTx = repo.recordMarginLock(
        userId: 'usr_institutional_01',
        tradeId: 'POS-TEST-1',
        marginAmount: marginAmt,
        symbol: 'XAU/USD',
      );
      expect(lockTx.isBalanced, isTrue);

      // 2. Release Margin
      final relTx = repo.recordMarginRelease(
        userId: 'usr_institutional_01',
        tradeId: 'POS-TEST-1',
        marginAmount: marginAmt,
        symbol: 'XAU/USD',
      );
      expect(relTx.isBalanced, isTrue);

      final proof = repo.generateTreasuryProof();
      expect(proof.isProofValid, isTrue);
      expect(proof.accountingDrift, equals(Decimal.zero));
    });

    test('Trade Realized Profit & Loss correctly balances with Dealing Desk Reserves', () {
      // 1. Client Realized Profit ($1,250.00)
      final profitTx = repo.recordTradePnl(
        userId: 'usr_institutional_01',
        tradeId: 'POS-WIN-1',
        pnlAmount: MoneyMath.toDec(1250.00),
        symbol: 'BTC/USD',
      );
      expect(profitTx.isBalanced, isTrue);

      // 2. Client Realized Loss (-$800.00)
      final lossTx = repo.recordTradePnl(
        userId: 'usr_institutional_01',
        tradeId: 'POS-LOSS-1',
        pnlAmount: MoneyMath.toDec(-800.00),
        symbol: 'EUR/USD',
      );
      expect(lossTx.isBalanced, isTrue);

      final proof = repo.generateTreasuryProof();
      expect(proof.isProofValid, isTrue);
      expect(proof.accountingDrift, equals(Decimal.zero));
    });
  });

  group('3. Complete Gold & Forex Trade Placement & Margin Lifecycle', () {
    late LedgerRepository repo;

    setUp(() {
      repo = LedgerRepository();
    });

    test('Live End-to-End Test: Deposit \$100 -> Open 0.01 Gold Trade (1:500) -> Price Move -> Close Position', () {
      const userId = 'usr_trader_77';

      // 1. User deposits $100
      repo.recordDeposit(
        userId: userId,
        amount: MoneyMath.toDec(100.00),
        method: 'USDT (TRC-20)',
      );
      final initialBal = repo.getClientLedgerBalance(userId);
      expect(initialBal.toDouble(), equals(100.00));

      // 2. Open Gold (XAU/USD) 0.01 micro lot with 1:500 leverage at $4345.00
      final lots = MoneyMath.toDec(0.01);
      final entryPrice = MoneyMath.toDec(4345.00);
      final requiredMargin = MoneyMath.calcRequiredMargin(
        lots: lots,
        contractSize: AppConstants.contractSizeGold,
        openPrice: entryPrice,
        leverage: Decimal.fromInt(500),
      );

      // (0.01 * 100 * 4345) / 500 = 8.69
      expect(requiredMargin.toDouble(), equals(8.69));
      expect(requiredMargin <= initialBal, isTrue, reason: 'Margin is fully sufficient for \$100 account');

      // 3. Lock Margin for Open Trade
      final lockTx = repo.recordMarginLock(
        userId: userId,
        tradeId: 'POS-GOLD-001',
        marginAmount: requiredMargin,
        symbol: 'XAU/USD',
      );
      expect(lockTx.isBalanced, isTrue);

      final freeMargin = initialBal - requiredMargin;
      expect(freeMargin.toDouble(), equals(91.31));

      // 4. Gold price moves up by \$10 to \$4355.00 (+100 pips)
      final exitPrice = MoneyMath.toDec(4355.00);
      final unrealizedPnl = MoneyMath.calcUnrealizedPnL(
        isBuy: true,
        openPrice: entryPrice,
        currentPrice: exitPrice,
        lots: lots,
        contractSize: AppConstants.contractSizeGold,
      );
      // (4355 - 4345) * 0.01 * 100 = +$10.00
      expect(unrealizedPnl.toDouble(), equals(10.00));

      final liveEquity = initialBal + unrealizedPnl;
      expect(liveEquity.toDouble(), equals(110.00));

      // 5. Close Trade: Release Margin and Settle Realized Profit
      final relTx = repo.recordMarginRelease(
        userId: userId,
        tradeId: 'POS-GOLD-001',
        marginAmount: requiredMargin,
        symbol: 'XAU/USD',
      );
      expect(relTx.isBalanced, isTrue);

      final pnlTx = repo.recordTradePnl(
        userId: userId,
        tradeId: 'POS-GOLD-001',
        pnlAmount: unrealizedPnl,
        symbol: 'XAU/USD',
      );
      expect(pnlTx.isBalanced, isTrue);

      // 6. Check final settled balance and audit proof
      final finalBal = repo.getClientLedgerBalance(userId);
      expect(finalBal.toDouble(), equals(110.00));

      final proof = repo.generateTreasuryProof();
      expect(proof.isProofValid, isTrue);
      expect(proof.accountingDrift, equals(Decimal.zero));
    });
  });
}

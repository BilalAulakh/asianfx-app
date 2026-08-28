import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:asianfxapp/core/constants/app_constants.dart';
import 'package:asianfxapp/core/math/money_math.dart';
import 'package:asianfxapp/data/repositories/ledger_repository.dart';
import 'package:asianfxapp/domain/entities/ledger_entities.dart';

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
      expect(marginLevel.toDouble() <= AppConstants.stopOutLevelPercent, isTrue);
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
}

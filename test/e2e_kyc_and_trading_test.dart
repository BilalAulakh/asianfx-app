import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:asianfxapp/core/math/money_math.dart';
import 'package:asianfxapp/data/datasources/market_feed_service.dart';
import 'package:asianfxapp/data/repositories/kyc_repository.dart';
import 'package:asianfxapp/data/repositories/ledger_repository.dart';
import 'package:asianfxapp/domain/entities/kyc_entities.dart';
import 'package:asianfxapp/domain/entities/trading_entities.dart';
import 'package:asianfxapp/domain/entities/user_entity.dart';
import 'package:asianfxapp/blocs/admin_bloc.dart';
import 'package:asianfxapp/blocs/dealing_desk_bloc.dart';
import 'package:asianfxapp/blocs/trading_engine_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:asianfxapp/blocs/kyc_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Complete End-to-End KYC Auto-Approval & Trade Execution Test Suite', () {
    late KycRepository kycRepo;
    late KycCubit kycCubit;
    late AdminBloc adminBloc;
    late TradingEngineCubit tradingEngine;
    late DealingDeskCubit dealingDesk;
    late MarketFeedService feedService;
    late LedgerRepository ledgerRepo;

    const testUserId = 'trader_vip_99';
    const testUserEmail = 'trader99@asianfx.com';

    setUp(() {
      feedService = MarketFeedService();
      ledgerRepo = LedgerRepository.instance;
      kycRepo = KycRepository();
      kycCubit = KycCubit(repository: kycRepo);
      adminBloc = AdminBloc();
      tradingEngine = TradingEngineCubit();
      dealingDesk = DealingDeskCubit(
        feedService: feedService,
        tradingEngineCubit: tradingEngine,
      );
    });

    tearDown(() {
      kycCubit.close();
      adminBloc.close();
      tradingEngine.close();
      dealingDesk.close();
    });

    test('1. KYC Auto-Approval: Document submission immediately unlocks Level 2 verified status', () async {
      // 1. Setup user profile in KYC repository
      await kycRepo.savePersonalInfo(
        userId: testUserId,
        firstName: 'Bilal',
        lastName: 'Aulakh',
        dateOfBirth: DateTime(1995, 8, 15),
        nationality: 'Pakistani',
        countryOfResidence: 'Pakistan',
        address: 'DHA Phase 5',
        city: 'Lahore',
        state: 'Punjab',
        postalCode: '54000',
      );

      final dummyBytes = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0,
        ...List.generate(200, (i) => i % 255),
        0xFF, 0xD9,
      ]);

      // Upload Front POI document
      await kycRepo.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.identity,
        documentType: KycDocumentType.cnic,
        fileName: 'cnic_front.jpg',
        bytes: dummyBytes,
        documentSide: 'FRONT',
        documentNumber: '35201-1234567-1',
      );

      // Upload Back POI document
      await kycRepo.uploadDocument(
        userId: testUserId,
        category: KycDocumentCategory.identity,
        documentType: KycDocumentType.cnic,
        fileName: 'cnic_back.jpg',
        bytes: dummyBytes,
        documentSide: 'BACK',
        documentNumber: '35201-1234567-1',
      );

      // 2. Submit KYC application with Auto-Approve enabled
      final autoApprovedProfile = await kycRepo.submitKycApplication(testUserId, autoApprove: true);

      // Verify that status is instantly APPROVED with zero manual waiting
      expect(autoApprovedProfile.status, equals(KycVerificationStatus.approved));
      expect(autoApprovedProfile.reviewedBy, contains('AI Auto-Engine'));

      // 3. Verify Admin Bloc auto-approves incoming request
      adminBloc.addKycRequest(
        AdminKycItem(
          id: 'kyc_req_001',
          userId: testUserId,
          userName: 'Bilal Aulakh',
          userEmail: testUserEmail,
          docType: 'National ID / CNIC',
          docNumber: '35201-1234567-1',
          submittedAt: DateTime.now(),
        ),
      );

      final registeredKyc = adminBloc.state.kycRequests.firstWhere((k) => k.userId == testUserId);
      expect(registeredKyc.status, equals(AdminKycStatus.approved));

      // 4. Verify User Entity reflects full KYC verified state
      final user = UserEntity(
        id: testUserId,
        email: testUserEmail,
        fullName: 'Bilal Aulakh',
        kycStatus: KycStatus.approved,
        kycTier: 2,
        status: AccountStatus.active,
        createdAt: DateTime.now(),
      );

      expect(user.isKycVerified, isTrue);
      expect(user.canTrade, isTrue);
    });

    test('2. Manual Deposit Approval & Account Funding', () async {
      // 1. User submits deposit request -> status is pending (admin review required)
      const depositTxId = 'DEP-TX-7788';
      adminBloc.addTransactionRequest(
        AdminTransaction(
          id: depositTxId,
          userId: testUserId,
          userName: 'Bilal Aulakh',
          userEmail: testUserEmail,
          type: 'DEPOSIT',
          amount: 5000.00,
          method: 'USDT TRC-20',
          accountOrAddress: 'TRX778899address',
          status: AdminTxStatus.pending,
          createdAt: DateTime.now(),
          isAutoApproved: false, // Strict Manual Approval
        ),
      );

      expect(adminBloc.state.transactions.first.status, equals(AdminTxStatus.pending));

      // 2. Admin approves deposit -> balance is funded into Trading Engine
      adminBloc.approveTransaction(depositTxId);
      expect(adminBloc.state.transactions.first.status, equals(AdminTxStatus.approved));

      // Fund user balance in trading engine & ledger
      ledgerRepo.recordDeposit(
        userId: testUserId,
        amount: MoneyMath.toDec(5000.00),
        method: 'USDT TRC-20',
      );
      tradingEngine.setBalance(testUserId, MoneyMath.toDec(5000.00));
      tradingEngine.switchUser(testUserId, initialBalance: MoneyMath.toDec(5000.00));

      expect(tradingEngine.state.accountState.ledgerBalance.toDouble(), equals(5000.00));
      expect(tradingEngine.state.accountState.freeMargin.toDouble(), equals(5000.00));
    });

    test('3. Live Trade Placement, Dynamic Tick Movement, Position Close & Solvency Settlement', () async {
      // 1. Setup funded account
      tradingEngine.setBalance(testUserId, MoneyMath.toDec(5000.00));
      tradingEngine.switchUser(testUserId, initialBalance: MoneyMath.toDec(5000.00));

      final goldInst = feedService.getInstrument('XAU/USD')!;
      expect(goldInst.symbol, equals('XAU/USD'));

      // 2. Place 0.1 Lot Gold BUY order
      final orderSuccess = await tradingEngine.placeOrder(
        instrument: goldInst,
        side: OrderSide.buy,
        type: OrderType.market,
        lots: MoneyMath.toDec(0.1), // 10 oz of Gold
        canTrade: true,
      );

      expect(orderSuccess, isTrue);
      expect(tradingEngine.state.openPositions.length, equals(1));

      final position = tradingEngine.state.openPositions.first;
      expect(position.symbol, equals('XAU/USD'));
      expect(position.side, equals(OrderSide.buy));
      expect(position.lots.toDouble(), equals(0.1));
      expect(position.requiredMargin.toDouble(), greaterThan(0.0));

      // 3. Check Dealing Desk exposure tracking & spread markup
      dealingDesk.calculateExposure();
      final goldExp = dealingDesk.state.instrumentExposures.firstWhere((e) => e.symbol == 'XAU/USD');
      expect(goldExp.activePositionCount, equals(1));
      expect(goldExp.totalBuyLots.toDouble(), equals(0.1));
      expect(goldExp.spreadMarkupPips, equals(15)); // Broker spread markup

      // 4. Simulate Gold price rising by +$20.00 (Profitable BUY trade)
      final openPrice = position.openPrice;
      final higherBid = openPrice + MoneyMath.toDec(20.00);
      final higherAsk = higherBid + MoneyMath.toDec(0.40);
      final liveGold = goldInst.copyWith(
        rawBid: higherBid,
        rawAsk: higherAsk,
      );

      // Feed service emits tick -> updates unrealized PnL
      feedService.emitTick(liveGold);
      await Future.delayed(const Duration(milliseconds: 50));

      final updatedPos = tradingEngine.state.openPositions.first;
      expect(updatedPos.unrealizedPnl.toDouble(), greaterThan(150.0)); // 0.1 lot * 100 oz * +$20 minus spread = ~$188.78

      // 5. Close Position manually -> settles realized profit
      await tradingEngine.closePosition(updatedPos.id);
      expect(tradingEngine.state.openPositions.isEmpty, isTrue);

      // Check balance is updated with realized profit
      expect(tradingEngine.state.accountState.ledgerBalance.toDouble(), greaterThan(5000.00));
      expect(tradingEngine.state.accountState.usedMargin.toDouble(), equals(0.0));

      // 6. Verify double-entry ledger solvency remains zero drift
      final audit = ledgerRepo.generateTreasuryProof();
      expect(audit.isZeroDriftVerified, isTrue);
      expect(audit.accountingDrift.toDouble(), equals(0.00));
    });
  });
}

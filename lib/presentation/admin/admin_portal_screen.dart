import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/math/money_math.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/dealing_entities.dart';
import '../../domain/entities/ledger_entities.dart';
import '../../domain/entities/trading_entities.dart';
import '../../domain/entities/user_entity.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dealing_desk_provider.dart';
import '../../providers/kyc_compliance_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/trading_engine_provider.dart';

class AdminPortalScreen extends ConsumerStatefulWidget {
  const AdminPortalScreen({super.key});

  @override
  ConsumerState<AdminPortalScreen> createState() => _AdminPortalScreenState();
}

class _AdminPortalScreenState extends ConsumerState<AdminPortalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authProvider).user;
    final dealerRisk = ref.watch(dealingDeskProvider);
    final complianceState = ref.watch(kycComplianceProvider);
    final treasuryProof = ref.watch(treasuryAuditProofProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D28),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD600).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFD600)),
              ),
              child: const Text(
                'GOVERNANCE',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFFD600),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Institutional Admin Portal',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFD600),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFFD600),
          unselectedLabelColor: const Color(0xFF848E9C),
          labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 12),
          tabs: [
            const Tab(text: 'Dealing Desk'),
            Tab(text: 'KYC & Compliance (${complianceState.pendingApplications.length})'),
            const Tab(text: 'Treasury & Audit'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 1. Chief Dealer Desk View
          _buildDealingDeskTab(dealerRisk),

          // 2. Compliance & AML View
          _buildComplianceTab(complianceState),

          // 3. Finance & Treasury Auditor View
          _buildTreasuryTab(treasuryProof),
        ],
      ),
    );
  }

  // ── 1. DEALING DESK VIEW ──────────────────────────────────────────────────
  Widget _buildDealingDeskTab(DealerRiskSummary risk) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Global Exposure & House PnL Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E2838), Color(0xFF101722)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2B384E)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HOUSE B-BOOK PnL',
                          style: TextStyle(fontSize: 11, color: Color(0xFF848E9C), fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          MoneyMath.formatPnL(risk.aggregateHouseFloatingPnl),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: risk.aggregateHouseFloatingPnl >= Decimal.zero
                                ? const Color(0xFF00D68F)
                                : const Color(0xFFFF4757),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'SPREAD REVENUE EARNED',
                          style: TextStyle(fontSize: 11, color: Color(0xFF848E9C), fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          MoneyMath.formatCurrency(risk.feeRevenueEarned),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFFD600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFF2B384E), height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _dealerStat('Gross Exposure', '${risk.totalGrossExposureLots.toDouble().toStringAsFixed(2)} Lots'),
                    _dealerStat('Net Exposure', '${risk.totalNetExposureLots.toDouble().toStringAsFixed(2)} Lots'),
                    _dealerStat('Open Positions', '${risk.totalOpenPositions}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Instrument Risk & Dynamic Spread Control',
            style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),

          // Per-Symbol Exposure & Spread Markup Sliders
          ...risk.instrumentExposures.map((exp) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF151D28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1C2535)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        exp.symbol,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: exp.routing == ExecutionRouting.bBookInternal
                              ? const Color(0xFFFFD600).withOpacity(0.2)
                              : const Color(0xFF00D68F).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          exp.routing == ExecutionRouting.bBookInternal ? 'B-BOOK INTERNAL' : 'A-BOOK STP',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: exp.routing == ExecutionRouting.bBookInternal
                                ? const Color(0xFFFFD600)
                                : const Color(0xFF00D68F),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Net: ${exp.netExposureLots.toDouble().toStringAsFixed(2)} L',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Buy: ${exp.totalBuyLots.toDouble().toStringAsFixed(2)} Lots', style: const TextStyle(fontSize: 11, color: Color(0xFF00D68F))),
                      Text('Sell: ${exp.totalSellLots.toDouble().toStringAsFixed(2)} Lots', style: const TextStyle(fontSize: 11, color: Color(0xFFFF4757))),
                      Text('Client PnL: ${MoneyMath.formatPnL(exp.clientFloatingPnl)}', style: const TextStyle(fontSize: 11, color: Color(0xFF848E9C))),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Spread Markup Slider
                  Row(
                    children: [
                      Text(
                        'Spread Markup: ${exp.spreadMarkupPips} pips',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFFD600)),
                      ),
                      Expanded(
                        child: Slider(
                          value: exp.spreadMarkupPips.toDouble(),
                          min: 5,
                          max: 100,
                          divisions: 19,
                          activeColor: const Color(0xFFFFD600),
                          inactiveColor: const Color(0xFF2B384E),
                          onChanged: (val) {
                            ref.read(dealingDeskProvider.notifier).updateSpreadMarkup(exp.symbol, val.round());
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 2. COMPLIANCE & AML DESK ──────────────────────────────────────────────
  Widget _buildComplianceTab(ComplianceState state) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Pending KYC Identity Verification Queue',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 10),

        if (state.pendingApplications.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF151D28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                '✓ KYC Review Queue is clear. No pending applications.',
                style: TextStyle(color: Color(0xFF00D68F), fontWeight: FontWeight.bold),
              ),
            ),
          )
        else
          ...state.pendingApplications.map((app) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF151D28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFB300)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        app.fullName,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'UNDER REVIEW',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFFFB300)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Email: ${app.email} • Country: ${app.country}', style: const TextStyle(fontSize: 11, color: Color(0xFF848E9C))),
                  Text('Doc: ${app.documentType} (#${app.documentNumber})', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  const SizedBox(height: 12),

                  // 1-Click Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ref.read(kycComplianceProvider.notifier).approveKyc(app.id);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D68F),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text('APPROVE & UNLOCK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            ref.read(kycComplianceProvider.notifier).rejectKyc(app.id, 'Unreadable documents');
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF4757),
                            side: const BorderSide(color: Color(0xFFFF4757)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 20),
        const Text(
          'AML & Sanctions Audit Logs',
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 10),

        ...state.highRiskAmlAlerts.map((alert) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF151D28),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1C2535)),
            ),
            child: Row(
              children: [
                const Icon(Icons.security, color: Color(0xFFFFD600), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alert,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── 3. TREASURY & AUDIT VIEW ──────────────────────────────────────────────
  Widget _buildTreasuryTab(TreasuryAuditProof proof) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zero-Drift Certificate
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF151D28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: proof.isProofValid ? const Color(0xFF00D68F) : AppColors.loss,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  proof.isProofValid ? Icons.verified_rounded : Icons.cancel_rounded,
                  color: proof.isProofValid ? const Color(0xFF00D68F) : AppColors.loss,
                  size: 36,
                ),
                const SizedBox(height: 8),
                const Text(
                  'DOUBLE-ENTRY INVARIANT PROOF',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Σ Debits (${MoneyMath.formatCurrency(proof.totalSystemDebits)}) == Σ Credits (${MoneyMath.formatCurrency(proof.totalSystemCredits)})',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF848E9C)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Accounting Drift: \$${proof.accountingDrift.toDouble().toStringAsFixed(4)} (Zero Drift)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00D68F)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Assets vs Liabilities
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151D28),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Segregated Assets (1001)', style: TextStyle(fontSize: 11, color: Color(0xFF848E9C))),
                      const SizedBox(height: 4),
                      Text(
                        MoneyMath.formatCurrency(proof.segregatedClientAssets),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00D68F)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151D28),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Client Liabilities (2001/2002)', style: TextStyle(fontSize: 11, color: Color(0xFF848E9C))),
                      const SizedBox(height: 4),
                      Text(
                        MoneyMath.formatCurrency(proof.totalClientLiabilities),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFFFB300)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dealerStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF848E9C))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}

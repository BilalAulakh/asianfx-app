import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../blocs/blocs.dart';
import '../../core/math/money_math.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../domain/entities/ledger_entities.dart';

class DoubleEntryStatementScreen extends StatefulWidget {
  const DoubleEntryStatementScreen({super.key});

  @override
  State<DoubleEntryStatementScreen> createState() =>
      _DoubleEntryStatementScreenState();
}

class _DoubleEntryStatementScreenState
    extends State<DoubleEntryStatementScreen> {
  LedgerTxType? _filterType;

  @override
  Widget build(BuildContext context) {
    final ledgerState = context.watch<LedgerCubit>().state;
    final transactions = ledgerState.transactions;
    final proof = ledgerState.auditProof ??
        LedgerRepository.instance.generateTreasuryProof();

    final filtered = _filterType == null
        ? transactions
        : transactions.where((t) => t.type == _filterType).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D28),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Double-Entry Financial Journal',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Real-time Invariant Proof Header Badge ────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E2838), Color(0xFF101722)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: proof.isProofValid ? const Color(0xFF00D68F) : AppColors.loss,
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      proof.isProofValid ? Icons.check_circle_rounded : Icons.warning_rounded,
                      color: proof.isProofValid ? const Color(0xFF00D68F) : AppColors.loss,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      proof.isProofValid
                          ? 'MATHEMATICAL PROOF VALID: Σ DEBITS == Σ CREDITS'
                          : 'LEDGER IMBALANCE DETECTED',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: proof.isProofValid ? const Color(0xFF00D68F) : AppColors.loss,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _proofMetric('Total Debits', MoneyMath.formatCurrency(proof.totalSystemDebits)),
                    _proofMetric('Total Credits', MoneyMath.formatCurrency(proof.totalSystemCredits)),
                    _proofMetric('Accounting Drift', '\$${proof.accountingDrift.toDouble().toStringAsFixed(2)}', isZero: true),
                  ],
                ),
              ],
            ),
          ),

          // ── Filter Chips ────────────────────────────────────────────────
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _filterChip('All Transactions', null),
                _filterChip('Deposits', LedgerTxType.deposit),
                _filterChip('Withdrawals', LedgerTxType.withdrawal),
                _filterChip('Margin Locks', LedgerTxType.tradeMarginLock),
                _filterChip('Margin Releases', LedgerTxType.tradeMarginRelease),
                _filterChip('Trade PnL', LedgerTxType.tradePnl),
                _filterChip('Fees', LedgerTxType.fee),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Ledger Journal Entries List ───────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'No matching ledger journal entries.',
                      style: TextStyle(color: Color(0xFF848E9C)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: filtered.length,
                    itemBuilder: (context, idx) {
                      final tx = filtered[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151D28),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF1C2535)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Reference & Timestamp
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFD600).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tx.referenceNumber,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFFD600),
                                    ),
                                  ),
                                ),
                                Text(
                                  DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.timestamp),
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 10,
                                    color: Color(0xFF848E9C),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tx.description,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Divider(color: Color(0xFF1C2535), height: 1),
                            const SizedBox(height: 8),

                            // Double-Entry Line Items (Debit & Credit breakdown)
                            ...tx.entries.map((entry) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 45,
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: entry.isDebit
                                            ? const Color(0xFF00D68F).withOpacity(0.15)
                                            : const Color(0xFFFF4757).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        entry.isDebit ? 'DR' : 'CR',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: entry.isDebit
                                              ? const Color(0xFF00D68F)
                                              : const Color(0xFFFF4757),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${entry.accountCode} - ${entry.accountName}',
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 11,
                                          color: Colors.white70,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      MoneyMath.formatCurrency(
                                        entry.isDebit ? entry.debit : entry.credit,
                                      ),
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: entry.isDebit
                                            ? const Color(0xFF00D68F)
                                            : const Color(0xFFFF4757),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _proofMetric(String label, String value, {bool isZero = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF848E9C))),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isZero ? const Color(0xFF00D68F) : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, LedgerTxType? type) {
    final isSelected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _filterType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFD600) : const Color(0xFF151D28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFFFFD600) : const Color(0xFF1C2535),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.black : const Color(0xFF848E9C),
            ),
          ),
        ),
      ),
    );
  }
}

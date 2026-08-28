import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/math/money_math.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/user_entity.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ledger_provider.dart';
import '../../providers/trading_engine_provider.dart';
import 'double_entry_statement_screen.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(clientLedgerBalanceProvider);
    final engineState = ref.watch(tradingEngineProvider);
    final account = engineState.accountState;
    final authUser = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF151D28),
        elevation: 0,
        title: const Text(
          'Client Vault & Treasury',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFFD600)),
            tooltip: 'Double-Entry Statement',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DoubleEntryStatementScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Main Segregated Vault Card ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E2838), Color(0xFF101722)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF2B384E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D68F).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00D68F)),
                        ),
                        child: const Text(
                          'SEGREGATED ASSET VAULT',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00D68F),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.verified_user_rounded, color: Color(0xFF00D68F), size: 18),
                      const SizedBox(width: 4),
                      const Text(
                        'Tier-1 Protected',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFF00D68F)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PURE CASH LEDGER BALANCE',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF848E9C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    MoneyMath.formatCurrency(balance),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Vault Breakdown Row
                  Row(
                    children: [
                      _vaultBreakdownItem('Free Margin', MoneyMath.formatCurrency(account.freeMargin)),
                      _vaultBreakdownItem('Used Margin', MoneyMath.formatCurrency(account.usedMargin)),
                      _vaultBreakdownItem('Floating PnL', MoneyMath.formatPnL(account.unrealizedPnl)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Action Buttons (Deposit, Withdraw, Statement) ──────────────
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showDepositModal(context),
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    label: const Text('DEPOSIT'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D68F),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showWithdrawModal(context, authUser),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: const Text('WITHDRAW'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF2B384E)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Double-Entry Ledger Proof Card ─────────────────────────────
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DoubleEntryStatementScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF151D28),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1C2535)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD600).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_rounded, color: Color(0xFFFFD600)),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Double-Entry Financial Statement',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Strict ledger audit • Σ Debits == Σ Credits (0.00 Drift)',
                            style: TextStyle(fontSize: 11, color: Color(0xFF848E9C)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFF848E9C)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Supported Payment Gateways Simulation ───────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF151D28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1C2535)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Institutional Gateway Channels',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _gatewayItem('USDT Tether (TRC-20)', 'Instant 0% Network Fee', Icons.currency_bitcoin),
                  const Divider(color: Color(0xFF1C2535), height: 16),
                  _gatewayItem('USDT Tether (ERC-20)', 'Tier-1 Segregated Wallet', Icons.shield),
                  const Divider(color: Color(0xFF1C2535), height: 16),
                  _gatewayItem('Institutional Bank Wire', 'SWIFT Fedwire Clearance', Icons.account_balance),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vaultBreakdownItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF848E9C))),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _gatewayItem(String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFD600), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13)),
              Text(subtitle, style: const TextStyle(color: Color(0xFF848E9C), fontSize: 11)),
            ],
          ),
        ),
        const Text('ONLINE', style: TextStyle(color: Color(0xFF00D68F), fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showDepositModal(BuildContext context) {
    final amountController = TextEditingController(text: '5000');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151D28),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Institutional Deposit Gateway',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F141C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2B384E)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('USDT (TRC-20) Vault Deposit Address:', style: TextStyle(fontSize: 11, color: Color(0xFF848E9C))),
                  SizedBox(height: 4),
                  Text('TY8vQxWz4JbX8sLpQ2vNw1p9ZmLq5R7k8A', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.bold, color: Color(0xFFFFD600), fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              decoration: const InputDecoration(
                labelText: 'Deposit Amount (USD)',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amountController.text) ?? 0.0;
                if (amt <= 0) return;

                ref.read(ledgerProvider.notifier).deposit(
                      userId: 'usr_institutional_01',
                      amount: MoneyMath.toDec(amt),
                      method: 'USDT (TRC-20 Institutional Settlement)',
                    );

                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF00D68F),
                    content: Text('✓ Deposited \$${amt.toStringAsFixed(2)} to Segregated Ledger!'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D68F),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('CONFIRM DEPOSIT SETTLEMENT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showWithdrawModal(BuildContext context, UserEntity? user) {
    if (user != null && !user.canWithdraw) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.loss,
          content: Text('KYC Approval Required before initiating withdrawals.'),
        ),
      );
      return;
    }

    final amountController = TextEditingController(text: '1000');
    final addressController = TextEditingController(text: 'TY9xKpLm82ZvWq31RbPz');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF151D28),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Institutional Withdrawal Disbursement',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              decoration: const InputDecoration(
                labelText: 'Withdrawal Amount (USD)',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Destination Wallet Address (USDT TRC-20)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(amountController.text) ?? 0.0;
                final amtDec = MoneyMath.toDec(amt);
                final engineState = ref.read(tradingEngineProvider);

                if (amtDec > engineState.accountState.freeMargin) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.loss,
                      content: Text('Insufficient Free Margin! Available: ${MoneyMath.formatCurrency(engineState.accountState.freeMargin)}'),
                    ),
                  );
                  return;
                }

                ref.read(ledgerProvider.notifier).withdraw(
                      userId: 'usr_institutional_01',
                      amount: amtDec,
                      destinationAddress: addressController.text,
                    );

                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF00D68F),
                    content: Text('✓ Withdrawal \$${amt.toStringAsFixed(2)} processed and ledger debited.'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4757),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('CONFIRM WITHDRAWAL DISBURSEMENT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

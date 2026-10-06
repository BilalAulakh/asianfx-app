import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_Notif> _notifications = [
    _Notif(type: 'trade', title: 'Trade Executed', body: 'Your BUY order for EURUSD (0.10 lots) was executed at 1.08532.', time: DateTime.now().subtract(const Duration(minutes: 5)), isRead: false),
    _Notif(type: 'profit', title: 'Take Profit Hit', body: 'Your XAUUSD position closed at \$2,380 — Profit: +\$225.00', time: DateTime.now().subtract(const Duration(hours: 1)), isRead: false),
    _Notif(type: 'deposit', title: 'Deposit Confirmed', body: 'Your deposit of \$5,000.00 via Bank Transfer has been credited.', time: DateTime.now().subtract(const Duration(hours: 3)), isRead: true),
    _Notif(type: 'security', title: 'New Login Detected', body: 'A new login was detected from Windows · Chrome · Karachi, PK', time: DateTime.now().subtract(const Duration(hours: 6)), isRead: true),
    _Notif(type: 'kyc', title: 'KYC Approved', body: 'Your identity verification has been approved. Full access unlocked.', time: DateTime.now().subtract(const Duration(days: 1)), isRead: true),
    _Notif(type: 'market', title: 'Gold Alert', body: 'XAUUSD surged 1.2% — now at \$2,341. Consider your positions.', time: DateTime.now().subtract(const Duration(days: 1, hours: 3)), isRead: true),
    _Notif(type: 'withdraw', title: 'Withdrawal Processing', body: 'Your withdrawal of \$250.00 is being processed (1-3 business days).', time: DateTime.now().subtract(const Duration(days: 2)), isRead: true),
  ];

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => !n.isRead).length;
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        title: Row(
          children: [
            const Text('Notifications', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.brandPrimary, borderRadius: BorderRadius.circular(8)),
                child: Text('$unread', style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black)),
              ),
            ],
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() { for (var n in _notifications) {
              n.isRead = true;
            } }),
            child: const Text('Mark all read', style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.brandPrimary)),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _notifications.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final n = _notifications[i];
          final color = _typeColor(n.type);
          return GestureDetector(
            onTap: () => setState(() => n.isRead = true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: n.isRead ? AppColors.darkCard : color.withAlpha(8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: n.isRead ? AppColors.darkBorder : color.withAlpha(50)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_typeIcon(n.type), size: 20, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(n.title, style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700, color: AppColors.textPrimary)),
                            ),
                            if (!n.isRead)
                              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.brandPrimary, shape: BoxShape.circle)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(n.body, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
                        const SizedBox(height: 6),
                        Text(AppFormatters.timeAgo(n.time), style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'trade': return AppColors.brandPrimary;
      case 'profit': return AppColors.profit;
      case 'deposit': return AppColors.info;
      case 'security': return AppColors.warning;
      case 'kyc': return AppColors.profit;
      case 'market': return AppColors.brandSecondary;
      default: return AppColors.textSecondary;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'trade': return Icons.swap_horiz_rounded;
      case 'profit': return Icons.trending_up_rounded;
      case 'deposit': return Icons.arrow_downward_rounded;
      case 'security': return Icons.security_rounded;
      case 'kyc': return Icons.verified_rounded;
      case 'market': return Icons.bar_chart_rounded;
      default: return Icons.notifications_rounded;
    }
  }
}

class _Notif {
  final String type;
  final String title;
  final String body;
  final DateTime time;
  bool isRead;
  _Notif({required this.type, required this.title, required this.body, required this.time, required this.isRead});
}

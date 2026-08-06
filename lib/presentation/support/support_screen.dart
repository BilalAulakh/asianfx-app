import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _msgController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {'text': 'Hello! How can I help you today?', 'isAgent': true, 'time': '10:00'},
    {'text': 'Hi, I need help with my deposit not reflecting.', 'isAgent': false, 'time': '10:01'},
    {'text': 'Could you please provide your transaction ID so I can investigate?', 'isAgent': true, 'time': '10:02'},
  ];

  final List<Map<String, String>> _faqs = [
    {'q': 'How do I deposit funds?', 'a': 'Go to Wallet, tap Deposit, select a payment method, enter the amount, and follow the on-screen steps.'},
    {'q': 'How long do withdrawals take?', 'a': 'Bank transfers take 1-3 business days. Crypto withdrawals process within 1 hour. Easypaisa/JazzCash are instant.'},
    {'q': 'What is leverage?', 'a': 'Leverage lets you control a larger position with a smaller deposit. 1:100 means \$100 controls \$10,000 of assets.'},
    {'q': 'How do I verify my account (KYC)?', 'a': 'Go to Profile > KYC Verification and upload your government-issued ID plus a selfie. Approval takes up to 24 hours.'},
    {'q': 'What are the trading hours?', 'a': 'Forex is open 24/5 (Mon-Fri). Crypto is 24/7. Stocks and indices follow local exchange hours.'},
    {'q': 'How is profit calculated?', 'a': 'Profit = (Close Price - Open Price) x Lot Size x Contract Size. For Sell orders the formula is reversed.'},
  ];

  int? _expandedFaq;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _msgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        title: const Text('Support', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary), onPressed: () => Navigator.pop(context)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.darkBorder)),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(color: AppColors.brandPrimary, borderRadius: BorderRadius.circular(10)),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(3),
              labelColor: Colors.black,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
              dividerColor: Colors.transparent,
              tabs: const [Tab(text: 'Live Chat'), Tab(text: 'Tickets'), Tab(text: 'FAQ')],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildLiveChat(), _buildTickets(), _buildFaq()],
      ),
    );
  }

  Widget _buildLiveChat() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.darkBorder)),
          child: Row(
            children: [
              Stack(
                children: [
                  const CircleAvatar(radius: 20, backgroundColor: AppColors.brandPrimary, child: Text('FX', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, color: Colors.black, fontSize: 12))),
                  Positioned(bottom: 0, right: 0, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.profit, shape: BoxShape.circle, border: Border.all(color: AppColors.darkCard, width: 1.5)))),
                ],
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FXAsianApp Support', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Row(children: [
                    Icon(Icons.circle, size: 8, color: AppColors.profit),
                    SizedBox(width: 4),
                    Text('Online · Avg. reply 2 min', style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
                  ]),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final m = _messages[i];
              final isAgent = m['isAgent'] as bool;
              return Align(
                alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: isAgent ? AppColors.darkCard : AppColors.brandPrimary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                      bottomLeft: isAgent ? Radius.zero : const Radius.circular(16),
                      bottomRight: isAgent ? const Radius.circular(16) : Radius.zero,
                    ),
                    border: isAgent ? Border.all(color: AppColors.darkBorder) : null,
                  ),
                  child: Text(m['text'] as String, style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: isAgent ? AppColors.textPrimary : Colors.black, height: 1.5)),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          decoration: const BoxDecoration(color: AppColors.darkSurface, border: Border(top: BorderSide(color: AppColors.darkBorder, width: 0.5))),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgController,
                  style: const TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Type your message...', hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.textMuted),
                    filled: true, fillColor: AppColors.darkCard,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.darkBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.darkBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.brandPrimary)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  if (_msgController.text.isNotEmpty) {
                    setState(() { _messages.add({'text': _msgController.text, 'isAgent': false, 'time': ''}); _msgController.clear(); });
                  }
                },
                child: Container(width: 44, height: 44, decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.send_rounded, color: Colors.black, size: 20)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTickets() {
    final tickets = [
      {'id': '#TK-1024', 'subject': 'Deposit not credited', 'status': 'Open', 'date': '3h ago'},
      {'id': '#TK-1021', 'subject': 'Leverage change request', 'status': 'Resolved', 'date': '2d ago'},
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded, color: Colors.black),
            label: const Text('New Ticket', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: Colors.black)),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandPrimary, minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tickets.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = tickets[i];
              final isOpen = t['status'] == 'Open';
              final color = isOpen ? AppColors.info : AppColors.profit;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.darkBorder)),
                child: Row(
                  children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(10)), child: Icon(isOpen ? Icons.confirmation_num_outlined : Icons.check_circle_outline_rounded, color: color, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t['subject']!, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      Text('${t['id']} · ${t['date']}', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.textSecondary)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                      child: Text(t['status']!, style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFaq() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _faqs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final faq = _faqs[i];
        final isExpanded = _expandedFaq == i;
        return GestureDetector(
          onTap: () => setState(() => _expandedFaq = isExpanded ? null : i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isExpanded ? AppColors.brandPrimary.withAlpha(8) : AppColors.darkCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isExpanded ? AppColors.brandPrimary.withAlpha(60) : AppColors.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(faq['q']!, style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: isExpanded ? FontWeight.w700 : FontWeight.w600, color: isExpanded ? AppColors.brandPrimary : AppColors.textPrimary))),
                    Icon(isExpanded ? Icons.remove_rounded : Icons.add_rounded, color: isExpanded ? AppColors.brandPrimary : AppColors.textMuted, size: 20),
                  ],
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.darkDivider, height: 1),
                  const SizedBox(height: 12),
                  Text(faq['a']!, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _selectedSignalTab = 0; // 0: Favorites, 1: All

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F141C),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────────────
              const Text(
                'Insights',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 16),

              // ── Top Movers ──────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOP MOVERS',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF848E9C),
                      letterSpacing: 0.8,
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Show more', style: TextStyle(color: Color(0xFFFFD600), fontSize: 12)),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              SizedBox(
                height: 80,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _moverCard('XNI/USD', '16754.12', '+2.19%', true),
                    _moverCard('UKOIL', '79.108', '+0.66%', true),
                    _moverCard('USOIL', '74.564', '+0.62%', true),
                    _moverCard('EUR/USD', '1.15430', '-0.12%', false),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Trading Signals ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TRADING SIGNALS',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF848E9C),
                      letterSpacing: 0.8,
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _selectedSignalTab = 0),
                        child: Text(
                          'Favorites',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _selectedSignalTab == 0 ? Colors.white : const Color(0xFF848E9C),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      GestureDetector(
                        onTap: () => setState(() => _selectedSignalTab = 1),
                        child: Text(
                          'All',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _selectedSignalTab == 1 ? Colors.white : const Color(0xFF848E9C),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _signalCard(
                symbol: 'GBP/DKK 30 Min',
                title: 'GBP/DKK: Watch 8.7367',
                desc: 'Research © 2026 Trading Central. MA-20 + MA-50 support level.',
                time: '1:35 PM',
                isBull: true,
              ),

              _signalCard(
                symbol: 'USD/HKD 30 Min',
                title: 'USD/HKD: First target 7.75',
                desc: 'Intraday continuation or reverse breakout level.',
                time: '1:35 PM',
                isBull: true,
              ),

              _signalCard(
                symbol: 'BTC Intraday',
                title: 'BTC: Watch 65,634',
                desc: 'The upside prevails as long as 64,068 is support, with 65,634 and 66,052 as targets.',
                time: '1:48 PM',
                isBull: true,
              ),

              _signalCard(
                symbol: 'ETH Intraday',
                title: 'ETH: Expect 1,945',
                desc: 'As long as 1,887 is support, look for 1,960 target.',
                time: '1:48 PM',
                isBull: true,
              ),

              const SizedBox(height: 24),

              // ── Upcoming Events (Economic Calendar) ─────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'UPCOMING EVENTS',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF848E9C),
                      letterSpacing: 0.8,
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Show more', style: TextStyle(color: Color(0xFFFFD600), fontSize: 12)),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              _eventTile('Inflation Rate YoY', 'CY Flag', '2:00 PM – 6 minutes ago'),
              _eventTile('Retail Sales MoM', 'EMU Flag', '2:00 PM – 6 minutes ago'),

              const SizedBox(height: 24),

              // ── Top News ────────────────────────────────────────────────────
              const Text(
                'TOP NEWS',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF848E9C),
                  letterSpacing: 0.8,
                ),
              ),

              const SizedBox(height: 12),

              _newsTile('Equities: Nvidia stands out as broader tech mood cools', 'Deutsche Bank • 23 mins ago'),
              _newsTile('Euro holds two-day gains against Yen, investors seek clarity', '0.29% 29 mins ago'),
              _newsTile('Australian Dollar: RBA uneasy pause', 'Standard Chartered'),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moverCard(String symbol, String price, String change, bool isUp) {
    final color = isUp ? const Color(0xFF0ECB81) : const Color(0xFFF6465D);
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E232A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B313A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(price, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text(change, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _signalCard({
    required String symbol,
    required String title,
    required String desc,
    required String time,
    required bool isBull,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E232A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B313A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(symbol, style: const TextStyle(color: Color(0xFF848E9C), fontSize: 11, fontWeight: FontWeight.w600)),
              Text(time, style: const TextStyle(color: Color(0xFF848E9C), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _eventTile(String title, String flag, String time) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E232A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 20,
            decoration: BoxDecoration(color: const Color(0xFF2B313A), borderRadius: BorderRadius.circular(3)),
            child: const Center(child: Text('🚩', style: TextStyle(fontSize: 10))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(time, style: const TextStyle(color: Color(0xFF848E9C), fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _newsTile(String title, String source) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E232A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          Text(source, style: const TextStyle(color: Color(0xFF848E9C), fontSize: 11)),
        ],
      ),
    );
  }
}

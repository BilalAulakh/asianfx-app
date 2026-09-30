import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../blocs/blocs.dart';

class TradingScreen extends StatefulWidget {
  const TradingScreen({super.key});

  @override
  State<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends State<TradingScreen> {
  int _selectedCategoryIndex = 0;
  final List<String> _categories = [
    'Favorites',
    'Most traded',
    'Top Movers',
    'Forex',
    'Crypto',
    'Indices',
  ];

  @override
  Widget build(BuildContext context) {
    final instruments = context.watch<MarketBloc>().state.instruments;
    final wallet = context.watch<WalletBloc>().state;

    // Filter instruments based on selected category
    final filtered = instruments.where((inst) {
      if (_selectedCategoryIndex == 0) return true; // Favorites
      if (_selectedCategoryIndex == 1) return inst.category == 'crypto' || inst.category == 'forex'; // Most traded
      if (_selectedCategoryIndex == 2) return inst.changePercent.abs() > 0.1; // Top Movers
      if (_selectedCategoryIndex == 3) return inst.category == 'forex'; // Forex
      if (_selectedCategoryIndex == 4) return inst.category == 'crypto'; // Crypto
      if (_selectedCategoryIndex == 5) return inst.category == 'indices'; // Indices
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F141C),
      body: SafeArea(
        child: Column(
          children: [
            // ── App Bar Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Trade',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    children: [
                      // Balance Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E232A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF2B313A)),
                        ),
                        child: Text(
                          '${wallet.balance.toStringAsFixed(2)} USD',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.schedule_rounded, color: Colors.white70, size: 22),
                    ],
                  ),
                ],
              ),
            ),

            // ── Category Horizontal Scroll Tabs ──────────────────────────────
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, idx) {
                  final isSelected = _selectedCategoryIndex == idx;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedCategoryIndex = idx),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : const Color(0xFF1E232A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _categories[idx],
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? Colors.black : const Color(0xFF848E9C),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // ── Instruments List ──────────────────────────────────────────────
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E232A), height: 1),
                itemBuilder: (context, idx) {
                  final inst = filtered[idx];
                  final isUp = inst.changePercent >= 0;

                  return InkWell(
                    onTap: () => context.push('/app/markets/chart/${inst.symbol}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          // Instrument Icon
                          _buildInstrumentIcon(inst.symbol),
                          const SizedBox(width: 12),

                          // Symbol & Name
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inst.symbol,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  inst.name,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    color: Color(0xFF848E9C),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Mini Sparkline Graphic
                          SizedBox(
                            width: 60,
                            height: 24,
                            child: CustomPaint(
                              painter: _MiniSparklinePainter(isUp: isUp),
                            ),
                          ),

                          const SizedBox(width: 14),

                          // Price & Change %
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                inst.bid.toStringAsFixed(inst.decimals),
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                    size: 11,
                                    color: isUp ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                                  ),
                                  Text(
                                    '${inst.changePercent.abs().toStringAsFixed(2)}%',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isUp ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstrumentIcon(String symbol) {
    Color bg = const Color(0xFF262D36);
    IconData iconData = Icons.currency_exchange_rounded;

    if (symbol.contains('BTC')) {
      bg = const Color(0xFFF7931A).withOpacity(0.2);
      return CircleAvatar(backgroundColor: bg, radius: 20, child: const Text('₿', style: TextStyle(color: Color(0xFFF7931A), fontWeight: FontWeight.bold, fontSize: 18)));
    } else if (symbol.contains('XAU')) {
      bg = const Color(0xFFFFD700).withOpacity(0.2);
      return CircleAvatar(backgroundColor: bg, radius: 20, child: const Icon(Icons.monetization_on_rounded, color: Color(0xFFFFD700), size: 20));
    } else if (symbol.contains('ETH')) {
      bg = const Color(0xFF627EEA).withOpacity(0.2);
      return CircleAvatar(backgroundColor: bg, radius: 20, child: const Text('Ξ', style: TextStyle(color: Color(0xFF627EEA), fontWeight: FontWeight.bold, fontSize: 18)));
    }

    return CircleAvatar(
      backgroundColor: bg,
      radius: 20,
      child: Icon(iconData, color: Colors.white70, size: 18),
    );
  }
}

class _MiniSparklinePainter extends CustomPainter {
  final bool isUp;
  _MiniSparklinePainter({required this.isUp});

  @override
  void paint(Canvas canvas, Size size) {
    final color = isUp ? const Color(0xFF0ECB81) : const Color(0xFFF6465D);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (isUp) {
      path.moveTo(0, size.height * 0.8);
      path.lineTo(size.width * 0.3, size.height * 0.6);
      path.lineTo(size.width * 0.6, size.height * 0.7);
      path.lineTo(size.width, size.height * 0.2);
    } else {
      path.moveTo(0, size.height * 0.2);
      path.lineTo(size.width * 0.3, size.height * 0.4);
      path.lineTo(size.width * 0.6, size.height * 0.3);
      path.lineTo(size.width, size.height * 0.8);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MiniSparklinePainter oldDelegate) => false;
}

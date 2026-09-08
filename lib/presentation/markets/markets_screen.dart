import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../domain/entities/trading_entities.dart';
import '../../providers/market_provider.dart';
import '../../providers/theme_provider.dart';

class MarketsScreen extends ConsumerStatefulWidget {
  const MarketsScreen({super.key});

  @override
  ConsumerState<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends ConsumerState<MarketsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  String _searchQuery = '';

  final List<String> _categories = const [
    'All',
    'Forex',
    'Crypto',
    'Metals',
    'Commodities',
    'Indices',
    'Stocks',
  ];

  bool get _isDark => ref.watch(themeProvider);
  Color get _bg => _isDark ? const Color(0xFF0A0E17) : const Color(0xFFF1F5F9);
  Color get _appBarBg => _isDark ? const Color(0xFF151D28) : Colors.white;
  Color get _cardBg => _isDark ? const Color(0xFF151D28) : Colors.white;
  Color get _borderColor => _isDark ? const Color(0xFF1C2535) : const Color(0xFFE2E8F0);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _textSecondary => _isDark ? const Color(0xFF848E9C) : const Color(0xFF64748B);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instruments = ref.watch(instrumentsProvider);
    final isDark = _isDark;

    // Filter by category and search query
    final filteredInstruments = instruments.where((inst) {
      if (_selectedCategory != 'All' &&
          inst.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchSymbol = inst.symbol.toLowerCase().contains(query);
        final matchName = inst.name.toLowerCase().contains(query);
        if (!matchSymbol && !matchName) return false;
      }
      return true;
    }).toList();

    // Highlights
    InstrumentEntity? topGainer;
    for (final inst in instruments) {
      if (topGainer == null || inst.change24h > topGainer.change24h) {
        topGainer = inst;
      }
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _appBarBg,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFFFD600).withValues(alpha: 0.5),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.trending_up_rounded, color: Color(0xFFFFD600), size: 16),
                  SizedBox(width: 5),
                  Text(
                    'MARKETS',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFFD600),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Market Watch',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            // Live Pulse Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00D68F),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${instruments.length} LIVE',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF00D68F),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle Theme',
            icon: Icon(
              isDark ? Icons.wb_sunny_outlined : Icons.nightlight_round,
              color: isDark ? const Color(0xFFFFD600) : const Color(0xFF475569),
            ),
            onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Highlights Banner Bar ──────────────────────────────────────────
          if (topGainer != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D68F).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star_rounded, color: Color(0xFF00D68F), size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOP 24H GAINER',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF848E9C),
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '${topGainer.symbol} (${topGainer.name})',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+${topGainer.change24h.toStringAsFixed(2)}%',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF00D68F),
                        ),
                      ),
                      Text(
                        topGainer.bid.toStringAsFixed(topGainer.decimals),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // ── Search & Filter Row ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: _textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search markets (e.g. BTC, Gold, EUR)...',
                  hintStyle: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: _textSecondary,
                  ),
                  prefixIcon: Icon(Icons.search_rounded, size: 18, color: _textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, size: 16, color: _textSecondary),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // ── Category Chips ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final cat = _categories[idx];
                  final isSelected = _selectedCategory == cat;

                  final count = cat == 'All'
                      ? instruments.length
                      : instruments.where((i) => i.category.toLowerCase() == cat.toLowerCase()).length;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFD600)
                            : (isDark ? const Color(0xFF1E2838) : Colors.white),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFFD600) : _borderColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cat,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                              color: isSelected
                                  ? Colors.black
                                  : (isDark ? Colors.white : const Color(0xFF334155)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.black.withValues(alpha: 0.15)
                                  : (isDark ? const Color(0xFF2A3649) : const Color(0xFFE2E8F0)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.black
                                    : (isDark ? const Color(0xFF848E9C) : const Color(0xFF64748B)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Market List Table Header ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'MARKET / PAIR',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '24H HIGH / LOW',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'BID / 24H',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Instruments List ─────────────────────────────────────────────
          Expanded(
            child: filteredInstruments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: _textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          'No markets matching "$_searchQuery"',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Try searching for Gold, BTC, ETH, or EUR',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: _textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _selectedCategory = 'All';
                            });
                          },
                          child: const Text('Show All Markets'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: filteredInstruments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final instrument = filteredInstruments[idx];
                      return _MarketCard(
                        instrument: instrument,
                        isDark: isDark,
                        cardBg: _cardBg,
                        borderColor: _borderColor,
                        textPrimary: _textPrimary,
                        textSecondary: _textSecondary,
                        onTap: () {
                          // Select symbol and jump to trading terminal
                          ref.read(activeSymbolProvider.notifier).state = instrument.symbol;
                          context.go(AppRoutes.terminal);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MarketCard extends ConsumerWidget {
  final InstrumentEntity instrument;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  const _MarketCard({
    required this.instrument,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });

  Color _getCategoryColor(String cat) {
    switch (cat.toLowerCase()) {
      case 'metals':
        return const Color(0xFFFFD600); // Gold
      case 'crypto':
        return const Color(0xFFFF9F1C); // Orange
      case 'forex':
        return const Color(0xFF2EC4B6); // Teal
      case 'commodities':
        return const Color(0xFFE76F51); // Coral
      case 'indices':
        return const Color(0xFF3A86FF); // Blue
      case 'stocks':
        return const Color(0xFF8338EC); // Purple
      default:
        return const Color(0xFF3A86FF);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch real-time live price stream for this symbol
    final priceAsync = ref.watch(priceStreamProvider(instrument.symbol));
    final live = priceAsync.when(
      data: (d) => d,
      loading: () => instrument,
      error: (_, _) => instrument,
    );

    final isPositive = live.isPositiveChange;
    final catColor = _getCategoryColor(instrument.category);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            // Left: Symbol badge & Name
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: catColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        instrument.symbol.split('/').first,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: catColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              instrument.symbol,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          instrument.name,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Center: 24h High / Low & Spread
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'H: ${live.high24h.toStringAsFixed(live.decimals)}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'L: ${live.low24h.toStringAsFixed(live.decimals)}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E2838)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Sp: ${live.spreadMarkupPips}p',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 9,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right: Live Bid Price & 24h Change Pill
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    live.bid.toStringAsFixed(live.decimals),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPositive
                          ? const Color(0xFF00D68F).withValues(alpha: 0.15)
                          : const Color(0xFFFF4757).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isPositive
                            ? const Color(0xFF00D68F).withValues(alpha: 0.3)
                            : const Color(0xFFFF4757).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPositive ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                          color: isPositive ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                          size: 14,
                        ),
                        Text(
                          '${isPositive ? '+' : ''}${live.change24h.toStringAsFixed(2)}%',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isPositive ? const Color(0xFF00D68F) : const Color(0xFFFF4757),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

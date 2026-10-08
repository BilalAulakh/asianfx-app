import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../blocs/blocs.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/trading_entities.dart';
import '../common/widgets/balance_pill.dart';
import '../common/widgets/symbol_badge.dart';

/// Exness-style "Trade" list: balance pill, title, tabs (Favorites / All /
/// asset classes), search, and one card per instrument. Tapping a card opens
/// its chart.
class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _tab; // null = default (Favorites when there are any)
  String _searchQuery = '';
  bool _searching = false;

  static const _favorites = 'Favorites';
  static const _all = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _title(String category) =>
      category.isEmpty ? category : category[0].toUpperCase() + category.substring(1);

  @override
  Widget build(BuildContext context) {
    final instruments = context.watch<MarketBloc>().state.instruments;
    final isDark = context.isDarkMode;
    final textPrimary = context.textPrimaryColor;
    final textSecondary = context.textSecondaryColor;

    final hasFavorites = instruments.any((i) => i.isFavorite);
    final tabs = [
      if (hasFavorites) _favorites,
      _all,
      ...{for (final i in instruments) _title(i.category)},
    ];
    final tab = (_tab != null && tabs.contains(_tab)) ? _tab! : tabs.first;

    final query = _searchQuery.toLowerCase();
    final shown = instruments.where((inst) {
      if (query.isNotEmpty) {
        return inst.symbol.toLowerCase().contains(query) || inst.name.toLowerCase().contains(query);
      }
      if (tab == _favorites) return inst.isFavorite;
      if (tab == _all) return true;
      return _title(inst.category) == tab;
    }).toList();

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Center(child: BalancePill()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Text(
                    'Trade',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Toggle theme',
                    icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: textPrimary),
                    onPressed: () => context.read<ThemeCubit>().toggleTheme(),
                  ),
                ],
              ),
            ),

            // ── Tabs + search (Exness) ───────────────────────────────────────
            SizedBox(
              height: 44,
              child: _searching
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              onChanged: (v) => setState(() => _searchQuery = v.trim()),
                              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textPrimary),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'Search instruments',
                                prefixIcon: Icon(Icons.search_rounded, size: 20, color: textSecondary),
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: context.cardBg,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _searching = false;
                              _searchQuery = '';
                              _searchController.clear();
                            }),
                            child: Text('Cancel', style: TextStyle(color: textPrimary)),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            children: [
                              for (final t in tabs)
                                _TabLabel(
                                  label: t,
                                  selected: t == tab,
                                  onTap: () => setState(() => _tab = t),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Search',
                          icon: Icon(Icons.search_rounded, color: textPrimary),
                          onPressed: () => setState(() => _searching = true),
                        ),
                      ],
                    ),
            ),
            Divider(height: 1, color: context.borderColor),

            // ── Instruments ─────────────────────────────────────────────────
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        query.isNotEmpty ? 'No instruments match "$_searchQuery"' : 'No instruments here yet',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _InstrumentCard(
                        symbol: shown[i].symbol,
                        onTap: () {
                          context.read<MarketBloc>().add(MarketSelectSymbolEvent(shown[i].symbol));
                          context.go(AppRoutes.terminal);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabLabel({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.textPrimaryColor : context.textSecondaryColor;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
            const SizedBox(height: 9),
            Container(
              height: 2,
              width: 24,
              decoration: BoxDecoration(
                color: selected ? context.textPrimaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exness instrument card: badge, symbol + name, live bid and 24h change.
class _InstrumentCard extends StatelessWidget {
  final String symbol;
  final VoidCallback onTap;

  const _InstrumentCard({required this.symbol, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final InstrumentEntity live = context.select((MarketBloc b) => b.state.getInstrument(symbol));
    final up = live.isPositiveChange;
    final changeColor = up ? AppColors.profit : AppColors.loss;

    return Material(
      color: context.cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              SymbolBadge(symbol: live.symbol, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      live.symbol,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      live.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: context.textSecondaryColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    live.bid.toStringAsFixed(live.displayDecimals),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimaryColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 12,
                        color: changeColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${live.change24h.abs().toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: changeColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

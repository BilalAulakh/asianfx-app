import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../providers/market_provider.dart';
import '../../domain/entities/trading_entities.dart';

class MarketsScreen extends ConsumerStatefulWidget {
  const MarketsScreen({super.key});

  @override
  ConsumerState<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends ConsumerState<MarketsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  final List<String> _categories = [
    'All', 'Forex', 'Crypto', 'Gold', 'Stocks', 'Indices', 'Commodities',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instruments = ref.watch(instrumentsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Markets',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Search Bar
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        hintText: AppStrings.searchMarkets,
                        hintStyle: TextStyle(
                          fontFamily: 'Inter',
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── Category Tabs ─────────────────────────────────────────────────
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final isSelected = _tabController.index == i;
                  return GestureDetector(
                    onTap: () => setState(() => _tabController.index = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.brandPrimary
                            : AppColors.darkCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.brandPrimary
                              : AppColors.darkBorder,
                        ),
                      ),
                      child: Text(
                        _categories[i],
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.black : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Instruments List ─────────────────────────────────────────────
            Expanded(
              child: Builder(builder: (context) {
                List<InstrumentEntity> filtered = instruments;

                // Category filter
                if (_tabController.index > 0) {
                  final cat = _categories[_tabController.index].toLowerCase();
                  filtered = filtered.where((i) => i.category == cat).toList();
                }

                // Search filter
                if (_searchQuery.isNotEmpty) {
                  filtered = filtered.where((i) =>
                    i.symbol.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                    i.name.toLowerCase().contains(_searchQuery.toLowerCase())
                  ).toList();
                }

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      'No instruments found',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Inter',
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.darkDivider),
                  itemBuilder: (context, i) =>
                      _InstrumentRow(instrument: filtered[i]),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstrumentRow extends ConsumerWidget {
  final InstrumentEntity instrument;
  const _InstrumentRow({required this.instrument});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final priceAsync = ref.watch(priceStreamProvider(instrument.symbol));
    final live = priceAsync.when(
      data: (d) => d,
      loading: () => instrument,
      error: (_, __) => instrument,
    );

    final isPositive = live.isPositiveChange;

    return InkWell(
      onTap: () => context.push('/app/markets/chart/${instrument.symbol}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            // Symbol Badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isPositive
                      ? [
                          AppColors.profit.withAlpha(30),
                          AppColors.profit.withAlpha(15)
                        ]
                      : [
                          AppColors.loss.withAlpha(30),
                          AppColors.loss.withAlpha(15)
                        ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  instrument.symbol.length >= 3
                      ? instrument.symbol.substring(0, 3)
                      : instrument.symbol,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isPositive ? AppColors.profit : AppColors.loss,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instrument.symbol,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    instrument.name,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Price + Change
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  live.bid.toStringAsFixed(instrument.decimals),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPositive
                        ? AppColors.profit.withAlpha(20)
                        : AppColors.loss.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${isPositive ? '+' : ''}${live.change24h.toStringAsFixed(2)}%',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isPositive ? AppColors.profit : AppColors.loss,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 8),

            // Chevron
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

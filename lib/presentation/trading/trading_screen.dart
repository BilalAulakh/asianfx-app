import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/formatters.dart';
import '../../providers/market_provider.dart';
import '../../providers/auth_provider.dart';
import '../../domain/entities/trading_entities.dart';
import '../common/widgets/fx_button.dart';

class TradingScreen extends ConsumerStatefulWidget {
  const TradingScreen({super.key});

  @override
  ConsumerState<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends ConsumerState<TradingScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  OrderSide _side = OrderSide.buy;
  OrderType _orderType = OrderType.market;
  double _lotSize = 0.01;
  double _stopLoss = 0.0;
  double _takeProfit = 0.0;
  double _leverage = 100;
  String _selectedSymbol = 'EURUSD';
  bool _isPlacingOrder = false;

  final List<double> _leverageOptions = [10, 25, 50, 100, 200, 500];

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

  double get _marginRequired {
    final instruments = ref.read(instrumentsProvider);
    final inst = instruments.firstWhere(
      (i) => i.symbol == _selectedSymbol,
      orElse: () => instruments.first,
    );
    return (inst.bid * _lotSize * 100000) / _leverage;
  }

  @override
  Widget build(BuildContext context) {
    final instruments = ref.watch(instrumentsProvider);
    final openTrades = ref.watch(openTradesProvider);
    final wallet = ref.watch(walletProvider);

    final inst = instruments.firstWhere(
      (i) => i.symbol == _selectedSymbol,
      orElse: () => instruments.first,
    );
    final priceAsync = ref.watch(priceStreamProvider(_selectedSymbol));
    final live = priceAsync.when(
      data: (d) => d,
      loading: () => inst,
      error: (_, __) => inst,
    );

    final openOnly = openTrades.where((t) => t.isOpen).toList();
    final pendingOnly = openTrades.where((t) => t.isPending).toList();
    final closedOnly = openTrades.where((t) => t.isClosed).toList();

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Text(
                    'Trade',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  // Balance badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 14, color: AppColors.brandPrimary),
                        const SizedBox(width: 6),
                        Text(
                          AppFormatters.currency(wallet.balance),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Tab Bar ───────────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.brandPrimary,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(3),
                labelColor: Colors.black,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: 'New Order'),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Open'),
                        if (openOnly.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.brandPrimary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${openOnly.length}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Tab(text: 'History'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Tab Content ──────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // New Order Tab
                  _buildNewOrderTab(live, inst),
                  // Open Positions Tab
                  _buildOpenPositionsTab(openOnly),
                  // History Tab
                  _buildHistoryTab(closedOnly),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewOrderTab(InstrumentEntity live, InstrumentEntity inst) {
    final isPositive = live.isPositiveChange;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Symbol Selector ────────────────────────────────────────────────
          _buildSymbolSelector(live, isPositive, inst),
          const SizedBox(height: 20),

          // ── Buy / Sell Toggle ──────────────────────────────────────────────
          _buildBuySellToggle(),
          const SizedBox(height: 20),

          // ── Order Type ────────────────────────────────────────────────────
          _buildOrderTypeSelector(),
          const SizedBox(height: 20),

          // ── Lot Size Slider ────────────────────────────────────────────────
          _buildLotSizeSection(),
          const SizedBox(height: 20),

          // ── SL / TP ────────────────────────────────────────────────────────
          _buildSlTpSection(live, inst),
          const SizedBox(height: 20),

          // ── Leverage ──────────────────────────────────────────────────────
          _buildLeverageSection(),
          const SizedBox(height: 20),

          // ── Order Summary ─────────────────────────────────────────────────
          _buildOrderSummary(live, inst),
          const SizedBox(height: 20),

          // ── Place Order Button ─────────────────────────────────────────────
          _buildPlaceOrderButton(live, inst),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSymbolSelector(InstrumentEntity live, bool isPositive, InstrumentEntity inst) {
    return GestureDetector(
      onTap: () => _showSymbolPicker(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: isPositive ? AppColors.profitGradient : AppColors.lossGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _selectedSymbol.substring(0, 2),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedSymbol,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    inst.name,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  live.bid.toStringAsFixed(inst.decimals),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isPositive ? AppColors.profit : AppColors.loss,
                  ),
                ),
                Text(
                  '${isPositive ? '+' : ''}${live.change24h.toStringAsFixed(2)}%',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: isPositive ? AppColors.profit : AppColors.loss,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.unfold_more_rounded, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBuySellToggle() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _side = OrderSide.buy),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: _side == OrderSide.buy ? AppColors.profitGradient : null,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _side == OrderSide.buy
                      ? [BoxShadow(color: AppColors.profit.withAlpha(40), blurRadius: 12)]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'BUY',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _side == OrderSide.buy ? Colors.white : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _side = OrderSide.sell),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: _side == OrderSide.sell ? AppColors.lossGradient : null,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _side == OrderSide.sell
                      ? [BoxShadow(color: AppColors.loss.withAlpha(40), blurRadius: 12)]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'SELL',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _side == OrderSide.sell ? Colors.white : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTypeSelector() {
    final types = [OrderType.market, OrderType.limit, OrderType.stop, OrderType.stopLimit];
    final labels = ['Market', 'Limit', 'Stop', 'Stop Limit'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Type',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(types.length, (i) {
            final isSelected = _orderType == types[i];
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _orderType = types[i]),
                child: Container(
                  margin: EdgeInsets.only(right: i < types.length - 1 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.brandPrimary.withAlpha(20)
                        : AppColors.darkCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.brandPrimary : AppColors.darkBorder,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColors.brandPrimary : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildLotSizeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Lot Size',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.darkCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.brandPrimary.withAlpha(60)),
              ),
              child: Text(
                _lotSize.toStringAsFixed(2),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: const SliderThemeData(
            trackHeight: 4,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(
            value: _lotSize,
            min: 0.01,
            max: 10.0,
            divisions: 999,
            onChanged: (v) => setState(() => _lotSize = double.parse(v.toStringAsFixed(2))),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['0.01', '0.10', '0.50', '1.00', '5.00', '10.00']
              .map((v) => GestureDetector(
                    onTap: () => setState(() => _lotSize = double.parse(v)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _lotSize == double.parse(v)
                            ? AppColors.brandPrimary.withAlpha(20)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        v,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _lotSize == double.parse(v)
                              ? AppColors.brandPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildSlTpSection(InstrumentEntity live, InstrumentEntity inst) {
    return Row(
      children: [
        Expanded(
          child: _SlTpField(
            label: 'Stop Loss',
            icon: Icons.trending_down_rounded,
            iconColor: AppColors.loss,
            value: _stopLoss == 0.0 ? '' : _stopLoss.toStringAsFixed(inst.decimals),
            hint: 'Optional',
            onChanged: (v) => setState(() => _stopLoss = double.tryParse(v) ?? 0.0),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SlTpField(
            label: 'Take Profit',
            icon: Icons.trending_up_rounded,
            iconColor: AppColors.profit,
            value: _takeProfit == 0.0 ? '' : _takeProfit.toStringAsFixed(inst.decimals),
            hint: 'Optional',
            onChanged: (v) => setState(() => _takeProfit = double.tryParse(v) ?? 0.0),
          ),
        ),
      ],
    );
  }

  Widget _buildLeverageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Leverage',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              '1:${_leverage.toInt()}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.brandSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _leverageOptions.map((l) {
            final isSelected = _leverage == l;
            return GestureDetector(
              onTap: () => setState(() => _leverage = l),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.brandSecondary.withAlpha(20)
                      : AppColors.darkCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.brandSecondary : AppColors.darkBorder,
                  ),
                ),
                child: Text(
                  '1:${l.toInt()}',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.brandSecondary : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildOrderSummary(InstrumentEntity live, InstrumentEntity inst) {
    final isBuy = _side == OrderSide.buy;
    final price = isBuy ? live.ask : live.bid;
    final margin = _marginRequired;
    final commission = _lotSize * 7.0; // $7 per lot (mock)
    final pipValue = _lotSize * 10.0;  // $10 per pip per lot (mock)

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          _SummaryRow('Price', price.toStringAsFixed(inst.decimals)),
          _SummaryRow('Spread', live.spread.toStringAsFixed(1)),
          _SummaryRow('Margin Required', AppFormatters.currency(margin)),
          _SummaryRow('Commission', '\$${commission.toStringAsFixed(2)}'),
          _SummaryRow('Pip Value', '\$${pipValue.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Widget _buildPlaceOrderButton(InstrumentEntity live, InstrumentEntity inst) {
    final isBuy = _side == OrderSide.buy;
    final price = isBuy ? live.ask : live.bid;
    return Column(
      children: [
        Row(
          children: [
            // Sell button
            Expanded(
              child: GestureDetector(
                onTap: _side == OrderSide.sell ? () => _placeOrder(live, inst) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: _side == OrderSide.sell ? AppColors.lossGradient : null,
                    color: _side == OrderSide.sell ? null : AppColors.darkCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _side == OrderSide.sell ? AppColors.loss : AppColors.darkBorder,
                    ),
                    boxShadow: _side == OrderSide.sell
                        ? [BoxShadow(color: AppColors.loss.withAlpha(40), blurRadius: 16, offset: const Offset(0, 4))]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'SELL',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _side == OrderSide.sell ? Colors.white : AppColors.textMuted,
                        ),
                      ),
                      Text(
                        live.bid.toStringAsFixed(inst.decimals),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: _side == OrderSide.sell ? Colors.white70 : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Buy button
            Expanded(
              child: GestureDetector(
                onTap: _side == OrderSide.buy ? () => _placeOrder(live, inst) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: _side == OrderSide.buy ? AppColors.profitGradient : null,
                    color: _side == OrderSide.buy ? null : AppColors.darkCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _side == OrderSide.buy ? AppColors.profit : AppColors.darkBorder,
                    ),
                    boxShadow: _side == OrderSide.buy
                        ? [BoxShadow(color: AppColors.profit.withAlpha(40), blurRadius: 16, offset: const Offset(0, 4))]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'BUY',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _side == OrderSide.buy ? Colors.white : AppColors.textMuted,
                        ),
                      ),
                      Text(
                        live.ask.toStringAsFixed(inst.decimals),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: _side == OrderSide.buy ? Colors.white70 : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOpenPositionsTab(List<TradeEntity> trades) {
    if (trades.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withAlpha(15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.show_chart_rounded, color: AppColors.brandPrimary, size: 32),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Open Positions',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Place a new order to see your positions here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: trades.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _OpenPositionCard(trade: trades[i]),
    );
  }

  Widget _buildHistoryTab(List<TradeEntity> trades) {
    if (trades.isEmpty) {
      return const Center(
        child: Text(
          'No closed trades yet',
          style: TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: trades.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _HistoryCard(trade: trades[i]),
    );
  }

  void _showSymbolPicker() {
    final instruments = ref.read(instrumentsProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.darkBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Instrument',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: instruments.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: AppColors.darkDivider,
              ),
              itemBuilder: (context, i) {
                final inst = instruments[i];
                return ListTile(
                  onTap: () {
                    setState(() => _selectedSymbol = inst.symbol);
                    Navigator.pop(context);
                  },
                  title: Text(
                    inst.symbol,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    inst.name,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: Text(
                    inst.bid.toStringAsFixed(inst.decimals),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      color: inst.isPositiveChange ? AppColors.profit : AppColors.loss,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _placeOrder(InstrumentEntity live, InstrumentEntity inst) async {
    setState(() => _isPlacingOrder = true);

    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 800));

    final price = _side == OrderSide.buy ? live.ask : live.bid;
    final newTrade = TradeEntity(
      id: 'tr_${DateTime.now().millisecondsSinceEpoch}',
      symbol: _selectedSymbol,
      side: _side,
      type: _orderType,
      status: OrderStatus.open,
      lotSize: _lotSize,
      openPrice: price,
      stopLoss: _stopLoss > 0 ? _stopLoss : null,
      takeProfit: _takeProfit > 0 ? _takeProfit : null,
      currentPrice: price,
      floatingPl: 0.0,
      commission: _lotSize * 7,
      swap: 0.0,
      leverage: _leverage,
      openTime: DateTime.now(),
    );

    ref.read(openTradesProvider.notifier).addTrade(newTrade);
    setState(() => _isPlacingOrder = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.profit, size: 18),
              const SizedBox(width: 10),
              Text(
                '${_side == OrderSide.buy ? 'Buy' : 'Sell'} $_selectedSymbol placed!',
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
              ),
            ],
          ),
          backgroundColor: AppColors.darkCardElevated,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );

      // Switch to open positions tab
      _tabController.animateTo(1);
    }
  }
}

// ── Supporting Widgets ──────────────────────────────────────────────────────
class _SlTpField extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  const _SlTpField({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: value,
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppColors.textMuted,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.darkBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: iconColor),
            ),
            filled: true,
            fillColor: AppColors.darkCard,
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenPositionCard extends ConsumerWidget {
  final TradeEntity trade;
  const _OpenPositionCard({required this.trade});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBuy = trade.side == OrderSide.buy;
    final isProfit = trade.floatingPl >= 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isBuy ? AppColors.profit.withAlpha(20) : AppColors.loss.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    isBuy ? 'B' : 'S',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isBuy ? AppColors.profit : AppColors.loss,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trade.symbol,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${trade.lotSize} lots | ${AppFormatters.duration(DateTime.now().difference(trade.openTime))}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    AppFormatters.plAmount(trade.floatingPl),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isProfit ? AppColors.profit : AppColors.loss,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(openTradesProvider.notifier).closeTrade(trade.id);
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: AppColors.loss,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: AppColors.darkDivider),
          const SizedBox(height: 10),
          Row(
            children: [
              _InfoChip('Open', trade.openPrice.toStringAsFixed(5)),
              _InfoChip('SL', trade.stopLoss?.toStringAsFixed(5) ?? '—'),
              _InfoChip('TP', trade.takeProfit?.toStringAsFixed(5) ?? '—'),
              _InfoChip('Swap', '\$${trade.swap.toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final TradeEntity trade;
  const _HistoryCard({required this.trade});

  @override
  Widget build(BuildContext context) {
    final isBuy = trade.side == OrderSide.buy;
    final isProfit = trade.floatingPl >= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isBuy ? AppColors.profit.withAlpha(15) : AppColors.loss.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isBuy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: isBuy ? AppColors.profit : AppColors.loss,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trade.symbol,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${trade.lotSize} lots | ${AppFormatters.dateTime(trade.openTime)}',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            AppFormatters.plAmount(trade.floatingPl),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isProfit ? AppColors.profit : AppColors.loss,
            ),
          ),
        ],
      ),
    );
  }
}

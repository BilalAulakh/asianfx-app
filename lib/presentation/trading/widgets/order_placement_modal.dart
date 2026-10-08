import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import '../../../blocs/blocs.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/math/money_math.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/market_feed_service.dart';
import '../../../domain/entities/trading_entities.dart';
import '../../common/widgets/price_staleness_chip.dart';

/// Institutional Order Ticket Modal
class OrderPlacementModal extends StatefulWidget {
  final InstrumentEntity instrument;
  final OrderSide initialSide;

  const OrderPlacementModal({
    super.key,
    required this.instrument,
    required this.initialSide,
  });

  static Future<void> show(
    BuildContext context, {
    required InstrumentEntity instrument,
    required OrderSide side,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B20),
      barrierColor: Colors.black.withValues(alpha: 0.75),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => OrderPlacementModal(
        instrument: instrument,
        initialSide: side,
      ),
    );
  }

  @override
  State<OrderPlacementModal> createState() => _OrderPlacementModalState();
}

class _OrderPlacementModalState extends State<OrderPlacementModal> {
  late OrderSide _side;
  OrderType _orderType = OrderType.market;
  double _lots = 0.01;
  int _leverage = 100;
  bool _enableSl = false;
  bool _enableTp = false;

  late TextEditingController _lotController;
  late TextEditingController _priceController;
  late TextEditingController _slController;
  late TextEditingController _tpController;

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    _lotController = TextEditingController(text: _lots.toStringAsFixed(2));

    // Refresh user balance immediately upon modal opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TradingEngineBloc>().refreshBalance();
    });

    final currentExecPrice = _side == OrderSide.buy
        ? widget.instrument.ask.toDouble()
        : widget.instrument.bid.toDouble();

    _priceController = TextEditingController(
      text: currentExecPrice.toStringAsFixed(widget.instrument.decimals),
    );

    final slPrice = _side == OrderSide.buy
        ? currentExecPrice * 0.985
        : currentExecPrice * 1.015;
    final tpPrice = _side == OrderSide.buy
        ? currentExecPrice * 1.03
        : currentExecPrice * 0.97;

    _slController = TextEditingController(
      text: slPrice.toStringAsFixed(widget.instrument.decimals),
    );
    _tpController = TextEditingController(
      text: tpPrice.toStringAsFixed(widget.instrument.decimals),
    );
  }

  @override
  void dispose() {
    _lotController.dispose();
    _priceController.dispose();
    _slController.dispose();
    _tpController.dispose();
    super.dispose();
  }

  void _adjustLots(double delta) {
    setState(() {
      _lots = double.parse(((_lots + delta).clamp(0.01, 100.0)).toStringAsFixed(2));
      _lotController.text = _lots.toStringAsFixed(2);
    });
  }

  double _priceStep(InstrumentEntity live) {
    if (live.symbol.contains('BTC') || live.symbol.contains('ETH')) return 10.0;
    if (live.decimals == 4) return 0.0001; // 1 pip
    if (live.decimals == 3) return 0.01;   // 1 pip
    if (live.decimals == 2) return 0.10;   // 10 cents on gold/silver
    return 1.0;
  }

  void _adjustPrice(double delta, InstrumentEntity live) {
    final livePrice = _side == OrderSide.buy ? live.ask.toDouble() : live.bid.toDouble();
    final current = double.tryParse(_priceController.text) ?? livePrice;
    final updated = (current + delta).clamp(0.00001, 1000000.0);
    setState(() {
      _priceController.text = updated.toStringAsFixed(live.decimals);
    });
  }

  void _setPriceByPips(int pips, InstrumentEntity live) {
    final livePrice = _side == OrderSide.buy ? live.ask.toDouble() : live.bid.toDouble();
    if (pips == 0) {
      setState(() {
        _priceController.text = livePrice.toStringAsFixed(live.decimals);
      });
      return;
    }
    double factor;
    if (live.symbol.contains('BTC') || live.symbol.contains('ETH')) {
      factor = 1.0;
    } else if (live.decimals == 4) {
      factor = 0.0001;
    } else if (live.decimals == 3) {
      factor = 0.01;
    } else if (live.decimals == 2) {
      factor = 0.10;
    } else {
      factor = 1.0;
    }
    final target = (livePrice + (pips * factor)).clamp(0.00001, 1000000.0);
    setState(() {
      _priceController.text = target.toStringAsFixed(live.decimals);
    });
  }

  void _updateSlTpDefaults(double basePrice, int decimals) {
    final slPrice = _side == OrderSide.buy ? basePrice * 0.985 : basePrice * 1.015;
    final tpPrice = _side == OrderSide.buy ? basePrice * 1.03 : basePrice * 0.97;
    _slController.text = slPrice.toStringAsFixed(decimals);
    _tpController.text = tpPrice.toStringAsFixed(decimals);
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<MarketBloc>().state.getInstrument(widget.instrument.symbol);
    final engineState = context.watch<TradingEngineBloc>().state;
    final account = engineState.accountState;

    // Free margin comes from the account state only. The old code fell back to
    // the in-memory double-entry ledger whenever the balance was not positive,
    // which mixed a demo bookkeeping aggregate into a real account's buying
    // power and let the ticket approve an order the server would reject.
    final effectiveFreeMargin = account.freeMargin;

    final execPrice = _side == OrderSide.buy ? live.ask : live.bid;
    final lotsDec = MoneyMath.toDec(_lots);
    final leverageDec = Decimal.fromInt(_leverage);

    final enteredLimitPrice = double.tryParse(_priceController.text);
    final effectiveOrderPrice = (_orderType != OrderType.market && enteredLimitPrice != null && enteredLimitPrice > 0)
        ? MoneyMath.toDec(enteredLimitPrice)
        : execPrice;

    // Convert the notional out of the instrument's quote currency so the preview
    // matches what rpc_open_trade will charge (e.g. USD/JPY, EUR/GBP, GER40/EUR).
    final requiredMargin = MoneyMath.calcRequiredMargin(
      lots: lotsDec,
      contractSize: live.contractSize,
      openPrice: effectiveOrderPrice,
      leverage: leverageDec,
      quoteToUsdRate: MarketFeedService().quoteToUsdRateFor(live),
    );

    // Charged once when the trade opens (server: commission_per_lot x lots).
    final commission = MarketFeedService().commissionPerLot(live.symbol) * lotsDec;

    // A resting limit/stop order reserves no margin until it triggers, so it
    // must not be blocked by the current free margin. The server requires
    // margin + commission to be free.
    final isMarginSufficient = _orderType != OrderType.market ||
        (requiredMargin + commission <= effectiveFreeMargin && effectiveFreeMargin > Decimal.zero);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sheet Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF262D34),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // No live price -> the server will answer NO_QUOTE; say so first.
            if (MarketFeedService().isStale(live.symbol))
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5484D).withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    PriceStalenessChip(symbol: live.symbol),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'No live price for this instrument right now (market closed or feed offline). '
                        'Orders will be rejected until a live price is available.',
                        style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Color(0xFFE5484D)),
                      ),
                    ),
                  ],
                ),
              ),

            // Header Symbol & Contract Specification
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFDE02).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFDE02), width: 1),
                  ),
                  child: Text(
                    live.symbol,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFFDE02),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        live.name,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '1 Lot = ${MoneyMath.formatDec(live.contractSize, 0)} units • Spread: ${live.spreadPips.toStringAsFixed(1)} pips',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: Color(0xFF8A919A),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF8A919A)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Order Type Selector (Market, Limit, Stop)
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF0F1317),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF262D34)),
              ),
              child: Row(
                children: [
                  _orderTypeTab('Market', OrderType.market, live),
                  _orderTypeTab('Limit', OrderType.limit, live),
                  _orderTypeTab('Stop', OrderType.stop, live),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Side Selector (Buy Long vs Sell Short)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _side = OrderSide.buy;
                        final basePrice = live.ask.toDouble();
                        if (_orderType == OrderType.market) {
                          _priceController.text = basePrice.toStringAsFixed(live.decimals);
                        }
                        _updateSlTpDefaults(basePrice, live.decimals);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _side == OrderSide.buy
                            ? AppColors.buyButton
                            : const Color(0xFF1E242A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'BUY\n${MoneyMath.formatDec(live.ask, live.displayDecimals)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _side == OrderSide.buy ? Colors.white : AppColors.buyButton,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _side = OrderSide.sell;
                        final basePrice = live.bid.toDouble();
                        if (_orderType == OrderType.market) {
                          _priceController.text = basePrice.toStringAsFixed(live.decimals);
                        }
                        _updateSlTpDefaults(basePrice, live.decimals);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _side == OrderSide.sell
                            ? AppColors.sellButton
                            : const Color(0xFF1E242A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'SELL\n${MoneyMath.formatDec(live.bid, live.displayDecimals)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _side == OrderSide.sell ? Colors.white : AppColors.sellButton,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Order / Limit Price Controller (Only visible for Limit & Stop orders)
            if (_orderType != OrderType.market) ...[
              Row(
                children: [
                  Icon(
                    _orderType == OrderType.limit ? Icons.tune_rounded : Icons.pan_tool_rounded,
                    size: 15,
                    color: const Color(0xFFFFDE02),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _orderType == OrderType.limit ? 'Limit Price (USD):' : 'Stop Price (USD):',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A919A),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _setPriceByPips(0, live),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFDE02).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFFDE02).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'Live: ${MoneyMath.formatDec(execPrice, live.displayDecimals)}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFDE02),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1317),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFDE02).withValues(alpha: 0.6), width: 1.2),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: Colors.white70, size: 20),
                      onPressed: () => _adjustPrice(-_priceStep(live), live),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        cursorColor: const Color(0xFFFFDE02),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFDE02),
                        ),
                        decoration: const InputDecoration(
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          setState(() {});
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: Colors.white70, size: 20),
                      onPressed: () => _adjustPrice(_priceStep(live), live),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Quick Pip Offset Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _pipChip('Market', 0, live),
                    if (_orderType == OrderType.limit) ...[
                      if (_side == OrderSide.buy) ...[
                        _pipChip('-5 pips', -5, live),
                        _pipChip('-10 pips', -10, live),
                        _pipChip('-25 pips', -25, live),
                        _pipChip('-50 pips', -50, live),
                      ] else ...[
                        _pipChip('+5 pips', 5, live),
                        _pipChip('+10 pips', 10, live),
                        _pipChip('+25 pips', 25, live),
                        _pipChip('+50 pips', 50, live),
                      ],
                    ] else ...[
                      if (_side == OrderSide.buy) ...[
                        _pipChip('+5 pips', 5, live),
                        _pipChip('+10 pips', 10, live),
                        _pipChip('+25 pips', 25, live),
                      ] else ...[
                        _pipChip('-5 pips', -5, live),
                        _pipChip('-10 pips', -10, live),
                        _pipChip('-25 pips', -25, live),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Lot Size Controller
            Row(
              children: [
                const Text(
                  'Volume (Lots):',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A919A),
                  ),
                ),
                const Spacer(),
                _lotPresetChip(0.01),
                _lotPresetChip(0.02),
                _lotPresetChip(0.05),
                _lotPresetChip(0.10),
              ],
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1317),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF262D34)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white70, size: 20),
                    onPressed: () => _adjustLots(-0.01),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _lotController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      cursorColor: const Color(0xFFFFDE02),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        final parsed = double.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          setState(() => _lots = parsed);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white70, size: 20),
                    onPressed: () => _adjustLots(0.01),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Optional Take Profit & Stop Loss
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _enableTp = !_enableTp),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _enableTp ? const Color(0xFF16C784).withValues(alpha: 0.12) : const Color(0xFF0F1317),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _enableTp ? const Color(0xFF16C784) : const Color(0xFF262D34),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _enableTp ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            size: 15,
                            color: _enableTp ? const Color(0xFF16C784) : const Color(0xFF8A919A),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Take Profit',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _enableSl = !_enableSl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _enableSl ? const Color(0xFFE5484D).withValues(alpha: 0.12) : const Color(0xFF0F1317),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _enableSl ? const Color(0xFFE5484D) : const Color(0xFF262D34),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _enableSl ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            size: 15,
                            color: _enableSl ? const Color(0xFFE5484D) : const Color(0xFF8A919A),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Stop Loss',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_enableTp || _enableSl) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_enableTp)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1317),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF16C784).withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TP Price',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: Color(0xFF16C784))),
                            TextField(
                              controller: _tpController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              cursorColor: const Color(0xFF16C784),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF16C784),
                              ),
                              decoration: _plainField,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_enableTp && _enableSl) const SizedBox(width: 8),
                  if (_enableSl)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1317),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE5484D).withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SL Price',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 10, color: Color(0xFFE5484D))),
                            TextField(
                              controller: _slController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              cursorColor: const Color(0xFFE5484D),
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFE5484D),
                              ),
                              decoration: _plainField,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),

            // Margin & Financial Health Summary Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1317),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMarginSufficient ? const Color(0xFF262D34) : AppColors.loss,
                ),
              ),
              child: Column(
                children: [
                  _metricRow('Required Margin', MoneyMath.formatCurrency(requiredMargin)),
                  if (commission > Decimal.zero) ...[
                    const SizedBox(height: 6),
                    _metricRow('Commission', MoneyMath.formatCurrency(commission)),
                  ],
                  const SizedBox(height: 6),
                  _metricRow('Available Free Margin', MoneyMath.formatCurrency(effectiveFreeMargin)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Account Leverage',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Color(0xFF8A919A),
                        ),
                      ),
                      Row(
                        // Single source of truth: the same list the engine and
                        // rpc_open_trade validate against.
                        children: AppConstants.availableLeverages.map((lev) {
                          final isSelected = _leverage == lev;
                          return GestureDetector(
                            onTap: () => setState(() => _leverage = lev),
                            child: Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFFFDE02) : const Color(0xFF1E242A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFFFDE02) : const Color(0xFF262D34),
                                ),
                              ),
                              child: Text(
                                '1:$lev',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.black : Colors.white70,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Submit Order Button
            ElevatedButton(
              onPressed: !isMarginSufficient || engineState.isSubmitting
                  ? null
                  : () async {
                      // Resolve everything that needs this BuildContext before the
                      // await: the sheet may be gone by the time the server answers.
                      final engine = context.read<TradingEngineBloc>();
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        Decimal? targetPrice;
                        if (_orderType != OrderType.market) {
                          targetPrice = MoneyMath.toDec(_priceController.text);
                          if (targetPrice <= Decimal.zero) {
                            throw Exception('Please enter a valid target price.');
                          }
                        }

                        final success = await engine.placeOrder(
                              instrument: live,
                              side: _side,
                              type: _orderType,
                              lots: lotsDec,
                              targetPrice: targetPrice,
                              stopLoss: _enableSl ? MoneyMath.toDec(_slController.text) : null,
                              takeProfit: _enableTp ? MoneyMath.toDec(_tpController.text) : null,
                              leverage: leverageDec,
                            );

                        if (success && mounted) {
                          navigator.pop();
                          final sideStr = _side == OrderSide.buy ? 'BUY' : 'SELL';
                          final typeStr = _orderType == OrderType.market
                              ? 'Market'
                              : (_orderType == OrderType.limit ? 'Limit' : 'Stop');
                          final priceStr = targetPrice != null
                              ? ' @ \$${MoneyMath.formatDec(targetPrice, live.displayDecimals)}'
                              : ' @ \$${MoneyMath.formatDec(execPrice, live.displayDecimals)}';

                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF16C784),
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                '✓ $sideStr $typeStr ${_lots.toStringAsFixed(2)} Lots ${live.symbol}$priceStr Placed!',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.loss,
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                e.toString().replaceAll('Exception: ', ''),
                                style: const TextStyle(fontFamily: 'Inter', color: Colors.white),
                              ),
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _side == OrderSide.buy ? AppColors.buyButton : AppColors.sellButton,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: engineState.isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      !isMarginSufficient
                          ? 'INSUFFICIENT FREE MARGIN'
                          : (_orderType == OrderType.market
                              ? 'PLACE ${_side == OrderSide.buy ? 'BUY' : 'SELL'} MARKET'
                              : (_orderType == OrderType.limit
                                  ? 'PLACE ${_side == OrderSide.buy ? 'BUY' : 'SELL'} LIMIT'
                                  : 'PLACE ${_side == OrderSide.buy ? 'BUY' : 'SELL'} STOP')),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderTypeTab(String label, OrderType type, InstrumentEntity live) {
    final isSelected = _orderType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _orderType = type;
            if (type != OrderType.market) {
              final livePrice = _side == OrderSide.buy ? live.ask.toDouble() : live.bid.toDouble();
              if (_priceController.text.isEmpty || double.tryParse(_priceController.text) == null) {
                _priceController.text = livePrice.toStringAsFixed(live.decimals);
              }
            }
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFDE02) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.black : const Color(0xFF8A919A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pipChip(String label, int pips, InstrumentEntity live) {
    return GestureDetector(
      onTap: () => _setPriceByPips(pips, live),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E242A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF262D34)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFDE02),
          ),
        ),
      ),
    );
  }

  Widget _lotPresetChip(double lot) {
    final isSelected = (_lots - lot).abs() < 0.001;
    return GestureDetector(
      onTap: () {
        setState(() {
          _lots = lot;
          _lotController.text = _lots.toStringAsFixed(2);
        });
      },
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFDE02).withValues(alpha: 0.2) : const Color(0xFF1E242A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFDE02) : const Color(0xFF262D34),
            width: 1,
          ),
        ),
        child: Text(
          lot.toStringAsFixed(2),
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? const Color(0xFFFFDE02) : Colors.white70,
          ),
        ),
      ),
    );
  }

  /// Bare input inside the TP/SL boxes: no theme fill (a light theme painted
  /// it white) and no border of its own.
  static const _plainField = InputDecoration(
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    isDense: true,
    hintText: '0.00',
    hintStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, color: Color(0xFF4A5568)),
    contentPadding: EdgeInsets.only(top: 4, bottom: 2),
  );

  Widget _metricRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: Color(0xFF8A919A),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

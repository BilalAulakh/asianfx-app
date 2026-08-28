import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/math/money_math.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/trading_entities.dart';
import '../../../providers/market_provider.dart';
import '../../../providers/trading_engine_provider.dart';

/// Institutional Order Ticket Modal
class OrderPlacementModal extends ConsumerStatefulWidget {
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
      backgroundColor: const Color(0xFF151D28),
      barrierColor: Colors.black.withOpacity(0.75),
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
  ConsumerState<OrderPlacementModal> createState() => _OrderPlacementModalState();
}

class _OrderPlacementModalState extends ConsumerState<OrderPlacementModal> {
  late OrderSide _side;
  OrderType _orderType = OrderType.market;
  double _lots = 0.10;
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
      _lots = (_lots + delta).clamp(0.01, 100.0);
      _lotController.text = _lots.toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final liveStream = ref.watch(priceStreamProvider(widget.instrument.symbol));
    final live = liveStream.when(
      data: (inst) => inst,
      loading: () => widget.instrument,
      error: (_, __) => widget.instrument,
    );

    final engineState = ref.watch(tradingEngineProvider);
    final account = engineState.accountState;

    final execPrice = _side == OrderSide.buy ? live.ask : live.bid;
    final lotsDec = MoneyMath.toDec(_lots);
    final leverageDec = Decimal.fromInt(_leverage);

    final requiredMargin = MoneyMath.calcRequiredMargin(
      lots: lotsDec,
      contractSize: live.contractSize,
      openPrice: execPrice,
      leverage: leverageDec,
    );

    final isMarginSufficient = requiredMargin <= account.freeMargin;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 16,
      ),
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
                color: const Color(0xFF2B384E),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header Symbol & Contract Specification
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD600).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD600), width: 1),
                ),
                child: Text(
                  live.symbol,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFFD600),
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
                        color: Color(0xFF848E9C),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFF848E9C)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Order Type Selector (Market, Limit, Stop)
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF0F141C),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2B384E)),
            ),
            child: Row(
              children: [
                _orderTypeTab('Market', OrderType.market),
                _orderTypeTab('Limit', OrderType.limit),
                _orderTypeTab('Stop', OrderType.stop),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Side Selector (Buy Long vs Sell Short)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _side = OrderSide.buy),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _side == OrderSide.buy
                          ? const Color(0xFF00D68F)
                          : const Color(0xFF1E2838),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'BUY (LONG)\n${MoneyMath.formatDec(live.ask, live.decimals)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _side == OrderSide.buy ? Colors.black : const Color(0xFF00D68F),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _side = OrderSide.sell),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _side == OrderSide.sell
                          ? const Color(0xFFFF4757)
                          : const Color(0xFF1E2838),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'SELL (SHORT)\n${MoneyMath.formatDec(live.bid, live.decimals)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _side == OrderSide.sell ? Colors.white : const Color(0xFFFF4757),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Lot Size Controller
          Row(
            children: [
              const Text(
                'Volume (Lots):',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF848E9C),
                ),
              ),
              const Spacer(),
              _lotChip('-1.0', () => _adjustLots(-1.0)),
              _lotChip('-0.1', () => _adjustLots(-0.1)),
              _lotChip('+0.1', () => _adjustLots(0.1)),
              _lotChip('+1.0', () => _adjustLots(1.0)),
            ],
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F141C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2B384E)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, color: Colors.white70, size: 20),
                  onPressed: () => _adjustLots(-0.05),
                ),
                Expanded(
                  child: TextField(
                    controller: _lotController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(border: InputBorder.none),
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
                  onPressed: () => _adjustLots(0.05),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Margin & Financial Health Summary Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F141C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isMarginSufficient ? const Color(0xFF2B384E) : AppColors.loss,
              ),
            ),
            child: Column(
              children: [
                _metricRow('Required Margin', MoneyMath.formatCurrency(requiredMargin)),
                const SizedBox(height: 6),
                _metricRow('Available Free Margin', MoneyMath.formatCurrency(account.freeMargin)),
                const SizedBox(height: 6),
                _metricRow('Account Leverage', '1:$_leverage'),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Submit Order Button
          ElevatedButton(
            onPressed: !isMarginSufficient || engineState.isSubmitting
                ? null
                : () async {
                    try {
                      final success = await ref
                          .read(tradingEngineProvider.notifier)
                          .placeOrder(
                            instrument: live,
                            side: _side,
                            type: _orderType,
                            lots: lotsDec,
                            targetPrice: _orderType != OrderType.market
                                ? MoneyMath.toDec(_priceController.text)
                                : null,
                            stopLoss: _enableSl ? MoneyMath.toDec(_slController.text) : null,
                            takeProfit: _enableTp ? MoneyMath.toDec(_tpController.text) : null,
                            leverage: leverageDec,
                          );

                      if (success && mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF00D68F),
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              '✓ ${_side == OrderSide.buy ? 'BUY' : 'SELL'} ${_lots.toStringAsFixed(2)} Lots ${live.symbol} Placed!',
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.loss,
                            content: Text(
                              e.toString(),
                              style: const TextStyle(fontFamily: 'Inter', color: Colors.white),
                            ),
                          ),
                        );
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: _side == OrderSide.buy
                  ? const Color(0xFF00D68F)
                  : const Color(0xFFFF4757),
              foregroundColor: _side == OrderSide.buy ? Colors.black : Colors.white,
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
                    isMarginSufficient
                        ? 'PLACE ${_side == OrderSide.buy ? 'BUY' : 'SELL'} ORDER'
                        : 'INSUFFICIENT FREE MARGIN',
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
    );
  }

  Widget _orderTypeTab(String label, OrderType type) {
    final isSelected = _orderType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _orderType = type),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFD600) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.black : const Color(0xFF848E9C),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lotChip(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2838),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2B384E)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            color: Color(0xFF848E9C),
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

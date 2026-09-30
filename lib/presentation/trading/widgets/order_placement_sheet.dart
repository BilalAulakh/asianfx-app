import 'package:flutter/material.dart';
import '../../../blocs/blocs.dart';
import '../../../core/math/money_math.dart';
import '../../../domain/entities/trading_entities.dart';

class OrderPlacementSheet extends StatefulWidget {
  final InstrumentEntity instrument;
  final OrderSide initialSide;

  const OrderPlacementSheet({
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
      backgroundColor: const Color(0xFF161B22),
      barrierColor: Colors.black.withAlpha(180),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => OrderPlacementSheet(
        instrument: instrument,
        initialSide: side,
      ),
    );
  }

  @override
  State<OrderPlacementSheet> createState() => _OrderPlacementSheetState();
}

class _OrderPlacementSheetState extends State<OrderPlacementSheet> {
  late OrderSide _selectedSide;
  double _lotSize = 0.10;
  bool _enableSl = false;
  bool _enableTp = false;
  late TextEditingController _lotController;
  late TextEditingController _slController;
  late TextEditingController _tpController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedSide = widget.initialSide;
    _lotController = TextEditingController(text: _lotSize.toStringAsFixed(2));

    final currentPrice = _selectedSide == OrderSide.buy ? widget.instrument.ask.toDouble() : widget.instrument.bid.toDouble();
    final defaultSl = _selectedSide == OrderSide.buy ? currentPrice * 0.985 : currentPrice * 1.015;
    final defaultTp = _selectedSide == OrderSide.buy ? currentPrice * 1.03 : currentPrice * 0.97;

    _slController = TextEditingController(text: defaultSl.toStringAsFixed(widget.instrument.decimals));
    _tpController = TextEditingController(text: defaultTp.toStringAsFixed(widget.instrument.decimals));
  }

  @override
  void dispose() {
    _lotController.dispose();
    _slController.dispose();
    _tpController.dispose();
    super.dispose();
  }

  void _updateLotSize(double delta) {
    setState(() {
      _lotSize = (_lotSize + delta).clamp(0.01, 50.0);
      _lotController.text = _lotSize.toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<MarketBloc>().state.getInstrument(widget.instrument.symbol);
    final wallet = context.watch<WalletBloc>().state;
    final execPrice = _selectedSide == OrderSide.buy ? live.ask.toDouble() : live.bid.toDouble();
    final isBuy = _selectedSide == OrderSide.buy;

    // Margin Calculation (Exness standard: 1:100 leverage)
    final contractSize = live.contractSize.toDouble();
    final requiredMargin = (execPrice * _lotSize * contractSize) / 100.0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 14,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2B313A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header: Symbol + Live Spread
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      widget.instrument.symbol,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B313A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.instrument.category.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFFD600),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Spread: ${live.spread.toStringAsFixed(1)} pts',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Color(0xFF848E9C),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Order Side Selector (BUY vs SELL)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF0F141C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2B313A)),
              ),
              child: Row(
                children: [
                  // SELL Tab
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedSide = OrderSide.sell),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !isBuy ? const Color(0xFFF6465D) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'SELL',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: !isBuy ? Colors.white : const Color(0xFFF6465D),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              live.bid.toStringAsFixed(widget.instrument.decimals),
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: !isBuy ? Colors.white : const Color(0xFF848E9C),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // BUY Tab
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedSide = OrderSide.buy),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isBuy ? const Color(0xFF0ECB81) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'BUY',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isBuy ? Colors.black : const Color(0xFF0ECB81),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              live.ask.toStringAsFixed(widget.instrument.decimals),
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isBuy ? Colors.black : const Color(0xFF848E9C),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Lot Size Stepper
            const Text(
              'Lot Size (Volume)',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF848E9C),
              ),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                _stepperButton(Icons.remove, () => _updateLotSize(-0.05)),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F141C),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2B313A)),
                    ),
                    child: TextField(
                      controller: _lotController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      cursorColor: const Color(0xFFFFD600),
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
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
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: (v) {
                        final val = double.tryParse(v);
                        if (val != null && val > 0) {
                          setState(() => _lotSize = val);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _stepperButton(Icons.add, () => _updateLotSize(0.05)),
              ],
            ),

            const SizedBox(height: 10),

            // Preset Lot Chips
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [0.01, 0.05, 0.10, 0.50, 1.00].map((preset) {
                final isSelected = (_lotSize - preset).abs() < 0.001;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _lotSize = preset;
                      _lotController.text = preset.toStringAsFixed(2);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFFFD600) : const Color(0xFF1E232A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFFFD600) : const Color(0xFF2B313A),
                      ),
                    ),
                    child: Text(
                      preset.toStringAsFixed(2),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.black : const Color(0xFF848E9C),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // Margin & Balance Breakdown
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E232A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2B313A)),
              ),
              child: Column(
                children: [
                  _infoRow('Required Margin', '\$${requiredMargin.toStringAsFixed(2)}'),
                  const SizedBox(height: 6),
                  _infoRow('Free Margin', '\$${wallet.freeMargin.toStringAsFixed(2)}'),
                  const SizedBox(height: 6),
                  _infoRow('Account Balance', '\$${wallet.balance.toStringAsFixed(2)}'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // TP & SL Options Toggle
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Take Profit', style: TextStyle(color: Colors.white, fontSize: 13)),
                    value: _enableTp,
                    activeColor: const Color(0xFF0ECB81),
                    onChanged: (v) => setState(() => _enableTp = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Stop Loss', style: TextStyle(color: Colors.white, fontSize: 13)),
                    value: _enableSl,
                    activeColor: const Color(0xFFF6465D),
                    onChanged: (v) => setState(() => _enableSl = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
            ),

            if (_enableTp || _enableSl) ...[
              Row(
                children: [
                  if (_enableTp)
                    Expanded(
                      child: TextField(
                        controller: _tpController,
                        style: const TextStyle(color: Color(0xFF0ECB81), fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'TP Price',
                          labelStyle: TextStyle(color: Color(0xFF0ECB81), fontSize: 12),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  if (_enableTp && _enableSl) const SizedBox(width: 10),
                  if (_enableSl)
                    Expanded(
                      child: TextField(
                        controller: _slController,
                        style: const TextStyle(color: Color(0xFFF6465D), fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'SL Price',
                          labelStyle: TextStyle(color: Color(0xFFF6465D), fontSize: 12),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Confirm Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isBuy ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                  foregroundColor: isBuy ? Colors.black : Colors.white,
                  elevation: 6,
                  shadowColor: isBuy ? const Color(0xFF0ECB81).withOpacity(0.4) : const Color(0xFFF6465D).withOpacity(0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isSubmitting
                    ? null
                    : () async {
                        setState(() => _isSubmitting = true);

                        final sl = _enableSl ? double.tryParse(_slController.text) : null;
                        final tp = _enableTp ? double.tryParse(_tpController.text) : null;

                        final success = await context.read<TradingEngineBloc>().placeOrder(
                              instrument: live,
                              side: _selectedSide,
                              type: OrderType.market,
                              lots: MoneyMath.toDec(_lotSize),
                              stopLoss: sl != null ? MoneyMath.toDec(sl) : null,
                              takeProfit: tp != null ? MoneyMath.toDec(tp) : null,
                            );

                        if (!mounted) return;
                        setState(() => _isSubmitting = false);

                        if (success) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: isBuy ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              content: Row(
                                children: [
                                  Icon(
                                    isBuy ? Icons.check_circle_rounded : Icons.arrow_downward_rounded,
                                    color: isBuy ? Colors.black : Colors.white,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${isBuy ? "BUY" : "SELL"} ${_lotSize.toStringAsFixed(2)} ${widget.instrument.symbol} @ \$${execPrice.toStringAsFixed(widget.instrument.decimals)} EXECUTED!',
                                      style: TextStyle(
                                        color: isBuy ? Colors.black : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      },
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(isBuy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'CONFIRM ${isBuy ? "BUY" : "SELL"} • ${_lotSize.toStringAsFixed(2)} LOTS',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1E232A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2B313A)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF848E9C), fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}

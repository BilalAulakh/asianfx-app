import 'package:flutter/material.dart';

/// Round badge with the base asset code (XAU, EUR, BTC…), coloured per asset.
class SymbolBadge extends StatelessWidget {
  final String symbol;
  final double size;

  const SymbolBadge({super.key, required this.symbol, this.size = 26});

  static Color colorFor(String base) => switch (base) {
        'XAU' => const Color(0xFFE0A526),
        'XAG' => const Color(0xFF9EA7B0),
        'XPT' || 'XPD' => const Color(0xFF7D8A96),
        'BTC' => const Color(0xFFF7931A),
        'ETH' => const Color(0xFF627EEA),
        'USOIL' || 'UKOIL' || 'WTI' => const Color(0xFF3B3F45),
        'EUR' => const Color(0xFF1F4BB5),
        'GBP' => const Color(0xFF7A1F3D),
        'USD' => const Color(0xFF2E7D4F),
        'AUD' || 'NZD' => const Color(0xFF0E6E78),
        'CAD' || 'CHF' => const Color(0xFFB3261E),
        _ => const Color(0xFF2E6FD8),
      };

  @override
  Widget build(BuildContext context) {
    final base = symbol.split('/').first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colorFor(base), shape: BoxShape.circle),
      child: Text(
        base.length > 3 ? base.substring(0, 3) : base,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size * 0.3,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

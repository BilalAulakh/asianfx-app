import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/feature_flags.dart';
import '../../../data/datasources/market_feed_service.dart';

/// LIVE / STALE / DEMO badge for one symbol.
///
/// A price is stale when no real quote has arrived for longer than
/// `broker_config.quote_max_age_seconds`. The server refuses to fill on a stale
/// price (NO_QUOTE), so the UI says so up front. Rebuilds itself every few
/// seconds because staleness changes with time, not with ticks.
class PriceStalenessChip extends StatefulWidget {
  final String symbol;
  final MarketFeedService? feed;

  const PriceStalenessChip({super.key, required this.symbol, this.feed});

  @override
  State<PriceStalenessChip> createState() => _PriceStalenessChipState();
}

class _PriceStalenessChipState extends State<PriceStalenessChip> {
  Timer? _timer;

  MarketFeedService get _feed => widget.feed ?? MarketFeedService();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _ago(Duration d) {
    if (d.inSeconds < 90) return '${d.inSeconds}s ago';
    if (d.inMinutes < 90) return '${d.inMinutes}m ago';
    if (d.inHours < 48) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final (Color color, String label) = () {
      if (kDemoMode) return (const Color(0xFFFF9F43), 'DEMO PRICE');
      if (!_feed.isStale(widget.symbol)) return (const Color(0xFF00D68F), 'LIVE');
      final at = _feed.lastLiveAt(widget.symbol);
      if (at == null) return (const Color(0xFFFF4757), 'NO LIVE PRICE');
      return (const Color(0xFFFF4757), 'STALE · ${_ago(DateTime.now().toUtc().difference(at.toUtc()))}');
    }();

    return Tooltip(
      message: kDemoMode
          ? 'Simulated price for demonstration only.'
          : 'Orders are rejected while there is no live price '
              '(market closed or price feed offline).',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(
          label,
          style: TextStyle(fontFamily: 'Inter', fontSize: 9.5, fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }
}

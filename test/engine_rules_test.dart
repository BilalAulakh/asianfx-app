import 'package:asianfxapp/blocs/trading_engine_bloc.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

/// Mirrors the server rule in fx_evaluate_account (20261002000400): a
/// triggered stop loss fills at the current executable price, never better
/// than the stop — so a gap through the level fills at the post-gap price.
void main() {
  group('stop-loss gap fill', () {
    test('long: gap below the stop fills at the bid, not the stop', () {
      expect(
        TradingEngineCubit.stopLossFillPrice(
            isBuy: true, stopLoss: d('1.0950'), bid: d('1.0900'), ask: d('1.0902')),
        d('1.0900'),
      );
    });

    test('long: touching the stop exactly fills at the stop', () {
      expect(
        TradingEngineCubit.stopLossFillPrice(
            isBuy: true, stopLoss: d('1.0950'), bid: d('1.0950'), ask: d('1.0952')),
        d('1.0950'),
      );
    });

    test('short: gap above the stop fills at the ask, not the stop', () {
      expect(
        TradingEngineCubit.stopLossFillPrice(
            isBuy: false, stopLoss: d('2000.00'), bid: d('2014.80'), ask: d('2015.20')),
        d('2015.20'),
      );
    });

    test('short: touching the stop exactly fills at the stop', () {
      expect(
        TradingEngineCubit.stopLossFillPrice(
            isBuy: false, stopLoss: d('2000.00'), bid: d('1999.60'), ask: d('2000.00')),
        d('2000.00'),
      );
    });
  });
}

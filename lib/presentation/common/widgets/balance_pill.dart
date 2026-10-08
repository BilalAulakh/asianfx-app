import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../blocs/blocs.dart';
import '../../../core/math/money_math.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// Exness-style account pill ("0.00 USD") shown at the top of the trading
/// screens. Shows equity; tapping opens the wallet.
class BalancePill extends StatelessWidget {
  const BalancePill({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.select((TradingEngineBloc b) => b.state.accountState);
    return Material(
      color: context.isDarkMode ? const Color(0xFF161B20) : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: context.subtleBorderColor)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => context.go(AppRoutes.vault),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            '${MoneyMath.formatCurrency(account.equity, symbol: '')} ${account.currency}',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

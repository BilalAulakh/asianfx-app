import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/connectivity_provider.dart';

/// Global overlay that monitors network connectivity and displays
/// a sleek, non-intrusive animated status banner whenever the internet drops
/// or reconnects.
class NetworkStatusOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const NetworkStatusOverlay({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<NetworkStatusOverlay> createState() => _NetworkStatusOverlayState();
}

class _NetworkStatusOverlayState extends ConsumerState<NetworkStatusOverlay>
    with SingleTickerProviderStateMixin {
  bool _showBanner = false;
  bool _isBackOnline = false;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to network state changes
    ref.listen<ConnectivityState>(connectivityProvider, (previous, next) {
      if (!next.isConnected) {
        // Disconnected
        _autoDismissTimer?.cancel();
        setState(() {
          _showBanner = true;
          _isBackOnline = false;
        });
      } else if (next.isConnected && (previous?.isConnected == false || next.wasDisconnected)) {
        // Just reconnected
        _autoDismissTimer?.cancel();
        setState(() {
          _showBanner = true;
          _isBackOnline = true;
        });

        // Auto-dismiss the "Back Online" success notification after 2.5 seconds
        _autoDismissTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) {
            setState(() {
              _showBanner = false;
              _isBackOnline = false;
            });
            ref.read(connectivityProvider.notifier).markOnlineAcknowledged();
          }
        });
      }
    });

    final connectivity = ref.watch(connectivityProvider);

    return Stack(
      children: [
        // Main App Content
        widget.child,

        // Animated Floating Network Status Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              offset: _showBanner ? Offset.zero : const Offset(0, -1.2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _showBanner ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _isBackOnline
                            ? const Color(0xFF0F261D) // Deep emerald dark
                            : const Color(0xFF261215), // Deep crimson dark
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isBackOnline
                              ? AppColors.profit.withValues(alpha: 0.7)
                              : AppColors.loss.withValues(alpha: 0.7),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isBackOnline ? AppColors.profit : AppColors.loss)
                                .withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Status Icon
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: (_isBackOnline ? AppColors.profit : AppColors.loss)
                                  .withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isBackOnline
                                  ? Icons.wifi_rounded
                                  : Icons.wifi_off_rounded,
                              color: _isBackOnline
                                  ? AppColors.profit
                                  : AppColors.loss,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Text Information
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _isBackOnline
                                      ? 'Back Online'
                                      : 'No Internet Connection',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _isBackOnline
                                        ? AppColors.profit
                                        : const Color(0xFFFF6B7A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isBackOnline
                                      ? 'Trading engine & live data synchronized.'
                                      : 'Live prices and orders paused. Check network.',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Retry Button (When Offline)
                          if (!_isBackOnline)
                            InkWell(
                              onTap: connectivity.isChecking
                                  ? null
                                  : () {
                                      ref
                                          .read(connectivityProvider.notifier)
                                          .checkConnection();
                                    },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.loss.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.loss.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: connectivity.isChecking
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.refresh_rounded,
                                            size: 13,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Retry',
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standalone Fullscreen or In-line Network Error Card
class NetworkErrorView extends ConsumerWidget {
  final VoidCallback? onRetry;
  final String? customMessage;

  const NetworkErrorView({
    super.key,
    this.onRetry,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.loss.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.loss.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: AppColors.loss,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Network Error',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              customMessage ??
                  'Unable to connect to FXAsian servers. Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: connectivity.isChecking
                  ? null
                  : (onRetry ??
                      () => ref
                          .read(connectivityProvider.notifier)
                          .checkConnection()),
              icon: connectivity.isChecking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                connectivity.isChecking ? 'Connecting...' : 'Retry Connection',
                style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPrimary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

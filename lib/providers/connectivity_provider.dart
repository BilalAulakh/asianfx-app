import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectivityState {
  final bool isConnected;
  final bool isChecking;
  final bool wasDisconnected;
  final DateTime? lastChecked;

  const ConnectivityState({
    required this.isConnected,
    this.isChecking = false,
    this.wasDisconnected = false,
    this.lastChecked,
  });

  ConnectivityState copyWith({
    bool? isConnected,
    bool? isChecking,
    bool? wasDisconnected,
    DateTime? lastChecked,
  }) {
    return ConnectivityState(
      isConnected: isConnected ?? this.isConnected,
      isChecking: isChecking ?? this.isChecking,
      wasDisconnected: wasDisconnected ?? this.wasDisconnected,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

class ConnectivityNotifier extends StateNotifier<ConnectivityState> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityNotifier() : super(const ConnectivityState(isConnected: true)) {
    _init();
  }

  void _init() {
    // Listen to device connectivity hardware changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _evaluateConnection(results);
    });

    // Check initial connectivity status
    checkConnection();
  }

  Future<void> checkConnection() async {
    state = state.copyWith(isChecking: true);
    try {
      final results = await _connectivity.checkConnectivity();
      await _evaluateConnection(results);
    } catch (_) {
      // Fallback
      state = state.copyWith(
        isConnected: false,
        isChecking: false,
        wasDisconnected: true,
        lastChecked: DateTime.now(),
      );
    }
  }

  Future<void> _evaluateConnection(List<ConnectivityResult> results) async {
    final hasHardwareLink = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn ||
        r == ConnectivityResult.other);

    if (!hasHardwareLink) {
      state = state.copyWith(
        isConnected: false,
        isChecking: false,
        wasDisconnected: true,
        lastChecked: DateTime.now(),
      );
      return;
    }

    // If hardware is connected, verify actual internet reachability (DNS lookup)
    final bool actuallyConnected = await _verifyInternetAccess();

    state = state.copyWith(
      isConnected: actuallyConnected,
      isChecking: false,
      wasDisconnected: !actuallyConnected ? true : state.wasDisconnected,
      lastChecked: DateTime.now(),
    );
  }

  Future<bool> _verifyInternetAccess() async {
    if (kIsWeb) {
      // dart:io is unavailable on Web, rely on navigator connectivity
      return true;
    }

    try {
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      // Fallback: try alternative high-availability host
      try {
        final lookupBackup = await InternetAddress.lookup('cloudflare.com')
            .timeout(const Duration(seconds: 3));
        return lookupBackup.isNotEmpty && lookupBackup[0].rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  void markOnlineAcknowledged() {
    state = state.copyWith(wasDisconnected: false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityState>((ref) {
  return ConnectivityNotifier();
});

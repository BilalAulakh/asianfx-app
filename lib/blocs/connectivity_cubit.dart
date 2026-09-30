import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

class ConnectivityCubit extends Cubit<ConnectivityState> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityCubit() : super(const ConnectivityState(isConnected: true)) {
    _init();
  }

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _evaluateConnection(results);
    });
    checkConnection();
  }

  Future<void> checkConnection() async {
    emit(state.copyWith(isChecking: true));
    try {
      final results = await _connectivity.checkConnectivity();
      await _evaluateConnection(results);
    } catch (_) {
      emit(state.copyWith(
        isConnected: false,
        isChecking: false,
        wasDisconnected: true,
        lastChecked: DateTime.now(),
      ));
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
      emit(state.copyWith(
        isConnected: false,
        isChecking: false,
        wasDisconnected: true,
        lastChecked: DateTime.now(),
      ));
      return;
    }

    final bool actuallyConnected = await _verifyInternetAccess();

    emit(state.copyWith(
      isConnected: actuallyConnected,
      isChecking: false,
      wasDisconnected: !actuallyConnected ? true : state.wasDisconnected,
      lastChecked: DateTime.now(),
    ));
  }

  Future<bool> _verifyInternetAccess() async {
    if (kIsWeb) {
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
    emit(state.copyWith(wasDisconnected: false));
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}

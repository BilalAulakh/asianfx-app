import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// TRON address checks. A format check ("T" + 33 Base58 characters) does not
/// catch a mistyped character; the Base58Check checksum does. Wallets refuse to
/// send to an address whose checksum fails, so such an address must never be
/// configured as a company deposit address.
class TronAddress {
  TronAddress._();

  static const _alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  static final RegExp _format = RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$');

  /// "T" + 33 Base58 characters. Cheap, but does not detect typos.
  static bool hasValidFormat(String raw) => _format.hasMatch(raw.trim());

  /// Full Base58Check validation: 25 bytes, 0x41 prefix, double-SHA256 checksum.
  static bool isValid(String raw) {
    final address = raw.trim();
    if (!hasValidFormat(address)) return false;
    final bytes = _base58Decode(address);
    if (bytes == null || bytes.length != 25 || bytes[0] != 0x41) return false;
    final body = bytes.sublist(0, 21);
    final hash = sha256.convert(sha256.convert(body).bytes).bytes;
    for (var i = 0; i < 4; i++) {
      if (hash[i] != bytes[21 + i]) return false;
    }
    return true;
  }

  static Uint8List? _base58Decode(String input) {
    var value = BigInt.zero;
    final base = BigInt.from(58);
    for (final ch in input.split('')) {
      final digit = _alphabet.indexOf(ch);
      if (digit < 0) return null;
      value = value * base + BigInt.from(digit);
    }
    final out = <int>[];
    while (value > BigInt.zero) {
      out.add((value & BigInt.from(0xff)).toInt());
      value = value >> 8;
    }
    for (var i = 0; i < input.length && input[i] == '1'; i++) {
      out.add(0);
    }
    return Uint8List.fromList(out.reversed.toList());
  }
}

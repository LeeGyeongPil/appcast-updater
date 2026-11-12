/// Ed25519 keys in the formats Sparkle uses.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;

import 'errors.dart';

Uint8List _decodeBase64(String text, String what) {
  try {
    return Uint8List.fromList(base64.decode(text.trim()));
  } on FormatException {
    throw KeyFormatException('$what is not valid base64');
  }
}

/// A 32-byte Ed25519 public key (`SUPublicEDKey` in Sparkle's Info.plist).
class EdPublicKey {
  EdPublicKey(List<int> bytes) : bytes = Uint8List.fromList(bytes) {
    if (this.bytes.length != 32) {
      throw KeyFormatException(
          'a public key must be 32 bytes, got ${this.bytes.length}');
    }
  }

  /// Parses the base64 text of `SUPublicEDKey`.
  factory EdPublicKey.fromBase64(String text) =>
      EdPublicKey(_decodeBase64(text, 'the public key'));

  final Uint8List bytes;

  String toBase64() => base64.encode(bytes);

  cg.SimplePublicKey toCryptography() =>
      cg.SimplePublicKey(bytes, type: cg.KeyPairType.ed25519);

  @override
  bool operator ==(Object other) =>
      other is EdPublicKey && other.toBase64() == toBase64();

  @override
  int get hashCode => toBase64().hashCode;
}

/// A private key read from a Sparkle key file.
///
/// Two formats exist: a 32-byte seed (Sparkle 2 `generate_keys`) and the
/// older 96-byte format (64-byte expanded key followed by the 32-byte public
/// key). The legacy format can verify and yield the public key but cannot
/// sign yet ([isLegacy]).
class EdPrivateKey {
  EdPrivateKey._(this._seed, this._legacyPublic);

  /// Builds a key from a 32-byte seed.
  factory EdPrivateKey.fromSeed(List<int> seed) {
    if (seed.length != 32) {
      throw KeyFormatException('a seed must be 32 bytes, got ${seed.length}');
    }
    return EdPrivateKey._(Uint8List.fromList(seed), null);
  }

  /// Parses the base64 text of a key file (32 or 96 bytes).
  factory EdPrivateKey.fromKeyFile(String content) {
    final raw = _decodeBase64(content, 'the key file');
    if (raw.length == 32) return EdPrivateKey._(raw, null);
    if (raw.length == 96) {
      return EdPrivateKey._(null, EdPublicKey(raw.sublist(64)));
    }
    throw KeyFormatException(
        'a key file must hold 32 or 96 bytes of base64, got ${raw.length}');
  }

  final Uint8List? _seed;
  final EdPublicKey? _legacyPublic;

  /// True for the 96-byte format.
  bool get isLegacy => _seed == null;

  /// The seed, or null for a legacy key.
  Uint8List? get seed => _seed;

  /// The base64 text to store in a key file.
  String toKeyFileText() =>
      base64.encode(_seed ?? (throw LegacyKeySigningUnsupported()));

  /// Derives the public key.
  Future<EdPublicKey> publicKey() async {
    final legacy = _legacyPublic;
    if (legacy != null) return legacy;
    final pair = await cg.Ed25519().newKeyPairFromSeed(_seed!);
    return EdPublicKey((await pair.extractPublicKey()).bytes);
  }

  /// Key pair for the `cryptography` package. Throws
  /// [LegacyKeySigningUnsupported] for a legacy key.
  Future<cg.SimpleKeyPair> toKeyPair() async {
    final seed = _seed;
    if (seed == null) throw LegacyKeySigningUnsupported();
    return cg.Ed25519().newKeyPairFromSeed(seed);
  }
}

/// A freshly generated key pair.
class EdKeyPair {
  EdKeyPair(this.privateKey, this.publicKey);

  /// Generates a new pair from a cryptographically secure random seed. Pass
  /// [random] only in tests.
  static Future<EdKeyPair> generate({Random? random}) async {
    final rng = random ?? Random.secure();
    final seed = List<int>.generate(32, (_) => rng.nextInt(256));
    final key = EdPrivateKey.fromSeed(seed);
    return EdKeyPair(key, await key.publicKey());
  }

  final EdPrivateKey privateKey;
  final EdPublicKey publicKey;
}

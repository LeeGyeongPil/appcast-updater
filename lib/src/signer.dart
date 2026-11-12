/// Signing and signature checking (plain Ed25519 over the raw bytes, exactly
/// what Sparkle's `sign_update` does).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cg;

import 'keys.dart';

/// Signs [data] and returns the 64-byte signature as base64.
///
/// Throws [LegacyKeySigningUnsupported] for a legacy 96-byte key.
Future<String> signBytes(List<int> data, EdPrivateKey key) async {
  final pair = await key.toKeyPair();
  final sig = await cg.Ed25519().sign(data, keyPair: pair);
  return base64.encode(sig.bytes);
}

/// Checks a base64 signature over [data]. Returns false for a wrong or
/// malformed signature.
Future<bool> verifyBytes(
    List<int> data, String signatureBase64, EdPublicKey key) async {
  final Uint8List sig;
  try {
    sig = Uint8List.fromList(base64.decode(signatureBase64.trim()));
  } on FormatException {
    return false;
  }
  if (sig.length != 64) return false;
  return cg.Ed25519().verify(data,
      signature: cg.Signature(sig, publicKey: key.toCryptography()));
}

/// The result of signing a file.
class SparkleSignature {
  SparkleSignature(this.signature, this.length);

  /// Base64 Ed25519 signature.
  final String signature;

  /// File size in bytes.
  final int length;

  /// The same text Sparkle's `sign_update` prints, ready to paste into an
  /// `<enclosure>` element.
  String toSparkleAttributes() =>
      'sparkle:edSignature="$signature" length="$length"';
}

/// Signs the whole file. The file is read into memory.
Future<SparkleSignature> signFile(File file, EdPrivateKey key) async {
  final bytes = await file.readAsBytes();
  return SparkleSignature(await signBytes(bytes, key), bytes.length);
}

/// Checks a downloaded update file before anything installs it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'appcast.dart';
import 'errors.dart';
import 'keys.dart';
import 'signer.dart';
import 'version.dart';

/// Verifies a file against its appcast item.
///
/// Order: size (without reading the file), signature, `au:sha256`, then the
/// downgrade rule. The first failure throws [UpdateVerificationException].
class UpdateVerifier {
  UpdateVerifier(this.publicKey, {this.allowUnsigned = false});

  /// The pinned `SUPublicEDKey`.
  final EdPublicKey publicKey;

  /// Accept items without `sparkle:edSignature`. Off by default; turning it
  /// on leaves only the optional sha256 as protection.
  final bool allowUnsigned;

  /// Verifies [file] for [item]; [currentVersion] is the installed version.
  Future<void> verifyFile(File file, AppcastItem item,
      {required String currentVersion}) async {
    final enc = item.enclosure;
    final size = await file.length();
    if (size != enc.length) {
      throw UpdateVerificationException(VerifyFailure.lengthMismatch,
          'file has $size bytes but the feed declares ${enc.length}');
    }
    final bytes = await file.readAsBytes();
    final sig = enc.edSignature;
    if (sig == null) {
      if (!allowUnsigned) {
        throw UpdateVerificationException(VerifyFailure.signatureMissing,
            'the feed item has no sparkle:edSignature');
      }
    } else {
      _checkSignatureShape(sig);
      if (!await verifyBytes(bytes, sig, publicKey)) {
        throw UpdateVerificationException(VerifyFailure.signatureInvalid,
            'the signature does not match the file');
      }
    }
    final expected = enc.sha256;
    if (expected != null) {
      final actual = crypto.sha256.convert(bytes).toString();
      if (actual != expected) {
        throw UpdateVerificationException(VerifyFailure.sha256Mismatch,
            'sha256 is $actual but the feed declares $expected');
      }
    }
    if (compareVersions(item.version, currentVersion) <= 0) {
      throw UpdateVerificationException(VerifyFailure.downgrade,
          'version ${item.version} is not newer than $currentVersion');
    }
  }

  void _checkSignatureShape(String sig) {
    try {
      if (base64.decode(sig).length == 64) return;
    } on FormatException {
      // fall through
    }
    throw UpdateVerificationException(VerifyFailure.signatureMalformed,
        'the signature is not base64 of 64 bytes');
  }
}

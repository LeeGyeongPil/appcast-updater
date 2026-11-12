/// Signed feeds (Sparkle 2.9+ `SURequireSignedFeed`): the feed text is
/// followed by a comment holding the signature of everything before it.
///
///     ...feed bytes...
///     <!-- sparkle-signatures:
///     edSignature: BASE64
///     length: N
///     -->
///
/// The signature covers the original bytes before the comment. Never parse
/// and re-serialize the feed before verifying it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';
import 'keys.dart';
import 'signer.dart';

final Uint8List _marker =
    Uint8List.fromList(utf8.encode('<!-- sparkle-signatures:\n'));

/// Signing, verifying and stripping the signature tail.
class SignedFeed {
  SignedFeed._();

  static int _lastMarker(Uint8List raw) {
    for (var i = raw.length - _marker.length; i >= 0; i--) {
      var hit = true;
      for (var j = 0; j < _marker.length; j++) {
        if (raw[i + j] != _marker[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return i;
    }
    return -1;
  }

  /// True if [raw] ends with a signature comment.
  static bool hasSignature(List<int> raw) =>
      _lastMarker(Uint8List.fromList(raw)) >= 0;

  /// The feed bytes without the signature comment (or [raw] if there is none).
  static Uint8List strip(List<int> raw) {
    var bytes = Uint8List.fromList(raw);
    // Repeat so that a feed carrying several comments ends up with none.
    for (var at = _lastMarker(bytes); at >= 0; at = _lastMarker(bytes)) {
      bytes = Uint8List.sublistView(bytes, 0, at);
    }
    return bytes;
  }

  /// Returns [raw] with exactly one signature comment for [key]. An existing
  /// comment is replaced. The body ends with a newline.
  static Future<Uint8List> sign(List<int> raw, EdPrivateKey key) async {
    var body = strip(raw);
    if (body.isEmpty || body.last != 0x0a) {
      body = Uint8List.fromList([...body, 0x0a]);
    }
    final sig = await signBytes(body, key);
    final tail = utf8.encode(
        '<!-- sparkle-signatures:\nedSignature: $sig\nlength: ${body.length}\n-->\n');
    return Uint8List.fromList([...body, ...tail]);
  }

  /// Checks the signature comment of [raw] against [key] and returns the
  /// signed feed bytes (without the comment). Throws
  /// [FeedSignatureException] if there is no comment, it is malformed, the
  /// declared length differs or the signature does not match.
  static Future<Uint8List> verify(List<int> raw, EdPublicKey key) async {
    final bytes = Uint8List.fromList(raw);
    final at = _lastMarker(bytes);
    if (at < 0) {
      throw FeedSignatureException('the feed has no sparkle-signatures comment',
          reason: FeedFailure.missing);
    }
    final body = Uint8List.sublistView(bytes, 0, at);
    final String block;
    try {
      block = utf8.decode(bytes.sublist(at + _marker.length));
    } on FormatException {
      throw FeedSignatureException('the signature comment is not valid UTF-8');
    }
    String? signature;
    int? length;
    var closed = false;
    for (final line in const LineSplitter().convert(block)) {
      if (closed) {
        if (line.trim().isNotEmpty) {
          throw FeedSignatureException(
              'unexpected data after the signature comment');
        }
        continue;
      }
      if (line.startsWith('edSignature:')) {
        signature = line.substring('edSignature:'.length).trim();
      } else if (line.startsWith('length:')) {
        length = int.tryParse(line.substring('length:'.length).trim());
      } else if (line.trim() == '-->') {
        closed = true;
      } else if (line.trim().isNotEmpty) {
        throw FeedSignatureException(
            'unexpected line in the signature comment');
      }
    }
    if (!closed || signature == null || length == null) {
      throw FeedSignatureException('the signature comment is incomplete');
    }
    if (length != body.length) {
      throw FeedSignatureException(
          'the feed has ${body.length} bytes before the signature but '
          'the comment declares $length',
          reason: FeedFailure.lengthMismatch);
    }
    if (!await verifyBytes(body, signature, key)) {
      throw FeedSignatureException('the feed signature does not match',
          reason: FeedFailure.signatureInvalid);
    }
    return body;
  }
}

// Compatibility with Sparkle 2.10.1 and with RFC 8032.
// How the Sparkle vectors were made: test/vectors/README.md
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:test/test.dart';

Uint8List hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ]);

void main() {
  group('RFC 8032 section 7.1', () {
    // https://www.rfc-editor.org/rfc/rfc8032#section-7.1 (public test vectors)
    final vectors = [
      (
        'TEST 1 (empty message)',
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
        '',
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      ),
      (
        'TEST 2 (one byte)',
        '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
        '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
        '72',
        '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
      ),
    ];
    for (final (name, seed, pub, msg, sig) in vectors) {
      test(name, () async {
        final key = EdPrivateKey.fromSeed(hex(seed));
        expect(base64.decode((await key.publicKey()).toBase64()), hex(pub));
        final signature = await signBytes(hex(msg), key);
        expect(base64.decode(signature), hex(sig));
        expect(await verifyBytes(hex(msg), signature, EdPublicKey(hex(pub))),
            isTrue);
      });
    }
  });

  group('Sparkle 2.10.1 sign_update', () {
    final vector =
        jsonDecode(File('test/vectors/sparkle-2.10.1.json').readAsStringSync())
            as Map<String, dynamic>;
    // Test-only seed: bytes 0..31 (not a secret).
    final key = EdPrivateKey.fromSeed(List.generate(32, (i) => i));
    // 1,000,000 bytes, byte i is i % 251.
    final message = Uint8List.fromList(List.generate(1000000, (i) => i % 251));
    final line = vector['message_sign_update_output'] as String;

    // 벡터는 바이트 단위로 비교하므로 체크아웃이 줄바꿈을 CRLF 로 바꾸면 안 된다
    // (Windows 러너의 core.autocrlf=true). .gitattributes 가 이를 막는다.
    test('the feed vectors were checked out without CRLF', () {
      for (final name in ['feed-body.xml', 'signed-feed.xml']) {
        final bytes = File('test/vectors/$name').readAsBytesSync();
        expect(bytes.contains(13), isFalse,
            reason: 'test/vectors/$name has CR bytes; check .gitattributes');
      }
    });

    test('the vector file says Sparkle accepted both signatures', () {
      expect(vector['sparkle_version'], '2.10.1');
      expect(vector['message_verify_rc'], 0);
      expect(vector['feed_verify_rc'], 0);
      expect(vector['feed_tampered_verify_rc'], isNot(0));
    });

    test('the public key from the seed is the one Sparkle side derived',
        () async {
      expect((await key.publicKey()).toBase64(), vector['public_key']);
    });

    test('Dart verifies the signature Sparkle made', () async {
      final sig = RegExp(r'edSignature="([^"]+)"').firstMatch(line)!.group(1)!;
      final pub = EdPublicKey.fromBase64(vector['public_key'] as String);
      expect(await verifyBytes(message, sig, pub), isTrue);
      final changed = Uint8List.fromList(message)..[12345] ^= 1;
      expect(await verifyBytes(changed, sig, pub), isFalse);
    });

    test('Dart prints the same line as sign_update, character for character',
        () async {
      final dir = Directory.systemTemp.createTempSync('appcast_compat_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/message.bin')..writeAsBytesSync(message);
      expect((await signFile(file, key)).toSparkleAttributes(), line);
    });

    test('Dart accepts the signed feed that Sparkle accepted (rc 0)', () async {
      final raw = File('test/vectors/signed-feed.xml').readAsBytesSync();
      final pub = EdPublicKey.fromBase64(vector['public_key'] as String);
      final body = await SignedFeed.verify(raw, pub);
      expect(body.length, vector['feed_length']);
      expect(body, File('test/vectors/feed-body.xml').readAsBytesSync());
      expect(() => SignedFeed.verify(Uint8List.fromList(raw)..[100] ^= 1, pub),
          throwsA(isA<FeedSignatureException>()));
    });

    test('Dart signs the feed body with the same signature Sparkle made',
        () async {
      final body = File('test/vectors/feed-body.xml').readAsBytesSync();
      expect(await signBytes(body, key), vector['feed_signature']);
      final ours = await SignedFeed.sign(body, key);
      expect(ours, File('test/vectors/signed-feed.xml').readAsBytesSync());
    });
  });
}

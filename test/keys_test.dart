import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:test/test.dart';

String b64(List<int> bytes) => base64.encode(bytes);

void main() {
  group('EdPublicKey', () {
    test('round trips base64', () async {
      final pub = await testSeedKey().publicKey();
      expect(EdPublicKey.fromBase64(pub.toBase64()), pub);
      expect(EdPublicKey.fromBase64('  ${pub.toBase64()}\n'), pub);
    });

    test('wrong size or bad base64 is a KeyFormatException', () {
      expect(() => EdPublicKey.fromBase64(b64(List.filled(31, 1))),
          throwsA(isA<KeyFormatException>()));
      expect(() => EdPublicKey.fromBase64('%%%'),
          throwsA(isA<KeyFormatException>()));
    });
  });

  group('EdPrivateKey.fromKeyFile', () {
    test('32 bytes is a seed key that can sign', () async {
      final key =
          EdPrivateKey.fromKeyFile('${b64(List.generate(32, (i) => i))}\n');
      expect(key.isLegacy, isFalse);
      expect(key.seed, hasLength(32));
      expect(await signBytes([1, 2, 3], key), isNotEmpty);
    });

    test('96 bytes is a legacy key: public key is the last 32 bytes', () async {
      final raw = List.generate(96, (i) => i + 100);
      final key = EdPrivateKey.fromKeyFile(b64(raw));
      expect(key.isLegacy, isTrue);
      expect(key.seed, isNull);
      expect(
          base64.decode((await key.publicKey()).toBase64()), raw.sublist(64));
    });

    test('signing with a legacy key throws LegacyKeySigningUnsupported',
        () async {
      final key = EdPrivateKey.fromKeyFile(b64(List.filled(96, 7)));
      await expectLater(
          signBytes([1], key), throwsA(isA<LegacyKeySigningUnsupported>()));
      expect(() => key.toKeyFileText(),
          throwsA(isA<LegacyKeySigningUnsupported>()));
    });

    test('other sizes and non-base64 are KeyFormatException', () {
      for (final bad in [
        b64(List.filled(64, 1)),
        b64(List.filled(31, 1)),
        '',
        'not base64!',
        '-----BEGIN'
      ]) {
        expect(() => EdPrivateKey.fromKeyFile(bad),
            throwsA(isA<KeyFormatException>()),
            reason: bad);
      }
    });

    test('fromSeed checks the size', () {
      expect(() => EdPrivateKey.fromSeed([1, 2]),
          throwsA(isA<KeyFormatException>()));
    });
  });

  group('EdKeyPair.generate', () {
    test('makes a working pair, and two pairs differ', () async {
      final a = await EdKeyPair.generate();
      final b = await EdKeyPair.generate();
      expect(a.publicKey, isNot(b.publicKey));
      final sig = await signBytes([9, 9], a.privateKey);
      expect(await verifyBytes([9, 9], sig, a.publicKey), isTrue);
      expect(await verifyBytes([9, 9], sig, b.publicKey), isFalse);
    });

    test('a seeded Random gives the same key (test hook)', () async {
      final a = await EdKeyPair.generate(random: Random(1));
      final b = await EdKeyPair.generate(random: Random(1));
      expect(a.publicKey, b.publicKey);
    });

    test('key file text can be read back', () async {
      final pair = await EdKeyPair.generate();
      final again = EdPrivateKey.fromKeyFile(pair.privateKey.toKeyFileText());
      expect(await again.publicKey(), pair.publicKey);
    });
  });

  group('verifyBytes', () {
    test('malformed signatures are false, not exceptions', () async {
      final pub = await testSeedKey().publicKey();
      expect(await verifyBytes([1], 'nope!', pub), isFalse);
      expect(await verifyBytes([1], b64(Uint8List(10)), pub), isFalse);
    });
  });
}

EdPrivateKey testSeedKey() =>
    EdPrivateKey.fromSeed(List.generate(32, (i) => i + 3));

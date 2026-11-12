import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

import 'support.dart';

class Release {
  Release(this.file, this.item, this.publicKey);
  final File file;
  final AppcastItem item;
  final EdPublicKey publicKey;
}

/// Writes a file and builds the item that describes it (really signed).
Future<Release> makeRelease(
  Directory dir, {
  String version = '130',
  int size = 4096,
  bool sign = true,
  bool withSha = false,
  String? url,
}) async {
  final key = testKey();
  final file = File('${dir.path}/Example-$version.exe')
    ..writeAsBytesSync(bytesOf(size));
  final sig = await signFile(file, key);
  final item = AppcastItem(
    version: version,
    enclosure: Enclosure(
      url: url ?? file.uri.toString(),
      length: sig.length,
      edSignature: sign ? sig.signature : null,
      sha256: withSha
          ? crypto.sha256.convert(file.readAsBytesSync()).toString()
          : null,
    ),
  );
  return Release(file, item, await key.publicKey());
}

Matcher failsWith(VerifyFailure reason) =>
    throwsA(isA<UpdateVerificationException>()
        .having((e) => e.reason, 'reason', reason));

void main() {
  group('UpdateVerifier', () {
    test('accepts an untouched, newer, signed file', () async {
      final r = await makeRelease(tempDir(), withSha: true);
      await UpdateVerifier(r.publicKey)
          .verifyFile(r.file, r.item, currentVersion: '120');
    });

    test('one changed byte: signatureInvalid', () async {
      final r = await makeRelease(tempDir());
      final bytes = r.file.readAsBytesSync()..[1000] ^= 1;
      r.file.writeAsBytesSync(bytes);
      await expectLater(
          UpdateVerifier(r.publicKey)
              .verifyFile(r.file, r.item, currentVersion: '120'),
          failsWith(VerifyFailure.signatureInvalid));
    });

    test('wrong public key: signatureInvalid', () async {
      final r = await makeRelease(tempDir());
      final other = await testKey(9).publicKey();
      await expectLater(
          UpdateVerifier(other)
              .verifyFile(r.file, r.item, currentVersion: '120'),
          failsWith(VerifyFailure.signatureInvalid));
    });

    test('different length: lengthMismatch before the content is read',
        () async {
      final r = await makeRelease(tempDir());
      // Same first bytes, one byte longer. If the verifier read the content
      // first it would report an invalid signature instead.
      r.file.writeAsBytesSync([...r.file.readAsBytesSync(), 0]);
      await expectLater(
          UpdateVerifier(r.publicKey)
              .verifyFile(r.file, r.item, currentVersion: '120'),
          failsWith(VerifyFailure.lengthMismatch));
    });

    test('shorter file: lengthMismatch', () async {
      final r = await makeRelease(tempDir());
      r.file.writeAsBytesSync(r.file.readAsBytesSync().sublist(0, 100));
      await expectLater(
          UpdateVerifier(r.publicKey)
              .verifyFile(r.file, r.item, currentVersion: '120'),
          failsWith(VerifyFailure.lengthMismatch));
    });

    test('sha256 differs: sha256Mismatch', () async {
      final r = await makeRelease(tempDir(), withSha: true);
      final wrong = AppcastItem(
        version: r.item.version,
        enclosure: Enclosure(
          url: r.item.enclosure.url,
          length: r.item.enclosure.length,
          edSignature: r.item.enclosure.edSignature,
          sha256: '0' * 64,
        ),
      );
      await expectLater(
          UpdateVerifier(r.publicKey)
              .verifyFile(r.file, wrong, currentVersion: '120'),
          failsWith(VerifyFailure.sha256Mismatch));
    });

    test('no signature: signatureMissing', () async {
      final r = await makeRelease(tempDir(), sign: false);
      await expectLater(
          UpdateVerifier(r.publicKey)
              .verifyFile(r.file, r.item, currentVersion: '120'),
          failsWith(VerifyFailure.signatureMissing));
    });

    test('allowUnsigned accepts a missing signature but still checks sha256',
        () async {
      final r = await makeRelease(tempDir(), sign: false, withSha: true);
      await UpdateVerifier(r.publicKey, allowUnsigned: true)
          .verifyFile(r.file, r.item, currentVersion: '120');
      r.file.writeAsBytesSync(bytesOf(4096, 1));
      await expectLater(
          UpdateVerifier(r.publicKey, allowUnsigned: true)
              .verifyFile(r.file, r.item, currentVersion: '120'),
          failsWith(VerifyFailure.sha256Mismatch));
    });

    test('signature that is not 64 bytes of base64: signatureMalformed',
        () async {
      final r = await makeRelease(tempDir());
      for (final bad in ['not base64!!', base64.encode(List.filled(10, 1))]) {
        final item = AppcastItem(
          version: '130',
          enclosure: Enclosure(
              url: r.item.enclosure.url,
              length: r.item.enclosure.length,
              edSignature: bad),
        );
        await expectLater(
            UpdateVerifier(r.publicKey)
                .verifyFile(r.file, item, currentVersion: '120'),
            failsWith(VerifyFailure.signatureMalformed));
      }
    });

    test('same or older version: downgrade', () async {
      final r = await makeRelease(tempDir(), version: '130');
      for (final current in ['130', '140']) {
        await expectLater(
            UpdateVerifier(r.publicKey)
                .verifyFile(r.file, r.item, currentVersion: current),
            failsWith(VerifyFailure.downgrade));
      }
    });

    test(
        'a signed but older file is still a downgrade (signature alone is not enough)',
        () async {
      final r = await makeRelease(tempDir(), version: '110');
      await expectLater(
          UpdateVerifier(r.publicKey)
              .verifyFile(r.file, r.item, currentVersion: '120'),
          failsWith(VerifyFailure.downgrade));
    });
  });

  group('Updater.downloadAndVerify (file://)', () {
    test('verified file gets its final name, no partial file stays', () async {
      final src = tempDir();
      final dst = tempDir();
      final r = await makeRelease(src);
      final updater = Updater(
          feedUrl: src.uri.resolve('appcast.xml'),
          publicKey: r.publicKey,
          currentVersion: '120',
          os: 'windows-x64');
      final file = await updater.downloadAndVerify(r.item, into: dst);
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), r.file.readAsBytesSync());
      expect(dst.listSync().map((e) => e.uri.pathSegments.last),
          ['Example-130.exe']);
    });

    test('a failed check leaves nothing behind', () async {
      final src = tempDir();
      final dst = tempDir();
      final r = await makeRelease(src);
      r.file.writeAsBytesSync(r.file.readAsBytesSync()..[5] ^= 1);
      final updater = Updater(
          feedUrl: src.uri.resolve('appcast.xml'),
          publicKey: r.publicKey,
          currentVersion: '120',
          os: 'windows-x64');
      await expectLater(updater.downloadAndVerify(r.item, into: dst),
          failsWith(VerifyFailure.signatureInvalid));
      expect(dst.listSync(), isEmpty);
    });

    test('a file longer than declared is aborted and not kept', () async {
      final src = tempDir();
      final dst = tempDir();
      final r = await makeRelease(src);
      // the feed says 4096 bytes but the server has more
      r.file.writeAsBytesSync(bytesOf(4096 * 3));
      final updater = Updater(
          feedUrl: src.uri.resolve('appcast.xml'),
          publicKey: r.publicKey,
          currentVersion: '120',
          os: 'windows-x64');
      await expectLater(updater.downloadAndVerify(r.item, into: dst),
          throwsA(isA<DownloadException>()));
      expect(dst.listSync(), isEmpty);
    });

    test('a hostile file name in the URL cannot leave the download folder',
        () async {
      final src = tempDir();
      final dst = Directory('${tempDir().path}/inner')..createSync();
      final r = await makeRelease(src);
      final item = AppcastItem(
        version: '130',
        enclosure: Enclosure(
          url: r.file.uri.toString(),
          length: r.item.enclosure.length,
          edSignature: r.item.enclosure.edSignature,
        ),
      );
      final file = await Updater(
              feedUrl: src.uri.resolve('a.xml'),
              publicKey: r.publicKey,
              currentVersion: '120',
              os: 'windows-x64')
          .downloadAndVerify(item, into: dst);
      expect(file.parent.path, dst.path);
    });
  });

  group('http', () {
    test('http:// is refused unless allowed', () async {
      final fetcher = Fetcher.auto();
      await expectLater(
          fetcher.fetchBytes(
              Uri.parse('http://downloads.example.com/appcast.xml')),
          refusesPlainHttp);
      await expectLater(
          fetcher.download(Uri.parse('http://downloads.example.com/a.exe'),
              File('${tempDir().path}/a.exe'),
              maxBytes: 10),
          refusesPlainHttp);
    });

    test('unsupported schemes are refused', () async {
      await expectLater(
          Fetcher.auto().fetchBytes(Uri.parse('ftp://downloads.example.com/a')),
          throwsA(isA<DownloadException>()));
    });

    test('Updater.check with an http feed URL fails before any signature work',
        () async {
      final updater = Updater(
          feedUrl: Uri.parse('http://downloads.example.com/appcast.xml'),
          publicKey: await testKey().publicKey(),
          currentVersion: '1',
          os: 'windows-x64');
      await expectLater(updater.check(), refusesPlainHttp);
    });

    test(
        'allowInsecureHttp downloads from a local server, still capped by length',
        () async {
      HttpServer server;
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      } on SocketException {
        markTestSkipped('cannot open a local socket in this environment');
        return;
      }
      addTearDown(() => server.close(force: true));
      final payload = bytesOf(5000);
      unawaited(server.forEach((req) async {
        req.response.add(payload);
        await req.response.close();
      }));
      final uri = Uri.parse('http://127.0.0.1:${server.port}/a.bin');
      final fetcher = Fetcher.auto(allowInsecureHttp: true);
      expect(await fetcher.fetchBytes(uri), payload);

      final dst = File('${tempDir().path}/a.bin');
      await expectLater(fetcher.download(uri, dst, maxBytes: 1000),
          throwsA(isA<DownloadException>()));
      expect(dst.existsSync(), isFalse);
      await fetcher.download(uri, dst, maxBytes: 5000);
      expect(dst.readAsBytesSync(), payload);
    });
  });

  group('Updater.check', () {
    test('a signed feed is verified, picked and parsed', () async {
      final dir = tempDir();
      final key = testKey();
      final feed = File('${dir.path}/appcast.xml')
        ..writeAsBytesSync(await SignedFeed.sign(
            utf8.encode(feedXml([itemXml(version: '130')])), key));
      final found = await Updater(
        feedUrl: feed.uri,
        publicKey: await key.publicKey(),
        currentVersion: '120',
        os: 'windows-x64',
        requireSignedFeed: true,
      ).check();
      expect(found.item!.version, '130');
      expect(found.feedWasSigned, isTrue);
    });

    test('an unsigned feed is refused when a signature is required', () async {
      final dir = tempDir();
      final feed = File('${dir.path}/appcast.xml')
        ..writeAsStringSync(feedXml([itemXml(version: '130')]));
      await expectLater(
          Updater(
            feedUrl: feed.uri,
            publicKey: await testKey().publicKey(),
            currentVersion: '120',
            os: 'windows-x64',
            requireSignedFeed: true,
          ).check(),
          throwsA(isA<FeedSignatureException>()
              .having((e) => e.reason, 'reason', FeedFailure.missing)));
    });

    test('a bad signature is refused even when signatures are optional',
        () async {
      final dir = tempDir();
      final key = testKey();
      final signed = await SignedFeed.sign(
          utf8.encode(feedXml([itemXml(version: '130')])), key);
      signed[40] ^= 1;
      final feed = File('${dir.path}/appcast.xml')..writeAsBytesSync(signed);
      await expectLater(
          Updater(
            feedUrl: feed.uri,
            publicKey: await key.publicKey(),
            currentVersion: '120',
            os: 'windows-x64',
          ).check(),
          throwsA(isA<FeedSignatureException>()));
    });

    test('an oversized feed is refused', () async {
      final dir = tempDir();
      final feed = File('${dir.path}/appcast.xml')
        ..writeAsBytesSync(bytesOf(2000));
      await expectLater(
          Updater(
            feedUrl: feed.uri,
            publicKey: await testKey().publicKey(),
            currentVersion: '120',
            os: 'windows-x64',
            maxFeedBytes: 1000,
          ).check(),
          throwsA(isA<DownloadException>()));
    });
  });
}

/// The refusal must come from the scheme rule itself, not from a failed
/// connection attempt (no packet is sent for a refused URL).
final Matcher refusesPlainHttp = throwsA(isA<DownloadException>()
    .having((e) => e.message, 'message', contains('refusing plain http')));

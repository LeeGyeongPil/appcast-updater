import 'dart:convert';
import 'dart:io';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:appcast_updater/src/cli/cli.dart';
import 'package:test/test.dart';

import 'support.dart';

class Result {
  Result(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
  @override
  String toString() => 'exit $code\nout: $out\nerr: $err';
}

Future<Result> cli(
  List<String> args, {
  Map<String, String> env = const {},
  String? stdin,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(
    args,
    out: out,
    err: err,
    env: env,
    stdin: stdin == null ? null : Stream.value(utf8.encode(stdin)),
  );
  return Result(code, out.toString(), err.toString());
}

void main() {
  group('release flow, end to end', () {
    late Directory dir;
    late String keyPath;
    late String keyText;
    late String feedPath;
    late String app1;
    late String app2;
    late EdPublicKey pub;

    String p(String name) => '${dir.path}/$name';

    setUp(() async {
      dir = tempDir();
      keyPath = p('release.key');
      feedPath = p('appcast.xml');
      app1 = p('Example-1.2.0-setup.exe');
      app2 = p('Example-1.3.0-setup.exe');
      File(app1).writeAsBytesSync(bytesOf(3000, 1));
      File(app2).writeAsBytesSync(bytesOf(4000, 2));
      final r = await cli(['keygen', '--out', keyPath]);
      expect(r.code, 0, reason: '$r');
      keyText = File(keyPath).readAsStringSync();
      pub = await EdPrivateKey.fromKeyFile(keyText).publicKey();
    });

    test('keygen writes a key file, prints the public key and the snippets',
        () async {
      final r = await cli(['keygen', '--out', p('second.key')]);
      expect(r.code, 0);
      final key =
          EdPrivateKey.fromKeyFile(File(p('second.key')).readAsStringSync());
      final printed = (await key.publicKey()).toBase64();
      expect(r.out, contains('SUPublicEDKey'));
      expect(r.out, contains('<string>$printed</string>'));
      expect(r.out, contains('EdDSAPub'));
      // the private key never appears on screen
      expect(r.out, isNot(contains(key.toKeyFileText())));
      if (!Platform.isWindows) {
        expect(File(p('second.key')).statSync().mode & 0x3f, 0,
            reason: 'group/other permissions');
      }
    });

    test('keygen refuses to overwrite an existing file', () async {
      final r = await cli(['keygen', '--out', keyPath]);
      expect(r.code, 1);
      expect(r.err, contains(keyPath));
      expect(File(keyPath).readAsStringSync(), keyText);
    });

    test('keygen into a missing folder fails with the path', () async {
      final r = await cli(['keygen', '--out', p('no/such/dir/x.key')]);
      expect(r.code, 1);
      expect(r.err, contains('no/such/dir/x.key'));
    });

    test('sign with the key from standard input prints the Sparkle line',
        () async {
      final r = await cli(['sign', app1, '--ed-key-file', '-'], stdin: keyText);
      expect(r.code, 0, reason: '$r');
      final line = r.out.trim();
      final m = RegExp(r'^sparkle:edSignature="([^"]+)" length="3000"$')
          .firstMatch(line);
      expect(m, isNotNull, reason: line);
      expect(await verifyBytes(File(app1).readAsBytesSync(), m!.group(1)!, pub),
          isTrue);
    });

    test('sign -p prints only the signature, and verify accepts it', () async {
      final r = await cli(['sign', app1, '--ed-key-file', keyPath, '-p']);
      expect(r.code, 0);
      final sig = r.out.trim();
      expect(sig, isNot(contains('length')));
      final ok =
          await cli(['verify', app1, sig, '--public-key', pub.toBase64()]);
      expect(ok.code, 0, reason: '$ok');
      final viaKey = await cli(['verify', app1, sig, '--ed-key-file', keyPath]);
      expect(viaKey.code, 0);
      final wrong =
          await cli(['verify', app2, sig, '--public-key', pub.toBase64()]);
      expect(wrong.code, 1);
      final bad =
          await cli(['verify', app1, 'nope!', '--public-key', pub.toBase64()]);
      expect(bad.code, 1);
    });

    Future<void> buildFeed() async {
      var r = await cli([
        'add',
        feedPath,
        '--file',
        app1,
        '--url',
        'https://downloads.example.com/a.exe',
        '--version',
        '120',
        '--short-version',
        '1.2.0',
        '--os',
        'windows-x64',
        '--ed-key-file',
        keyPath,
        '--title',
        'Example',
        '--pub-date',
        '2026-11-01T00:00:00Z',
      ]);
      expect(r.code, 0, reason: '$r');
      r = await cli([
        'add',
        feedPath,
        '--file',
        app2,
        '--url',
        'https://downloads.example.com/b.exe',
        '--version',
        '130',
        '--short-version',
        '1.3.0',
        '--os',
        'windows-x64',
        '--channel',
        'beta',
        '--phased-interval',
        '86400',
        '--ed-key-file',
        '-',
        '--pub-date',
        '2026-11-10T00:00:00Z',
      ], stdin: keyText);
      expect(r.code, 0, reason: '$r');
    }

    test(
        'add creates the feed, puts new items on top and fills signature and sha256',
        () async {
      await buildFeed();
      final feed = Appcast.parse(File(feedPath).readAsStringSync());
      expect(feed.title, 'Example');
      expect(feed.items.map((i) => i.version), ['130', '120']);
      final first = feed.items.last;
      expect(first.enclosure.length, 3000);
      expect(first.enclosure.sha256, hasLength(64));
      expect(
          await verifyBytes(
              File(app1).readAsBytesSync(), first.enclosure.edSignature!, pub),
          isTrue);
    });

    test('the same version and os is refused without --replace', () async {
      await buildFeed();
      final before = File(feedPath).readAsStringSync();
      final args = [
        'add',
        feedPath,
        '--file',
        app2,
        '--url',
        'https://downloads.example.com/b2.exe',
        '--version',
        '130',
        '--os',
        'windows-x64',
        '--ed-key-file',
        keyPath,
      ];
      final r = await cli(args);
      expect(r.code, 1);
      expect(r.err, contains('--replace'));
      expect(File(feedPath).readAsStringSync(), before);
      final again = await cli([...args, '--replace']);
      expect(again.code, 0, reason: '$again');
      final feed = Appcast.parse(File(feedPath).readAsStringSync());
      expect(feed.items, hasLength(2));
      expect(feed.items.first.enclosure.url,
          'https://downloads.example.com/b2.exe');
    });

    test('sign-feed, verify-feed, then a tampered feed fails', () async {
      await buildFeed();
      final signed =
          await cli(['sign-feed', feedPath, '--ed-key-file', keyPath]);
      expect(signed.code, 0, reason: '$signed');
      final ok =
          await cli(['verify-feed', feedPath, '--public-key', pub.toBase64()]);
      expect(ok.code, 0, reason: '$ok');

      final bytes = File(feedPath).readAsBytesSync();
      bytes[bytes.length ~/ 3] ^= 1;
      File(feedPath).writeAsBytesSync(bytes);
      final bad =
          await cli(['verify-feed', feedPath, '--public-key', pub.toBase64()]);
      expect(bad.code, 1);
      expect(bad.err, isNotEmpty);
    });

    test('verify-feed on an unsigned feed fails', () async {
      await buildFeed();
      final r = await cli(['verify-feed', feedPath, '--ed-key-file', keyPath]);
      expect(r.code, 1);
    });

    test('verify-feed reads file:// URLs', () async {
      await buildFeed();
      await cli(['sign-feed', feedPath, '--ed-key-file', keyPath]);
      final r = await cli([
        'verify-feed',
        File(feedPath).uri.toString(),
        '--ed-key-file',
        keyPath
      ]);
      expect(r.code, 0, reason: '$r');
    });

    test(
        'add to a signed feed removes the signature, warns, and --sign-feed keeps it',
        () async {
      await buildFeed();
      await cli(['sign-feed', feedPath, '--ed-key-file', keyPath]);
      final args = [
        'add',
        feedPath,
        '--file',
        app1,
        '--url',
        'https://downloads.example.com/c.exe',
        '--version',
        '140',
        '--ed-key-file',
        keyPath,
      ];
      final plain = await cli(args);
      expect(plain.code, 0, reason: '$plain');
      expect(plain.err, contains('sign-feed'));
      expect(
          SignedFeed.hasSignature(File(feedPath).readAsBytesSync()), isFalse);

      await cli(['sign-feed', feedPath, '--ed-key-file', keyPath]);
      final withSign = await cli(
          [...args.map((a) => a == '140' ? '150' : a), '--sign-feed']);
      expect(withSign.code, 0, reason: '$withSign');
      expect(withSign.err, isEmpty);
      await SignedFeed.verify(File(feedPath).readAsBytesSync(), pub);
    });

    test('check picks the update and explains every other item', () async {
      await buildFeed();
      final r = await cli([
        'check',
        feedPath,
        '--current',
        '100',
        '--os',
        'windows-x64',
        '--explain',
        '--now',
        '2026-11-12T00:00:00Z',
      ]);
      expect(r.code, 0, reason: '$r');
      expect(r.out, contains('Update available: 1.2.0 (120)'));
      expect(r.out, contains('1.3.0 (130)'));
      expect(r.out, contains('channel "beta" is not enabled'));
    });

    test('check --explain shows the phased rollout time', () async {
      await buildFeed();
      final r = await cli([
        'check',
        feedPath,
        '--current',
        '125',
        '--os',
        'windows-x64',
        '--channel',
        'beta',
        '--group',
        '5',
        '--explain',
        '--now',
        '2026-11-11T00:00:00Z',
      ]);
      expect(r.code, 0, reason: '$r');
      expect(r.out, contains('No update'));
      expect(r.out, contains('group 5'));
      expect(r.out, contains('2026-11-15T00:00:00.000Z'));
    });

    test('check without --explain stays short, wrong os is explained',
        () async {
      await buildFeed();
      final short = await cli(
          ['check', feedPath, '--current', '100', '--os', 'windows-x64']);
      expect(short.out, isNot(contains('not chosen')));
      final mac = await cli([
        'check',
        feedPath,
        '--current',
        '100',
        '--os',
        'macos',
        '--explain'
      ]);
      expect(mac.out, contains('No update'));
      expect(mac.out, contains('windows-x64'));
    });

    test('check works in Korean, with no English sentences', () async {
      await buildFeed();
      final r = await cli([
        'check',
        feedPath,
        '--current',
        '100',
        '--os',
        'windows-x64',
        '--explain',
        '--now',
        '2026-11-12T00:00:00Z',
        '--lang',
        'ko',
      ]);
      expect(r.code, 0, reason: '$r');
      expect(r.out, contains('받을 수 있는 업데이트: 1.2.0 (120)'));
      expect(r.out, contains('채널이 꺼져'));
      expect(r.out, isNot(contains('Update available')));
      expect(r.out, isNot(contains('not enabled')));
    });

    test('check on a signed feed still reads it', () async {
      await buildFeed();
      await cli(['sign-feed', feedPath, '--ed-key-file', keyPath]);
      final r = await cli(
          ['check', feedPath, '--current', '100', '--os', 'windows-x64']);
      expect(r.out, contains('1.2.0'));
    });

    test(
        'a file that cannot be written is reported with the path the user gave',
        () async {
      if (Platform.isWindows)
        return markTestSkipped('permissions work differently');
      await buildFeed();
      final locked = Directory(p('locked'))..createSync();
      final target = '${locked.path}/appcast.xml';
      File(feedPath).copySync(target);
      Process.runSync('chmod', ['555', locked.path]);
      addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
      // root can write anywhere; skip then
      try {
        File('${locked.path}/probe').writeAsStringSync('x');
        return markTestSkipped('this user can write to a read-only folder');
      } on FileSystemException {
        // expected
      }
      final r = await cli(['sign-feed', target, '--ed-key-file', keyPath]);
      expect(r.code, 1, reason: '$r');
      expect(r.err, contains(target));
      expect(r.err, isNot(contains('.tmp')));
    });
  });

  group('wrong usage exits with 2', () {
    final cases = <String, List<String>>{
      'no command': [],
      'unknown command': ['frobnicate'],
      'unknown option': ['sign', 'x', '--bogus'],
      'unknown option of check': ['check', 'a.xml', '--nope'],
      'missing value': ['keygen', '--out'],
      'missing positional': ['sign', '--ed-key-file', 'k'],
      'extra positional': ['sign', 'a', 'b', '--ed-key-file', 'k'],
      'missing required option': ['keygen'],
      'bad number': [
        'check',
        'a.xml',
        '--current',
        '1',
        '--os',
        'x',
        '--group',
        'two'
      ],
      'group out of range': [
        'check',
        'a.xml',
        '--current',
        '1',
        '--os',
        'x',
        '--group',
        '7'
      ],
      'bad date': [
        'check',
        'a.xml',
        '--current',
        '1',
        '--os',
        'x',
        '--now',
        'tomorrow'
      ],
      'bad language': ['--lang', 'fr', 'keygen'],
      'language without value': ['keygen', '--lang'],
    };
    for (final e in cases.entries) {
      test(e.key, () async {
        final r = await cli(e.value);
        expect(r.code, 2, reason: '$r');
        expect(r.err, isNotEmpty);
        expect(r.out, isEmpty);
      });
    }

    test('the unknown option is named and help is suggested', () async {
      final r = await cli(['sign', 'x', '--bogus']);
      expect(r.err, contains('--bogus'));
      expect(r.err, contains('--help'));
    });
  });

  group('other failures', () {
    test('missing file exits 1 and names the file', () async {
      final dir = tempDir();
      final key = '${dir.path}/k.key';
      await cli(['keygen', '--out', key]);
      final r =
          await cli(['sign', '${dir.path}/missing.bin', '--ed-key-file', key]);
      expect(r.code, 1);
      expect(r.err, contains('missing.bin'));
    });

    test('a key file that is not a key exits 3', () async {
      final dir = tempDir();
      File('${dir.path}/bad.key').writeAsStringSync('this is not a key');
      File('${dir.path}/a.bin').writeAsBytesSync([1]);
      final r = await cli([
        'sign',
        '${dir.path}/a.bin',
        '--ed-key-file',
        '${dir.path}/bad.key'
      ]);
      expect(r.code, 3);
      expect(r.err, contains('bad.key'));
    });

    test('a key from standard input that is not a key exits 3', () async {
      final dir = tempDir();
      File('${dir.path}/a.bin').writeAsBytesSync([1]);
      final r = await cli(['sign', '${dir.path}/a.bin', '--ed-key-file', '-'],
          stdin: 'xxx');
      expect(r.code, 3);
    });

    test('no key at all exits 3', () async {
      final dir = tempDir();
      File('${dir.path}/a.bin').writeAsBytesSync([1]);
      final r = await cli(['sign', '${dir.path}/a.bin']);
      expect(r.code, 3);
    });

    test('a bad public key exits 3', () async {
      final dir = tempDir();
      File('${dir.path}/a.bin').writeAsBytesSync([1]);
      final r = await cli(
          ['verify', '${dir.path}/a.bin', 'AAAA', '--public-key', 'AAAA']);
      expect(r.code, 3);
    });

    test('a file that is not a feed exits 1', () async {
      final dir = tempDir();
      File('${dir.path}/f.xml').writeAsStringSync('<html/>');
      final r = await cli([
        'check',
        '${dir.path}/f.xml',
        '--current',
        '1',
        '--os',
        'windows-x64'
      ]);
      expect(r.code, 1);
      expect(r.err, contains('f.xml'));
    });

    test('add refuses a damaged existing feed without touching it', () async {
      final dir = tempDir();
      final key = '${dir.path}/k.key';
      await cli(['keygen', '--out', key]);
      File('${dir.path}/f.xml').writeAsStringSync('<rss><channel>');
      File('${dir.path}/a.bin').writeAsBytesSync([1]);
      final r = await cli([
        'add',
        '${dir.path}/f.xml',
        '--file',
        '${dir.path}/a.bin',
        '--url',
        'https://downloads.example.com/a',
        '--version',
        '2',
        '--ed-key-file',
        key,
      ]);
      expect(r.code, 1);
      expect(File('${dir.path}/f.xml').readAsStringSync(), '<rss><channel>');
    });

    test('http:// feed URLs are refused', () async {
      final r = await cli([
        'verify-feed',
        'http://downloads.example.com/a.xml',
        '--public-key',
        'AAAA'
      ]);
      expect(r.code, 1);
    });
  });

  group('legacy 96-byte keys', () {
    late Directory dir;
    late String legacyPath;
    final raw = List.generate(96, (i) => (i * 3 + 1) & 0xff);

    setUp(() {
      dir = tempDir();
      legacyPath = '${dir.path}/legacy.key';
      File(legacyPath).writeAsStringSync('${base64.encode(raw)}\n');
      File('${dir.path}/a.bin').writeAsBytesSync([1, 2, 3]);
      File('${dir.path}/f.xml')
          .writeAsStringSync(feedXml([itemXml(version: '1')]));
    });

    test('pubkey works and prints the last 32 bytes', () async {
      final r = await cli(['pubkey', '--ed-key-file', legacyPath]);
      expect(r.code, 0, reason: '$r');
      expect(base64.decode(r.out.trim()), raw.sublist(64));
    });

    test('sign exits 3 with a message that says what to do', () async {
      final r =
          await cli(['sign', '${dir.path}/a.bin', '--ed-key-file', legacyPath]);
      expect(r.code, 3, reason: '$r');
      expect(r.out, isEmpty);
      expect(r.err, contains('96-byte'));
      expect(r.err, contains('sign_update'));
    });

    test('add and sign-feed exit 3 and leave the feed alone', () async {
      final before = File('${dir.path}/f.xml').readAsStringSync();
      final add = await cli([
        'add',
        '${dir.path}/f.xml',
        '--file',
        '${dir.path}/a.bin',
        '--url',
        'https://downloads.example.com/a',
        '--version',
        '2',
        '--ed-key-file',
        legacyPath,
      ]);
      expect(add.code, 3);
      final sf = await cli(
          ['sign-feed', '${dir.path}/f.xml', '--ed-key-file', legacyPath]);
      expect(sf.code, 3);
      expect(File('${dir.path}/f.xml').readAsStringSync(), before);
    });

    test('the message is Korean in Korean mode', () async {
      final r = await cli([
        'sign',
        '${dir.path}/a.bin',
        '--ed-key-file',
        legacyPath,
        '--lang',
        'ko'
      ]);
      expect(r.code, 3);
      expect(r.err, contains('96바이트'));
    });

    test('verify-feed works with the public half of a legacy key', () async {
      final legacy = EdPrivateKey.fromKeyFile(base64.encode(raw));
      final pub = await legacy.publicKey();
      final seedKey = testKey();
      // a feed signed by someone else is simply not valid for this key
      final signed = await SignedFeed.sign(
          utf8.encode(feedXml([itemXml(version: '1')])), seedKey);
      File('${dir.path}/s.xml').writeAsBytesSync(signed);
      final r = await cli(
          ['verify-feed', '${dir.path}/s.xml', '--ed-key-file', legacyPath]);
      expect(r.code, 1);
      final ok = await cli([
        'verify-feed',
        '${dir.path}/s.xml',
        '--public-key',
        (await seedKey.publicKey()).toBase64()
      ]);
      expect(ok.code, 0);
      expect(pub.toBase64(), isNot((await seedKey.publicKey()).toBase64()));
    });
  });

  group('help and version', () {
    test('--help works and exits 0', () async {
      final r = await cli(['--help']);
      expect(r.code, 0);
      expect(r.out, contains('Usage'));
      for (final c in [
        'keygen',
        'pubkey',
        'sign',
        'verify',
        'add',
        'sign-feed',
        'verify-feed',
        'check'
      ]) {
        expect(r.out, contains(c));
        final sub = await cli([c, '--help']);
        expect(sub.code, 0, reason: c);
        expect(sub.out, contains('Usage'), reason: c);
      }
    });

    test('--version', () async {
      final r = await cli(['--version']);
      expect(r.code, 0);
      expect(r.out.trim(), 'appcast $packageVersion');
    });

    // `appcast --version` prints packageVersion, so it must follow pubspec.yaml.
    test('packageVersion matches the version in pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match =
          RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml has no version: line');
      expect(packageVersion, match!.group(1));
    });
  });
}

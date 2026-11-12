import 'dart:io';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:appcast_updater/src/cli/cli.dart';
import 'package:appcast_updater/src/cli/messages_en.dart';
import 'package:appcast_updater/src/cli/messages_ko.dart';
import 'package:test/test.dart';

import 'support.dart';

Future<({int code, String out, String err})> run(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(args, out: out, err: err, env: const {});
  return (code: code, out: out.toString(), err: err.toString());
}

class Release {
  Release(this.file, this.item, this.publicKey);
  final File file;
  final AppcastItem item;
  final EdPublicKey publicKey;
}

Future<Release> makeRelease(Directory dir) async {
  final key = testKey();
  final file = File('${dir.path}/Example-130.exe')
    ..writeAsBytesSync(bytesOf(4096));
  final sig = await signFile(file, key);
  final item = AppcastItem(
    version: '130',
    enclosure: Enclosure(
        url: file.uri.toString(),
        length: sig.length,
        edSignature: sig.signature),
  );
  return Release(file, item, await key.publicKey());
}

String badItem(String enclosureAttrs, {String extra = ''}) => '''
<rss version="2.0" xmlns:sparkle="$sparkleNamespace"><channel><title>t</title>
<item><title>x</title>$extra$enclosureAttrs</item></channel></rss>''';

void main() {
  group('item error reasons', () {
    test('every malformed item carries a machine-readable reason', () {
      final feed = feedOf([
        itemXml(version: '1').replaceAll(RegExp(r'<enclosure[^>]*/>'), ''),
        itemXml(version: '2').replaceAll('length="10"', 'length="ten"'),
        itemXml(version: '3')
            .replaceAll('<sparkle:version>3</sparkle:version>', ''),
        itemXml(version: '4', interval: 5).replaceAll('>5<', '>soon<'),
        itemXml(version: '5', pubDate: 'yesterday'),
      ]);
      expect(feed.errors.map((e) => e.reason), [
        ItemFailure.missingEnclosure,
        ItemFailure.badLength,
        ItemFailure.missingVersion,
        ItemFailure.badPhasedInterval,
        ItemFailure.badPubDate,
      ]);
    });

    test('feed-level failures carry a reason', () {
      FeedFormatFailure? kind(String xml) {
        try {
          Appcast.parse(xml);
        } on AppcastFormatException catch (e) {
          return e.reason;
        }
        return null;
      }

      expect(kind('<rss><channel>'), FeedFormatFailure.notXml);
      expect(kind(''), FeedFormatFailure.notXml);
      expect(kind('<rss version="2.0"></rss>'), FeedFormatFailure.noChannel);
      expect(
          () => Appcast.parseBytes([0xff, 0xfe, 0x00]),
          throwsA(isA<AppcastFormatException>()
              .having((e) => e.reason, 'reason', FeedFormatFailure.notUtf8)));
    });
  });

  group('check --explain names what is wrong', () {
    late Directory dir;
    setUp(() => dir = tempDir());

    Future<String> explain(String name, String xml, String lang) async {
      final f = File('${dir.path}/$name')..writeAsStringSync(xml);
      final r = await run([
        '--lang',
        lang,
        'check',
        f.path,
        '--current',
        '1',
        '--os',
        'macos',
        '--explain'
      ]);
      expect(r.code, 0, reason: '${r.err}');
      return r.out;
    }

    test('missing enclosure url (en)', () async {
      final out = await explain('a.xml', badItem(''), 'en');
      expect(out, contains('Item #1'));
      expect(out, contains('<enclosure>'));
      expect(out, contains('url'));
    });

    test('missing enclosure url (ko)', () async {
      final out = await explain('a.xml', badItem(''), 'ko');
      expect(out, contains('<enclosure>'));
      expect(out, contains('url'));
      expect(out, matches(RegExp(r'[가-힣]')));
      expect(out, isNot(contains('is malformed')));
    });

    test('each reason has its own sentence in both languages', () {
      final keys = ItemFailure.values.map((r) => 'check.item_error.${r.name}');
      for (final k in keys) {
        expect(messagesEn.containsKey(k), isTrue, reason: k);
        expect(messagesKo.containsKey(k), isTrue, reason: k);
      }
      final en = keys.map((k) => messagesEn[k]).toSet();
      expect(en.length, ItemFailure.values.length);
    });

    test('bad length, version, interval and date are told apart', () async {
      final feed = feedXml([
        itemXml(version: '2').replaceAll('length="10"', 'length="ten"'),
        itemXml(version: '3')
            .replaceAll('<sparkle:version>3</sparkle:version>', ''),
        itemXml(version: '5', pubDate: 'yesterday'),
      ]);
      final out = await explain('b.xml', feed, 'en');
      expect(out, contains('#1'));
      expect(out, contains('length'));
      expect(out, contains('#2'));
      expect(out, contains('sparkle:version'));
      expect(out, contains('#3'));
      expect(out, contains('pubDate'));
    });
  });

  group('check on a broken feed says why', () {
    late Directory dir;
    setUp(() => dir = tempDir());

    Future<String> errOf(String content, String lang) async {
      final f = File('${dir.path}/bad.xml')
        ..writeAsBytesSync(content.codeUnits);
      final r = await run(
          ['--lang', lang, 'check', f.path, '--current', '1', '--os', 'macos']);
      expect(r.code, 1);
      return r.err;
    }

    test('not XML', () async {
      expect(await errOf('', 'en'), contains('not well-formed XML'));
      expect(await errOf('<rss><channel>', 'ko'), contains('XML'));
    });
    test('no channel', () async {
      expect(await errOf('<rss version="2.0"></rss>', 'en'),
          contains('<channel>'));
      expect(await errOf('<rss version="2.0"></rss>', 'ko'),
          matches(RegExp(r'[가-힣]')));
    });
    test('not UTF-8', () async {
      final f = File('${dir.path}/latin.xml')
        ..writeAsBytesSync([0x3c, 0x72, 0xff, 0xfe]);
      final r = await run(
          ['--lang', 'en', 'check', f.path, '--current', '1', '--os', 'macos']);
      expect(r.code, 1);
      expect(r.err, contains('UTF-8'));
      final k = await run(
          ['--lang', 'ko', 'check', f.path, '--current', '1', '--os', 'macos']);
      expect(k.err, contains('UTF-8'));
      expect(k.err, matches(RegExp(r'[가-힣]')));
    });
  });

  group('enclosure scheme follows the feed', () {
    Updater updaterFor(Uri feed, EdPublicKey key) => Updater(
        feedUrl: feed,
        publicKey: key,
        currentVersion: '120',
        os: 'windows-x64');

    test('an https feed cannot make the client read a local file', () async {
      final src = tempDir();
      final dst = tempDir();
      final r = await makeRelease(src);
      final item = AppcastItem(
        version: '130',
        enclosure: Enclosure(
            url: r.file.uri.toString(),
            length: r.item.enclosure.length,
            edSignature: r.item.enclosure.edSignature),
      );
      await expectLater(
          updaterFor(
                  Uri.parse('https://downloads.example.com/a.xml'), r.publicKey)
              .downloadAndVerify(item, into: dst),
          throwsA(isA<DownloadException>()
              .having((e) => e.message, 'message', contains('file://'))));
      expect(dst.listSync(), isEmpty);
    });

    test('a local file feed may still point at file enclosures', () async {
      final src = tempDir();
      final dst = tempDir();
      final r = await makeRelease(src);
      final item = AppcastItem(
        version: '130',
        enclosure: Enclosure(
            url: r.file.uri.toString(),
            length: r.item.enclosure.length,
            edSignature: r.item.enclosure.edSignature),
      );
      final file = await updaterFor(src.uri.resolve('appcast.xml'), r.publicKey)
          .downloadAndVerify(item, into: dst);
      expect(file.existsSync(), isTrue);
    });
  });
}

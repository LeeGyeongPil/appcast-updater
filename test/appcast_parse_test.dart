import 'dart:io';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:test/test.dart';

import 'support.dart';

void expectFullFeed(Appcast feed) {
  expect(feed.title, 'Example');
  expect(feed.errors, isEmpty);
  expect(feed.items, hasLength(3));

  final beta = feed.items[0];
  expect(beta.version, '130');
  expect(beta.shortVersion, '1.3.0');
  expect(beta.channel, 'beta');
  expect(beta.critical, isTrue);
  expect(beta.criticalBelowVersion, '125');
  expect(beta.minimumSystemVersion, '10.0.19041');
  expect(beta.maximumSystemVersion, '11.0');
  expect(beta.phasedRolloutInterval, 86400);
  expect(beta.pubDate, DateTime.utc(2026, 11, 12, 1));
  expect(
      beta.releaseNotesLink, 'https://downloads.example.com/notes/1.3.0.html');
  final enc = beta.enclosure;
  expect(enc.url, 'https://downloads.example.com/Example-1.3.0-setup.exe');
  expect(enc.length, 12345);
  expect(enc.type, 'application/octet-stream');
  expect(enc.edSignature, 'c2lnbmF0dXJl');
  expect(enc.os, 'windows-x64');
  expect(enc.installerArguments, '/VERYSILENT /NORESTART');
  // stored in lowercase so comparisons do not depend on how it was written
  expect(enc.sha256,
      'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789');

  final plain = feed.items[1];
  expect(plain.version, '120');
  expect(plain.channel, isNull);
  expect(plain.critical, isFalse);
  expect(plain.enclosure.os, isNull);
  expect(plain.enclosure.edSignature, isNull);

  // old feeds keep the version on the enclosure
  final old = feed.items[2];
  expect(old.version, '110');
  expect(old.shortVersion, '1.1.0');
}

void main() {
  final text = File('test/fixtures/full.xml').readAsStringSync();

  test('reads every M1 field', () {
    expectFullFeed(Appcast.parse(text));
  });

  test('parseBytes reads the same feed', () {
    expectFullFeed(
        Appcast.parseBytes(File('test/fixtures/full.xml').readAsBytesSync()));
  });

  test('namespace prefixes do not matter, the URI does', () {
    final renamed = text
        .replaceAll('xmlns:sparkle', 'xmlns:sp')
        .replaceAll('sparkle:', 'sp:')
        .replaceAll('xmlns:au', 'xmlns:ext')
        .replaceAll('au:sha256', 'ext:sha256');
    expect(renamed, isNot(contains('sparkle:')));
    expectFullFeed(Appcast.parse(renamed));
  });

  test('a prefix declared on the item itself works', () {
    final xml = '''<rss version="2.0"><channel><title>T</title>
<item xmlns:s="http://www.andymatuschak.org/xml-namespaces/sparkle">
<s:version>5</s:version>
<enclosure url="https://downloads.example.com/a.zip" length="1"/></item></channel></rss>''';
    expect(Appcast.parse(xml).items.single.version, '5');
  });

  test('elements in a foreign namespace are ignored', () {
    final xml = feedXml([
      itemXml(version: '5').replaceFirst('<sparkle:version>5</sparkle:version>',
          '<sparkle:version>5</sparkle:version><other:channel xmlns:other="urn:other">beta</other:channel>'),
    ]);
    expect(Appcast.parse(xml).items.single.channel, isNull);
  });

  group('malformed items', () {
    test('are skipped and reported, good items survive', () {
      final feed = Appcast.parse(feedXml([
        itemXml(version: '1').replaceAll(RegExp(r'<enclosure[^>]*/>'), ''),
        itemXml(version: '2').replaceAll('length="10"', 'length="ten"'),
        itemXml(version: '3')
            .replaceAll('<sparkle:version>3</sparkle:version>', ''),
        itemXml(version: '4', interval: 5).replaceAll('>5<', '>soon<'),
        itemXml(version: '5', pubDate: 'yesterday'),
        itemXml(version: '6'),
      ]));
      expect(feed.items.map((i) => i.version), ['6']);
      expect(feed.errors.map((e) => e.index), [0, 1, 2, 3, 4]);
    });
  });

  group('not a feed', () {
    test('invalid XML throws', () {
      expect(() => Appcast.parse('<rss><channel>'),
          throwsA(isA<AppcastFormatException>()));
    });
    test('no channel throws', () {
      expect(() => Appcast.parse('<rss version="2.0"></rss>'),
          throwsA(isA<AppcastFormatException>()));
    });
    test('invalid UTF-8 throws', () {
      expect(() => Appcast.parseBytes([0xff, 0xfe, 0x00]),
          throwsA(isA<AppcastFormatException>()));
    });
  });

  test('RFC 822 dates: zones and round trip', () {
    expect(parseRfc822('Wed, 12 Nov 2026 03:00:00 +0900'),
        DateTime.utc(2026, 11, 11, 18));
    expect(parseRfc822('12 Nov 2026 03:00 GMT'), DateTime.utc(2026, 11, 12, 3));
    expect(parseRfc822('not a date'), isNull);
    final d = DateTime.utc(2026, 11, 12, 1, 2, 3);
    expect(parseRfc822(formatRfc822(d)), d);
  });

  test('isCriticalFor follows the documented rule', () {
    // https://sparkle-project.org/documentation/publishing/ (checked 2026-11-12):
    // critical for installs older than the criticalUpdate version attribute.
    final feed = Appcast.parse(text);
    final withAttr = feed.items[0];
    expect(withAttr.isCriticalFor('120'), isTrue);
    expect(withAttr.isCriticalFor('125'), isFalse);
    expect(withAttr.isCriticalFor('130'), isFalse);
    final noAttr = Appcast.parse(feedXml([itemXml(version: '9', critical: '')]))
        .items
        .single;
    expect(noAttr.isCriticalFor('1'), isTrue);
    expect(noAttr.isCriticalFor('8'), isTrue);
    expect(feed.items[1].isCriticalFor('1'), isFalse);
  });
}

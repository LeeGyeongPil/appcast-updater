import 'dart:convert';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:test/test.dart';

import 'support.dart';

int count(List<int> haystack, String needle) =>
    RegExp(RegExp.escape(needle)).allMatches(utf8.decode(haystack)).length;

Matcher failsWith(FeedFailure reason) => throwsA(
    isA<FeedSignatureException>().having((e) => e.reason, 'reason', reason));

void main() {
  final body = utf8.encode(feedXml([itemXml(version: '130')]));
  final key = testKey();

  test('sign adds exactly one tail and verify returns the signed body',
      () async {
    final signed = await SignedFeed.sign(body, key);
    expect(count(signed, 'sparkle-signatures'), 1);
    expect(utf8.decode(signed), endsWith('-->\n'));
    final verified = await SignedFeed.verify(signed, await key.publicKey());
    expect(verified, body);
  });

  test('the signed feed is still a readable appcast', () async {
    final signed = await SignedFeed.sign(body, key);
    expect(Appcast.parseBytes(signed).items.single.version, '130');
  });

  test('one changed byte before the tail: FeedSignatureException', () async {
    final signed = await SignedFeed.sign(body, key);
    signed[body.length ~/ 2] ^= 1;
    await expectLater(SignedFeed.verify(signed, await key.publicKey()),
        failsWith(FeedFailure.signatureInvalid));
  });

  test('a feed with a different length than declared is refused', () async {
    final signed = await SignedFeed.sign(body, key);
    final text = utf8.decode(signed).replaceFirst('<channel>', '<channel> ');
    await expectLater(
        SignedFeed.verify(utf8.encode(text), await key.publicKey()),
        failsWith(FeedFailure.lengthMismatch));
  });

  test('signing again replaces the tail instead of stacking tails', () async {
    final once = await SignedFeed.sign(body, key);
    final twice = await SignedFeed.sign(once, testKey(2));
    expect(count(twice, 'sparkle-signatures'), 1);
    await SignedFeed.verify(twice, await testKey(2).publicKey());
    await expectLater(SignedFeed.verify(twice, await key.publicKey()),
        failsWith(FeedFailure.signatureInvalid));
  });

  test('strip removes every tail', () async {
    final once = await SignedFeed.sign(body, key);
    final stacked = [
      ...once,
      ...utf8
          .encode('<!-- sparkle-signatures:\nedSignature: AA\nlength: 1\n-->\n')
    ];
    expect(count(SignedFeed.strip(stacked), 'sparkle-signatures'), 0);
    expect(SignedFeed.hasSignature(stacked), isTrue);
    expect(SignedFeed.hasSignature(body), isFalse);
    expect(SignedFeed.strip(body), body);
  });

  test('a feed without a tail is refused by verify', () async {
    await expectLater(SignedFeed.verify(body, await key.publicKey()),
        failsWith(FeedFailure.missing));
  });

  test('wrong key: signatureInvalid', () async {
    final signed = await SignedFeed.sign(body, key);
    await expectLater(SignedFeed.verify(signed, await testKey(5).publicKey()),
        failsWith(FeedFailure.signatureInvalid));
  });

  test('damaged tails are refused, never accepted', () async {
    final pub = await key.publicKey();
    final good = utf8.decode(await SignedFeed.sign(body, key));
    final cases = <String, String>{
      'no closing marker': good.replaceFirst('-->\n', ''),
      'no length': good.replaceFirst(RegExp(r'length: \d+\n'), ''),
      'no signature': good.replaceFirst(RegExp(r'edSignature: [^\n]+\n'), ''),
      'junk after the tail': '${good}<item/>',
      'junk inside the tail':
          good.replaceFirst('length:', 'color: red\nlength:'),
    };
    for (final e in cases.entries) {
      await expectLater(SignedFeed.verify(utf8.encode(e.value), pub),
          failsWith(FeedFailure.malformed),
          reason: e.key);
    }
  });

  test('text appended after the tail does not smuggle content in', () async {
    final pub = await key.publicKey();
    final signed = await SignedFeed.sign(body, key);
    final extra = [...signed, ...utf8.encode('<!-- more -->')];
    await expectLater(
        SignedFeed.verify(extra, pub), throwsA(isA<FeedSignatureException>()));
  });

  test('a body without a trailing newline still round-trips', () async {
    final text = utf8.encode('<rss><channel/></rss>');
    final signed = await SignedFeed.sign(text, key);
    final verified = await SignedFeed.verify(signed, await key.publicKey());
    expect(utf8.decode(verified), '<rss><channel/></rss>\n');
  });

  group('AppcastWriter', () {
    test('creates a feed, adds items on top, keeps existing text', () {
      final w = AppcastWriter.createEmpty('Example');
      w.addItem(
          version: '110',
          url: 'https://downloads.example.com/a.exe',
          length: 5,
          os: 'windows-x64');
      w.addItem(
        version: '120',
        shortVersion: '1.2.0',
        url: 'https://downloads.example.com/b.exe',
        length: 6,
        edSignature: 'c2ln',
        sha256: 'ab' * 32,
        os: 'windows-x64',
        channel: 'beta',
        minimumSystemVersion: '10.0',
        phasedRolloutInterval: 3600,
        critical: true,
        criticalBelowVersion: '115',
        installerArguments: '/S',
        releaseNotesLink: 'https://downloads.example.com/n.html',
        pubDate: DateTime.utc(2026, 11, 12),
      );
      final feed = Appcast.parse(w.toXmlString());
      expect(feed.items.map((i) => i.version), ['120', '110']);
      final top = feed.items.first;
      expect(top.shortVersion, '1.2.0');
      expect(top.channel, 'beta');
      expect(top.enclosure.edSignature, 'c2ln');
      expect(top.enclosure.sha256, 'ab' * 32);
      expect(top.criticalBelowVersion, '115');
      expect(top.phasedRolloutInterval, 3600);
      expect(top.enclosure.installerArguments, '/S');
      expect(top.pubDate, DateTime.utc(2026, 11, 12));
    });

    test('adding to a feed that uses another prefix keeps that prefix', () {
      final xml = feedXml([itemXml(version: '100')])
          .replaceAll('xmlns:sparkle', 'xmlns:sp')
          .replaceAll('sparkle:', 'sp:');
      final w = AppcastWriter.parse(xml);
      w.addItem(
          version: '110',
          url: 'https://downloads.example.com/a.exe',
          length: 5);
      final out = w.toXmlString();
      expect(out, isNot(contains('xmlns:sparkle')));
      expect(Appcast.parse(out).items.map((i) => i.version), ['110', '100']);
    });

    test('the same version and os needs replace: true', () {
      final w = AppcastWriter.createEmpty('Example');
      void add({bool replace = false, String? os = 'windows-x64'}) => w.addItem(
          version: '120',
          url: 'https://downloads.example.com/a.exe',
          length: 5,
          os: os,
          replace: replace);
      add();
      expect(add, throwsA(isA<DuplicateItemException>()));
      add(os: 'macos'); // other os is a different item
      add(replace: true);
      expect(Appcast.parse(w.toXmlString()).items, hasLength(2));
    });

    test('text is escaped', () {
      final w = AppcastWriter.createEmpty('A & B <c>');
      w.addItem(
          version: '1',
          url: 'https://downloads.example.com/a.exe?x=1&y=2',
          length: 1,
          title: 'R&D "x"');
      final feed = Appcast.parse(w.toXmlString());
      expect(feed.title, 'A & B <c>');
      expect(feed.items.single.enclosure.url,
          'https://downloads.example.com/a.exe?x=1&y=2');
      expect(feed.items.single.title, 'R&D "x"');
    });

    test('invalid feeds are reported', () {
      expect(() => AppcastWriter.parse('<rss>'),
          throwsA(isA<AppcastFormatException>()));
      expect(() => AppcastWriter.parse('<rss/>'),
          throwsA(isA<AppcastFormatException>()));
    });
  });
}

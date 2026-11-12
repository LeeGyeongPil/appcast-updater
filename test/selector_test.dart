import 'dart:io';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:test/test.dart';

import 'support.dart';

// Rules: https://sparkle-project.org/documentation/publishing/ (checked 2026-11-12)
final now = DateTime.utc(2026, 11, 12, 12);

UpdateSelector selector({
  String current = '100',
  String os = 'windows-x64',
  String? system,
  Set<String> channels = const {},
  int? group,
  bool user = false,
  String? untaggedMeans,
  DateTime? at,
}) =>
    UpdateSelector(
      currentVersion: current,
      os: os,
      systemVersion: system,
      channels: channels,
      rolloutGroup: group,
      userInitiated: user,
      untaggedMeans: untaggedMeans,
      clock: () => at ?? now,
    );

RejectReason? reasonFor(Selection s, String version) {
  for (final r in s.rejections) {
    if (r.item.version == version) return r.reason;
  }
  return null;
}

void main() {
  group('newest acceptable item wins', () {
    test('picks the highest version, rejects the rest as superseded', () {
      final s = selector().select(feedOf([
        itemXml(version: '120'),
        itemXml(version: '130'),
        itemXml(version: '110'),
      ]));
      expect(s.item!.version, '130');
      expect(reasonFor(s, '120'), RejectReason.superseded);
      expect(reasonFor(s, '110'), RejectReason.superseded);
    });

    test('rejections keep feed order', () {
      final s = selector(current: '125').select(feedOf([
        itemXml(version: '120'),
        itemXml(version: '130'),
        itemXml(version: '110'),
      ]));
      expect(s.rejections.map((r) => r.item.version), ['120', '110']);
    });

    test('nothing newer: no item and a reason per item', () {
      final s = selector(current: '130').select(feedOf([
        itemXml(version: '130'),
        itemXml(version: '120'),
      ]));
      expect(s.item, isNull);
      expect(s.rejections.map((r) => r.reason),
          [RejectReason.notNewer, RejectReason.notNewer]);
    });

    test('versions compare with Sparkle rules, not as text', () {
      final s =
          selector(current: '1.9').select(feedOf([itemXml(version: '1.10')]));
      expect(s.item!.version, '1.10');
    });
  });

  group('os', () {
    final feed = feedOf([
      itemXml(version: '110', os: 'macos'),
      itemXml(version: '120', os: 'windows-x64'),
      itemXml(version: '130', os: 'windows-arm64'),
      itemXml(version: '140', os: 'windows'),
      itemXml(version: '150'),
    ]);

    test('matches the exact tag and the family tag, and untagged items', () {
      final s = selector(os: 'windows-x64').select(feed);
      expect(s.item!.version, '150');
      expect(reasonFor(s, '110'), RejectReason.wrongOs);
      expect(reasonFor(s, '130'), RejectReason.wrongOs);
      expect(reasonFor(s, '120'), RejectReason.superseded);
      expect(reasonFor(s, '140'), RejectReason.superseded);
    });

    test('untaggedMeans: macos makes untagged items macOS only', () {
      final s =
          selector(os: 'windows-x64', untaggedMeans: 'macos').select(feed);
      expect(s.item!.version, '140');
      expect(reasonFor(s, '150'), RejectReason.wrongOs);
    });
  });

  group('channels', () {
    final feed = feedOf([
      itemXml(version: '110'),
      itemXml(version: '120', channel: 'beta'),
    ]);

    test('the default channel is always included, others need opt-in', () {
      final s = selector().select(feed);
      expect(s.item!.version, '110');
      expect(reasonFor(s, '120'), RejectReason.channelNotAllowed);
      expect(s.rejections.single.expected, 'beta');
    });

    test('opting in to beta includes both', () {
      final s = selector(channels: {'beta'}).select(feed);
      expect(s.item!.version, '120');
      expect(reasonFor(s, '110'), RejectReason.superseded);
    });
  });

  group('system version', () {
    final feed = feedOf(
        [itemXml(version: '120', minSystem: '10.0.19041', maxSystem: '11.0')]);

    test('inside the range is fine', () {
      expect(selector(system: '10.0.22631').select(feed).item, isNotNull);
      expect(selector(system: '11.0').select(feed).item, isNotNull);
    });
    test('older than the minimum', () {
      final s = selector(system: '6.3').select(feed);
      expect(s.item, isNull);
      expect(reasonFor(s, '120'), RejectReason.systemTooOld);
      expect(s.rejections.single.actual, '6.3');
    });
    test('newer than the maximum', () {
      expect(reasonFor(selector(system: '12.0').select(feed), '120'),
          RejectReason.systemTooNew);
    });
    test('unknown system version skips the checks', () {
      expect(selector().select(feed).item, isNotNull);
    });
  });

  group('informational items', () {
    test('are never offered for download', () {
      final s = selector()
          .select(feedOf([itemXml(version: '120', informational: true)]));
      expect(s.item, isNull);
      expect(reasonFor(s, '120'), RejectReason.informational);
    });
  });

  group('phased rollout', () {
    // published at 2026-11-12T00:00Z, one day between groups
    const pub = 'Thu, 12 Nov 2026 00:00:00 +0000';
    final feed =
        feedOf([itemXml(version: '120', pubDate: pub, interval: 86400)]);

    test('group 0 gets it at publication time', () {
      expect(selector(group: 0).select(feed).item, isNotNull);
    });
    test('group 2 waits two intervals', () {
      final s = selector(group: 2).select(feed); // now = Nov 12 12:00
      expect(s.item, isNull);
      final r = s.rejections.single;
      expect(r.reason, RejectReason.rolloutNotYet);
      expect(r.availableAt, DateTime.utc(2026, 11, 14));
      expect(r.group, 2);
      expect(
          selector(group: 2, at: DateTime.utc(2026, 11, 14)).select(feed).item,
          isNotNull);
    });
    test('group 6 waits six intervals', () {
      expect(
          selector(group: 6, at: DateTime.utc(2026, 11, 17, 23))
              .select(feed)
              .item,
          isNull);
      expect(
          selector(group: 6, at: DateTime.utc(2026, 11, 18)).select(feed).item,
          isNotNull);
    });
    test('a user clicking "check for updates" skips the rollout', () {
      expect(selector(group: 6, user: true).select(feed).item, isNotNull);
    });
    test('critical updates skip the rollout', () {
      final critical = feedOf([
        itemXml(version: '120', pubDate: pub, interval: 86400, critical: ''),
      ]);
      final s = selector(group: 6).select(critical);
      expect(s.item, isNotNull);
      expect(s.critical, isTrue);
    });
    test('no group known: rollout is not applied', () {
      expect(selector().select(feed).item, isNotNull);
    });
  });

  group('critical updates', () {
    test('with a version attribute: critical only below it', () {
      final feed = feedOf([itemXml(version: '130', critical: '120')]);
      expect(selector(current: '110').select(feed).critical, isTrue);
      expect(selector(current: '120').select(feed).critical, isFalse);
      expect(selector(current: '125').select(feed).critical, isFalse);
    });
    test('a plain item is not critical', () {
      expect(selector().select(feedOf([itemXml(version: '130')])).critical,
          isFalse);
    });
  });

  group('RolloutGroupStore', () {
    test('keeps the first group it was given', () {
      final file = tempDir().uri.resolve('state/group.txt');
      final store = RolloutGroupStore(File.fromUri(file));
      expect(store.load(), isNull);
      store.save(4);
      expect(RolloutGroupStore(File.fromUri(file)).load(), 4);
    });

    test('loadOrCreate picks once and then repeats the same group', () {
      final file = File.fromUri(tempDir().uri.resolve('g.txt'));
      final first = RolloutGroupStore(file).loadOrCreate();
      expect(first, inInclusiveRange(0, 6));
      for (var i = 0; i < 20; i++) {
        expect(RolloutGroupStore(file).loadOrCreate(), first);
      }
    });

    test('a damaged file counts as no group', () {
      final file = File.fromUri(tempDir().uri.resolve('g.txt'))
        ..writeAsStringSync('99');
      expect(RolloutGroupStore(file).load(), isNull);
      file.writeAsStringSync('banana');
      expect(RolloutGroupStore(file).load(), isNull);
    });

    test('saving a group outside 0..6 fails', () {
      final store =
          RolloutGroupStore(File.fromUri(tempDir().uri.resolve('g.txt')));
      expect(() => store.save(7), throwsRangeError);
    });

    test('random groups cover 0..6', () {
      final seen = {for (var i = 0; i < 500; i++) RolloutGroup.random()};
      expect(seen, {0, 1, 2, 3, 4, 5, 6});
    });
  });
}

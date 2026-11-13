import 'dart:io';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:appcast_updater/src/cli/cli.dart';
import 'package:test/test.dart';

import 'support.dart';

Future<(int, String, String)> run(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCli(args,
      out: out, err: err, env: const {}, stdin: const Stream.empty());
  return (code, out.toString(), err.toString());
}

void main() {
  late Directory dir;
  late String feedPath;
  late String keyPath;
  late String filePath;

  setUp(() async {
    dir = tempDir();
    feedPath = '${dir.path}/appcast.xml';
    keyPath = '${dir.path}/release.key';
    filePath = '${dir.path}/app.exe';
    File(filePath).writeAsBytesSync(bytesOf(500));
    final r = await run(['keygen', '--out', keyPath]);
    expect(r.$1, 0, reason: '${r.$3}');
  });

  void writeFeed(List<String> items) =>
      File(feedPath).writeAsStringSync(feedXml(items));

  List<String> addArgs(String version,
          {String? os, String? channel, List<String> extra = const []}) =>
      [
        'add',
        feedPath,
        '--file',
        filePath,
        '--url',
        'https://downloads.example.com/app-$version.exe',
        '--version',
        version,
        if (os != null) ...['--os', os],
        if (channel != null) ...['--channel', channel],
        '--ed-key-file',
        keyPath,
        ...extra,
      ];

  List<String> versionsOf({String? os, String? channel}) =>
      Appcast.parse(File(feedPath).readAsStringSync())
          .items
          .where((i) =>
              (i.enclosure.os ?? '') == (os ?? '') &&
              (i.channel ?? '') == (channel ?? ''))
          .map((i) => i.version)
          .toList();

  List<String> fourWindows() => [
        for (final v in ['10', '20', '30', '40'])
          itemXml(version: v, os: 'windows-x64', signature: 'c2ln'),
      ];

  test('(a) without --keep nothing is removed', () async {
    writeFeed(fourWindows());
    final r = await run(addArgs('50', os: 'windows-x64'));
    expect(r.$1, 0, reason: r.$3);
    expect(r.$2, isNot(contains('Removed')));
    expect(versionsOf(os: 'windows-x64'), hasLength(5));
  });

  test('(b) --keep 2 leaves the newest two and reports the count', () async {
    writeFeed(fourWindows());
    final r =
        await run(addArgs('50', os: 'windows-x64', extra: ['--keep', '2']));
    expect(r.$1, 0, reason: r.$3);
    expect(r.$2, contains('Removed 3 old item(s)'));
    expect(versionsOf(os: 'windows-x64'), ['50', '40']);
  });

  test('(b) the count is exact when exactly 2 are removed', () async {
    writeFeed(fourWindows().take(3).toList());
    final r =
        await run(addArgs('50', os: 'windows-x64', extra: ['--keep', '2']));
    expect(r.$2, contains('Removed 2 old item(s)'));
  });

  test('(c) os and channel groups do not affect each other', () async {
    writeFeed([
      ...fourWindows(),
      itemXml(version: '1', os: 'macos', signature: 'c2ln'),
      itemXml(version: '2', os: 'macos', signature: 'c2ln'),
      itemXml(
          version: '5', os: 'windows-x64', channel: 'beta', signature: 'c2ln'),
      itemXml(
          version: '6', os: 'windows-x64', channel: 'beta', signature: 'c2ln'),
    ]);
    final r =
        await run(addArgs('50', os: 'windows-x64', extra: ['--keep', '2']));
    expect(r.$1, 0, reason: r.$3);
    expect(versionsOf(os: 'windows-x64'), ['50', '40']);
    expect(versionsOf(os: 'macos'), ['1', '2']);
    expect(versionsOf(os: 'windows-x64', channel: 'beta'), ['5', '6']);
  });

  test('(d) newest is decided by version, not by position', () async {
    writeFeed([
      for (final v in ['30', '10', '40', '20'])
        itemXml(version: v, os: 'windows-x64', signature: 'c2ln'),
    ]);
    final r =
        await run(addArgs('5', os: 'windows-x64', extra: ['--keep', '2']));
    expect(r.$1, 0, reason: r.$3);
    expect(versionsOf(os: 'windows-x64').toSet(), {'30', '40'});
  });

  test('(e) minimumAutoupdateVersion and unparseable items stay', () async {
    final floor = itemXml(version: '15', os: 'windows-x64', signature: 'c2ln')
        .replaceFirst('<sparkle:version>',
            '<sparkle:minimumAutoupdateVersion>12</sparkle:minimumAutoupdateVersion><sparkle:version>');
    const broken = '    <item><title>broken</title></item>';
    writeFeed([...fourWindows(), floor, broken]);
    final r =
        await run(addArgs('50', os: 'windows-x64', extra: ['--keep', '1']));
    expect(r.$1, 0, reason: r.$3);
    final text = File(feedPath).readAsStringSync();
    expect(text, contains('<title>broken</title>'));
    expect(text, contains('minimumAutoupdateVersion'));
    expect(versionsOf(os: 'windows-x64'), ['50', '15']);
  });

  test('(f) bad --keep values are usage errors and leave the feed alone',
      () async {
    writeFeed(fourWindows());
    final before = File(feedPath).readAsStringSync();
    for (final bad in ['0', '-1', 'abc']) {
      final r =
          await run(addArgs('50', os: 'windows-x64', extra: ['--keep', bad]));
      expect(r.$1, exitUsage, reason: bad);
      expect(File(feedPath).readAsStringSync(), before, reason: bad);
    }
  });

  test('(f2) --keep 0 says 1 or more is needed, in both languages', () async {
    writeFeed(fourWindows());
    final en = await run(addArgs('50',
        os: 'windows-x64', extra: ['--keep', '0', '--lang', 'en']));
    expect(en.$1, exitUsage);
    expect(en.$3, contains('1 or more'));
    final ko = await run(addArgs('50',
        os: 'windows-x64', extra: ['--keep', '0', '--lang', 'ko']));
    expect(ko.$1, exitUsage);
    expect(ko.$3, contains('1 이상'));
  });

  test('(g) --keep with --sign-feed gives a valid signature', () async {
    writeFeed(fourWindows());
    final r = await run(addArgs('50',
        os: 'windows-x64', extra: ['--keep', '2', '--sign-feed']));
    expect(r.$1, 0, reason: r.$3);
    final key = EdPrivateKey.fromKeyFile(File(keyPath).readAsStringSync());
    await SignedFeed.verify(
        File(feedPath).readAsBytesSync(), await key.publicKey());
    expect(versionsOf(os: 'windows-x64'), ['50', '40']);
  });

  test('(h) Korean message', () async {
    writeFeed(fourWindows());
    final r = await run([
      '--lang',
      'ko',
      ...addArgs('50', os: 'windows-x64', extra: ['--keep', '2'])
    ]);
    expect(r.$1, 0, reason: r.$3);
    expect(r.$2, contains('오래된 항목 3개를 지웠습니다'));
  });

  test('AppcastWriter.prune rejects keep < 1', () {
    final w = AppcastWriter.parse(feedXml(fourWindows()));
    expect(() => w.prune(keep: 0), throwsArgumentError);
    expect(w.prune(keep: 10), 0);
  });
}

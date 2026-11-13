// Offline practice run (no network, nothing is installed).
//
// Real: key generation, Ed25519 signing and verification, sha256, feed
// signing, tamper detection, downgrade blocking.
// Fake: the "download server" is a folder read through file:// URLs, and the
// installer step is only announced.
//
//     dart run example/main.dart [--lang en|ko]
//
// The language follows the CLI: --lang, then APPCAST_UPDATER_LANG, then
// LC_ALL, LC_MESSAGES, LANG.
//
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:appcast_updater/appcast_updater.dart';
// Same package, so the example reuses the CLI's language rules.
import 'package:appcast_updater/src/cli/i18n.dart';

// Everything is written below this folder (relative to where you run it).
const playground = 'build/example-playground';

/// Deterministic pseudo-random file content, so runs look the same.
Uint8List fakeRelease(int seed, int size) {
  var x = seed;
  return Uint8List.fromList(List.generate(size, (_) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    return x >> 16 & 0xff;
  }));
}

// Example messages: {name} placeholders are replaced by [say].
const en = {
  'intro': 'Practice mode: file:// folder stands in for a web server.',
  's1': '1. created a signing key; public key: {key}',
  's1b': '   signed Example-{v}-setup.exe: {sig}...',
  's2': '2. wrote and signed {path}',
  's3': '3. update found: {v} (build {build})',
  's4': '4. verified {v}: {path}',
  'bug_file': '   BUG: tampered file accepted',
  's5': '5. rejected: {reason} (one byte of the file was changed)',
  'bug_down': '   BUG: downgrade accepted',
  's6': '6. rejected: {reason} (installed build 140 is newer than 130)',
  'bug_feed': '   BUG: tampered feed accepted',
  's7': '7. rejected: feed signature (the feed was changed after signing)',
  'ready': 'Ready to install {v}. (This package version does not '
      'run installers; the Windows installer step is on the roadmap.)',
  'cleanup': 'Delete {dir}/ when you are done.',
  'bad_lang': 'Unknown --lang value "{value}". Use en or ko.',
};
const ko = {
  'intro': '연습 모드: file:// 폴더가 웹 서버를 대신합니다.',
  's1': '1. 서명 키를 만들었습니다. 공개키: {key}',
  's1b': '   Example-{v}-setup.exe 에 서명했습니다: {sig}...',
  's2': '2. {path} 를 만들고 서명했습니다',
  's3': '3. 업데이트를 찾았습니다: {v} (빌드 {build})',
  's4': '4. {v} 검증 완료: {path}',
  'bug_file': '   BUG: 변조된 파일을 받아들였습니다',
  's5': '5. 거절됨: {reason} (파일의 1바이트를 바꿨습니다)',
  'bug_down': '   BUG: 다운그레이드를 받아들였습니다',
  's6': '6. 거절됨: {reason} (설치된 빌드 140 이 130 보다 최신입니다)',
  'bug_feed': '   BUG: 변조된 피드를 받아들였습니다',
  's7': '7. 거절됨: 피드 서명 (서명 뒤에 피드가 바뀌었습니다)',
  'ready': '{v} 설치 준비가 끝났습니다. (이 패키지 버전은 설치 프로그램을 '
      '실행하지 않습니다. Windows 설치 단계는 로드맵에 있습니다.)',
  'cleanup': '끝나면 {dir}/ 를 지우세요.',
  'bad_lang': '알 수 없는 --lang 값 "{value}" 입니다. en 또는 ko 를 쓰세요.',
};

late Map<String, String> _table;

/// Prints the message [key] with {name} placeholders replaced.
void say(String key, [Map<String, Object?> args = const {}]) {
  var text = _table[key]!;
  for (final e in args.entries) {
    text = text.replaceAll('{${e.key}}', '${e.value}');
  }
  print(text);
}

/// Reads --lang en|ko (or --lang=ko); null when absent. Exits 2 when invalid.
Lang? readLangFlag(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    String? value;
    if (args[i] == '--lang') {
      value = i + 1 < args.length ? args[i + 1] : '';
    } else if (args[i].startsWith('--lang=')) {
      value = args[i].substring('--lang='.length);
    }
    if (value == null) continue;
    final parsed = parseLangFlag(value);
    if (parsed == null) {
      stderr.writeln(en['bad_lang']!.replaceAll('{value}', value));
      exit(2);
    }
    return parsed;
  }
  return null;
}

Future<void> main(List<String> args) async {
  final lang =
      resolveLanguage(flag: readLangFlag(args), env: Platform.environment);
  _table = lang == Lang.ko ? ko : en;
  final root = Directory(playground);
  if (root.existsSync()) root.deleteSync(recursive: true);
  final server = Directory('$playground/server')..createSync(recursive: true);
  final downloads = Directory('$playground/downloads');
  say('intro');

  // 1. Release side: make a key and sign two releases.
  final keys = await EdKeyPair.generate();
  say('s1', {'key': keys.publicKey.toBase64()});
  final feed = AppcastWriter.createEmpty('Example');
  for (final v in ['1.2.0', '1.3.0']) {
    final file = File('${server.path}/Example-$v-setup.exe')
      ..writeAsBytesSync(fakeRelease(v.codeUnitAt(2), 64 * 1024));
    final sig = await signFile(file, keys.privateKey);
    say('s1b', {'v': v, 'sig': sig.toSparkleAttributes().substring(0, 40)});
    feed.addItem(
      version: v.replaceAll('.', ''),
      shortVersion: v,
      url: Uri.file(file.absolute.path).toString(),
      length: sig.length,
      edSignature: sig.signature,
      os: 'windows-x64',
      pubDate: DateTime.utc(2026, 11, 12),
    );
  }
  final feedFile = File('${server.path}/appcast.xml');
  final signedFeed = await SignedFeed.sign(
      Uint8List.fromList(feed.toXmlString().codeUnits), keys.privateKey);
  feedFile.writeAsBytesSync(signedFeed);
  say('s2', {'path': '${server.path}/appcast.xml'});

  // 2. App side: the installed app is 1.2.0 (build 120).
  Updater updater({String current = '120'}) => Updater(
        feedUrl: Uri.file(feedFile.absolute.path),
        publicKey: keys.publicKey,
        currentVersion: current,
        os: 'windows-x64',
        requireSignedFeed: true,
      );
  final found = await updater().check();
  final item = found.item!;
  say('s3', {'v': item.shortVersion, 'build': item.version});
  final file = await updater().downloadAndVerify(item, into: downloads);
  say('s4', {'v': item.shortVersion, 'path': file.path});

  // 3. A file changed by one byte must be rejected.
  final tampered = File('$playground/tampered.exe')
    ..writeAsBytesSync(file.readAsBytesSync()..[100] ^= 1);
  try {
    await UpdateVerifier(keys.publicKey)
        .verifyFile(tampered, item, currentVersion: '120');
    say('bug_file');
  } on UpdateVerificationException catch (e) {
    say('s5', {'reason': e.reason.name});
  }

  // 4. Offering an older or equal build must be rejected.
  try {
    await UpdateVerifier(keys.publicKey)
        .verifyFile(file, item, currentVersion: '140');
    say('bug_down');
  } on UpdateVerificationException catch (e) {
    say('s6', {'reason': e.reason.name});
  }

  // 5. A feed changed after signing must be rejected.
  final bytes = feedFile.readAsBytesSync()..[60] ^= 1;
  feedFile.writeAsBytesSync(bytes);
  try {
    await updater().check();
    say('bug_feed');
  } on FeedSignatureException {
    say('s7');
  }

  say('ready', {'v': item.shortVersion});
  say('cleanup', {'dir': playground});
}

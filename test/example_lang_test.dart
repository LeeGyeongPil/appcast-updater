import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../example/main.dart' as example;

final hangul = RegExp(r'[가-힣]');

Future<ProcessResult> runExample(List<String> args,
    [Map<String, String> env = const {}]) {
  // Decode as UTF-8 on every OS (Process.run would use the Windows code page).
  return Process.run(
      Platform.resolvedExecutable, ['run', 'example/main.dart', ...args],
      environment: env, stdoutEncoding: utf8, stderrEncoding: utf8);
}

void main() {
  test('example language tables have the same keys', () {
    expect(example.ko.keys.toSet(), example.en.keys.toSet());
  });

  test('Korean example text keeps English words to identifiers only', () {
    const allowed = {'file', 'Windows'};
    for (final e in example.ko.entries.where((e) => e.key != 'bad_lang')) {
      final stripped = e.value.replaceAll(RegExp(r'\{\w+\}'), '');
      for (final m
          in RegExp(r'[A-Za-z][A-Za-z0-9_-]{3,}').allMatches(stripped)) {
        final w = m.group(0)!;
        final ok = allowed.contains(w) || w.contains('-') || w.contains('_');
        expect(ok, isTrue, reason: 'English word "$w" in ko ${e.key}');
      }
    }
  });

  test('the practice example honors --lang and the environment', () async {
    final ko = await runExample(['--lang', 'ko']);
    expect(ko.exitCode, 0, reason: '${ko.stderr}');
    expect(ko.stdout as String, contains(hangul));
    expect(ko.stdout as String, contains('signatureInvalid'));

    final en = await runExample(['--lang=en'], {'LANG': 'ko_KR.UTF-8'});
    expect(en.exitCode, 0, reason: '${en.stderr}');
    expect(en.stdout as String, isNot(contains(hangul)));
    expect(en.stdout as String, contains('Practice mode'));

    final env = await runExample(
        [], {'APPCAST_UPDATER_LANG': 'ko', 'LANG': 'en_US.UTF-8'});
    expect(env.stdout as String, contains(hangul));

    final bad = await runExample(['--lang', 'xx']);
    expect(bad.exitCode, 2);
  }, timeout: const Timeout(Duration(minutes: 3)));
}

import 'dart:io';

import 'package:appcast_updater/src/cli/cli.dart';
import 'package:appcast_updater/src/cli/i18n.dart';
import 'package:appcast_updater/src/cli/messages_en.dart';
import 'package:appcast_updater/src/cli/messages_ko.dart';
import 'package:test/test.dart';

Future<String> helpWith(List<String> args, Map<String, String> env) async {
  final out = StringBuffer();
  final err = StringBuffer();
  await runCli(args, out: out, err: err, env: env);
  return out.toString() + err.toString();
}

final hangul = RegExp(r'[가-힣]');

void main() {
  group('language priority', () {
    test('--lang beats everything', () {
      final env = {
        'APPCAST_UPDATER_LANG': 'en',
        'LC_ALL': 'en_US.UTF-8',
        'LANG': 'en_US'
      };
      expect(resolveLanguage(flag: Lang.ko, env: env), Lang.ko);
      final ko = {'APPCAST_UPDATER_LANG': 'ko', 'LC_ALL': 'ko_KR.UTF-8'};
      expect(resolveLanguage(flag: Lang.en, env: ko), Lang.en);
    });

    test('APPCAST_UPDATER_LANG beats the locale variables', () {
      expect(
          resolveLanguage(
              env: {'APPCAST_UPDATER_LANG': 'ko', 'LC_ALL': 'en_US.UTF-8'}),
          Lang.ko);
      expect(
          resolveLanguage(
              env: {'APPCAST_UPDATER_LANG': 'en', 'LC_ALL': 'ko_KR.UTF-8'}),
          Lang.en);
    });

    test('LC_ALL beats LC_MESSAGES beats LANG', () {
      expect(
          resolveLanguage(env: {
            'LC_ALL': 'ko_KR.UTF-8',
            'LC_MESSAGES': 'en_US',
            'LANG': 'en_US'
          }),
          Lang.ko);
      expect(resolveLanguage(env: {'LC_MESSAGES': 'ko_KR', 'LANG': 'en_US'}),
          Lang.ko);
      expect(
          resolveLanguage(env: {
            'LC_ALL': 'en_US',
            'LC_MESSAGES': 'ko_KR',
            'LANG': 'ko_KR'
          }),
          Lang.en);
      expect(resolveLanguage(env: {'LANG': 'ko_KR.UTF-8'}), Lang.ko);
    });

    test('empty values are skipped', () {
      expect(
          resolveLanguage(
              env: {'APPCAST_UPDATER_LANG': '', 'LC_ALL': '', 'LANG': 'ko_KR'}),
          Lang.ko);
    });

    test('anything that is not Korean is English', () {
      expect(resolveLanguage(env: {}), Lang.en);
      expect(resolveLanguage(env: {'LANG': 'C'}), Lang.en);
      expect(resolveLanguage(env: {'LANG': 'ja_JP.UTF-8'}), Lang.en);
      expect(resolveLanguage(env: {'LANG': 'de_DE'}), Lang.en);
    });

    test('flag values', () {
      expect(parseLangFlag('ko'), Lang.ko);
      expect(parseLangFlag('EN'), Lang.en);
      expect(parseLangFlag('ko_KR.UTF-8'), Lang.ko);
      expect(parseLangFlag('fr'), isNull);
      expect(parseLangFlag(''), isNull);
    });
  });

  group('the two message tables', () {
    test('have exactly the same keys', () {
      expect(messagesKo.keys.toSet(), messagesEn.keys.toSet());
    });

    test('have the same placeholders per key', () {
      final ph = RegExp(r'\{(\w+)\}');
      for (final k in messagesEn.keys) {
        final en = ph.allMatches(messagesEn[k]!).map((m) => m.group(1)).toSet();
        final ko = ph.allMatches(messagesKo[k]!).map((m) => m.group(1)).toSet();
        expect(ko, en, reason: k);
      }
    });

    test('Korean messages contain Korean, English ones do not', () {
      for (final k in messagesEn.keys) {
        expect(hangul.hasMatch(messagesEn[k]!), isFalse, reason: 'en $k');
        // Korean text: every message has Hangul except pure-token lines
        if (!k.startsWith('ok.keygen_dart')) {
          expect(hangul.hasMatch(messagesKo[k]!), isTrue, reason: 'ko $k');
        }
      }
    });

    test('every command has help in both languages', () {
      for (final c in [
        'main',
        'keygen',
        'pubkey',
        'sign',
        'verify',
        'add',
        'sign-feed',
        'verify-feed',
        'check'
      ]) {
        expect(messagesEn.containsKey('help.$c'), isTrue, reason: c);
        expect(messagesKo.containsKey('help.$c'), isTrue, reason: c);
      }
    });

    test('Messages.t fills placeholders and rejects unknown keys', () {
      final m = Messages(Lang.en);
      expect(m.t('err.file_not_found', {'path': 'x.bin'}),
          'File not found: x.bin');
      expect(() => m.t('nope'), throwsArgumentError);
    });
  });

  group('the CLI really switches', () {
    test('--lang ko / --lang en help', () async {
      final ko = await helpWith(['--lang', 'ko', '--help'], {});
      final en = await helpWith(['--lang', 'en', '--help'], {});
      expect(ko, contains('사용법'));
      expect(ko, isNot(contains('Usage')));
      expect(en, contains('Usage'));
      expect(hangul.hasMatch(en), isFalse);
      expect(ko, isNot(en));
    });

    test('--lang can come after the command', () async {
      final ko = await helpWith(['sign', '--help', '--lang', 'ko'], {});
      expect(ko, contains('사용법'));
    });

    test('the environment picks the language when there is no flag', () async {
      expect(await helpWith(['--help'], {'APPCAST_UPDATER_LANG': 'ko'}),
          contains('사용법'));
      expect(
          await helpWith(['--help'], {'LANG': 'ko_KR.UTF-8'}), contains('사용법'));
      expect(
          await helpWith(['--help'],
              {'LANG': 'ko_KR.UTF-8', 'APPCAST_UPDATER_LANG': 'en'}),
          contains('Usage'));
      expect(await helpWith(['--help'], {'LANG': 'ko_KR.UTF-8'}).then((s) => s),
          isNot(contains('Usage')));
    });

    test('errors are translated, including unknown options', () async {
      final ko = await helpWith(['sign', 'x', '--bogus', '--lang', 'ko'], {});
      expect(ko, contains('알 수 없는 옵션'));
      expect(ko, contains('--bogus'));
      expect(ko, isNot(contains('Unknown')));
      final en = await helpWith(['sign', 'x', '--bogus'], {});
      expect(en, contains('Unknown option'));
      final cmd = await helpWith(['zzz'], {'LANG': 'ko_KR.UTF-8'});
      expect(cmd, contains('알 수 없는 명령'));
      expect(cmd, isNot(contains('Unknown')));
    });

    test('Korean help text does not contain English sentences', () async {
      // Words that may stay: commands, options, file formats, product names.
      const allowed = {
        'appcast',
        'keygen',
        'pubkey',
        'sign',
        'verify',
        'add',
        'check',
        'Sparkle',
        'WinSparkle',
        'Ed25519',
        'EdDSA',
        'EdDSAPub',
        'SUPublicEDKey',
        'SURequireSignedFeed',
        'sign_update',
        'explain',
        'channel',
        'critical',
        'below',
        'replace',
        'file',
        'url',
        'version',
        'short',
        'title',
        'system',
        'phased',
        'interval',
        'notes',
        'installer',
        'arguments',
        'date',
        'group',
        'user',
        'initiated',
        'untagged',
        'means',
        'now',
        'current',
        'out',
        'key',
        'public',
        'lang',
        'help',
        'base64',
        'edSignature',
        'length',
        'windows',
        'macos',
        'Dart',
        'plist',
        'Info',
        'bogus',
        'nope',
        'LANG',
        'sparkle',
        'http',
        'https',
      };
      for (final k in messagesKo.keys
          .where((k) => k.startsWith('help.') || k.startsWith('err.'))) {
        final stripped = messagesKo[k]!.replaceAll(RegExp(r'\{\w+\}'), '');
        final words = RegExp(r'[A-Za-z][A-Za-z0-9_-]{3,}')
            .allMatches(stripped)
            .map((m) => m.group(0)!);
        for (final w in words) {
          final ok = allowed.contains(w) || w.contains('-') || w.contains('_');
          expect(ok, isTrue, reason: 'English word "$w" in ko $k');
        }
      }
    });
  });

  test('the CLI executable runs and honors --lang (process level)', () async {
    final r = await Process.run(Platform.resolvedExecutable,
        ['run', 'appcast_updater:appcast', '--lang', 'ko', '--help']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout as String, contains('사용법'));
    final e = await Process.run(Platform.resolvedExecutable,
        ['run', 'appcast_updater:appcast', '--lang', 'en', '--help']);
    expect(e.stdout as String, contains('Usage'));
    final bad = await Process.run(Platform.resolvedExecutable,
        ['run', 'appcast_updater:appcast', '--nope']);
    expect(bad.exitCode, 2);
  });
}

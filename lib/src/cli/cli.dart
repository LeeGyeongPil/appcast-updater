/// The `appcast` command line. All text goes through [Messages]; nothing is
/// printed directly, so tests can run commands in memory.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../appcast.dart';
import '../errors.dart';
import '../feed_writer.dart';
import '../fetch.dart';
import '../keys.dart';
import '../selector.dart';
import '../signed_feed.dart';
import '../signer.dart';
import 'argparse.dart';
import 'i18n.dart';
import 'io_util.dart';

/// Version printed by `appcast --version`. Keep in sync with pubspec.yaml.
const String packageVersion = '0.1.0';

/// Exit codes.
const int exitOk = 0;
const int exitFailed = 1;
const int exitUsage = 2;
const int exitKey = 3;

/// A failure that ends the command with a message and an exit code.
class _Fail implements Exception {
  _Fail(this.key, this.args, this.code);
  final String key;
  final Map<String, Object?> args;
  final int code;
}

const _keyOption = '--ed-key-file';
const _pubOption = '--public-key';

const Map<String, CommandSpec> _commands = {
  'keygen': CommandSpec(values: {'--out'}),
  'pubkey': CommandSpec(values: {_keyOption}),
  'sign': CommandSpec(
      values: {_keyOption},
      flags: {'-p'},
      minPositionals: 1,
      maxPositionals: 1,
      positionalNames: ['<file>']),
  'verify': CommandSpec(
      values: {_keyOption, _pubOption},
      minPositionals: 2,
      maxPositionals: 2,
      positionalNames: ['<file>', '<signature>']),
  'add': CommandSpec(
      values: {
        '--file',
        '--url',
        '--version',
        '--short-version',
        '--title',
        '--os',
        '--channel',
        '--min-system',
        '--max-system',
        '--phased-interval',
        '--critical-below',
        '--notes-url',
        '--installer-arguments',
        '--pub-date',
        _keyOption,
      },
      flags: {'--critical', '--replace', '--sign-feed'},
      minPositionals: 1,
      maxPositionals: 1,
      positionalNames: ['<appcast.xml>']),
  'sign-feed': CommandSpec(
      values: {_keyOption},
      minPositionals: 1,
      maxPositionals: 1,
      positionalNames: ['<appcast.xml>']),
  'verify-feed': CommandSpec(
      values: {_keyOption, _pubOption},
      minPositionals: 1,
      maxPositionals: 1,
      positionalNames: ['<appcast.xml|url>']),
  'check': CommandSpec(
      values: {
        '--current',
        '--os',
        '--channel',
        '--system-version',
        '--group',
        '--untagged-means',
        '--now',
      },
      flags: {'--explain', '--user-initiated'},
      minPositionals: 1,
      maxPositionals: 1,
      positionalNames: ['<appcast.xml|url>']),
};

/// Runs the CLI. Returns the exit code.
///
/// [env] is the process environment (for the language), [stdin] is read only
/// when a key is passed as `--ed-key-file -`.
Future<int> runCli(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  required Map<String, String> env,
  Stream<List<int>>? stdin,
}) async {
  // --lang is global and may appear anywhere.
  Lang? langFlag;
  final rest = <String>[];
  String? badLang;
  var missingLangValue = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? value;
    if (a == '--lang') {
      if (i + 1 < args.length) {
        value = args[++i];
      } else {
        missingLangValue = true;
        continue;
      }
    } else if (a.startsWith('--lang=')) {
      value = a.substring('--lang='.length);
    } else {
      rest.add(a);
      continue;
    }
    final parsed = parseLangFlag(value);
    if (parsed == null) {
      badLang = value;
    } else {
      langFlag = parsed;
    }
  }
  final m = Messages(resolveLanguage(flag: langFlag, env: env));

  try {
    if (badLang != null) throw UsageError('err.bad_lang', {'value': badLang});
    if (missingLangValue) {
      throw UsageError('err.missing_value', {'option': '--lang'});
    }
    if (rest.isEmpty) throw UsageError('err.missing_command');
    final first = rest.first;
    if (first == '--help' || first == '-h' || first == 'help') {
      out.writeln(m.t('help.main', {'version': packageVersion}));
      return exitOk;
    }
    if (first == '--version') {
      out.writeln('appcast $packageVersion');
      return exitOk;
    }
    final spec = _commands[first];
    if (spec == null) {
      throw UsageError('err.unknown_command', {'command': first});
    }
    final parsed = parseArgs(first, rest.sublist(1), spec);
    if (parsed.help) {
      out.writeln(m.t('help.$first'));
      return exitOk;
    }
    final ctx = _Context(m, out, err, stdin);
    switch (first) {
      case 'keygen':
        return await ctx.keygen(parsed);
      case 'pubkey':
        return await ctx.pubkey(parsed);
      case 'sign':
        return await ctx.sign(parsed);
      case 'verify':
        return await ctx.verify(parsed);
      case 'add':
        return await ctx.add(parsed);
      case 'sign-feed':
        return await ctx.signFeed(parsed);
      case 'verify-feed':
        return await ctx.verifyFeed(parsed);
      default:
        return await ctx.check(parsed);
    }
  } on UsageError catch (e) {
    err.writeln(m.t(e.key, e.args));
    return exitUsage;
  } on _Fail catch (e) {
    err.writeln(m.t(e.key, e.args));
    return e.code;
  } on LegacyKeySigningUnsupported {
    err.writeln(m.t('err.legacy_key'));
    return exitKey;
  } on FileWriteException catch (e) {
    err.writeln(m.t('err.write_failed', {'path': e.path}));
    return exitFailed;
  }
}

class _Context {
  _Context(this.m, this.out, this.err, this.stdin);
  final Messages m;
  final StringSink out;
  final StringSink err;
  final Stream<List<int>>? stdin;

  // ---- input helpers ----

  Future<Uint8List> _readFile(String path) async {
    try {
      return await File(path).readAsBytes();
    } on PathNotFoundException {
      throw _Fail('err.file_not_found', {'path': path}, exitFailed);
    } on FileSystemException {
      throw _Fail('err.cannot_read', {'path': path}, exitFailed);
    }
  }

  Future<String> _readKeyText(ParsedArgs p) async {
    final path = p.option(_keyOption);
    if (path == null) throw _Fail('err.key_required', {}, exitKey);
    if (path == '-') {
      return utf8.decodeStream(stdin ?? const Stream<List<int>>.empty());
    }
    return utf8.decode(await _readFile(path), allowMalformed: true);
  }

  String _keySource(ParsedArgs p) {
    final path = p.option(_keyOption);
    return path == null || path == '-' ? m.t('word.stdin') : path;
  }

  Future<EdPrivateKey> _privateKey(ParsedArgs p) async {
    final text = await _readKeyText(p);
    try {
      return EdPrivateKey.fromKeyFile(text);
    } on KeyFormatException {
      throw _Fail('err.key_format', {'source': _keySource(p)}, exitKey);
    }
  }

  Future<EdPublicKey> _publicKey(ParsedArgs p) async {
    final text = p.option(_pubOption);
    if (text != null) {
      try {
        return EdPublicKey.fromBase64(text);
      } on KeyFormatException {
        throw _Fail('err.pubkey_format', {}, exitKey);
      }
    }
    return (await _privateKey(p)).publicKey();
  }

  /// Reads a feed from a path or from a file/https URL.
  Future<Uint8List> _readFeed(String source) async {
    final lower = source.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('file://')) {
      try {
        return await Fetcher.auto().fetchBytes(Uri.parse(source));
      } on DownloadException {
        throw _Fail('err.download', {'path': source}, exitFailed);
      } on FormatException {
        throw _Fail('err.download', {'path': source}, exitFailed);
      }
    }
    return _readFile(source);
  }

  int _intOption(ParsedArgs p, String name) {
    final v = p.require(name);
    final n = int.tryParse(v);
    if (n == null || n < 0) {
      throw UsageError('err.bad_int', {'option': name, 'value': v});
    }
    return n;
  }

  DateTime _dateOption(String name, String value) {
    final d = parseRfc822(value) ?? DateTime.tryParse(value);
    if (d == null)
      throw UsageError('err.bad_date', {'option': name, 'value': value});
    return d.toUtc();
  }

  // ---- commands ----

  Future<int> keygen(ParsedArgs p) async {
    final path = p.require('--out');
    final pair = await EdKeyPair.generate();
    final file = File(path);
    try {
      await file.create(exclusive: true);
    } on PathExistsException {
      throw _Fail('err.exists', {'path': path}, exitFailed);
    } on FileSystemException {
      throw _Fail('err.write_failed', {'path': path}, exitFailed);
    }
    try {
      if (!Platform.isWindows) await Process.run('chmod', ['600', path]);
    } on ProcessException {
      // permissions are best effort
    }
    try {
      await file.writeAsString('${pair.privateKey.toKeyFileText()}\n');
    } on FileSystemException {
      throw _Fail('err.write_failed', {'path': path}, exitFailed);
    }
    final key = pair.publicKey.toBase64();
    out
      ..writeln(m.t('ok.keygen_written', {'path': path}))
      ..writeln(m.t('ok.keygen_public', {'key': key}))
      ..writeln()
      ..writeln(m.t('ok.keygen_plist'))
      ..writeln('  <key>SUPublicEDKey</key>')
      ..writeln('  <string>$key</string>')
      ..writeln()
      ..writeln(m.t('ok.keygen_winsparkle'))
      ..writeln('  EdDSAPub EDDSA {"$key"}')
      ..writeln()
      ..writeln(m.t('ok.keygen_dart'))
      ..writeln("  EdPublicKey.fromBase64('$key')");
    return exitOk;
  }

  Future<int> pubkey(ParsedArgs p) async {
    final key = await _privateKey(p);
    out.writeln((await key.publicKey()).toBase64());
    return exitOk;
  }

  Future<int> sign(ParsedArgs p) async {
    final bytes = await _readFile(p.positionals.first);
    final key = await _privateKey(p);
    final sig = await signBytes(bytes, key);
    if (p.flag('-p')) {
      out.writeln(sig);
    } else {
      out.writeln(SparkleSignature(sig, bytes.length).toSparkleAttributes());
    }
    return exitOk;
  }

  Future<int> verify(ParsedArgs p) async {
    final bytes = await _readFile(p.positionals[0]);
    final sig = p.positionals[1];
    final key = await _publicKey(p);
    final shapeOk = () {
      try {
        return base64.decode(sig).length == 64;
      } on FormatException {
        return false;
      }
    }();
    if (!shapeOk) {
      err.writeln(m.t('fail.verify_malformed'));
      return exitFailed;
    }
    if (await verifyBytes(bytes, sig, key)) {
      out.writeln(m.t('ok.verify_valid'));
      return exitOk;
    }
    err.writeln(m.t('fail.verify_invalid'));
    return exitFailed;
  }

  Future<int> add(ParsedArgs p) async {
    final feedPath = p.positionals.first;
    // Validate everything before touching any file.
    final releasePath = p.require('--file');
    final url = p.require('--url');
    final version = p.require('--version');
    if (p.option(_keyOption) == null)
      throw _Fail('err.key_required', {}, exitKey);
    final interval = p.option('--phased-interval') == null
        ? null
        : _intOption(p, '--phased-interval');
    final pubDate = p.option('--pub-date') == null
        ? null
        : _dateOption('--pub-date', p.option('--pub-date')!);

    final key = await _privateKey(p);
    final release = await _readFile(releasePath);
    final signature = await signBytes(release, key);
    final sha = crypto.sha256.convert(release).toString();

    final feedFile = File(feedPath);
    AppcastWriter writer;
    var hadSignature = false;
    if (feedFile.existsSync()) {
      final raw = await _readFile(feedPath);
      hadSignature = SignedFeed.hasSignature(raw);
      try {
        writer = AppcastWriter.parse(utf8.decode(SignedFeed.strip(raw)));
      } on AppcastFormatException catch (e) {
        throw _Fail(
            'err.feed_format.${e.reason.name}', {'path': feedPath}, exitFailed);
      } on FormatException {
        throw _Fail('err.feed_format.notUtf8', {'path': feedPath}, exitFailed);
      }
    } else {
      writer = AppcastWriter.createEmpty(p.option('--title') ?? 'Appcast');
    }
    try {
      writer.addItem(
        version: version,
        url: url,
        length: release.length,
        edSignature: signature,
        sha256: sha,
        shortVersion: p.option('--short-version'),
        title: feedFile.existsSync() ? p.option('--title') : null,
        os: p.option('--os'),
        channel: p.option('--channel'),
        minimumSystemVersion: p.option('--min-system'),
        maximumSystemVersion: p.option('--max-system'),
        phasedRolloutInterval: interval,
        critical: p.flag('--critical') || p.option('--critical-below') != null,
        criticalBelowVersion: p.option('--critical-below'),
        releaseNotesLink: p.option('--notes-url'),
        installerArguments: p.option('--installer-arguments'),
        pubDate: pubDate,
        replace: p.flag('--replace'),
      );
    } on DuplicateItemException {
      throw _Fail(
          'err.duplicate',
          {
            'version': version,
            'os': p.option('--os') ?? m.t('word.any_os'),
            'path': feedPath,
          },
          exitFailed);
    }
    var bytes = Uint8List.fromList(utf8.encode(writer.toXmlString()));
    final signAgain = p.flag('--sign-feed');
    if (signAgain) bytes = await SignedFeed.sign(bytes, key);
    writeFileAtomic(feedPath, bytes);
    out.writeln(m.t('ok.added', {
      'version': version,
      'os': p.option('--os') ?? m.t('word.any_os'),
      'path': feedPath,
    }));
    if (hadSignature && !signAgain) {
      err.writeln(m.t('warn.feed_unsigned', {'path': feedPath}));
    }
    return exitOk;
  }

  Future<int> signFeed(ParsedArgs p) async {
    final path = p.positionals.first;
    final raw = await _readFile(path);
    final key = await _privateKey(p);
    writeFileAtomic(path, await SignedFeed.sign(raw, key));
    out.writeln(m.t('ok.feed_signed', {'path': path}));
    return exitOk;
  }

  Future<int> verifyFeed(ParsedArgs p) async {
    final source = p.positionals.first;
    final raw = await _readFeed(source);
    final key = await _publicKey(p);
    try {
      await SignedFeed.verify(raw, key);
    } on FeedSignatureException catch (e) {
      err.writeln(m.t('fail.feed.${e.reason.name}'));
      return exitFailed;
    }
    out.writeln(m.t('ok.feed_valid', {'path': source}));
    return exitOk;
  }

  Future<int> check(ParsedArgs p) async {
    final source = p.positionals.first;
    final current = p.require('--current');
    final os = p.require('--os');
    final group = p.option('--group') == null ? null : _intOption(p, '--group');
    if (group != null && group >= RolloutGroup.count) {
      throw UsageError('err.bad_int', {'option': '--group', 'value': '$group'});
    }
    final now = p.option('--now') == null
        ? null
        : _dateOption('--now', p.option('--now')!);
    final channels = <String>{
      for (final v in p.options['--channel'] ?? const <String>[])
        ...v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
    };
    final raw = await _readFeed(source);
    final Appcast appcast;
    try {
      appcast = Appcast.parseBytes(SignedFeed.strip(raw));
    } on AppcastFormatException catch (e) {
      throw _Fail(
          'err.feed_format.${e.reason.name}', {'path': source}, exitFailed);
    }
    final selection = UpdateSelector(
      currentVersion: current,
      os: os,
      systemVersion: p.option('--system-version'),
      channels: channels,
      rolloutGroup: group,
      userInitiated: p.flag('--user-initiated'),
      untaggedMeans: p.option('--untagged-means'),
      clock: now == null ? null : () => now,
    ).select(appcast);

    final item = selection.item;
    if (item == null) {
      out.writeln(m.t('check.none'));
    } else {
      out.writeln(m.t('check.update', {'label': item.label}));
      if (selection.critical) out.writeln(m.t('check.critical'));
      out.writeln(m.t('check.file', {'url': item.enclosure.url}));
    }
    if (p.flag('--explain')) {
      if (selection.rejections.isNotEmpty)
        out.writeln(m.t('check.explain_head'));
      for (final r in selection.rejections) {
        out.writeln('  ${r.item.label}: ${_why(r)}');
      }
      for (final e in appcast.errors) {
        out.writeln(
            m.t('check.item_error.${e.reason.name}', {'index': e.index + 1}));
      }
    }
    return exitOk;
  }

  String _why(Rejection r) => m.t('why.${r.reason.name}', {
        'expected': r.expected ?? m.t('word.any_os'),
        'actual': r.actual ?? '',
        'group': r.group ?? '',
        'time': r.availableAt?.toUtc().toIso8601String() ?? '',
      });
}

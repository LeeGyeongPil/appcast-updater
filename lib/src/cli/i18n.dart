/// Language choice and message lookup for the CLI.
library;

import 'messages_en.dart';
import 'messages_ko.dart';

/// Languages the CLI speaks.
enum Lang { en, ko }

/// The environment variable that sets the language.
const String langEnvVar = 'APPCAST_UPDATER_LANG';

/// Parses a `--lang` value: `en` or `ko` (also `ko_KR.UTF-8` style).
Lang? parseLangFlag(String value) {
  final v = value.trim().toLowerCase();
  if (v == 'en' || v.startsWith('en_') || v.startsWith('en-')) return Lang.en;
  if (v == 'ko' || v.startsWith('ko_') || v.startsWith('ko-')) return Lang.ko;
  return null;
}

/// Chooses the language: [flag] (`--lang`), then `APPCAST_UPDATER_LANG`, then
/// the first non-empty of `LC_ALL`, `LC_MESSAGES`, `LANG`. A value that starts
/// with `ko` selects Korean; everything else is English.
Lang resolveLanguage({Lang? flag, required Map<String, String> env}) {
  if (flag != null) return flag;
  for (final name in [langEnvVar, 'LC_ALL', 'LC_MESSAGES', 'LANG']) {
    final value = env[name]?.trim() ?? '';
    if (value.isEmpty) continue;
    return value.toLowerCase().startsWith('ko') ? Lang.ko : Lang.en;
  }
  return Lang.en;
}

/// Message table of one language.
class Messages {
  Messages(this.lang) : _table = lang == Lang.ko ? messagesKo : messagesEn;

  final Lang lang;
  final Map<String, String> _table;

  /// The message for [key] with `{name}` placeholders replaced by [args].
  String t(String key, [Map<String, Object?> args = const {}]) {
    var text = _table[key] ?? (throw ArgumentError('unknown message key $key'));
    for (final e in args.entries) {
      text = text.replaceAll('{${e.key}}', '${e.value}');
    }
    return text;
  }
}

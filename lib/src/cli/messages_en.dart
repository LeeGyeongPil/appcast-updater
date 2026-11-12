/// English CLI messages. Keys must match `messages_ko.dart` exactly.
library;

const Map<String, String> messagesEn = {
  'help.main':
      '''appcast {version} - sign releases and check Sparkle-style update feeds

Usage: appcast [--lang en|ko] <command> [options]

Commands:
  keygen       Create an Ed25519 signing key (Sparkle compatible)
  pubkey       Print the public key of a key file
  sign         Sign a release file (same output as Sparkle sign_update)
  verify       Check the signature of a release file
  add          Add a release to an appcast file (creates it if needed)
  sign-feed    Sign an appcast file (SURequireSignedFeed)
  verify-feed  Check the signature of an appcast file or URL
  check        Show which update a given install would get (--explain says why not)

Global options:
  --lang en|ko   Language of this tool (default: APPCAST_UPDATER_LANG, then LC_ALL, LC_MESSAGES, LANG)
  --version      Print the version
  -h, --help     Show this help (also works after a command)

Run 'appcast <command> --help' for the options of a command.
Key files are read with --ed-key-file <file>; use '-' to read the key from standard input.
Exit codes: 0 success, 1 check failed or file problem, 2 wrong usage, 3 key problem.''',
  'help.keygen': '''Usage: appcast keygen --out <file>

Creates a new Ed25519 key. The private key (a 32-byte seed in base64, the format
of Sparkle 2) is written to <file>; the public key is printed together with the
lines to paste into your app. An existing file is never overwritten.''',
  'help.pubkey': '''Usage: appcast pubkey --ed-key-file <file|->

Prints the public key (the SUPublicEDKey value). Works with 32-byte and legacy 96-byte keys.''',
  'help.sign': '''Usage: appcast sign <file> --ed-key-file <file|-> [-p]

Prints sparkle:edSignature="..." length="..." for the file, exactly like Sparkle sign_update.
  -p   Print only the signature''',
  'help.verify':
      '''Usage: appcast verify <file> <signature> (--public-key <base64> | --ed-key-file <file|->)

Exit code 0 if the signature matches the file, 1 if not.''',
  'help.add':
      '''Usage: appcast add <appcast.xml> --file <release file> --url <download url> --version <build number>
                   --ed-key-file <file|-> [options]

Signs the release file and puts a new item on top of the feed. The feed is created if missing.
Options:
  --short-version <text>        Version shown in the UI
  --title <text>                Item title (feed title when creating a feed)
  --os <name>                   For example windows-x64 or macos
  --channel <name>              Channel of this item (default channel if omitted)
  --min-system <version>        Minimum system version
  --max-system <version>        Maximum system version
  --phased-interval <seconds>   Phased rollout interval
  --critical                    Mark as critical update
  --critical-below <version>    Critical only for installs older than this version
  --notes-url <url>             Release notes link
  --installer-arguments <text>  Arguments for the installer
  --pub-date <date>             RFC 822 or ISO 8601 date (default: now)
  --replace                     Replace an item with the same version and os
  --sign-feed                   Sign the feed afterwards
A feed signature is removed when the feed changes; use --sign-feed or run sign-feed afterwards.''',
  'help.sign-feed':
      '''Usage: appcast sign-feed <appcast.xml> --ed-key-file <file|->

Appends (or replaces) the sparkle-signatures comment, which signs the feed text before it.''',
  'help.verify-feed':
      '''Usage: appcast verify-feed <appcast.xml|url> (--public-key <base64> | --ed-key-file <file|->)

Exit code 0 if the feed signature is valid, 1 if not.''',
  'help.check':
      '''Usage: appcast check <appcast.xml|url> --current <version> --os <name> [options]

Shows the update this install would be offered.
Options:
  --explain               List why every other item was not chosen
  --channel <names>       Extra channels, comma separated
  --system-version <v>    System version for minimum/maximum checks
  --group <0-6>           Phased rollout group of this install
  --user-initiated        Pretend the user clicked "check for updates"
  --untagged-means <os>   Treat items without sparkle:os as this os
  --now <date>            Use this date instead of the current time (ISO 8601)''',
  'err.unknown_option':
      'Unknown option: {option}. Run "appcast {command} --help" to see the options.',
  'err.unknown_command':
      'Unknown command: {command}. Run "appcast --help" to see the commands.',
  'err.missing_command':
      'No command given. Run "appcast --help" to see the commands.',
  'err.missing_value': 'Option {option} needs a value.',
  'err.missing_option': 'Missing required option {option}.',
  'err.missing_arg': 'Missing argument: {arg}.',
  'err.extra_arg': 'Unexpected argument: {arg}.',
  'err.bad_lang': 'Unsupported language "{value}". Use en or ko.',
  'err.bad_int': 'Option {option} needs a whole number, got "{value}".',
  'err.bad_date':
      'Option {option} needs a date such as 2026-11-12T00:00:00Z, got "{value}".',
  'err.file_not_found': 'File not found: {path}',
  'err.cannot_read': 'Cannot read {path}.',
  'err.write_failed':
      'Cannot write {path}. Check that the folder exists and is writable.',
  'err.exists':
      'Refusing to overwrite {path}. Choose another file name or delete it first.',
  'err.key_format':
      '{source} is not a valid key file. Expected base64 of a 32-byte seed (or a legacy 96-byte key).',
  'err.pubkey_format': 'The public key is not valid base64 of 32 bytes.',
  'err.key_required':
      'A key is required: pass --ed-key-file <file> (or - for standard input).',
  'err.legacy_key':
      'This is a legacy 96-byte private key. It can print its public key and verify, but signing with it is not supported yet. Sign with Sparkle sign_update, or make a new key with "appcast keygen" (the public key in your app changes too).',
  'err.feed_format.notXml':
      '{path} is not well-formed XML (an empty or cut-off file also looks like this).',
  'err.feed_format.noChannel':
      '{path} is XML but has no <channel> element, so it is not an appcast feed.',
  'err.feed_format.notUtf8':
      '{path} is not UTF-8 text. Save the feed as UTF-8.',
  'err.download':
      'Could not fetch {path}. Check the address and your connection (http:// is refused).',
  'err.duplicate':
      'Version {version} for {os} is already in {path}. Use --replace to overwrite it.',
  'word.stdin': 'standard input',
  'word.any_os': 'any OS',
  'word.default_channel': 'default',
  'ok.keygen_written':
      'Private key written to {path}. Keep it secret and store it as a CI secret.',
  'ok.keygen_public': 'Public key: {key}',
  'ok.keygen_plist': 'Sparkle, in Info.plist:',
  'ok.keygen_winsparkle': 'WinSparkle, in your resource file:',
  'ok.keygen_dart': 'Dart:',
  'ok.verify_valid': 'The signature is valid.',
  'fail.verify_invalid': 'The signature does NOT match the file.',
  'fail.verify_malformed': 'The signature is not base64 of 64 bytes.',
  'ok.added': 'Added {version} ({os}) to {path}.',
  'warn.feed_unsigned':
      'The feed signature was removed because the feed changed. Run "appcast sign-feed {path}" (or use --sign-feed).',
  'ok.feed_signed': 'Signed {path}.',
  'ok.feed_valid': 'The feed signature of {path} is valid.',
  'fail.feed.missing': 'The feed has no signature.',
  'fail.feed.malformed': 'The signature comment is damaged.',
  'fail.feed.lengthMismatch':
      'The feed was changed after signing (length differs).',
  'fail.feed.signatureInvalid':
      'The feed was changed after signing (signature does not match).',
  'check.update': 'Update available: {label}',
  'check.critical': 'This update is critical for the installed version.',
  'check.file': 'File: {url}',
  'check.none': 'No update: nothing newer is offered to this install.',
  'check.explain_head': 'Items not chosen:',
  'check.item_error.missingEnclosure':
      'Item #{index} was skipped: it has no <enclosure> with a url attribute.',
  'check.item_error.badLength':
      'Item #{index} was skipped: the <enclosure> length is missing or not a whole number of bytes.',
  'check.item_error.missingVersion':
      'Item #{index} was skipped: it has no sparkle:version.',
  'check.item_error.badPhasedInterval':
      'Item #{index} was skipped: sparkle:phasedRolloutInterval is not a number of seconds.',
  'check.item_error.badPubDate':
      'Item #{index} was skipped: pubDate is not an RFC 822 date such as "Wed, 12 Nov 2026 00:00:00 +0000".',
  'why.wrongOs': 'built for {expected}, this install is {actual}',
  'why.channelNotAllowed':
      'channel "{expected}" is not enabled (add it with --channel)',
  'why.systemTooOld':
      'needs system {expected} or newer, this install has {actual}',
  'why.systemTooNew':
      'needs system {expected} or older, this install has {actual}',
  'why.informational': 'informational item, nothing to install',
  'why.notNewer': 'not newer than the installed version {actual}',
  'why.rolloutNotYet': 'phased rollout: group {group} is served from {time}',
  'why.superseded': 'a newer item was chosen',
};

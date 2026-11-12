/// Appcast model and parser.
library;

import 'dart:convert';

import 'package:xml/xml.dart';

import 'errors.dart';
import 'version.dart';

/// Namespace URI of Sparkle's extension elements. Prefixes are chosen by the
/// feed author, so elements are always matched by this URI, never by prefix.
const String sparkleNamespace =
    'http://www.andymatuschak.org/xml-namespaces/sparkle';

/// Namespace URI of this package's extension attribute `sha256`.
/// Sparkle and WinSparkle ignore it.
const String auNamespace = 'urn:appcast-updater:1';

/// The downloadable file of an item (`<enclosure>`).
class Enclosure {
  Enclosure({
    required this.url,
    required this.length,
    this.type,
    this.edSignature,
    this.os,
    this.installerArguments,
    this.sha256,
  });

  final String url;

  /// Declared size in bytes.
  final int length;
  final String? type;

  /// Base64 Ed25519 signature (`sparkle:edSignature`).
  final String? edSignature;

  /// `sparkle:os`, for example `windows-x64`. Null means untagged.
  final String? os;

  /// `sparkle:installerArguments` (used by the Windows installer in a later
  /// version).
  final String? installerArguments;

  /// Lowercase hex SHA-256 (`au:sha256`).
  final String? sha256;
}

/// One release (`<item>`).
class AppcastItem {
  AppcastItem({
    required this.version,
    required this.enclosure,
    this.title,
    this.shortVersion,
    this.channel,
    this.critical = false,
    this.criticalBelowVersion,
    this.informational = false,
    this.minimumSystemVersion,
    this.maximumSystemVersion,
    this.phasedRolloutInterval,
    this.pubDate,
    this.releaseNotesLink,
  });

  /// `sparkle:version`, the build number used for comparisons.
  final String version;

  /// `sparkle:shortVersionString`, the version shown in the UI.
  final String? shortVersion;
  final String? title;

  /// `sparkle:channel`. Null is the default channel.
  final String? channel;

  /// Has a `sparkle:criticalUpdate` element.
  final bool critical;

  /// The `sparkle:version` attribute of `criticalUpdate`: only installs older
  /// than this version are critical.
  final String? criticalBelowVersion;

  /// Has a `sparkle:informationalUpdate` element (nothing to download).
  final bool informational;
  final String? minimumSystemVersion;
  final String? maximumSystemVersion;

  /// `sparkle:phasedRolloutInterval` in seconds.
  final int? phasedRolloutInterval;
  final DateTime? pubDate;
  final String? releaseNotesLink;
  final Enclosure enclosure;

  /// Whether this update is critical for an installed [currentVersion]:
  /// a `criticalUpdate` element without a version attribute always is, with
  /// one only when the installed version is older than the attribute.
  bool isCriticalFor(String currentVersion) {
    if (!critical) return false;
    final below = criticalBelowVersion;
    return below == null || compareVersions(currentVersion, below) < 0;
  }

  /// Short label for messages: `1.3.0 (130)`.
  String get label =>
      shortVersion == null ? version : '$shortVersion ($version)';
}

/// Why an `<item>` could not be read.
enum ItemFailure {
  /// No `<enclosure>`, or it has no `url` attribute.
  missingEnclosure,

  /// The enclosure `length` is missing, negative or not a number.
  badLength,

  /// No `sparkle:version`.
  missingVersion,

  /// `sparkle:phasedRolloutInterval` is not a number of seconds.
  badPhasedInterval,

  /// `pubDate` is not an RFC 822 date.
  badPubDate,
}

/// An `<item>` that could not be read.
class ItemError {
  ItemError(this.index, this.message, this.reason);

  /// Zero-based position among the `<item>` elements.
  final int index;
  final String message;
  final ItemFailure reason;
  @override
  String toString() => 'item #${index + 1}: $message';
}

/// A parsed feed.
class Appcast {
  Appcast(this.title, this.items, this.errors);

  /// Parses feed text. Throws [AppcastFormatException] if it is not a feed;
  /// broken items are skipped and listed in [errors].
  factory Appcast.parse(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlException catch (e) {
      throw AppcastFormatException('the feed is not valid XML: ${e.message}',
          reason: FeedFormatFailure.notXml);
    }
    final channel = doc.rootElement.getElement('channel');
    if (channel == null) {
      throw AppcastFormatException('the feed has no <channel> element',
          reason: FeedFormatFailure.noChannel);
    }
    final items = <AppcastItem>[];
    final errors = <ItemError>[];
    var index = 0;
    for (final el in channel.findElements('item')) {
      try {
        items.add(_parseItem(el));
      } on _ItemProblem catch (p) {
        errors.add(ItemError(index, p.message, p.reason));
      }
      index++;
    }
    return Appcast(
        _text(channel.getElement('title')), List.unmodifiable(items), errors);
  }

  /// Like [parse] for raw bytes (UTF-8).
  factory Appcast.parseBytes(List<int> bytes) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw AppcastFormatException('the feed is not valid UTF-8',
          reason: FeedFormatFailure.notUtf8);
    }
    return Appcast.parse(text);
  }

  final String? title;
  final List<AppcastItem> items;

  /// Items that were skipped because they are malformed.
  final List<ItemError> errors;
}

class _ItemProblem implements Exception {
  _ItemProblem(this.reason, this.message);
  final ItemFailure reason;
  final String message;
}

String? _text(XmlElement? el) {
  final t = el?.innerText.trim();
  return t == null || t.isEmpty ? null : t;
}

XmlElement? _ext(XmlElement parent, String local) {
  for (final c in parent.childElements) {
    if (c.name.local == local && c.name.namespaceUri == sparkleNamespace) {
      return c;
    }
  }
  return null;
}

String? _attr(XmlElement el, String local, String namespace) {
  for (final a in el.attributes) {
    if (a.name.local == local && a.name.namespaceUri == namespace) {
      final v = a.value.trim();
      return v.isEmpty ? null : v;
    }
  }
  return null;
}

AppcastItem _parseItem(XmlElement el) {
  final enc = el.getElement('enclosure');
  final String? url = enc?.getAttribute('url');
  if (enc == null || url == null || url.trim().isEmpty) {
    throw _ItemProblem(ItemFailure.missingEnclosure,
        'missing <enclosure> with a url attribute');
  }
  final lengthText = enc.getAttribute('length')?.trim();
  final length = lengthText == null ? null : int.tryParse(lengthText);
  if (length == null || length < 0) {
    throw _ItemProblem(
        ItemFailure.badLength, 'enclosure length is missing or not a number');
  }
  // Old feeds put the version on the enclosure instead of an element.
  final version =
      _text(_ext(el, 'version')) ?? _attr(enc, 'version', sparkleNamespace);
  if (version == null) {
    throw _ItemProblem(ItemFailure.missingVersion, 'missing sparkle:version');
  }
  final interval = _text(_ext(el, 'phasedRolloutInterval'));
  final intervalValue = interval == null ? null : int.tryParse(interval);
  if (interval != null && (intervalValue == null || intervalValue < 0)) {
    throw _ItemProblem(
        ItemFailure.badPhasedInterval, 'phasedRolloutInterval is not a number');
  }
  final pubText = _text(el.getElement('pubDate'));
  final pub = pubText == null ? null : parseRfc822(pubText);
  if (pubText != null && pub == null) {
    throw _ItemProblem(
        ItemFailure.badPubDate, 'pubDate is not an RFC 822 date');
  }
  final criticalEl = _ext(el, 'criticalUpdate');
  final sha = _attr(enc, 'sha256', auNamespace)?.toLowerCase();
  return AppcastItem(
    version: version,
    title: _text(el.getElement('title')),
    shortVersion: _text(_ext(el, 'shortVersionString')) ??
        _attr(enc, 'shortVersionString', sparkleNamespace),
    channel: _text(_ext(el, 'channel')),
    critical: criticalEl != null,
    criticalBelowVersion: criticalEl == null
        ? null
        : _attr(criticalEl, 'version', sparkleNamespace),
    informational: _ext(el, 'informationalUpdate') != null,
    minimumSystemVersion: _text(_ext(el, 'minimumSystemVersion')),
    maximumSystemVersion: _text(_ext(el, 'maximumSystemVersion')),
    phasedRolloutInterval: intervalValue,
    pubDate: pub,
    releaseNotesLink: _text(_ext(el, 'releaseNotesLink')),
    enclosure: Enclosure(
      url: url.trim(),
      length: length,
      type: enc.getAttribute('type'),
      edSignature: _attr(enc, 'edSignature', sparkleNamespace),
      os: _attr(enc, 'os', sparkleNamespace),
      installerArguments: _attr(enc, 'installerArguments', sparkleNamespace),
      sha256: sha,
    ),
  );
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

final RegExp _rfc822 =
    RegExp(r'^(?:[A-Za-z]{3},\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
        r'(\d{2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|GMT|UTC|UT|Z)?$');

/// Parses an RFC 822 date such as `Wed, 12 Nov 2026 00:00:00 +0000` into UTC.
/// Returns null when [text] is not one.
DateTime? parseRfc822(String text) {
  final m = _rfc822.firstMatch(text.trim());
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  final zone = m.group(7);
  var offset = Duration.zero;
  if (zone != null && (zone.startsWith('+') || zone.startsWith('-'))) {
    final sign = zone.startsWith('-') ? -1 : 1;
    offset = Duration(
        hours: int.parse(zone.substring(1, 3)),
        minutes: int.parse(zone.substring(3, 5)));
    if (sign < 0) offset = -offset;
  }
  final local = DateTime.utc(
    int.parse(m.group(3)!),
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  );
  return local.subtract(offset);
}

/// Formats [date] as an RFC 822 date in UTC.
String formatRfc822(DateTime date) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final u = date.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[u.weekday - 1]}, ${two(u.day)} ${months[u.month - 1]} '
      '${u.year} ${two(u.hour)}:${two(u.minute)}:${two(u.second)} +0000';
}

/// Reads one `<item>` element, or returns null if it is malformed. Used by
/// the feed writer; not part of the public API.
AppcastItem? tryParseItemElement(XmlElement el) {
  try {
    return _parseItem(el);
  } on _ItemProblem {
    return null;
  }
}

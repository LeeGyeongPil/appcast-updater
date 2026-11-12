/// Creating and extending appcast files.
library;

import 'package:xml/xml.dart';

import 'appcast.dart';
import 'errors.dart';
import 'version.dart';

/// Edits an appcast file in place: new items go on top, existing text is left
/// as it is. A signature comment must be removed first (see
/// `SignedFeed.strip`) and added again after editing.
class AppcastWriter {
  AppcastWriter._(this._doc, this._channel);

  /// A new feed with one `<channel>`.
  factory AppcastWriter.createEmpty(String title) {
    final t = XmlText(title).toXmlString();
    return AppcastWriter.parse('<?xml version="1.0" encoding="utf-8"?>\n'
        '<rss version="2.0" xmlns:sparkle="$sparkleNamespace" '
        'xmlns:au="$auNamespace">\n'
        '  <channel>\n    <title>$t</title>\n  </channel>\n</rss>\n');
  }

  /// Opens existing feed text.
  factory AppcastWriter.parse(String xml) {
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
    return AppcastWriter._(doc, channel);
  }

  final XmlDocument _doc;
  final XmlElement _channel;

  /// Prefix bound to [uri] on the root element, declaring [preferred] if the
  /// feed does not use the namespace yet.
  String _prefix(String uri, String preferred) {
    final root = _doc.rootElement;
    for (final a in root.attributes) {
      if (a.name.prefix == 'xmlns' && a.value == uri) return a.name.local;
    }
    root.attributes
        .add(XmlAttribute(XmlName.fromString('xmlns:$preferred'), uri));
    return preferred;
  }

  /// Adds an item at the top of the channel.
  ///
  /// Throws [DuplicateItemException] if an item with the same version and os
  /// exists, unless [replace] is true (the old item is removed).
  void addItem({
    required String version,
    required String url,
    required int length,
    String? edSignature,
    String? sha256,
    String? shortVersion,
    String? title,
    String? os,
    String? channel,
    String? minimumSystemVersion,
    String? maximumSystemVersion,
    int? phasedRolloutInterval,
    bool critical = false,
    String? criticalBelowVersion,
    String? releaseNotesLink,
    String? installerArguments,
    String type = 'application/octet-stream',
    DateTime? pubDate,
    bool replace = false,
  }) {
    final duplicates = <XmlElement>[];
    for (final el in _channel.findElements('item').toList()) {
      final existing = tryParseItemElement(el);
      if (existing == null) continue;
      final sameOs = (existing.enclosure.os ?? '').toLowerCase() ==
          (os ?? '').toLowerCase();
      if (sameOs && compareVersions(existing.version, version) == 0) {
        duplicates.add(el);
      }
    }
    if (duplicates.isNotEmpty && !replace) {
      throw DuplicateItemException(version, os);
    }
    for (final el in duplicates) {
      _removeWithIndent(el);
    }

    final sp = _prefix(sparkleNamespace, 'sparkle');
    final au = sha256 == null ? 'au' : _prefix(auNamespace, 'au');
    const pad = '\n      ';
    final children = <XmlNode>[];
    void leaf(String name, String text,
        [Map<String, String> attrs = const {}]) {
      children.add(XmlText(pad));
      children.add(XmlElement(
          XmlName.fromString(name),
          [
            for (final e in attrs.entries)
              XmlAttribute(XmlName.fromString(e.key), e.value)
          ],
          text.isEmpty ? [] : [XmlText(text)]));
    }

    leaf('title', title ?? shortVersion ?? version);
    leaf('pubDate', formatRfc822(pubDate ?? DateTime.now().toUtc()));
    leaf('$sp:version', version);
    if (shortVersion != null) leaf('$sp:shortVersionString', shortVersion);
    if (channel != null) leaf('$sp:channel', channel);
    if (critical) {
      leaf('$sp:criticalUpdate', '', {
        if (criticalBelowVersion != null) '$sp:version': criticalBelowVersion
      });
    }
    if (minimumSystemVersion != null) {
      leaf('$sp:minimumSystemVersion', minimumSystemVersion);
    }
    if (maximumSystemVersion != null) {
      leaf('$sp:maximumSystemVersion', maximumSystemVersion);
    }
    if (phasedRolloutInterval != null) {
      leaf('$sp:phasedRolloutInterval', '$phasedRolloutInterval');
    }
    if (releaseNotesLink != null)
      leaf('$sp:releaseNotesLink', releaseNotesLink);
    leaf('enclosure', '', {
      'url': url,
      if (os != null) '$sp:os': os,
      if (edSignature != null) '$sp:edSignature': edSignature,
      if (installerArguments != null)
        '$sp:installerArguments': installerArguments,
      if (sha256 != null) '$au:sha256': sha256,
      'length': '$length',
      'type': type,
    });
    children.add(XmlText('\n    '));

    final item = XmlElement(XmlName('item'), const [], children);
    final first = _channel.findElements('item').firstOrNull;
    if (first != null) {
      final at = _channel.children.indexOf(first);
      _channel.children.insertAll(at, [item, XmlText('\n    ')]);
    } else {
      // after the last child, before the closing tag
      final trailing = _channel.children.isNotEmpty &&
              _channel.children.last is XmlText &&
              _channel.children.last.value!.trim().isEmpty
          ? _channel.children.removeLast()
          : null;
      _channel.children.addAll([XmlText('\n    '), item]);
      _channel.children.add(trailing ?? XmlText('\n  '));
    }
  }

  void _removeWithIndent(XmlElement el) {
    final parent = el.parent!;
    final at = parent.children.indexOf(el);
    parent.children.removeAt(at);
    if (at < parent.children.length) {
      final next = parent.children[at];
      if (next is XmlText && next.value.trim().isEmpty) {
        parent.children.removeAt(at);
      }
    }
  }

  /// The feed text.
  String toXmlString() => _doc.toXmlString();
}

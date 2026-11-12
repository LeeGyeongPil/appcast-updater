import 'dart:io';
import 'dart:typed_data';

import 'package:appcast_updater/appcast_updater.dart';
import 'package:test/test.dart';

/// A fresh temporary folder that is removed after the test. Its path is never
/// printed or compared.
Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('appcast_test_');
  addTearDown(() => _removeTempDir(dir));
  return dir;
}

/// Removes a test folder.
///
/// On Windows a file that is still open (or being scanned by antivirus)
/// cannot be deleted, so a cleanup failure there is retried a few times and
/// then ignored: the folder lives in the system temp folder and a leftover
/// must not fail the test. On other OSes a failure is a real bug and is
/// reported as is.
Future<void> _removeTempDir(Directory dir) async {
  if (!Platform.isWindows) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    return;
  }
  for (var attempt = 1; attempt <= 5; attempt++) {
    if (!dir.existsSync()) return;
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      // Wait a little for the handle to close, then try again.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}

/// One `<item>` as feed text.
String itemXml({
  required String version,
  String? os,
  String? channel,
  String? pubDate,
  int? interval,
  String? critical, // '' = element without version, otherwise the attribute
  String? minSystem,
  String? maxSystem,
  bool informational = false,
  int length = 10,
  String? signature,
  String? sha256,
}) =>
    '''
    <item>
      <title>v$version</title>
      ${pubDate == null ? '' : '<pubDate>$pubDate</pubDate>'}
      <sparkle:version>$version</sparkle:version>
      ${channel == null ? '' : '<sparkle:channel>$channel</sparkle:channel>'}
      ${critical == null ? '' : critical.isEmpty ? '<sparkle:criticalUpdate/>' : '<sparkle:criticalUpdate sparkle:version="$critical"/>'}
      ${minSystem == null ? '' : '<sparkle:minimumSystemVersion>$minSystem</sparkle:minimumSystemVersion>'}
      ${maxSystem == null ? '' : '<sparkle:maximumSystemVersion>$maxSystem</sparkle:maximumSystemVersion>'}
      ${interval == null ? '' : '<sparkle:phasedRolloutInterval>$interval</sparkle:phasedRolloutInterval>'}
      ${informational ? '<sparkle:informationalUpdate/>' : ''}
      <enclosure url="https://downloads.example.com/Example-$version.exe" ${os == null ? '' : 'sparkle:os="$os"'} ${signature == null ? '' : 'sparkle:edSignature="$signature"'} ${sha256 == null ? '' : 'au:sha256="$sha256"'} length="$length" type="application/octet-stream"/>
    </item>''';

/// A whole feed around [items].
String feedXml(List<String> items) => '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:au="urn:appcast-updater:1">
  <channel>
    <title>Example</title>
${items.join('\n')}
  </channel>
</rss>
''';

Appcast feedOf(List<String> items) => Appcast.parse(feedXml(items));

/// Deterministic test content.
Uint8List bytesOf(int length, [int salt = 0]) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 7 + salt) & 0xff));

/// A key made from a fixed seed. Test-only, not a secret.
EdPrivateKey testKey([int salt = 1]) =>
    EdPrivateKey.fromSeed(List.generate(32, (i) => (i + salt) & 0xff));

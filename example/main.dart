// Offline practice run (no network, nothing is installed).
//
// Real: key generation, Ed25519 signing and verification, sha256, feed
// signing, tamper detection, downgrade blocking.
// Fake: the "download server" is a folder read through file:// URLs, and the
// installer step is only announced.
//
//     dart run example/main.dart
//
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:appcast_updater/appcast_updater.dart';

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

Future<void> main() async {
  final root = Directory(playground);
  if (root.existsSync()) root.deleteSync(recursive: true);
  final server = Directory('$playground/server')..createSync(recursive: true);
  final downloads = Directory('$playground/downloads');
  print('Practice mode: file:// folder stands in for a web server.');

  // 1. Release side: make a key and sign two releases.
  final keys = await EdKeyPair.generate();
  print('1. created a signing key; public key: ${keys.publicKey.toBase64()}');
  final feed = AppcastWriter.createEmpty('Example');
  for (final v in ['1.2.0', '1.3.0']) {
    final file = File('${server.path}/Example-$v-setup.exe')
      ..writeAsBytesSync(fakeRelease(v.codeUnitAt(2), 64 * 1024));
    final sig = await signFile(file, keys.privateKey);
    print(
        '   signed Example-$v-setup.exe: ${sig.toSparkleAttributes().substring(0, 40)}...');
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
  print('2. wrote and signed ${server.path}/appcast.xml');

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
  print('3. update found: ${item.shortVersion} (build ${item.version})');
  final file = await updater().downloadAndVerify(item, into: downloads);
  print('4. verified ${item.shortVersion}: ${file.path}');

  // 3. A file changed by one byte must be rejected.
  final tampered = File('$playground/tampered.exe')
    ..writeAsBytesSync(file.readAsBytesSync()..[100] ^= 1);
  try {
    await UpdateVerifier(keys.publicKey)
        .verifyFile(tampered, item, currentVersion: '120');
    print('   BUG: tampered file accepted');
  } on UpdateVerificationException catch (e) {
    print('5. rejected: ${e.reason.name} (one byte of the file was changed)');
  }

  // 4. Offering an older or equal build must be rejected.
  try {
    await UpdateVerifier(keys.publicKey)
        .verifyFile(file, item, currentVersion: '140');
    print('   BUG: downgrade accepted');
  } on UpdateVerificationException catch (e) {
    print(
        '6. rejected: ${e.reason.name} (installed build 140 is newer than 130)');
  }

  // 5. A feed changed after signing must be rejected.
  final bytes = feedFile.readAsBytesSync()..[60] ^= 1;
  feedFile.writeAsBytesSync(bytes);
  try {
    await updater().check();
    print('   BUG: tampered feed accepted');
  } on FeedSignatureException {
    print('7. rejected: feed signature (the feed was changed after signing)');
  }

  print('Ready to install ${item.shortVersion}. (This package version does not '
      'run installers; the Windows installer step is on the roadmap.)');
  print('Delete $playground/ when you are done.');
}

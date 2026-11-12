/// The app-side entry point: check for an update, download it, verify it.
library;

import 'dart:io';

import 'appcast.dart';
import 'errors.dart';
import 'fetch.dart';
import 'keys.dart';
import 'selector.dart';
import 'signed_feed.dart';
import 'verifier.dart';

/// What [Updater.check] found.
class UpdateCheck {
  UpdateCheck(this.appcast, this.selection, this.feedWasSigned);

  /// The parsed feed (with the signature comment removed).
  final Appcast appcast;
  final Selection selection;

  /// The feed carried a valid signature.
  final bool feedWasSigned;

  /// The item to offer, or null if the app is up to date.
  AppcastItem? get item => selection.item;

  /// The offered item is critical for this install.
  bool get critical => selection.critical;
}

/// Checks a feed and downloads verified updates.
///
///     final updater = Updater(
///       feedUrl: Uri.parse('https://downloads.example.com/appcast.xml'),
///       publicKey: EdPublicKey.fromBase64(publicKeyFromInfoPlist),
///       currentVersion: '120',
///       os: 'windows-x64',
///       requireSignedFeed: true,
///     );
///     final found = await updater.check();
///     if (found.item != null) {
///       final file = await updater.downloadAndVerify(found.item!, into: dir);
///     }
class Updater {
  Updater({
    required this.feedUrl,
    required this.publicKey,
    required this.currentVersion,
    required this.os,
    this.systemVersion,
    this.channels = const {},
    this.rolloutGroup,
    this.requireSignedFeed = false,
    this.userInitiated = false,
    this.untaggedMeans,
    this.maxFeedBytes = 5 * 1024 * 1024,
    Fetcher? fetcher,
    DateTime Function()? clock,
  })  : fetcher = fetcher ?? Fetcher.auto(),
        _clock = clock;

  final Uri feedUrl;

  /// The pinned public key (`SUPublicEDKey`).
  final EdPublicKey publicKey;
  final String currentVersion;
  final String os;
  final String? systemVersion;
  final Set<String> channels;
  final int? rolloutGroup;

  /// Refuse feeds without a valid signature comment. A feed that carries a
  /// signature is always verified, whatever this flag says.
  final bool requireSignedFeed;
  final bool userInitiated;
  final String? untaggedMeans;
  final int maxFeedBytes;
  final Fetcher fetcher;
  final DateTime Function()? _clock;

  /// Fetches the feed, verifies its signature and picks an update.
  Future<UpdateCheck> check() async {
    final raw = await fetcher.fetchBytes(feedUrl, maxBytes: maxFeedBytes);
    var signed = false;
    var body = raw;
    if (SignedFeed.hasSignature(raw)) {
      body = await SignedFeed.verify(raw, publicKey);
      signed = true;
    } else if (requireSignedFeed) {
      throw FeedSignatureException('the feed has no sparkle-signatures comment',
          reason: FeedFailure.missing);
    }
    final appcast = Appcast.parseBytes(body);
    final selection = UpdateSelector(
      currentVersion: currentVersion,
      os: os,
      systemVersion: systemVersion,
      channels: channels,
      rolloutGroup: rolloutGroup,
      userInitiated: userInitiated,
      untaggedMeans: untaggedMeans,
      clock: _clock,
    ).select(appcast);
    return UpdateCheck(appcast, selection, signed);
  }

  /// Downloads the file of [item] into [into] and verifies it (size,
  /// signature, sha256, downgrade). The file gets its final name only after
  /// verification; on any failure nothing is left behind.
  Future<File> downloadAndVerify(AppcastItem item,
      {required Directory into, bool allowUnsigned = false}) async {
    final url = Uri.parse(item.enclosure.url);
    // A remote feed must not make the client read local files. Only a feed
    // that itself lives on disk (file://) may point at file:// enclosures.
    if (url.scheme == 'file' && feedUrl.scheme != 'file') {
      throw DownloadException(
          'the feed at $feedUrl points at a file:// enclosure, which is only '
          'allowed when the feed itself is a file:// URL');
    }
    final name = _safeName(url, item);
    await into.create(recursive: true);
    final partial = File('${into.path}${Platform.pathSeparator}.$name.part');
    final target = File('${into.path}${Platform.pathSeparator}$name');
    try {
      await fetcher.download(url, partial, maxBytes: item.enclosure.length);
      await UpdateVerifier(publicKey, allowUnsigned: allowUnsigned)
          .verifyFile(partial, item, currentVersion: currentVersion);
      await partial.rename(target.path);
      return target;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  /// A file name that cannot escape the download folder.
  static String _safeName(Uri url, AppcastItem item) {
    final last = url.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    final cleaned = (last ?? 'update-${item.version}')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'^\.+'), '_');
    return cleaned.isEmpty ? 'update-${item.version}' : cleaned;
  }
}

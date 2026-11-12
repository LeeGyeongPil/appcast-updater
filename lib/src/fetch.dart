/// Getting feeds and update files from `file://` and `https://` URLs.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'errors.dart';

/// Where feeds and update files come from.
abstract class Fetcher {
  /// Fetches [uri] into memory. Fails with [DownloadException] as soon as
  /// more than [maxBytes] arrive.
  Future<Uint8List> fetchBytes(Uri uri, {int maxBytes = 5 * 1024 * 1024});

  /// Streams [uri] into [destination]. Fails with [DownloadException] as soon
  /// as more than [maxBytes] arrive; the partial file is deleted.
  Future<void> download(Uri uri, File destination, {required int maxBytes});

  /// Picks the implementation by scheme: `file` and `https` (and `http` only
  /// when [allowInsecureHttp] is true).
  factory Fetcher.auto({
    bool allowInsecureHttp = false,
    Duration timeout = const Duration(minutes: 5),
  }) =>
      _SchemeFetcher(FileFetcher(),
          HttpFetcher(allowInsecureHttp: allowInsecureHttp, timeout: timeout));
}

Future<void> _drain(
  Stream<List<int>> source,
  IOSink sink,
  int maxBytes,
  String what,
) async {
  var total = 0;
  await for (final chunk in source) {
    total += chunk.length;
    if (total > maxBytes) {
      throw DownloadException(
          '$what is larger than the allowed $maxBytes bytes; aborted');
    }
    sink.add(chunk);
  }
}

Future<void> _downloadWith(
  Stream<List<int>> Function() open,
  File destination,
  int maxBytes,
  String what,
) async {
  final sink = destination.openWrite();
  try {
    await _drain(open(), sink, maxBytes, what);
    await sink.close();
  } catch (_) {
    try {
      await sink.close();
    } catch (_) {
      // the original error matters more
    }
    if (await destination.exists()) await destination.delete();
    rethrow;
  }
}

/// Reads `file://` URLs.
class FileFetcher implements Fetcher {
  File _file(Uri uri) {
    if (uri.scheme != 'file') {
      throw DownloadException(
          'FileFetcher only reads file:// URLs, got "$uri"');
    }
    return File(uri.toFilePath());
  }

  @override
  Future<Uint8List> fetchBytes(Uri uri,
      {int maxBytes = 5 * 1024 * 1024}) async {
    final file = _file(uri);
    final builder = BytesBuilder(copy: false);
    var total = 0;
    try {
      await for (final chunk in file.openRead()) {
        total += chunk.length;
        if (total > maxBytes) {
          throw DownloadException(
              '$uri is larger than the allowed $maxBytes bytes');
        }
        builder.add(chunk);
      }
    } on FileSystemException catch (e) {
      throw DownloadException('cannot read $uri: ${e.message}');
    }
    return builder.takeBytes();
  }

  @override
  Future<void> download(Uri uri, File destination,
      {required int maxBytes}) async {
    final file = _file(uri);
    try {
      await _downloadWith(file.openRead, destination, maxBytes, '$uri');
    } on FileSystemException catch (e) {
      throw DownloadException('cannot copy $uri: ${e.message}');
    }
  }
}

/// Reads `https://` URLs (and `http://` only if allowed). Redirects are
/// followed by hand, at most five, and every hop is checked against the same
/// scheme rule, so an https URL can not redirect to plain http.
class HttpFetcher implements Fetcher {
  HttpFetcher({
    this.allowInsecureHttp = false,
    this.timeout = const Duration(minutes: 5),
    HttpClient? client,
  }) : _injected = client;

  /// Allow `http://`. Off by default because anyone on the network can then
  /// read and replace the feed (signature checks still apply to the content).
  final bool allowInsecureHttp;

  /// Limit for connecting and for each wait for data.
  final Duration timeout;
  final HttpClient? _injected;

  void _checkScheme(Uri uri) {
    if (uri.scheme == 'https') return;
    if (uri.scheme == 'http' && allowInsecureHttp) return;
    if (uri.scheme == 'http') {
      throw DownloadException(
          'refusing plain http URL "$uri"; use https or set allowInsecureHttp: true');
    }
    throw DownloadException('unsupported URL scheme "${uri.scheme}" in "$uri"');
  }

  Future<HttpClientResponse> _open(HttpClient client, Uri start) async {
    var uri = start;
    for (var hop = 0; hop <= 5; hop++) {
      _checkScheme(uri);
      final HttpClientResponse response;
      try {
        final request = await client.getUrl(uri).timeout(timeout);
        request.followRedirects = false;
        response = await request.close().timeout(timeout);
      } on SocketException catch (e) {
        throw DownloadException('cannot reach $uri: ${e.message}');
      } on TimeoutException {
        throw DownloadException('timed out waiting for $uri');
      } on HandshakeException catch (e) {
        throw DownloadException('TLS error for $uri: ${e.message}');
      }
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null)
          throw DownloadException('redirect without location from $uri');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw DownloadException('$uri answered HTTP ${response.statusCode}');
      }
      return response;
    }
    throw DownloadException('too many redirects from $start');
  }

  @override
  Future<Uint8List> fetchBytes(Uri uri,
      {int maxBytes = 5 * 1024 * 1024}) async {
    final client = _injected ?? HttpClient();
    try {
      final response = await _open(client, uri);
      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.timeout(timeout)) {
        total += chunk.length;
        if (total > maxBytes) {
          throw DownloadException(
              '$uri is larger than the allowed $maxBytes bytes');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      if (_injected == null) client.close(force: true);
    }
  }

  @override
  Future<void> download(Uri uri, File destination,
      {required int maxBytes}) async {
    final client = _injected ?? HttpClient();
    try {
      final response = await _open(client, uri);
      await _downloadWith(
          () => response.timeout(timeout), destination, maxBytes, '$uri');
    } finally {
      if (_injected == null) client.close(force: true);
    }
  }
}

class _SchemeFetcher implements Fetcher {
  _SchemeFetcher(this._file, this._http);
  final FileFetcher _file;
  final HttpFetcher _http;

  Fetcher _pick(Uri uri) => uri.scheme == 'file' ? _file : _http;

  @override
  Future<Uint8List> fetchBytes(Uri uri, {int maxBytes = 5 * 1024 * 1024}) =>
      _pick(uri).fetchBytes(uri, maxBytes: maxBytes);

  @override
  Future<void> download(Uri uri, File destination, {required int maxBytes}) =>
      _pick(uri).download(uri, destination, maxBytes: maxBytes);
}

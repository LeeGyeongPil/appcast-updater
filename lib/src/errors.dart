/// Exceptions thrown by the package. Messages are English and meant for
/// developers; the CLI maps these types to localized messages.
library;

/// Why [AppcastFormatException] was thrown.
enum FeedFormatFailure {
  /// The text is not well-formed XML (an empty file counts).
  notXml,

  /// The XML has no `<channel>` element under the root.
  noChannel,

  /// The bytes are not UTF-8.
  notUtf8,
}

/// The appcast XML is not usable (not XML, no channel element, ...).
class AppcastFormatException implements Exception {
  AppcastFormatException(this.message,
      {this.reason = FeedFormatFailure.notXml});
  final String message;
  final FeedFormatFailure reason;
  @override
  String toString() => 'AppcastFormatException: $message';
}

/// Why [UpdateVerificationException] was thrown.
enum VerifyFailure {
  /// The file size differs from the `length` attribute (checked first,
  /// before any file content is read).
  lengthMismatch,

  /// The item has no `sparkle:edSignature`.
  signatureMissing,

  /// The signature is not base64 of 64 bytes.
  signatureMalformed,

  /// The Ed25519 signature does not match the file.
  signatureInvalid,

  /// The `au:sha256` attribute does not match the file.
  sha256Mismatch,

  /// The item version is not newer than the installed version.
  downgrade,
}

/// A downloaded file failed verification. Never install such a file.
class UpdateVerificationException implements Exception {
  UpdateVerificationException(this.reason, this.message);
  final VerifyFailure reason;
  final String message;
  @override
  String toString() => 'UpdateVerificationException(${reason.name}): $message';
}

/// Why [FeedSignatureException] was thrown.
enum FeedFailure {
  /// No `sparkle-signatures` comment at the end of the feed.
  missing,

  /// The comment is incomplete or has unexpected content.
  malformed,

  /// The declared length differs from the feed body length.
  lengthMismatch,

  /// The signature does not match the feed body.
  signatureInvalid,
}

/// The feed signature is missing, malformed or does not match the feed body.
class FeedSignatureException implements Exception {
  FeedSignatureException(this.message, {this.reason = FeedFailure.malformed});
  final String message;
  final FeedFailure reason;
  @override
  String toString() => 'FeedSignatureException: $message';
}

/// A key file or key string is not a valid Ed25519 key.
class KeyFormatException implements Exception {
  KeyFormatException(this.message);
  final String message;
  @override
  String toString() => 'KeyFormatException: $message';
}

/// The 96-byte legacy private key format can be used to verify and to
/// extract the public key, but signing with it is not supported yet.
class LegacyKeySigningUnsupported implements Exception {
  @override
  String toString() =>
      'LegacyKeySigningUnsupported: signing with a legacy 96-byte private '
      'key is not supported yet; use Sparkle sign_update or a 32-byte seed key';
}

/// A download was refused or aborted (insecure URL, too large, I/O error).
class DownloadException implements Exception {
  DownloadException(this.message);
  final String message;
  @override
  String toString() => 'DownloadException: $message';
}

/// A file could not be written. [path] is the path the caller asked for.
class FileWriteException implements Exception {
  FileWriteException(this.path, this.message);
  final String path;
  final String message;
  @override
  String toString() => 'FileWriteException: cannot write $path: $message';
}

/// An item with the same version and os is already in the feed.
class DuplicateItemException implements Exception {
  DuplicateItemException(this.version, this.os);
  final String version;
  final String? os;
  @override
  String toString() =>
      'DuplicateItemException: version $version (os: ${os ?? 'any'}) already '
      'exists; pass replace: true to overwrite it';
}

/// Sparkle-compatible appcast parsing, EdDSA signing and update verification.
///
/// Check for an update with `Updater`, sign releases with `signFile` and
/// `SignedFeed`, and write feeds with `AppcastWriter`.
library;

export 'src/appcast.dart'
    show
        Appcast,
        AppcastItem,
        Enclosure,
        ItemError,
        ItemFailure,
        auNamespace,
        formatRfc822,
        parseRfc822,
        sparkleNamespace;
export 'src/errors.dart';
export 'src/feed_writer.dart' show AppcastWriter;
export 'src/fetch.dart' show Fetcher, FileFetcher, HttpFetcher;
export 'src/keys.dart' show EdKeyPair, EdPrivateKey, EdPublicKey;
export 'src/selector.dart'
    show
        RejectReason,
        Rejection,
        RolloutGroup,
        RolloutGroupStore,
        Selection,
        UpdateSelector;
export 'src/signed_feed.dart' show SignedFeed;
export 'src/signer.dart'
    show SparkleSignature, signBytes, signFile, verifyBytes;
export 'src/updater.dart' show UpdateCheck, Updater;
export 'src/verifier.dart' show UpdateVerifier;
export 'src/version.dart' show compareVersions;

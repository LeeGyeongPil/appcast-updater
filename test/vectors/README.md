# Test vectors

## `sparkle-2.10.1.json`, `feed-body.xml`, `signed-feed.xml`

Made with the real Sparkle `sign_update` (release 2.10.1, archive sha256
`1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27`, checked 2026-11-12).

- **Seed:** bytes `0..31` (a test-only key that protects nothing; the tests build it in code).
  Sparkle read it as a base64 key file.
- **Public key:** derived from the seed with OpenSSL (PKCS#8 wrapper around the seed, last 32 bytes of the public DER).
- **Message:** 1,000,000 bytes, byte `i` = `i % 251`.
  `sign_update --ed-key-file seed.txt message.bin` printed the line stored in `message_sign_update_output`.
  `sign_update --verify --ed-key-file seed.txt message.bin <signature>` returned 0 (`message_verify_rc`).
- **Signed feed:** `feed-body.xml` is a small hand-written feed. Sparkle's feed-signing mode could not
  save its output inside the build sandbox, so the body was signed as a plain file and the comment was
  added by hand in the format of Sparkle's `SPUExtractSignedFeed`:

  ```
  <!-- sparkle-signatures:
  edSignature: <base64>
  length: <body length>
  -->
  ```

  Then `sign_update --verify --ed-key-file seed.txt signed-feed.xml` returned 0 (`feed_verify_rc`), and the
  same command on a copy with one flipped byte returned 1 (`feed_tampered_verify_rc`).

The tests check, in both directions: Dart verifies what Sparkle signed, Dart prints the same line as
Sparkle, and Dart signs the feed body with the same bytes.

RFC 8032 vectors (section 7.1, tests 1 and 2) are public standard vectors and live in `sparkle_compat_test.dart`.
They are not secrets.

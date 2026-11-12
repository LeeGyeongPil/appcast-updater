/// File helpers for the CLI.
library;

import 'dart:io';

import '../errors.dart';

/// Writes [bytes] to [path] through a temporary file in the same folder and
/// renames it into place, so a reader never sees a half-written file. Errors
/// are reported with [path], the path the caller asked for.
void writeFileAtomic(String path, List<int> bytes) {
  final target = File(path);
  final tmp = File('$path.tmp${pid}');
  try {
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(path);
  } on FileSystemException catch (e) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } on FileSystemException {
      // nothing more to do
    }
    throw FileWriteException(target.path, e.message);
  }
}

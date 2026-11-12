/// Version comparison with the same rules as Sparkle's
/// `SUStandardVersionComparator` (Sparkle 2.10.1).
library;

enum _Kind { number, string, separator }

final RegExp _digit = RegExp(r'^[0-9]$');
final RegExp _space = RegExp(r'^\s$');
final RegExp _punct = RegExp(r'^\p{P}$', unicode: true);

_Kind _kindOf(String ch) {
  if (ch == '.') return _Kind.separator;
  if (_digit.hasMatch(ch)) return _Kind.number;
  if (_space.hasMatch(ch) || _punct.hasMatch(ch)) return _Kind.separator;
  return _Kind.string;
}

/// Splits into runs of the same kind; every separator is its own part and a
/// dash ends the version (`1.0-beta` is `1.0`).
List<String> _split(String version) {
  final parts = <String>[];
  final buffer = StringBuffer();
  _Kind? current;
  for (final rune in version.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '-') break;
    final kind = _kindOf(ch);
    if (current != null && (kind != current || kind == _Kind.separator)) {
      parts.add(buffer.toString());
      buffer.clear();
    }
    buffer.write(ch);
    current = kind;
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString());
  return parts;
}

/// Number of leading parts that are numbers or '.' separators.
int _numericPrefix(List<String> parts) {
  var n = 0;
  while (n < parts.length &&
      (parts[n] == '.' || _kindOf(parts[n][0]) == _Kind.number)) {
    n++;
  }
  return n;
}

/// `1.0` and `1.0.0` must line up: pad the shorter numeric prefix with `.0`.
void _pad(List<String> a, List<String> b) {
  final pa = _numericPrefix(a);
  final pb = _numericPrefix(b);
  if (pa == pb) return;
  final shorter = pa < pb ? a : b;
  final at = pa < pb ? pa : pb;
  final pairs = (pa - pb).abs() ~/ 2;
  shorter.insertAll(at, [
    for (var i = 0; i < pairs; i++) ...['.', '0'],
  ]);
}

int _compareNumbers(String a, String b) {
  final x = a.replaceFirst(RegExp(r'^0+(?=.)'), '');
  final y = b.replaceFirst(RegExp(r'^0+(?=.)'), '');
  if (x.length != y.length) return x.length < y.length ? -1 : 1;
  return x.compareTo(y).sign;
}

/// Returns a negative number if [a] is older than [b], zero if they are the
/// same version and a positive number if [a] is newer.
///
/// Rules (Sparkle): parts compare numerically, otherwise as text; a number is
/// newer than text (`1.0beta` < `1.0`); a version that continues with text is
/// older (`2.0b1` < `2.0`), one that continues with a separator or number is
/// newer (`1.0 beta` > `1.0`); `-` and everything after it is ignored.
int compareVersions(String a, String b) {
  final pa = _split(a);
  final pb = _split(b);
  _pad(pa, pb);
  final n = pa.length < pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final ka = _kindOf(pa[i][0]);
    final kb = _kindOf(pb[i][0]);
    if (ka == kb) {
      final c = ka == _Kind.number
          ? _compareNumbers(pa[i], pb[i])
          : pa[i].compareTo(pb[i]).sign;
      if (c != 0) return c;
    } else if (ka != _Kind.string && kb == _Kind.string) {
      return 1;
    } else if (ka == _Kind.string && kb != _Kind.string) {
      return -1;
    } else {
      // number against separator: the separator is the invalid one
      return ka == _Kind.number ? 1 : -1;
    }
  }
  if (pa.length == pb.length) return 0;
  final longerIsA = pa.length > pb.length;
  final extra = longerIsA ? pa[n] : pb[n];
  final extraIsText = _kindOf(extra[0]) == _Kind.string;
  // longer version with text next is older; otherwise longer is newer
  if (longerIsA) return extraIsText ? -1 : 1;
  return extraIsText ? 1 : -1;
}

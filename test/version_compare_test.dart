// Rules from Sparkle's SUStandardVersionComparator (2.10.1):
// https://raw.githubusercontent.com/sparkle-project/Sparkle/2.10.1/Sparkle/SUStandardVersionComparator.m
import 'package:appcast_updater/appcast_updater.dart';
import 'package:test/test.dart';

void main() {
  // [a, b, expected sign of compareVersions(a, b)]
  const cases = <(String, String, int)>[
    ('1.0', '1.0.0', 0),
    ('1.0.0', '1.0', 0),
    ('1.10', '1.9', 1),
    ('1.9', '1.10', -1),
    ('1.0beta', '1.0', -1),
    ('1.0', '1.0beta', 1),
    ('1.0 beta', '1.0', 1),
    ('1.0-beta', '1.0', 0),
    ('130', '120', 1),
    ('2.0b1', '2.0', -1),
    ('1.0a', '1.0b', -1),
    ('1.0', '1.0.1', -1),
    ('1.0.0.0', '1', 0),
    ('2.0', '1.99.99', 1),
    ('1.0', '1.0beta1', 1),
    ('007', '7', 0),
    ('99999999999999999999', '99999999999999999998', 1),
    ('1.0.1beta', '1.0', 1),
  ];

  for (final (a, b, expected) in cases) {
    test('compareVersions("$a", "$b") is ${expected.sign}', () {
      expect(compareVersions(a, b).sign, expected);
      // the order must be antisymmetric
      expect(compareVersions(b, a).sign, -expected);
    });
  }

  test('a version equals itself', () {
    for (final v in ['1', '1.2.3', '2.0b1', '130', '']) {
      expect(compareVersions(v, v), 0);
    }
  });
}

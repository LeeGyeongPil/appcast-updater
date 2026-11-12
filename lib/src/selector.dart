/// Picking the update an installed app should be offered.
library;

import 'dart:io';
import 'dart:math';

import 'appcast.dart';
import 'version.dart';

/// Why an item was not chosen.
enum RejectReason {
  /// `sparkle:os` does not match this machine.
  wrongOs,

  /// The item is on a channel this app did not opt in to.
  channelNotAllowed,

  /// The machine is older than `minimumSystemVersion`.
  systemTooOld,

  /// The machine is newer than `maximumSystemVersion`.
  systemTooNew,

  /// Informational items have nothing to download.
  informational,

  /// The item is not newer than the installed version.
  notNewer,

  /// Phased rollout: this install's group is not served yet.
  rolloutNotYet,

  /// A newer item was chosen instead.
  superseded,
}

/// A rejected item with the facts behind the decision.
class Rejection {
  Rejection(this.item, this.reason,
      {this.expected, this.actual, this.availableAt, this.group});

  final AppcastItem item;
  final RejectReason reason;

  /// What the item requires (os, channel, system version) when relevant.
  final String? expected;

  /// What this install has when relevant.
  final String? actual;

  /// For [RejectReason.rolloutNotYet]: when this group is served.
  final DateTime? availableAt;

  /// For [RejectReason.rolloutNotYet]: this install's group.
  final int? group;

  /// English description for logs.
  String get detail {
    switch (reason) {
      case RejectReason.wrongOs:
        return 'os is ${expected ?? 'untagged'}, this machine is $actual';
      case RejectReason.channelNotAllowed:
        return 'channel "$expected" is not enabled';
      case RejectReason.systemTooOld:
        return 'needs system $expected or newer, this machine is $actual';
      case RejectReason.systemTooNew:
        return 'needs system $expected or older, this machine is $actual';
      case RejectReason.informational:
        return 'informational item, nothing to install';
      case RejectReason.notNewer:
        return 'not newer than the installed version $actual';
      case RejectReason.rolloutNotYet:
        return 'rollout group $group is served from '
            '${availableAt?.toUtc().toIso8601String()}';
      case RejectReason.superseded:
        return 'a newer version was chosen';
    }
  }
}

/// The outcome of [UpdateSelector.select].
class Selection {
  Selection(this.item, this.critical, this.rejections);

  /// The chosen item, or null when there is nothing to offer.
  final AppcastItem? item;

  /// Whether the chosen item is critical for this install.
  final bool critical;

  /// Every item that was not chosen, in feed order.
  final List<Rejection> rejections;
}

/// Applies Sparkle's selection rules for one install.
class UpdateSelector {
  UpdateSelector({
    required this.currentVersion,
    required this.os,
    this.systemVersion,
    this.channels = const {},
    this.rolloutGroup,
    this.userInitiated = false,
    this.untaggedMeans,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Installed `sparkle:version`.
  final String currentVersion;

  /// This machine, for example `windows-x64`.
  final String os;

  /// Operating system version, for the min/max checks. Null skips them.
  final String? systemVersion;

  /// Non-default channels this install accepts. The default channel (items
  /// without `sparkle:channel`) is always included.
  final Set<String> channels;

  /// This install's phased rollout group 0..6. Null skips the rollout check.
  final int? rolloutGroup;

  /// A user asked for the check: phased rollout is ignored.
  final bool userInitiated;

  /// How to read items without `sparkle:os`. Null means they match every
  /// OS (WinSparkle behavior); `macos` matches Sparkle for macOS.
  final String? untaggedMeans;
  final DateTime Function() _clock;

  bool _osMatches(String? itemOs) {
    final tag = itemOs ?? untaggedMeans;
    if (tag == null) return true;
    final a = tag.toLowerCase();
    final b = os.toLowerCase();
    // `windows` covers `windows-x64`, `windows-arm64`, ...
    return a == b || b.startsWith('$a-');
  }

  /// Chooses the newest acceptable item of [appcast].
  Selection select(Appcast appcast) {
    final rejections = <Rejection>[];
    AppcastItem? best;
    final accepted = <AppcastItem>[];
    for (final item in appcast.items) {
      final r = _check(item);
      if (r != null) {
        rejections.add(r);
        continue;
      }
      accepted.add(item);
      if (best == null || compareVersions(item.version, best.version) > 0) {
        best = item;
      }
    }
    for (final item in accepted) {
      if (!identical(item, best)) {
        rejections.add(Rejection(item, RejectReason.superseded));
      }
    }
    // keep feed order
    final order = {
      for (var i = 0; i < appcast.items.length; i++) appcast.items[i]: i,
    };
    rejections.sort((a, b) => order[a.item]!.compareTo(order[b.item]!));
    return Selection(
        best, best != null && best.isCriticalFor(currentVersion), rejections);
  }

  Rejection? _check(AppcastItem item) {
    if (!_osMatches(item.enclosure.os)) {
      return Rejection(item, RejectReason.wrongOs,
          expected: item.enclosure.os, actual: os);
    }
    final ch = item.channel;
    if (ch != null && !channels.contains(ch)) {
      return Rejection(item, RejectReason.channelNotAllowed, expected: ch);
    }
    final sys = systemVersion;
    final min = item.minimumSystemVersion;
    final max = item.maximumSystemVersion;
    if (sys != null && min != null && compareVersions(sys, min) < 0) {
      return Rejection(item, RejectReason.systemTooOld,
          expected: min, actual: sys);
    }
    if (sys != null && max != null && compareVersions(sys, max) > 0) {
      return Rejection(item, RejectReason.systemTooNew,
          expected: max, actual: sys);
    }
    if (item.informational) {
      return Rejection(item, RejectReason.informational);
    }
    if (compareVersions(item.version, currentVersion) <= 0) {
      return Rejection(item, RejectReason.notNewer, actual: currentVersion);
    }
    final group = rolloutGroup;
    final interval = item.phasedRolloutInterval;
    final pub = item.pubDate;
    final ignoresRollout = item.isCriticalFor(currentVersion) || userInitiated;
    if (!ignoresRollout && group != null && interval != null && pub != null) {
      final at = pub.add(Duration(seconds: interval * group));
      if (_clock().isBefore(at)) {
        return Rejection(item, RejectReason.rolloutNotYet,
            availableAt: at, group: group);
      }
    }
    return null;
  }
}

/// Phased rollout groups: 0..6, a new group every interval.
class RolloutGroup {
  RolloutGroup._();

  /// Number of groups.
  static const int count = 7;

  /// A random group.
  static int random([Random? random]) => (random ?? Random()).nextInt(count);
}

/// Remembers the rollout group of this install in a small text file, so
/// the same install always lands in the same group.
class RolloutGroupStore {
  RolloutGroupStore(this.file);
  final File file;

  /// The saved group, or null if none was saved or the file is unreadable.
  int? load() {
    try {
      final n = int.tryParse(file.readAsStringSync().trim());
      return n != null && n >= 0 && n < RolloutGroup.count ? n : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Saves [group].
  void save(int group) {
    if (group < 0 || group >= RolloutGroup.count) {
      throw RangeError.range(group, 0, RolloutGroup.count - 1, 'group');
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$group\n');
  }

  /// Returns the saved group, picking and saving a random one the first time.
  int loadOrCreate([Random? random]) {
    final saved = load();
    if (saved != null) return saved;
    final group = RolloutGroup.random(random);
    save(group);
    return group;
  }
}

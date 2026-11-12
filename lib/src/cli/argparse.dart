/// A small argument parser: `--name value`, `--name=value`, flags, `-p`.
library;

/// Thrown for wrong usage. [key] is a message key, [args] its placeholders.
class UsageError implements Exception {
  UsageError(this.key, [this.args = const {}]);
  final String key;
  final Map<String, Object?> args;
}

/// The options one command accepts.
class CommandSpec {
  const CommandSpec({
    this.values = const {},
    this.flags = const {},
    this.minPositionals = 0,
    this.maxPositionals = 0,
    this.positionalNames = const [],
  });

  /// Options that take a value, such as `--out`.
  final Set<String> values;

  /// Options without a value, such as `--explain` or `-p`. `--help` and
  /// `-h` are always accepted.
  final Set<String> flags;
  final int minPositionals;
  final int maxPositionals;

  /// Names for "missing argument" messages.
  final List<String> positionalNames;
}

/// The parsed command line of one command.
class ParsedArgs {
  ParsedArgs(this.positionals, this.options, this.flags);
  final List<String> positionals;
  final Map<String, List<String>> options;
  final Set<String> flags;

  bool get help => flags.contains('--help') || flags.contains('-h');
  bool flag(String name) => flags.contains(name);

  /// The last value given for [name].
  String? option(String name) => options[name]?.last;

  /// Like [option] but fails with a usage error if missing.
  String require(String name) =>
      option(name) ??
      (throw UsageError('err.missing_option', {'option': name}));
}

/// Parses [args] (without the command name) with [spec].
ParsedArgs parseArgs(String command, List<String> args, CommandSpec spec) {
  final positionals = <String>[];
  final options = <String, List<String>>{};
  final flags = <String>{};
  var onlyPositionals = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (onlyPositionals || arg == '-' || !arg.startsWith('-')) {
      positionals.add(arg);
      continue;
    }
    if (arg == '--') {
      onlyPositionals = true;
      continue;
    }
    final eq = arg.startsWith('--') ? arg.indexOf('=') : -1;
    final name = eq > 0 ? arg.substring(0, eq) : arg;
    if (name == '--help' || name == '-h' || spec.flags.contains(name)) {
      flags.add(name);
    } else if (spec.values.contains(name)) {
      if (eq > 0) {
        options.putIfAbsent(name, () => []).add(arg.substring(eq + 1));
      } else if (i + 1 < args.length) {
        options.putIfAbsent(name, () => []).add(args[++i]);
      } else {
        throw UsageError('err.missing_value', {'option': name});
      }
    } else {
      throw UsageError(
          'err.unknown_option', {'option': name, 'command': command});
    }
  }
  if (flags.contains('--help') || flags.contains('-h')) {
    return ParsedArgs(positionals, options, flags);
  }
  if (positionals.length > spec.maxPositionals) {
    throw UsageError(
        'err.extra_arg', {'arg': positionals[spec.maxPositionals]});
  }
  if (positionals.length < spec.minPositionals) {
    final name = spec.positionalNames.length > positionals.length
        ? spec.positionalNames[positionals.length]
        : '<arg>';
    throw UsageError('err.missing_arg', {'arg': name});
  }
  return ParsedArgs(positionals, options, flags);
}

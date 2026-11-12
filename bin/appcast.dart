import 'dart:io';

import 'package:appcast_updater/src/cli/cli.dart';

Future<void> main(List<String> args) async {
  final code = await runCli(
    args,
    out: stdout,
    err: stderr,
    env: Platform.environment,
    stdin: stdin,
  );
  await stdout.flush();
  await stderr.flush();
  exit(code);
}

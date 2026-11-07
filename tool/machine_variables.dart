// The variables this machine's own settings hold that a process may not
// have been handed — read from those settings for a session
// (session_hooks/install.dart writes them into its settings) and for the
// GPU engine's build hook (packages/gpu_engine/hook/build.dart), whose
// environment the hooks runner filters them out of.
import 'dart:io';

/// The variables this machine's own settings hold and a session may not
/// have been handed: the Rust toolchain's homes.
///
/// 유저 2026-11-07 (gpu-engine-skeleton-Q7): 「세션 설정에 두 변수를 적는다
/// — install.dart 가 이 기계의 윈도 설정에서 읽어 적게」. The desktop app
/// hands a session the environment it was itself started with: on the main
/// PC it started on 10-29 and Rust went onto D: on 11-05, so every session's
/// cargo kept a second home on C: (`~/.cargo`, `~/.rustup`) while the
/// landing chain read D: — a crate one session fetched was missing to the
/// other, and a land was refused for it. Off Windows a session's shell
/// reads the login profile, which holds them already.
const kMachineVariables = ['CARGO_HOME', 'RUSTUP_HOME'];

/// [kMachineVariables] as [read] finds them, the ones it has, slashed.
Map<String, String> machineVariables(String? Function(String name) read) => {
  for (final name in kMachineVariables)
    if (read(name) case final value? when value.trim().isNotEmpty)
      name: slashed(value.trim()),
};

/// [kMachineVariables] as this machine's own settings hold them: on
/// Windows the user's, and none anywhere else.
Map<String, String> thisMachinesVariables() => Platform.isWindows
    ? machineVariables(windowsUserVariable)
    : const <String, String>{};

/// [name]'s value in what `reg query HKCU\Environment /v <name>` printed,
/// with the `%VARIABLE%`s of an expandable value [expand]ed; null when it
/// printed none.
String? registryValue(
  String printed,
  String name,
  String Function(String variable) expand,
) {
  final line = RegExp(
    '^\\s+${RegExp.escape(name)}\\s+(REG_SZ|REG_EXPAND_SZ)\\s+(.*?)\\s*\$',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(printed);
  if (line == null) return null;
  final value = line.group(2)!;
  return line.group(1)!.toUpperCase() == 'REG_SZ'
      ? value
      : value.replaceAllMapped(
          RegExp('%([^%]+)%'),
          (variable) => expand(variable.group(1)!),
        );
}

/// [name] as Windows keeps it for this user, whatever this process was
/// handed.
String? windowsUserVariable(String name) {
  final asked = Process.runSync('reg', [
    'query',
    r'HKCU\Environment',
    '/v',
    name,
  ]);
  if (asked.exitCode != 0) return null;
  return registryValue(
    '${asked.stdout}',
    name,
    (variable) => Platform.environment[variable] ?? '%$variable%',
  );
}

/// [path] the way a POSIX shell and a settings file both read it.
String slashed(String path) {
  final forward = path.replaceAll('\\', '/');
  return forward.length > 1 && forward.endsWith('/')
      ? forward.substring(0, forward.length - 1)
      : forward;
}

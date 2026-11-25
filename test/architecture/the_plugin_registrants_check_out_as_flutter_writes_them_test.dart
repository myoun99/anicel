import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/git_attributes.dart';

/// 🚨★★Flutter rewrites its plugin registrants on every `pub get`, in LF.
///
/// A checkout under `core.autocrlf` handed them back as CRLF, so every lane
/// that ran one flutter command showed all of them as modified — line
/// endings and nothing else — and `lane.sh land` refused the dirty lane.
/// Measured 2026-09-10 in one lane: re-checked out under the old attributes
/// the seven came back `w/crlf` and `flutter pub get` turned all seven into
/// `M`; with `eol=lf` the same two steps left the lane clean.
///
/// The rule lives in `.gitattributes`; this checks it covers every
/// registrant the desktop platforms keep. ⚠️IN-PROCESS, not by asking git:
/// `tests_do_not_race_the_code_test` bans spawning, so the registrants are
/// listed from disk and matched with the part of git's pattern rules that
/// file uses ([eolRulesOf]). iOS and Android are not scanned — their
/// registrants are gitignored (`ios/.gitignore`, `android/.gitignore`), so
/// no checkout ever writes them.
void main() {
  test('every desktop plugin registrant checks out as LF', () {
    final registrant = RegExp(
      r'^(generated_plugin_registrant\.\w+|generated_plugins\.cmake|'
      r'GeneratedPluginRegistrant\.\w+)$',
    );
    const folders = [
      'linux/flutter',
      'windows/flutter',
      'macos/Flutter',
      // The GPU engine's measurement app: tool/resolve_packages.sh's
      // `pub get` in packages/gpu_engine rewrites these too.
      'packages/gpu_engine/example/windows/flutter',
      'packages/gpu_engine/example/linux/flutter',
      'packages/gpu_engine/example/macos/Flutter',
    ];
    final found = <String>[
      for (final folder in folders)
        for (final entity in Directory(folder).listSync())
          if (entity is File)
            if (entity.uri.pathSegments.last case final name
                when registrant.hasMatch(name))
              '$folder/$name',
    ];
    for (final folder in folders) {
      expect(
        found.any((path) => path.startsWith('$folder/')),
        isTrue,
        reason: 'fixture: $folder keeps its registrants',
      );
    }

    final eolOf = eolRulesOf('.gitattributes');

    expect(
      [
        for (final path in found)
          if (eolOf(path) != 'lf') '$path: eol=${eolOf(path)}',
      ],
      isEmpty,
      reason: 'flutter writes these in LF; a checkout that hands them back '
          'as CRLF makes every lane look modified after one flutter command, '
          'and `lane.sh land` refuses a dirty lane — cover the file in the '
          'plugin registrant block of `.gitattributes`',
    );
  });
}

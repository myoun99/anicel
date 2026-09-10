import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
/// file uses ([_gitPattern]). iOS and Android are not scanned — their
/// registrants are gitignored (`ios/.gitignore`, `android/.gitignore`), so
/// no checkout ever writes them.
void main() {
  test('every desktop plugin registrant checks out as LF', () {
    final registrant = RegExp(
      r'^(generated_plugin_registrant\.\w+|generated_plugins\.cmake|'
      r'GeneratedPluginRegistrant\.\w+)$',
    );
    const folders = ['linux/flutter', 'windows/flutter', 'macos/Flutter'];
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

    final rules = <(RegExp, String)>[];
    for (final raw in File('.gitattributes').readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final fields = line.split(RegExp(r'\s+'));
      for (final attribute in fields.skip(1)) {
        if (attribute.startsWith('eol=')) {
          rules.add((_gitPattern(fields.first), attribute.substring(4)));
        }
      }
    }
    String eolOf(String path) {
      var eol = 'unspecified';
      for (final (pattern, value) in rules) {
        if (pattern.hasMatch(path)) {
          eol = value; // The last rule that matches wins, as in git.
        }
      }
      return eol;
    }

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

/// git's pattern rules, as far as `.gitattributes` uses them: a pattern
/// with a slash is anchored at the repository root and one without matches
/// a file name at any depth; `**` crosses directories, `*` and `?` stay
/// inside one path segment.
RegExp _gitPattern(String pattern) {
  final relative = pattern.startsWith('/') ? pattern.substring(1) : pattern;
  final body = StringBuffer();
  for (var i = 0; i < relative.length; i += 1) {
    if (relative.startsWith('**', i)) {
      body.write('.*');
      i += 1;
    } else if (relative[i] == '*') {
      body.write('[^/]*');
    } else if (relative[i] == '?') {
      body.write('[^/]');
    } else {
      body.write(RegExp.escape(relative[i]));
    }
  }
  return RegExp(pattern.contains('/') ? '^$body\$' : '(^|/)$body\$');
}

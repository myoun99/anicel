// ignore_for_file: avoid_print
// The other half of `session_forwarders.dart` (G4-1, 2026-09-08): once a
// forwarder is DELETED, every call site of it is a compile error, and
// `flutter analyze` names each one file:line:col. This inserts the
// collaborator at exactly that column — `session.projectFps` becomes
// `session.projectSettings.projectFps` — so nothing is guessed by pattern.
//
//   flutter analyze > a.log 2>&1
//   dart run tool/refactor/session_receiver.dart a.log spec.json [--dry]
//
// 🚨WHY THE COLUMN AND NOT A REGEX: this codebase has Korean identifiers
// and comments on the same lines, and analyzer columns are UTF-16 offsets.
// A column-anchored insertion survives them; a regex sweep over the line
// does not (measured 2026-09-04, when a batch replace corrupted Korean).
//
// The spec is a JSON list of groups:
//   [{"getter": "projectSettings",
//     "members": {"projectFps": "projectFps",
//                 "projectTimelineLayout": "projectLayout"}}]
// The value is the name ON the collaborator — the two differ whenever the
// forwarder renamed the verb on its way through the host.
//
// Only errors that say `for the type 'EditorSessionManager'` are touched,
// so a same-named member on another type is left alone. An error whose
// column does not actually hold the member name is REFUSED, not guessed.
import 'dart:convert';
import 'dart:io';

const _hostType = "for the type 'EditorSessionManager'";

void main(List<String> args) {
  final log = File(args[0]).readAsLinesSync();
  final spec = (jsonDecode(File(args[1]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final dry = args.contains('--dry');

  final replacement = <String, String>{};
  for (final group in spec) {
    final getter = group['getter'] as String;
    for (final e in (group['members'] as Map<String, dynamic>).entries) {
      replacement[e.key] = '$getter.${e.value}';
    }
  }

  // file -> (line, col, member), 1-based as the analyzer reports them.
  final edits = <String, List<(int, int, String)>>{};
  final unknown = <String>{};
  // `flutter analyze` writes `… - lib\src\a.dart:12:34 - undefined_getter`.
  final locus = RegExp(r'\s-\s(\S+\.dart):(\d+):(\d+)\s-\s');
  final quoted = RegExp("'([A-Za-z_][A-Za-z0-9_]*)'");
  for (final line in log) {
    if (!line.contains(_hostType)) continue;
    final where = locus.firstMatch(line);
    final what = quoted.firstMatch(line);
    if (where == null || what == null) continue;
    final member = what.group(1)!;
    if (!replacement.containsKey(member)) {
      unknown.add(member);
      continue;
    }
    (edits[where.group(1)!.trim().replaceAll(r'\', '/')] ??= []).add((
      int.parse(where.group(2)!),
      int.parse(where.group(3)!),
      member,
    ));
  }

  var applied = 0;
  var refused = 0;
  for (final entry in edits.entries) {
    final file = File(entry.key);
    final lines = file.readAsStringSync().split('\n');
    // Bottom-up, right-to-left: an earlier edit must not move a later one.
    final sorted = entry.value.toList()
      ..sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : b.$2.compareTo(a.$2));
    for (final (ln, col, member) in sorted) {
      final text = lines[ln - 1];
      final at = col - 1;
      if (at + member.length > text.length ||
          text.substring(at, at + member.length) != member) {
        print('REFUSED ${entry.key}:$ln:$col does not hold "$member"');
        refused += 1;
        continue;
      }
      lines[ln - 1] =
          text.substring(0, at) +
          replacement[member]! +
          text.substring(at + member.length);
      applied += 1;
    }
    if (!dry) file.writeAsStringSync(lines.join('\n'));
  }
  for (final m in unknown) {
    print('NOT IN SPEC $m');
  }
  print(
    'inserted $applied receivers in ${edits.length} files'
    '${refused > 0 ? ', $refused refused' : ''}${dry ? ' (dry)' : ''}',
  );
  if (refused > 0) exit(2);
}

// ignore_for_file: avoid_print
// G3 of the god-object decomposition: a verb that MOVED to a collaborator
// takes its call sites with it. `session.foo()` becomes
// `session.<collaborator>.foo()` everywhere — ⛔no forwarder is left on the
// host, so a call site this misses is a COMPILE ERROR, not a silent
// survivor. That is the safety net: `flutter analyze` names the rest.
//
//   dart run tool/refactor/session_call_sites.dart <spec.json> [--dry]
//
// The spec is a JSON object:
//   {"receivers": ["s", "session", ...],      // session-typed expressions
//    "roots": ["lib", "test"],
//    "skip": ["lib/src/ui/editor_session_manager.dart", ...],
//    "moves": [{"getter": "layerVerbs", "members": ["deleteActiveLayer"]}]}
//
// A rewrite fires only when the receiver text is one of `receivers` — a
// same-named method on another type (`LayerController.toggleLayerVisibility`,
// `cutCommandCoordinator.renameLayer`) is left alone.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final spec =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final dry = args.contains('--dry');
  // Longest first: `widget.session` must win over `session`, or the
  // alternation matches the tail and the lookbehind refuses it.
  final receivers = (spec['receivers'] as List).cast<String>()
    ..sort((a, b) => b.length.compareTo(a.length));
  final roots = (spec['roots'] as List).cast<String>();
  final skip = ((spec['skip'] as List?) ?? const []).cast<String>().toSet();
  final getterOf = <String, String>{};
  for (final move in (spec['moves'] as List).cast<Map<String, dynamic>>()) {
    for (final m in (move['members'] as List).cast<String>()) {
      getterOf[m] = move['getter'] as String;
    }
  }
  final recvAlt = receivers.map(RegExp.escape).join('|');
  final memberAlt = getterOf.keys.map(RegExp.escape).join('|');
  final pattern = RegExp(
    '(?<![A-Za-z0-9_.])($recvAlt)\\.($memberAlt)(?![A-Za-z0-9_])',
  );

  var files = 0;
  var hits = 0;
  for (final root in roots) {
    for (final entity in Directory(root).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (skip.any(path.endsWith)) continue;
      final before = entity.readAsStringSync();
      final after = before.replaceAllMapped(pattern, (m) {
        hits += 1;
        return '${m[1]}.${getterOf[m[2]]}.${m[2]}';
      });
      if (after == before) continue;
      files += 1;
      print(path);
      if (!dry) entity.writeAsStringSync(after);
    }
  }
  print('rewrote $hits call sites in $files files${dry ? ' (dry)' : ''}');
}

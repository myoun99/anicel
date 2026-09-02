// Lists clone candidates across lib/ — the audit's Round 1 work list.
//   dart run tool/refactor/clones.dart [--min 40] [--top 60] [--same-body]
// See clone_scan.dart for what a candidate is (and is not).
import 'dart:io';

import 'clone_scan.dart';

void main(List<String> args) {
  var min = 40;
  var top = 60;
  var crossOnly = true;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--min') min = int.parse(args[++i]);
    if (args[i] == '--top') top = int.parse(args[++i]);
    if (args[i] == '--same-body') crossOnly = false;
  }
  final bodies = cloneBodies('lib');
  final hits = cloneCandidates(bodies, minTokens: min, crossOnly: crossOnly);
  stdout.writeln(
    'bodies: ${bodies.length}; clone candidates (>= $min tokens): '
    '${hits.length}',
  );
  for (final h in hits.take(top)) {
    stdout.writeln(h.describe());
  }
}

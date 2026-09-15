import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★★WHERE THE FILM STOPS IS STATED BY ONE STACK.
///
/// The out-of-cut wash, the のりしろ mark, the cut-end line and the trim
/// grip are four widgets with one rule between them: static when nothing is
/// being trimmed, following the live preview otherwise. `TimelineFrameGridStack`
/// has owned that rule since UI-R18 #14. The x-sheet then grew the same four
/// by hand, turned on their side — a copy that agreed with the original on the
/// day it was written and nothing after that could see drift in.
///
/// ⛔SO THIS SCANS SOURCE (the law of [one_sheet_ink_layer_test]): a behaviour
/// test proves the sheet shows a wash; only a scan proves it has no wash of
/// its own. A grid that wants the overlays hands the stack an `axis`.
void main() {
  const home = 'lib/src/ui/timeline/timeline_frame_grid_stack.dart';
  const overlays = [
    'TimelineOutsideCutWashPainter',
    'TimelineBodyNoriShiroBoundary',
    'TimelineBodyCutEndBoundary',
    'TimelineCutEndDragHandle',
  ];

  /// `Name(` outside a comment — a construction. The file that DECLARES the
  /// class is skipped: its constructor is `const Name({`, which also matches.
  List<String> constructionsOf(String name, File file) {
    final text = file.readAsStringSync();
    if (text.contains('class $name ')) return const [];
    final call = RegExp('\\b$name\\(');
    final hits = <String>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      if (call.hasMatch(line)) hits.add('${libPath(file)}:${i + 1}');
    }
    return hits;
  }

  test('premise: the stack constructs all four overlays', () {
    // An empty scan must not be able to pass — if the stack stopped
    // building one of them, the second test would go green for nothing.
    final stack = File(home);
    for (final name in overlays) {
      expect(
        constructionsOf(name, stack),
        isNotEmpty,
        reason: '$name is built by the stack; the scan below assumes so',
      );
    }
  });

  test('no other file in lib builds a cut-end overlay', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (libPath(file) == home) continue;
      for (final name in overlays) {
        offenders.addAll(constructionsOf(name, file));
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'the x-sheet once carried its own wash, mark, line and grip, '
          'transposed by hand. Pass `axis:` to TimelineFrameGridStack instead',
    );
  });
}

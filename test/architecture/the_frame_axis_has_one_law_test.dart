import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨THE FRAME AXIS HAS ONE frame→pixel LAW (F-220).
///
/// 🗣️유저 2026-09-29: 「타임라인/콘티패널 줌, 1.7에서 2.8까지 이동하면
/// 안바뀌고 … 제대로 퍼센테이지 바뀔때마다 줌 상태가 바뀌지 않음」. The zoom
/// follows every percent now, so a cell is seldom a whole number of pixels,
/// and `timelineFrameEdge` puts every boundary on the whole pixel nearest it
/// — a frame line stays one crisp column at any zoom. That holds only while
/// EVERY surface reads its boundaries there: a surface that multiplied a
/// frame count by the cell's extent put the same boundary up to half a
/// pixel off the law's, beside a line the law put on its pixel. Some fifty
/// of them did, across the timeline, the X-sheet and the storyboard.
///
/// ⛔A behaviour test cannot hold this — each surface passes on its own at a
/// whole-pixel zoom, which is what every fixture uses. So the rule is read
/// off the source: in the frame-axis code, a product of a frame count and a
/// cell's extent stands only where the ledger says why it is not a
/// boundary.
void main() {
  // A cell's extent times something, in either order.
  final product = RegExp(
    r'\*\s*[\w.!]*(?:frameCell(?:Width|Extent)|[pP]ixelsPerFrame|[cC]ellExtent|cellWidth)\b'
    r'|(?:frameCell(?:Width|Extent)|[pP]ixelsPerFrame|[cC]ellExtent|cellWidth)\)?\s*\*\s*[\w(]',
  );

  /// Every product the frame-axis code keeps, and why it is not a boundary.
  const ledger = <String, (int, String)>{
    'lib/src/ui/timeline/timeline_frame_coordinate_policy.dart': (
      1,
      'the law itself',
    ),
    'lib/src/ui/timeline/timeline_beat_lines.dart': (
      2,
      'how wide six frames and a second are — thresholds, not positions',
    ),
    'lib/src/ui/timeline/timeline_frame_ruler_painter.dart': (
      1,
      'how wide a second is, for the labels\' spacing',
    ),
    'lib/src/ui/timeline/timeline_grid_metrics.dart': (
      1,
      'whether a stride holds a mark — a threshold',
    ),
    'lib/src/ui/timeline/timeline_frame_window.dart': (
      1,
      'the window bucket\'s span — a repaint cadence, not a position',
    ),
    'lib/src/ui/timeline/timeline_frame_rows_scroll_body.dart': (
      1,
      'the window bucket\'s span',
    ),
    'lib/src/ui/timeline/xsheet_grid/xsheet_grid_frame_scroll.dart': (
      1,
      'the window bucket\'s span',
    ),
    'lib/src/ui/timeline/timeline_frame_span_layout.dart': (
      1,
      'chrome sized in cells (a grip is half a cell), not a span between '
          'two boundaries',
    ),
    'lib/src/ui/timeline/timeline_run_end_handles.dart': (
      1,
      'a handle\'s size — half a cell, clamped',
    ),
    'lib/src/ui/timeline/timeline_block_word.dart': (
      1,
      'a word\'s cell inside the box its span was laid out in',
    ),
    'lib/src/ui/timeline/timeline_zoom_limits.dart': (
      1,
      'the ×1.25 zoom step — a zoom times a factor, no frame count',
    ),
  };

  Iterable<File> frameAxisSources() => [
    ...dartFilesUnder('lib/src/ui/timeline'),
    ...dartFilesUnder('lib/src/ui/storyboard'),
    File('lib/src/ui/storyboard_panel.dart'),
    File('lib/src/ui/storyboard_cut_blocks_painter.dart'),
  ];

  test('a frame count times a cell\'s extent stands only where the ledger '
      'says why', () {
    final found = <String, List<String>>{};
    for (final file in frameAxisSources()) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        final line = lines[index];
        if (line.trimLeft().startsWith('//')) continue;
        if (product.hasMatch(line)) {
          (found[libPath(file)] ??= []).add('${index + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      found,
      isNotEmpty,
      reason: 'the scan found no product at all — the law itself is one, so '
          'it is reading the wrong tree',
    );
    final offending = <String>[
      for (final MapEntry(key: path, value: hits) in found.entries)
        if (hits.length != (ledger[path]?.$1 ?? 0))
          '$path — ${hits.length} (ledger ${ledger[path]?.$1 ?? 0}):\n'
              '    ${hits.join('\n    ')}',
      for (final path in ledger.keys)
        if (!found.containsKey(path)) '$path — 0, but the ledger says it has',
    ];
    expect(
      offending,
      isEmpty,
      reason:
          'a boundary is `timelineFrameEdge` (or a geometry\'s `edgeAt`, a '
          'scale\'s `leftForFrame`) and a width is the distance between two '
          'of them — ⛔never a frame count times the cell\'s extent. If this '
          'one is not a boundary, write it into the ledger with the reason.\n'
          '${offending.join('\n')}',
    );
  });
}

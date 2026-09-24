import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart'
    show SePaperSpan;
import 'package:anicel/src/ui/timeline/timeline_silhouette_painter.dart';

import 'timeline_frame_geometry_probe.dart';
import '../../helpers/dart_sources.dart';

/// 🚨EVERY BLOCK WEARS ONE CORNER (유저 2026-09-23: 「모서리 호버하니까
/// 티나는데 … 모서리랑 블록이랑 모서리가 통일안되서 그런거같은데 확실하게
/// 통일해줘. 모양새.」).
///
/// The law is [timelineBlockCornerRadiusAt]: six, no more than half the cell.
/// It existed since F-79 and the ring wore it — while the SE paper kept a 4 of
/// its own, the storyboard's panels and standing outline a bare 6, the
/// selection band, the pattern span and the classic cells pass a bare 6 too,
/// and the drop silhouette a 3. Each drifted alone, which is why the answer is
/// a LEDGER as well as behaviour: a behaviour pin covers the readers that
/// exist, the ledger covers the next one to type a number.
///
/// ⚠️The pins run at an 8px cell, where the law gives 4 — at 100% zoom it
/// gives the bare 6, and a pin there cannot tell a reader of the law from a
/// reader of the number.
void main() {
  const cell = 8.0;
  const cross = 28.0;
  final law = timelineBlockCornerRadiusAt(cellExtent: cell, crossExtent: cross);

  test('the law bites at this zoom — or the pins below would measure '
      'nothing', () {
    expect(law, const Radius.circular(4));
  });

  test('⛔the only NUMBERED corners left in block code are the ledger\'s, '
      'each with its reason', () {
    // THE LEDGER. A number here is a corner that is deliberately NOT a frame
    // block's; a new one earns a line with its reason, and a block corner
    // never does — it reads [timelineBlockCornerRadiusAt].
    const ledger = <String, int>{
      // The law's own base value, private so nothing else can read it.
      // Plus the STANDING-CELL ring — one cell, its own 3px/4px look
      // (유저 2026-08-08: 「standing is ONE thing」), not a block.
      'lib/src/ui/timeline/timeline_cell_style.dart': 2,
      // The folded row's summary pills — the negative-space design 유저
      // confirmed on 2026-08-10, inset and outlined, not the paper.
      'lib/src/ui/timeline/collapsed_row_overlay.dart': 2,
      // A name TAG in the SE lane preview, not a block.
      'lib/src/ui/timeline/se_name_tag_lane_preview.dart': 1,
    };
    final numbered = RegExp(r'Radius\.circular\(\s*[0-9]');
    final found = <String, int>{};
    for (final root in const [
      'lib/src/ui/timeline',
      'lib/src/ui/storyboard',
    ]) {
      for (final entity in dartFilesUnder(root)) {
        _count(entity, numbered, found);
      }
    }
    for (final path in const [
      'lib/src/ui/storyboard_cut_blocks_painter.dart',
      'lib/src/ui/storyboard_panel.dart',
    ]) {
      _count(File(path), numbered, found);
    }
    expect(
      found,
      ledger,
      reason:
          '⛔A numbered corner in block code. If it is a frame block — its '
          'paper, an outline around one, a band over a run of them — it '
          'reads timelineBlockCornerRadiusAt(cellExtent:, crossExtent:). If '
          'it is genuinely something else, give it a ledger line and a '
          'reason.',
    );
  });

  test('the classic cells pass rounds a block by the law, as its tiles do', () {
    final layer = Layer(
      id: const LayerId('a'),
      name: 'A',
      frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
      timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 3)},
    );
    final painter = TimelineRowCellsPainter(
      layer: layer,
      geometry: testFrameGeometry(
        frameCellExtent: cell,
        frameEndIndexExclusive: 6,
      ),
      crossAxisExtent: cross,
      exposureStateForLayer: (layer, frameIndex) {
        if (layer.timeline[frameIndex]?.isDrawing ?? false) {
          return TimelineCellExposureState.drawingStart;
        }
        return coveringDrawingBlockAt(layer.timeline, frameIndex) != null
            ? TimelineCellExposureState.held
            : TimelineCellExposureState.uncovered;
      },
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
    );
    expect(painter.resolvedCellStyleFor(0).radius?.topLeft, law);
    expect(painter.resolvedCellStyleFor(2).radius?.bottomRight, law);
    expect(painter.resolvedCellStyleFor(1).radius?.topLeft, Radius.zero);
  });

  testWidgets('the SE paper span rounds by the law', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 3 * cell,
            height: cross,
            child: SePaperSpan(
              axis: Axis.horizontal,
              frameCellExtent: cell,
              startFrame: 0,
            ),
          ),
        ),
      ),
    );
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(SePaperSpan),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    final spy = _RRectSpy();
    painter.paint(spy, const Size(3 * cell, cross));
    expect(spy.rrects.first.tlRadius, law);
  });

  test('the drop silhouette rounds by the law, read off its own box', () {
    final spy = _RRectSpy();
    const TimelineSilhouettePainter(
      frames: 3,
      axis: Axis.horizontal,
    ).paint(spy, const Size(3 * cell, cross));
    // The dashes run half a pixel in, concentric with the block's corner.
    expect(spy.rrects.first.tlRadius, Radius.circular(law.x - 0.5));
  });

  test('the selection band over frames rounds by the law; over rows it is '
      'square (F-26)', () {
    expect(
      timelineRangeSelectionBandDecorationAt(
        cellExtent: cell,
        crossExtent: cross,
      ).borderRadius,
      BorderRadius.all(law),
    );
    expect(timelineRowSelectionBandDecoration.borderRadius, BorderRadius.zero);
  });
}

void _count(File file, RegExp pattern, Map<String, int> found) {
  var hits = 0;
  for (final line in file.readAsLinesSync()) {
    if (line.trimLeft().startsWith('//')) {
      continue;
    }
    hits += pattern.allMatches(line).length;
  }
  if (hits > 0) {
    found[file.path.replaceAll(r'\', '/')] = hits;
  }
}

class _RRectSpy implements Canvas {
  final rrects = <RRect>[];

  @override
  void drawRRect(RRect rrect, Paint paint) => rrects.add(rrect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

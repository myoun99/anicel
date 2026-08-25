import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';

import 'timeline_cell_probe.dart';

/// F-3, second half — **the frame grid is the sheet's ruling, and every row
/// stands on the same frames.**
///
/// 유저: 「프레임 그리드가 아예 안 그려지는 레이어가 있다(확인된 것 = 이미지
/// 레이어). 전 종류 전수조사」.
///
/// ⚠️A survey, not a spot check. The camera row was excluded from this same
/// line once (D43-2 재개 b) and the exclusion survived because every test that
/// looked at the grid built a DRAWING row. So this walks
/// [LayerKind.values] — a kind added later joins the survey by existing.
void main() {
  const trackId = TrackId('grid-track');
  const cutId = CutId('grid-cut');

  /// One row per kind, each carrying a block over frames [1,5) so the
  /// INTERIOR boundaries (2, 3, 4) exist to be ruled.
  Layer layerOfKind(LayerKind kind) => Layer(
    id: LayerId('grid-${kind.name}'),
    name: kind.name,
    kind: kind,
    frames: [
      Frame(
        id: FrameId('grid-frame-${kind.name}'),
        duration: 4,
        strokes: const [],
      ),
    ],
    timeline: {
      1: TimelineExposure.drawing(
        FrameId('grid-frame-${kind.name}'),
        length: 4,
      ),
    },
  );

  /// ⛔Folder rows derive their blocks from members and adjustment rows have
  /// no exposures of their own, so a fixture cannot put a block on them —
  /// they are surveyed for the EMPTY-cell grid instead, which is the same
  /// line drawn by the other arm of the law.
  const blocklessKinds = {LayerKind.folder, LayerKind.adjustment};

  Project project() => Project(
    id: const ProjectId('grid-project'),
    name: 'Grid',
    createdAt: DateTime.utc(2026, 8, 25),
    tracks: [
      Track(
        id: trackId,
        name: 'V',
        cuts: [
          Cut(
            id: cutId,
            name: '1',
            duration: 12,
            canvasSize: const CanvasSize(width: 64, height: 64),
            layers: [
              for (final kind in LayerKind.values)
                if (kind != LayerKind.se) layerOfKind(kind),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> pumpWorkspace(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every row kind rules its frame boundaries', (tester) async {
    await pumpWorkspace(tester);

    final missing = <String>[];
    for (final kind in LayerKind.values) {
      if (kind == LayerKind.se) {
        continue;
      }
      final id = 'grid-${kind.name}';
      if (find
          .byKey(ValueKey<String>('timeline-row-cells-$id'))
          .evaluate()
          .isEmpty) {
        missing.add('${kind.name}: no cells row on screen');
        continue;
      }
      final painter = timelineRowCellsPainterFor(tester, id);
      // Frame 2 is interior to the block on rows that carry one, and plain
      // empty space on the two kinds that cannot carry one. Both arms of the
      // law rule it.
      final probe = blocklessKinds.contains(kind) ? 8 : 2;
      if (painter.heldSeamLineFor(probe) == null) {
        missing.add('${kind.name}: no frame boundary line at $probe');
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'the grid is the sheet ruling — a row opting out of it is a '
          'row claiming its columns sit somewhere else',
    );
  });

  testWidgets('and every row kind rules its own bottom seam', (tester) async {
    await pumpWorkspace(tester);

    final missing = <String>[];
    for (final kind in LayerKind.values) {
      if (kind == LayerKind.se) {
        continue;
      }
      final id = 'grid-${kind.name}';
      if (find
          .byKey(ValueKey<String>('timeline-row-cells-$id'))
          .evaluate()
          .isEmpty) {
        continue;
      }
      if (timelineRowCellsPainterFor(tester, id).rowSeamLineFor(2) == null) {
        missing.add(kind.name);
      }
    }

    expect(missing, isEmpty);
  });
}

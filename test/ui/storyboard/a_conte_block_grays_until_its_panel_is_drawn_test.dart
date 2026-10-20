import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard/storyboard_rows_channel.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/cel_text_fixture.dart' show drawingOf, tileFilledWith;
import '../../helpers/conte_track_fixture.dart';
import '../../helpers/storyboard_twirls.dart';
import '../timeline/timeline_frame_geometry_probe.dart';

/// 🗣️F-357: the conte row grays a block whose panel holds no picture yet,
/// as the timeline grays an unworked block (R26 #44) — the same painter on
/// the same fact, asked of the cut each block belongs to, on the rail and
/// in the folded overlay alike.
void main() {
  // cut-1: p1 [0,4) · p2 [4,8) · p3 [8,12); a gap [12,15); cut-2: q1 [15,25).
  const p1 = (CutId('cut-1'), LayerId('cut-1-conte'), FrameId('p1'));
  const p2 = (CutId('cut-1'), LayerId('cut-1-conte'), FrameId('p2'));
  const q1 = (CutId('cut-2'), LayerId('cut-2-conte'), FrameId('q1'));
  Project film() {
    final base = conteTrackProject();
    final track = base.tracks.single;
    final second = track.cuts[1];
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            track.cuts[0],
            second.copyWith(
              layers: [
                ...second.layers,
                Layer(
                  id: const LayerId('cut-2-conte'),
                  name: 'Conte',
                  kind: LayerKind.storyboard,
                  frames: [
                    Frame(id: const FrameId('q1'), duration: 1, strokes: []),
                  ],
                  timeline: {
                    0: const TimelineExposure.drawing(
                      FrameId('q1'),
                      length: 10,
                    ),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  testWidgets('a block is gray while its panel is undrawn — asked of its '
      'own cut — and turns when the fact moves', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final drawn = <(CutId, LayerId, FrameId)>{p2, q1};
    final asked = <(CutId, LayerId, FrameId)>[];
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    final ConteCelContent content = (
      holdsAPicture: (Cut cut, LayerId row, FrameId cel) {
        asked.add((cut.id, row, cel));
        return drawn.contains((cut.id, row, cel));
      },
      revision: revision,
    );
    final channel = StoryboardRowsChannel();
    final folded = ValueNotifier<StoryboardFoldedRow?>(null);
    addTearDown(folded.dispose);
    final geometry = testFrameGeometry(
      frameCellExtent: 10,
      frameEndIndexExclusive: 25,
    );
    addTearDown(geometry.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: StoryboardPanel(
                  project: film(),
                  activeCutId: const CutId('cut-1'),
                  rowsChannel: channel,
                  conteCelContent: content,
                ),
              ),
              SizedBox(
                height: 40,
                child: ValueListenableBuilder<StoryboardFoldedRow?>(
                  valueListenable: folded,
                  builder: (context, row, _) =>
                      row?.frames?.call(context, geometry) ??
                      const SizedBox(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    folded.value = channel.foldedRowFor(
      LayerRowAddress(trackConteRowId(conteTrackId)),
    );
    await tester.pump();

    final painters = [
      for (final paint in tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      ))
        if (paint.painter case final TimelineRowCellsPainter painter
            when painter.layer.id == trackConteRowId(conteTrackId))
          painter,
    ];
    expect(painters, hasLength(2), reason: '⛔전제: the rail and the overlay');

    for (final painter in painters) {
      bool has(int frame) =>
          painter.celHasContentForLayer!(painter.layer, frame);
      Color paper(int frame) => painter.resolvedCellStyleFor(frame).background;

      drawn.remove(p1);
      expect(has(1), isFalse, reason: 'p1 holds no picture');
      expect(has(5), isTrue);
      expect(paper(1), isNot(paper(5)), reason: 'and the undrawn one grays');
      expect(has(13), isTrue, reason: 'a gap has no block to gray');

      asked.clear();
      expect(has(16), isTrue);
      expect(
        asked,
        [q1],
        reason: 'the block past the gap is asked of ITS cut, not the active',
      );

      final before = painter.celContentRevision;
      drawn.add(p1);
      revision.value += 1;
      expect(painter.celContentRevision, isNot(before));
      expect(has(1), isTrue);
      expect(paper(1), paper(5));
    }
  });

  testWidgets('the storyboard tab hands the row the session\x27s fact — a '
      'panel goes white when its cel takes ink', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    final cut = session.activeCutOrNull!;
    final conte = session.activeLayer!;
    final cel = conte.timeline[0]!.frameId!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: withStoryboardTwirls(
            session,
            (twirls) => StoryboardTabHost(
              session: session,
              expandedLaneLayerIds: twirls.expandedLaneLayerIds,
              onToggleLayerLanes: twirls.onToggleLayerLanes,
              expandedLaneGroupKeys: twirls.expandedLaneGroupKeys,
              onToggleLaneGroupKey: twirls.onToggleLaneGroupKey,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final track = session.repository.requireProject().tracks.single.id;
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<TimelineRowCellsPainter>()
        .singleWhere((painter) => painter.layer.id == trackConteRowId(track));
    bool drawnAtTheStart() =>
        painter.celHasContentForLayer!(painter.layer, 0);

    expect(drawnAtTheStart(), isFalse);
    final before = painter.celContentRevision;
    session.renderCaches.brushFrameStore.storeBakedSurface(
      session.brushFrameKeyForCut(cut, conte.id, cel),
      drawingOf({TileCoord(x: 0, y: 0): tileFilledWith([0, 0, 0, 255])}),
    );
    expect(drawnAtTheStart(), isTrue);
    expect(painter.celContentRevision, isNot(before));
  });
}

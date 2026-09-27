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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_silhouette_painter.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import '../../helpers/placed_sound_conform.dart';

/// 「끄는 동안 보이는 것은 놓았을 때 생길 것이다」 (미디어 배치 라운드 2d
/// 2부) for a SOUND held over an SE row's empty cell: the block it would
/// start there is drawn while it hovers.
///
/// 🚨It never was. The silhouette comes with no preview ROW — nothing on
/// the row moves for a sound — and the row's gate rebuilt only when its
/// preview row changed, so the span sat in the channel and no row drew it.
/// Found beside I-47 (a file over a reference row), which hands over the
/// same span-only preview.
void main() {
  const seRowId = LayerId('se-row');

  testWidgets('a sound held over an EMPTY SE cell draws the block it would '
      'start there', (tester) async {
    const foot = 'C:/snd/foot.wav';
    const dragSourceKey = ValueKey<String>('test-media-drag-source');
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('silhouette-project'),
        name: 'Silhouette Project',
        createdAt: DateTime.utc(2026, 9, 27),
        tracks: [
          Track(
            id: const TrackId('silhouette-track'),
            name: 'Video',
            seLayers: [
              Layer(
                id: seRowId,
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(
                    id: const FrameId('se-f1'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
                timeline: {
                  2: const TimelineExposure.drawing(
                    FrameId('se-f1'),
                    length: 4,
                  ),
                },
              ),
            ],
            cuts: [
              Cut(
                id: const CutId('silhouette-cut'),
                name: 'Cut',
                duration: 48,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: const [],
              ),
            ],
          ),
        ],
      ),
      // A second of sound for every file, answered at once.
      audioConformStore: soundConformStore(),
    );
    addTearDown(session.dispose);
    // The silhouette reads the conform's SYNCHRONOUS door, so the sound's
    // length has to be known before it hovers — as a pooled sound's is.
    await tester.runAsync(() => session.audioConformStore.ensurePeaksFor(foot));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 40,
                child: Draggable<MediaAssetDragData>(
                  data: const MediaAssetDragData(path: foot, name: 'foot.wav'),
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  feedback: const SizedBox(width: 8, height: 8),
                  child: Container(
                    key: dragSourceKey,
                    width: 40,
                    height: 40,
                    color: const Color(0xFF888888),
                  ),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: session,
                  builder: (context, _) => TimelineTabHost(
                    session: session,
                    orientation: TimelineOrientation.horizontal,
                    onOrientationChanged: (_) {},
                    pixelsPerFrame: 48,
                    onPixelsPerFrameChanged: (_) {},
                    showSeconds: false,
                    onShowSecondsChanged: (_) {},
                    onPlaceMediaAsset: (layerId, frameIndex, path) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final silhouette = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is TimelineSilhouettePainter,
    );
    expect(silhouette, findsNothing, reason: 'premise: nothing held yet');

    // Cell 8: two cells into the stretch after the block on 2..5.
    final gap = find.byKey(
      const ValueKey<String>('timeline-se-cell-drop-se-row-6'),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getTopLeft(gap) + const Offset(2 * 48 + 24, 8));
    await tester.pump();

    expect(silhouette, findsOneWidget);

    await gesture.moveTo(const Offset(20, 20));
    await tester.pump();
    expect(silhouette, findsNothing, reason: 'it goes when the sound leaves');
    await gesture.up();
    await tester.pumpAndSettle();
  });
}

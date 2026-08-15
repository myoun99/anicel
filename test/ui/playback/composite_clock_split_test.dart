import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// S1 — THE COMPOSITE'S COST, SPLIT AT ITS ONLY SEAM.
///
/// 「빔이 느리게 차」 is one number until the compose says which half it
/// lives in: the Dart-side walk or the full-canvas `toImage`. The split
/// rides `InputInspector.note`, because the machine that must answer is
/// the release iPad — a debug-only probe measures the wrong build.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  const frameKey = BrushFrameKey(
    projectId: ProjectId('project'),
    trackId: TrackId('track'),
    cutId: CutId('cut'),
    layerId: LayerId('layer'),
    frameId: FrameId('frame-a'),
  );

  BrushFrameStore storeWithStroke() {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 1, y: 1),
          color: 0xFF000000,
          size: 2,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
    return store;
  }

  Cut cut() => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    duration: 4,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 2),
        },
      ),
    ],
  );

  testWidgets('the two-clock note appears under the inspector and only '
      'there', (tester) async {
    await tester.runAsync(() async {
      final store = storeWithStroke();
      final cache = CutFrameCompositeCache(
        layerImages: LayerFrameImageCache(frameStore: store),
        frameStore: store,
        frameKeyOf: (cut, layerId, frameId) => BrushFrameKey(
          projectId: const ProjectId('project'),
          trackId: const TrackId('track'),
          cutId: cut.id,
          layerId: layerId,
          frameId: frameId,
        ),
      );
      addTearDown(cache.dispose);
      InputInspector.notes.clear();
      addTearDown(() {
        InputInspector.visible.value = false;
        InputInspector.notes.clear();
      });

      // Hidden: the compose runs bare — no clocks, no note.
      InputInspector.visible.value = false;
      await cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      expect(
        InputInspector.notes.where((line) => line.startsWith('cmp ')),
        isEmpty,
        reason: 'a hidden inspector must cost and say nothing',
      );

      // Visible: one fresh compose (other quality tier — the FULL one
      // above is already cached), one note carrying both halves.
      InputInspector.visible.value = true;
      await cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.half,
      );
      final note = InputInspector.notes.lastWhere(
        (line) => line.startsWith('cmp '),
        orElse: () => fail('the compose under the inspector emits its note'),
      );
      expect(note, contains('walk '));
      expect(note, contains('img '));
      expect(note, contains('ms'));
    });
  });
}

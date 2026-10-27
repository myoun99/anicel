import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_image_bytes.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★THE FRAME A SCREEN STANDS ON HOLDS ITS FOLDERS' PICTURES
/// (`FramePictures.heldNodes`; card paint-walk-redoes-the-same-work-each-
/// step): laid for the screen, a folder drawn whole is kept, and a stroke's
/// step patched into the frame as it stands is cut from it — one page of
/// them at the most, on the playback line beside the frames' pictures, and
/// let go of at a memory warning.
void main() {
  const canvasSize = CanvasSize(width: 32, height: 24);
  const folder = LayerId('folder');

  Layer row(String id) => Layer(
    id: LayerId(id),
    name: id,
    folderId: folder,
    frames: [Frame(id: FrameId('$id-0'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-0'), length: 1)},
  );

  /// Two drawn rows in a folder at half strength — one picture of its own.
  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('held'),
      name: 'Held',
      createdAt: DateTime.utc(2026, 10, 27),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: 'cut',
              duration: 1,
              canvasSize: canvasSize,
              layers: [
                row('a'),
                row('b'),
                createFolderLayer(id: folder, name: 'F').copyWith(opacity: 0.5),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  void draw(EditorSessionManager s, String id, double x) {
    final cut = s.requireActiveCut;
    BrushFrameEditingCoordinator(
      initialFrameKey: s.brushFrameKeyForCut(
        cut,
        LayerId(id),
        FrameId('$id-0'),
      ),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 8,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: x, y: 12),
          color: 0xFF000000,
          size: 10,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.square,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
  }

  /// [s] with both rows drawn, and the frame the screen stands on.
  DemandedPicture drawn(EditorSessionManager s) {
    draw(s, 'a', 10);
    draw(s, 'b', 20);
    return (cut: s.requireActiveCut, frameIndex: 0, paintPaper: true);
  }

  testWidgets('laid for the screen that stands on it the frame keeps its '
      'folder, and a step patched in as it stands is cut from it — laid '
      'ahead of a screen, it keeps none', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final pictures = s.playbackRig.framePictures;
      final picture = drawn(s);

      await pictures.make(picture, shouldAbort: () => false);
      expect(pictures.heldNodes, hasLength(0), reason: 'made ahead');

      final shown = session();
      addTearDown(shown.dispose);
      final standing = shown.playbackRig.framePictures;
      final stood = drawn(shown);
      await standing.makeShown(
        standing.stackOf(stood),
        stood,
        shouldAbort: () => false,
      );
      expect(standing.heldNodes, hasLength(1), reason: 'the folder');

      debugSubtreeRasterCount = 0;
      final recorder = ui.PictureRecorder();
      standing
          .frameAsItStands(standing.stackOf(stood), stood)
          .drawing
          .draw(ui.Canvas(recorder)..clipRect(const Rect.fromLTWH(6, 8, 9, 7)));
      recorder.endRecording().dispose();
      expect(debugSubtreeRasterCount, 0, reason: 'cut from what is held');
    });
  });

  testWidgets('⚖️what is held is one page at the most — the page of the frame '
      'last kept on', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final pictures = s.playbackRig.framePictures;
      final picture = drawn(s);
      await pictures.makeShown(
        pictures.stackOf(picture),
        picture,
        shouldAbort: () => false,
      );
      pictures.heldNodes.clear();

      void keep(String key, Rect bounds) {
        final recorder = ui.PictureRecorder();
        drawSubtreeAsImage(
          canvas: ui.Canvas(recorder),
          bounds: bounds,
          rasterScale: 1,
          paintSubtree: (into, _) => into.drawPaint(Paint()),
          compose: (blit) => blit(Paint()),
          held: SubtreeHold(pictures.heldNodes, key: key, keeps: true),
        );
        recorder.endRecording().dispose();
      }

      keep('past the page', const Rect.fromLTWH(0, 0, 33, 24));
      expect(pictures.heldNodes, hasLength(0));
      keep('the page', const Rect.fromLTWH(0, 0, 32, 24));
      expect(pictures.heldNodes, hasLength(1));
    });
  });

  testWidgets('🚨what is held comes off the playback line, is counted with '
      'the frames\' pictures, and goes at a memory warning and with the '
      'session', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      final pictures = s.playbackRig.framePictures;
      final line = s.playbackRig.playbackCache;
      final picture = drawn(s);
      final budget = line.playbackCacheByteBudget;
      final lendable = line.lendableBytes;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      int censused() => collectMemoryCensus([s]).items
          .firstWhere((item) => item.id == 'framePictures')
          .bytes;
      final before = censused();
      debugDefaultTargetPlatformOverride = null;

      await pictures.makeShown(
        pictures.stackOf(picture),
        picture,
        shouldAbort: () => false,
      );
      final held = pictures.heldNodes.heldBytes;
      expect(held, greaterThan(0), reason: '⛔premise: the folder is held');
      expect(
        held,
        lessThanOrEqualTo(estimatedImageBytes(32, 24)),
        reason: '⛔premise',
      );

      expect(line.bytes, budget - held);
      expect(line.lendableBytes, lendable - held);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        censused() - before,
        held + s.renderCaches.framePictureStore.estimatedBytes,
      );
      debugDefaultTargetPlatformOverride = null;

      line.respondToMemoryPressure();
      expect(pictures.heldNodes, hasLength(0));

      await pictures.makeShown(
        pictures.stackOf(picture),
        (cut: picture.cut, frameIndex: 0, paintPaper: false),
        shouldAbort: () => false,
      );
      expect(pictures.heldNodes, hasLength(1), reason: '⛔premise');
      s.dispose();
      expect(pictures.heldNodes, hasLength(0));
    });
  });
}

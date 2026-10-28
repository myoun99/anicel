import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
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
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★THE FRAME A SCREEN STANDS ON HOLDS ITS FOLDERS' PICTURES
/// (`FramePictures.heldNodes`; card paint-walk-redoes-the-same-work-each-
/// step): laid for the canvas that stands on it, a folder drawn whole is
/// kept, and a stroke's step patched into the frame as it stands is cut
/// from it — on the playback line beside the frames' pictures, each a page
/// at the most and as many as the line has room for (🗣️유저 2026-10-27,
/// Q3 = c: 「위 폴더는 하나씩, 재생 메모리 몫 안에서 전부」), only those of the
/// frame last drawn to hold them, and let go of at a memory warning.
void main() {
  const canvasSize = CanvasSize(width: 32, height: 24);
  const folders = [LayerId('folder'), LayerId('folder2')];
  const rowsOf = [
    ['a', 'b'],
    ['c', 'd'],
  ];
  final page = estimatedImageBytes(32, 24);

  Layer row(String id, [LayerId? folder]) => Layer(
    id: LayerId(id),
    name: id,
    folderId: folder,
    frames: [Frame(id: FrameId('$id-0'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-0'), length: 1)},
  );

  /// [count] folders at half strength, two drawn rows in each — each one
  /// picture of its own — and, [withPen], a row a pen may draw on between
  /// the first and the rest.
  EditorSessionManager session({int count = 1, bool withPen = false}) {
    final layers = [
      for (var at = 0; at < count; at += 1) ...[
        for (final id in rowsOf[at]) row(id, folders[at]),
        createFolderLayer(
          id: folders[at],
          name: 'F$at',
        ).copyWith(opacity: 0.5),
        if (withPen && at == 0) row('pen'),
      ],
    ];
    return EditorSessionManager(
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
                layers: layers,
              ),
            ],
          ),
        ],
      ),
    );
  }

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

  /// [s] with every row of its [count] folders drawn, and the frame the
  /// screen stands on.
  DemandedPicture drawn(EditorSessionManager s, {int count = 1}) {
    for (var at = 0; at < count; at += 1) {
      draw(s, rowsOf[at][0], 10);
      draw(s, rowsOf[at][1], 20);
    }
    return (
      cut: s.requireActiveCut,
      frameIndex: 0,
      paintPaper: true,
      ghosts: false,
    );
  }

  /// Laid for a canvas that stands on it to draw.
  Future<void> shown(EditorSessionManager s, DemandedPicture picture) {
    final pictures = s.playbackRig.framePictures;
    return pictures.makeShown(
      pictures.stackOf(picture),
      picture,
      shouldAbort: () => false,
      keepsNodes: true,
    );
  }

  testWidgets('laid for the canvas that stands on it the frame keeps its '
      'folder, and a step patched in as it stands is cut from it — laid '
      'ahead of a screen, or for one that draws nothing live, it keeps '
      'none', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final pictures = s.playbackRig.framePictures;
      final picture = drawn(s);

      await pictures.make(picture, shouldAbort: () => false);
      expect(pictures.heldNodes, hasLength(0), reason: 'made ahead');

      final still = session();
      addTearDown(still.dispose);
      final stillPictures = still.playbackRig.framePictures;
      final shownStill = drawn(still);
      await stillPictures.makeShown(
        stillPictures.stackOf(shownStill),
        shownStill,
        shouldAbort: () => false,
        keepsNodes: false,
      );
      expect(stillPictures.heldNodes, hasLength(0), reason: 'nothing live');

      final standing = session();
      addTearDown(standing.dispose);
      final standingPictures = standing.playbackRig.framePictures;
      final stood = drawn(standing);
      await shown(standing, stood);
      expect(standingPictures.heldNodes, hasLength(1), reason: 'the folder');

      debugSubtreeRasterCount = 0;
      final recorder = ui.PictureRecorder();
      standingPictures
          .frameAsItStands(standingPictures.stackOf(stood), stood)
          .drawing
          .draw(ui.Canvas(recorder)..clipRect(const Rect.fromLTWH(6, 8, 9, 7)));
      recorder.endRecording().dispose();
      expect(debugSubtreeRasterCount, 0, reason: 'cut from what is held');
    });
  });

  testWidgets('🗣️every folder over the pen is held, and a step patched in '
      'draws none of them', (tester) async {
    await tester.runAsync(() async {
      final s = session(count: 2);
      addTearDown(s.dispose);
      final pictures = s.playbackRig.framePictures;
      final stood = drawn(s, count: 2);
      await shown(s, stood);
      expect(pictures.heldNodes, hasLength(2));

      debugSubtreeRasterCount = 0;
      final recorder = ui.PictureRecorder();
      pictures
          .frameAsItStands(pictures.stackOf(stood), stood)
          .drawing
          .draw(ui.Canvas(recorder)..clipRect(const Rect.fromLTWH(6, 8, 9, 7)));
      recorder.endRecording().dispose();
      expect(debugSubtreeRasterCount, 0, reason: 'both cut from what is held');
    });
  });

  testWidgets('🗣️what is held is the frame last drawn to hold them — what it '
      'held before it changed is let go of', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final pictures = s.playbackRig.framePictures;
      final stood = drawn(s);
      await shown(s, stood);
      final node = pictures.heldNodes.heldBytes;
      expect(pictures.heldNodes, hasLength(1), reason: '⛔premise');

      // The folder draws something else now: a picture of its own anew.
      draw(s, 'a', 26);
      await shown(s, stood);
      expect(pictures.heldNodes, hasLength(1));
      expect(pictures.heldNodes.heldBytes, node);
    });
  });

  testWidgets('🚨the frame laid for the canvas that stands on it is not drawn '
      'again to hold its nodes as the screen takes it — one laid ahead is, '
      'and one whose held were let go of since', (tester) async {
    await tester.runAsync(() async {
      /// How many rasters holding the nodes of [s]'s frame [stood] draws.
      Future<int> holding(
        EditorSessionManager s,
        DemandedPicture stood,
      ) async {
        final pictures = s.playbackRig.framePictures;
        debugSubtreeRasterCount = 0;
        await pictures.holdNodesOf(
          pictures.stackOf(stood),
          stood,
          shouldAbort: () => false,
        );
        return debugSubtreeRasterCount;
      }

      /// A session whose line has no room for the folder: every frame
      /// drawn whole draws it.
      EditorSessionManager noRoom() {
        final s = session();
        addTearDown(s.dispose);
        s.playbackRig.playbackCache.lend(1 << 40);
        return s;
      }

      final ahead = noRoom();
      final laidAhead = drawn(ahead);
      await ahead.playbackRig.framePictures.make(
        laidAhead,
        shouldAbort: () => false,
      );
      expect(await holding(ahead, laidAhead), 1, reason: '⛔premise');
      expect(await holding(ahead, laidAhead), 0, reason: 'held since');

      final standing = noRoom();
      final stood = drawn(standing);
      await shown(standing, stood);
      expect(await holding(standing, stood), 0);

      final warned = session();
      addTearDown(warned.dispose);
      final atWarning = drawn(warned);
      await shown(warned, atWarning);
      final pictures = warned.playbackRig.framePictures;
      expect(pictures.heldNodes, hasLength(1), reason: '⛔premise');
      warned.playbackRig.playbackCache.respondToMemoryPressure();
      expect(await holding(warned, atWarning), 1);
      expect(pictures.heldNodes, hasLength(1));
    });
  });

  testWidgets('⚖️each node held is a page at the most, and as many are held '
      'as the playback line has room for', (tester) async {
    await tester.runAsync(() async {
      void keep(HeldSubtreeRasters held, String key, Rect bounds) {
        final recorder = ui.PictureRecorder();
        drawSubtreeAsImage(
          canvas: ui.Canvas(recorder),
          bounds: bounds,
          paper: bounds,
          rasterScale: 1,
          paintSubtree: (into, _) => into.drawPaint(Paint()),
          compose: (blit) => blit(Paint()),
          held: SubtreeHold(held, key: key, keeps: true),
        );
        recorder.endRecording().dispose();
      }

      /// The nodes held in a session on a line of [line] bytes, the page
      /// told by a frame laid on it.
      Future<HeldSubtreeRasters> heldOn({int? line}) async {
        final s = session();
        addTearDown(s.dispose);
        if (line != null) {
          s.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(line);
        }
        final held = s.playbackRig.framePictures.heldNodes;
        await shown(s, drawn(s));
        held.clear();
        return held;
      }

      const whole = Rect.fromLTWH(0, 0, 32, 24);
      final wide = await heldOn();
      keep(wide, 'past the page', const Rect.fromLTWH(0, 0, 33, 24));
      expect(wide, hasLength(0));
      keep(wide, 'the page', whole);
      keep(wide, 'another page', whole);
      expect(wide, hasLength(2), reason: 'a page each, not one together');

      final narrow = await heldOn(line: 2 * page - 1);
      keep(narrow, 'the page', whole);
      keep(narrow, 'another page', whole);
      expect(narrow, hasLength(1), reason: 'the line has room for one');
    });
  });

  testWidgets('⚖️once a canvas holds them, the frames\' pictures made ahead '
      'give way to them — never the one it shows — and they take no more '
      'than the line has room for', (tester) async {
    await tester.runAsync(() async {
      // A frame's picture and its folder's, measured on a line they fit.
      final measured = session();
      addTearDown(measured.dispose);
      final at = drawn(measured);
      await shown(measured, at);
      final picture = measured.renderCaches.framePictureStore.estimatedBytes;
      final node = measured.playbackRig.framePictures.heldNodes.heldBytes;
      expect(node, greaterThan(0), reason: '⛔premise');

      final s = session();
      addTearDown(s.dispose);
      s.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(
        2 * picture + node - 1,
      );
      final pictures = s.playbackRig.framePictures;
      final store = s.renderCaches.framePictureStore;
      final stood = drawn(s);
      final ahead = (
        cut: stood.cut,
        frameIndex: 0,
        paintPaper: false,
        ghosts: false,
      );
      await pictures.make(ahead, shouldAbort: () => false);
      await shown(s, stood);
      expect(store.estimatedBytes, 2 * picture, reason: '⛔premise: laid');
      expect(pictures.heldNodes.heldBytes, node, reason: '⛔premise: held');

      // As the screen holds the picture it shows.
      final key = pictures.keyOf(stood);
      store.retainPin(key);
      addTearDown(() => store.releasePin(key));
      await pictures.holdNodesOf(
        pictures.stackOf(stood),
        stood,
        shouldAbort: () => false,
      );
      expect(pictures.heldNodes.heldBytes, node);
      expect(store.estimatedBytes, picture, reason: 'the one ahead gave way');
      expect(store.holds(key), isTrue);

      /// How many nodes a canvas holds, standing on the frame made ahead on
      /// a line with room for its picture and its folder but a byte — the
      /// picture [pinned] as the screen holds it, and [lent] bytes lent.
      Future<int> heldStanding({required bool pinned, int lent = 0}) async {
        final s = session();
        addTearDown(s.dispose);
        final line = s.playbackRig.playbackCache
          ..debugSetPlaybackCacheBudgetBytes(picture + node - 1);
        final pictures = s.playbackRig.framePictures;
        final stood = drawn(s);
        await pictures.make(stood, shouldAbort: () => false);
        if (pinned) {
          final key = pictures.keyOf(stood);
          s.renderCaches.framePictureStore.retainPin(key);
          addTearDown(() => s.renderCaches.framePictureStore.releasePin(key));
        }
        line.lend(lent);
        await pictures.holdNodesOf(
          pictures.stackOf(stood),
          stood,
          shouldAbort: () => false,
        );
        return pictures.heldNodes.length;
      }

      expect(await heldStanding(pinned: false), 1, reason: '⛔premise');
      expect(await heldStanding(pinned: true), 0, reason: 'what it shows');
      expect(
        await heldStanding(pinned: false, lent: picture),
        0,
        reason: 'what is lent',
      );
    });
  });

  testWidgets('⚖️what lies below the pen held is no room for the nodes over '
      'it', (tester) async {
    await tester.runAsync(() async {
      /// The bytes held below the pen and in all, standing on a frame with
      /// a folder under the pen and one over it, on a line of [line].
      Future<({int below, int all})> heldOn({int? line}) async {
        final s = session(count: 2, withPen: true);
        addTearDown(s.dispose);
        if (line != null) {
          s.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(line);
        }
        final pictures = s.playbackRig.framePictures;
        final stood = drawn(s, count: 2);
        final nodes = [
          for (final node in pictures.stackOf(stood))
            switch (node) {
              CompositeLeaf(
                payload: CanvasLayerImageRequest(:final frameKey),
              )
                  when frameKey.layerId == const LayerId('pen') =>
                CompositeLeaf<CanvasStackRow>(
                  CanvasActiveLayerRow(opacity: 1, frameKey: frameKey),
                ),
              _ => node,
            },
        ];
        await pictures.holdNodesOf(nodes, stood, shouldAbort: () => false);
        return (
          below: pictures.heldNodes.heldBelowBytes,
          all: pictures.heldNodes.heldBytes,
        );
      }

      final wide = await heldOn();
      final over = wide.all - wide.below;
      expect(wide.below, greaterThan(0), reason: '⛔premise: under the pen');
      expect(over, greaterThan(0), reason: '⛔premise: over the pen');

      final narrow = await heldOn(line: wide.below + over - 1);
      expect(narrow.below, wide.below);
      expect(narrow.all, wide.below, reason: 'no room left over it');
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

      await shown(s, picture);
      final held = pictures.heldNodes.heldBytes;
      expect(held, greaterThan(0), reason: '⛔premise: the folder is held');
      expect(held, lessThanOrEqualTo(page), reason: '⛔premise');

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

      await shown(s, (
        cut: picture.cut,
        frameIndex: 0,
        paintPaper: false,
        ghosts: false,
      ));
      expect(pictures.heldNodes, hasLength(1), reason: '⛔premise');
      s.dispose();
      expect(pictures.heldNodes, hasLength(0));
    });
  });
}

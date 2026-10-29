// A FRAME WITH A MOVIE ON IT STANDS ONCE AND WAITS FOR ITS FILM.
//
// 🐞10-30 (the hands-on verify's 23.976 `.mov`, then any movie placed): the
// app hung the moment a movie stood on the canvas. A movie cel has its
// picture before it is decoded (`celHasRenderableContent`), yet a read
// cannot bring it into hand — its picture is the movie tier's, banked
// nowhere (`BrushFrameStore.installMovieCel`) — so the read answered at
// once, the view stood again in the same microtask, and again, forever:
// the hydrator that decodes the movie never got a turn.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/movie_cel.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart'
    show FrameGhosts;
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/quiet_turns.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';

/// The cels' reads, counted — and refused past [_enough], where a view that
/// reads again and again would otherwise hold the test forever.
final class _CountedReads extends LayerFrameImageCache {
  _CountedReads({required super.frameStore});

  int reads = 0;

  @override
  Future<void> readIn(BrushFrameKey key, {required CanvasSize canvasSize}) {
    reads += 1;
    if (reads > _enough) {
      throw StateError('read $reads times and still not in hand');
    }
    return super.readIn(key, canvasSize: canvasSize);
  }
}

const int _enough = 100;

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  final film = BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('movie'),
    frameId: movieCelFrameId(const FrameId('take'), 0),
  );
  final picture = (
    cut: Cut(
      id: film.cutId,
      name: 'c',
      duration: 1,
      canvasSize: canvasSize,
      layers: const [],
    ),
    frameIndex: 0,
    paintPaper: false,
    ghosts: FrameGhosts.none,
  );
  final nodes = [
    CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: film, opacity: 1),
    ),
  ];

  testWidgets('🎯a movie cel not decoded yet is read once, not again and '
      'again — the frame stands and waits for its film', (tester) async {
    final cels = BrushFrameStore();
    expect(
      cels.celHasRenderableContent(film),
      isTrue,
      reason: 'fixture: a movie cel is part of its frame before it decodes',
    );
    final images = _CountedReads(frameStore: cels);
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    // No quiet comes, as none came in the app: the view standing again in
    // the same microtask left no frame for one. A making that drew the
    // frame would note the film as drawing nothing yet and end it here.
    final noQuiet = (await tester.runAsync(
      () async => QuietTurns(
        clock: QuietClock(
          held: () => true,
          quiet: () => null,
          gpuDone: () async {},
        ),
      ),
    ))!;
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => nodes,
      quietTurns: noQuiet,
    );

    await tester.pumpWidget(
      onAScreen(
        GlobalKey(),
        size: const Size(8, 8),
        under: const Color(0xFFFFFFFF),
        view: standingOn(
          run,
          picture: picture,
          nodes: nodes,
          viewport: CanvasViewport(),
          live: (
            activeSurfacePainter: null,
            floatOverlay: null,
            liftedRows: const {},
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 5; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      images.reads,
      2,
      reason: 'the film is asked for by the frame standing and by its '
          'making, and a read that brought nothing into hand does not stand '
          'the frame again',
    );
  });
}

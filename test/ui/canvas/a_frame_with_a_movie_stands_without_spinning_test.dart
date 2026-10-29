// A FRAME WITH A MOVIE ON IT STANDS ONCE AND DOES NOT SPIN.
//
// 🐞10-30 (the hands-on verify's 23.976 `.mov`, then any movie placed): the
// app hung the moment a movie stood on the canvas. A movie cel is never in
// hand, decoded or not — its picture is the movie tier's, banked nowhere —
// so a read answered at once, and the view stood again and read again in
// the same microtask, for ever (probed in the app: 21 million stands in two
// minutes, the UI thread never free again).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
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

  testWidgets('🎯a movie on the canvas is read, and the frame does not stand '
      'again for a read that brought nothing into hand', (tester) async {
    final cels = BrushFrameStore()
      ..installMovieCel(
        film,
        BitmapSurface(canvasSize: canvasSize, tileSize: defaultCelTileSize),
      );
    final images = _CountedReads(frameStore: cels);
    addTearDown(images.dispose);
    expect(
      images.storedSurfaceIsInHand(film, canvasSize: canvasSize),
      isFalse,
      reason: 'fixture: a decoded movie is not in hand, as in the app',
    );
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    // No quiet comes, as none came in the app: the frame laying its
    // picture waits for one, and nothing else ends the stands.
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
    await tester.pump(const Duration(milliseconds: 16));
    final settled = images.reads;
    for (var frame = 0; frame < 5; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(settled, inInclusiveRange(1, _enough), reason: 'the film is read');
    expect(
      images.reads,
      settled,
      reason: 'a read that brought nothing into hand does not stand the '
          'frame again — standing again, it read again',
    );
  });
}

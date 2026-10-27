import 'dart:ui' show Picture;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import '../../helpers/a_canvas_standing_on_a_frame.dart';

/// 🚨F-244 (저장 2026-10-27, Surface Pro 11): A FRAME VIEW IS PAINTED AGAIN
/// ONLY FOR WHAT CHANGES IN IT. The canvas's underlay is laid out again at
/// each commit of the timeline, and a frame drawn as it stands — a page of
/// paper and no row — was composed whole with it at each block moved: 🔬a
/// 1920×1080 composite a commit, +25ms in profile.
///
/// The oracle is the picture the view's paint recorded: a view not painted
/// again holds the one it held.
void main() {
  const canvasSize = CanvasSize(width: 32, height: 32);
  final cut = Cut(
    id: const CutId('c'),
    name: 'Cut',
    duration: 1,
    canvasSize: canvasSize,
    layers: [],
  );
  final screen = GlobalKey();

  /// What the frame view's paint recorded last.
  Picture? recorded(WidgetTester tester) {
    RenderObject? at = tester.renderObject(
      find.descendant(
        of: find.byType(FramePictureView),
        matching: find.byType(CustomPaint),
      ),
    );
    while (at != null && !at.isRepaintBoundary) {
      at = at.parent;
    }
    return (at!.debugLayer!.firstChild! as PictureLayer).picture;
  }

  testWidgets('a page of paper and no row is not composed again for a '
      'neighbour laid out again — and is for a change of its own', (
    tester,
  ) async {
    final images = LayerFrameImageCache(frameStore: BrushFrameStore());
    addTearDown(images.dispose);
    final store = FramePictureStore<FramePictureKey>(gpu: WritesNeverLand());
    addTearDown(store.dispose);
    final run = runOver(
      images,
      store,
      canvasSize: canvasSize,
      stackOf: (_) => const [],
    );
    final picture = (cut: cut, frameIndex: 0, paintPaper: true, ghosts: false);
    final LiveRows live = (
      activeSurfacePainter: BitmapSurfacePainter(
        surface: BitmapSurface(canvasSize: canvasSize, tileSize: 16),
        showTransparentBackground: false,
        lineage: 'a-frame-view-painted-again',
      ),
      floatOverlay: null,
      liftedRows: const {},
    );
    // What the canvas's tick layer builds again at a commit — and lays out
    // again, its builder with it.
    final commits = ValueNotifier(0);
    addTearDown(commits.dispose);
    Widget shown(CanvasViewport viewport) => onAScreen(
      screen,
      size: const Size(48, 40),
      under: const Color(0xFF203040),
      view: ValueListenableBuilder<int>(
        valueListenable: commits,
        builder: (context, commit, _) => LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              standingOn(
                run,
                picture: picture,
                nodes: const <CompositeNode<CanvasStackRow>>[],
                viewport: viewport,
                live: live,
              ),
              Text('$commit', textDirection: TextDirection.ltr),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(shown(CanvasViewport(panX: 8, panY: 4)));
    expect(
      run.pictures.drawsOnlyItsPage(
        run.pictures.keyAsItStands(const [], picture),
      ),
      isTrue,
      reason: '⛔전제: the frame is its page alone, drawn as it stands',
    );
    final before = recorded(tester);

    commits.value += 1;
    await tester.pump();

    expect(
      recorded(tester),
      same(before),
      reason: '🚨a neighbour laid out again composed the page again',
    );

    await tester.pumpWidget(shown(CanvasViewport(panX: 12, panY: 4)));

    expect(
      recorded(tester),
      isNot(same(before)),
      reason: 'LIVENESS: a view that moved paints the page again',
    );
  });
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import '../../helpers/the_frame_as_it_stands.dart';

/// 🎯A BUFFER ON THE EDITING CANVAS IS SIZED BY WHAT READS IT (card
/// nested-folder-buffers-read-past-the-view): the view at the top, and under
/// a folder that folder's own buffer, which a blur on it reads past the view
/// — the camera's walk since export-folders-and-rows-at-their-extent. Cut to
/// the view at every depth, a buffered row inside a blurred folder lost its
/// ink past the screen's edge, and the blur there changed as the view moved.
///
/// Each case is the camera's pin (`a_folder_through_the_camera_is_buffered_
/// at_its_shot_test`): a row in a buffer of its own inside the blurred one
/// lays the same bytes as the row drawn straight into it — a cel off the pen
/// as well as the pen's (↩️the bake's recordings of the rows beside the
/// pen's, until ②-5a; a row's image, as the stack drew the onion's ghosts
/// from, whole or held in pieces, until ②-5b-1).
void main() {
  setUpAll(LayerBlendShader.load);

  // The view sees (16, 16)–(48, 32) of the canvas. The ink lies left of it,
  // up to its edge. ⚠️The blur is wide on purpose: under `--enable-impeller`
  // a blur of 4 hardly reaches past the two pixels the pieces were laid
  // beyond what a canvas sees, and the pieces' case (↩️until ②-5b-1) could
  // not fail there.
  const canvasSize = CanvasSize(width: 64, height: 48);
  const view = Size(32, 16);
  final viewport = CanvasViewport(panX: -16, panY: -16);
  final blur = [ResolvedLayerEffect(kind: EffectKind.blur, values: [8, 0])];

  const frameKey = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  /// The row the pen draws on: the tile left of the view filled, or empty.
  BitmapSurfacePainter pen({required bool inked}) {
    final pixels = Uint8List(16 * 16 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 40;
      pixels[i + 1] = 90;
      pixels[i + 2] = 200;
      pixels[i + 3] = 255;
    }
    return BitmapSurfacePainter(
      surface: BitmapSurface(
        canvasSize: canvasSize,
        tileSize: 16,
        tiles: {
          if (inked)
            TileCoord(x: 0, y: 1): BitmapTile(size: 16, pixels: pixels),
        },
      ),
      showTransparentBackground: false,
    );
  }

  /// A drawn cel left of the view, its ink up to the view's edge.
  LayerFrameImageCache celLeftOfTheView() {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 16,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        for (var i = 0; i < 5; i += 1)
          BrushDab(
            center: CanvasPoint(x: 8, y: 16.0 + 4 * i),
            color: 0xFFC83228,
            size: 16,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: i,
          ),
      ],
    );
    final cache = LayerFrameImageCache(frameStore: store);
    addTearDown(cache.dispose);
    return cache;
  }

  const penRow = CompositeLeaf<CanvasStackRow>(
    CanvasActiveLayerRow(opacity: 1),
  );
  const celRow = CompositeLeaf<CanvasStackRow>(
    CanvasLayerImageRequest(frameKey: frameKey, opacity: 1),
  );

  CompositeNode<CanvasStackRow> folder(
    List<CompositeNode<CanvasStackRow>> children, {
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeGroup(
    children: children,
    opacity: 1,
    blendMode: LayerBlendMode.normal,
    effects: effects,
  );

  CompositeNode<CanvasStackRow> adjustment(
    List<CompositeNode<CanvasStackRow>> children, {
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeAdjustment(children: children, effects: effects, mix: 1);

  /// A row in multiply over [backdrop] — over nothing, the row as it is.
  CompositeNode<CanvasStackRow> blended(
    CompositeNode<CanvasStackRow> source, {
    List<CompositeNode<CanvasStackRow>> backdrop = const [],
  }) => CompositeBackdropBlend(
    backdrop: backdrop,
    source: source,
    blendMode: LayerBlendMode.multiply,
  );

  /// What is laid over the view for [nodes], through the display buffer —
  /// or on the [walk] that paints the screen: the frame as it stands
  /// ([TheFrameAsItStands]), the [pen]'s row drawn live.
  Future<Uint8List> paint(
    WidgetTester tester,
    List<CompositeNode<CanvasStackRow>> nodes, {
    BitmapSurfacePainter? pen,
    LayerFrameImageCache? cache,
    bool walk = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final images =
        cache ?? LayerFrameImageCache(frameStore: BrushFrameStore());
    // A view of its own each time: nothing one paint kept is the other's.
    final Widget stack = TheFrameAsItStands(
      key: UniqueKey(),
      nodes: nodes,
      imageCache: images,
      canvasSize: canvasSize,
      viewport: viewport,
      activeSurfacePainter: pen,
      debugDisableSingleBuffer: walk,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox.fromSize(size: view, child: stack)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byWidget(stack),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .first
        .painter!;
    final bytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), view);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        view.width.round(),
        view.height.round(),
      );
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  void expectTheSame(Uint8List bytes, Uint8List reference) {
    var shown = false;
    for (var i = 3; i < reference.length; i += 4) {
      shown = shown || reference[i] != 0;
    }
    expect(shown, isTrue, reason: 'LIVENESS: the blur reaches into the view');
    expect(bytes, reference);
  }

  group('🎯in the chain the pen draws in', () {
    for (final (says, walk) in <(String, bool)>[
      ('through the display buffer', false),
      ('on the walk that paints the screen', true),
    ]) {
      testWidgets('a folder inside a blurred folder, $says', (tester) async {
        final straight = await paint(
          tester,
          [
            folder([penRow], effects: blur),
          ],
          pen: pen(inked: true),
          walk: walk,
        );
        final nested = await paint(
          tester,
          [
            folder([
              folder([penRow]),
            ], effects: blur),
          ],
          pen: pen(inked: true),
          walk: walk,
        );

        expectTheSame(nested, straight);
      });
    }

    for (final (says, buffered) in <(
      String,
      CompositeNode<CanvasStackRow> Function(CompositeNode<CanvasStackRow>),
    )>[
      ('an adjustment', (row) => adjustment([row])),
      ('a row composed over its backdrop', blended),
    ]) {
      testWidgets('$says inside a blurred folder', (tester) async {
        final straight = await paint(
          tester,
          [
            folder([penRow], effects: blur),
          ],
          pen: pen(inked: true),
        );
        final nested = await paint(
          tester,
          [
            folder([buffered(penRow)], effects: blur),
          ],
          pen: pen(inked: true),
        );

        expectTheSame(nested, straight);
      });
    }

    testWidgets('a folder inside a blurred adjustment', (tester) async {
      final straight = await paint(
        tester,
        [
          adjustment([penRow], effects: blur),
        ],
        pen: pen(inked: true),
      );
      final nested = await paint(
        tester,
        [
          adjustment([
            folder([penRow]),
          ], effects: blur),
        ],
        pen: pen(inked: true),
      );

      expectTheSame(nested, straight);
    });

    // A blend's own buffer is what reads the rows it composes.
    testWidgets('a folder as the row a blend composes', (tester) async {
      final straight = await paint(
        tester,
        [
          folder([blended(penRow)], effects: blur),
        ],
        pen: pen(inked: true),
      );
      final nested = await paint(
        tester,
        [
          folder([
            blended(folder([penRow])),
          ], effects: blur),
        ],
        pen: pen(inked: true),
      );

      expectTheSame(nested, straight);
    });

    testWidgets('a folder in the backdrop a blend composes over', (
      tester,
    ) async {
      final cache = celLeftOfTheView();
      final straight = await paint(
        tester,
        [
          folder([
            blended(celRow, backdrop: [penRow]),
          ], effects: blur),
        ],
        pen: pen(inked: true),
        cache: cache,
      );
      final nested = await paint(
        tester,
        [
          folder([
            blended(
              celRow,
              backdrop: [
                folder([penRow]),
              ],
            ),
          ], effects: blur),
        ],
        pen: pen(inked: true),
        cache: cache,
      );

      expectTheSame(nested, straight);
    });
  });

  // ↩️The rows beside the pen's, recorded once and replayed under it, until
  // the bake went with the live rows (one-picture-per-frame ②-5a); and the
  // rows' images the stack drew the onion's ghosts from — whole, or held in
  // pieces past a side — until the ghosts were a picture of their own
  // (②-5b-1). A cel off the pen is drawn from its tiles, as the pen's is.
  group('🎯a cel off the pen', () {
    testWidgets('a folder inside a blurred folder', (tester) async {
      final cache = celLeftOfTheView();
      final straight = await paint(
        tester,
        [
          folder([celRow], effects: blur),
        ],
        cache: cache,
      );
      final nested = await paint(
        tester,
        [
          folder([
            folder([celRow]),
          ], effects: blur),
        ],
        cache: cache,
      );

      expectTheSame(nested, straight);
    });
  });
}

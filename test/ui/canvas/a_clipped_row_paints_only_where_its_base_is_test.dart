import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/cels_parked_cold.dart';
import '../../helpers/the_frame_as_it_stands.dart';

/// 🗣️I-92 (유저 2026-10-24): a row clipped to the layer below shows only
/// where the base's picture is — by the base's alpha, a soft edge as soft
/// — and a row in another blend than normal reads the base's whole colour
/// under it, its alpha the base's to lay once ([CompositeClip],
/// [CompositeOpaque]).
///
/// Both walks, the frame as it stands ([StackedFrame] — a canvas draws it
/// so, and its one picture is made of it) and the camera (the export's),
/// over the same shapes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A row in multiply is composed over its backdrop in the shader.
  setUpAll(LayerBlendShader.load);

  const canvasSize = CanvasSize(width: 4, height: 4);

  /// The base: grey, opaque at (0, 0), half at (1, 0), nothing at (2, 0).
  BitmapSurface base() => _surface({
    0: [128, 128, 128, 255],
    1: [128, 128, 128, 128],
  });

  /// What clips to it: [rgba] at (0, 0), (1, 0) and (2, 0).
  BitmapSurface over(List<int> rgba) =>
      _surface({0: rgba, 1: rgba, 2: rgba});

  const red = [220, 20, 10, 255];
  const blue = [10, 20, 220, 255];
  // Blue multiplied into the grey: 128 × (10, 20, 220) / 255.
  const blueOnGrey = [5, 10, 110];

  /// [over] clipped to [base] as the plan hands it over — composed over its
  /// backdrop where it is in [blendMode].
  List<CompositeNode<L>> clipped<L>(
    L base,
    L over, {
    LayerBlendMode blendMode = LayerBlendMode.normal,
    double opacity = 1,
  }) => [
    CompositeClip<L>(
      base: CompositeLeaf<L>(base),
      scope: [
        if (blendMode == LayerBlendMode.normal)
          CompositeLeaf<L>(over)
        else
          CompositeBackdropBlend<L>(
            backdrop: [CompositeOpaque<L>(CompositeLeaf<L>(base))],
            source: CompositeLeaf<L>(over),
            blendMode: blendMode,
          ),
      ],
      opacity: opacity,
      blendMode: LayerBlendMode.normal,
    ),
  ];

  void expectClipped(Uint8List bytes, List<int> rgb, {double strength = 1}) {
    List<int> at(int x) => bytes.sublist(x * 4, x * 4 + 4);
    expect(at(0).sublist(0, 3), _near(rgb), reason: 'where the base is whole');
    expect(at(0)[3], closeTo(255 * strength, 2));
    expect(
      at(1).sublist(0, 3),
      _near(rgb),
      reason: 'its colour as it is where the base is half',
    );
    expect(at(1)[3], closeTo(128 * strength, 2), reason: 'the base\'s alpha');
    expect(at(2)[3], 0, reason: 'where the base has nothing, nothing');
  }

  group('the camera', () {
    Future<Uint8List> render(
      List<CompositeNode<CutFrameCompositeLayer>> nodes,
    ) async {
      final view = cameraViewOver(canvasSize.canvasRect);
      final image = await const CameraFrameRenderService(
        background: ui.Color(0x00000000),
      ).renderThroughCamera(
        nodes: nodes,
        pose: view.pose,
        cameraFrameSize: view.frameSize,
      );
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      return data!.buffer.asUint8List();
    }

    CutFrameCompositeLayer row(BitmapSurface surface) =>
        CutFrameCompositeLayer(surface: surface, opacity: 1);

    test('a clipped row shows by the base\'s alpha', () async {
      expectClipped(
        await render(clipped(row(base()), row(over(red)))),
        red.sublist(0, 3),
      );
    });

    test('in multiply it reads the base\'s whole colour, and lays by its '
        'alpha', () async {
      expectClipped(
        await render(
          clipped(
            row(base()),
            row(over(blue)),
            blendMode: LayerBlendMode.multiply,
          ),
        ),
        blueOnGrey,
      );
    });

    test('the group lays at the base\'s strength', () async {
      expectClipped(
        await render(clipped(row(base()), row(over(red)), opacity: 0.5)),
        red.sublist(0, 3),
        strength: 0.5,
      );
    });
  });

  group('the editing stack', () {
    const key = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('base'),
      frameId: FrameId('base-1'),
    );

    /// The frame of [nodes] as it stands — the base a stored cel, what
    /// clips to it the row being drawn on, [live] — painted.
    /// ↩️It was the editing stack's own walk, until the canvas drew the
    /// frame's one picture and the frame as it stands (one-picture-per-frame
    /// ②-5a).
    Future<Uint8List> render(
      WidgetTester tester,
      List<CompositeNode<CanvasStackRow>> nodes, {
      required BitmapSurface live,
    }) async {
      final store = BrushFrameStore();
      parkCold(store, {key: base()});
      final cache = LayerFrameImageCache(frameStore: store);
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 4,
                height: 4,
                child: TheFrameAsItStands(
                  nodes: nodes,
                  imageCache: cache,
                  canvasSize: canvasSize,
                  viewport: CanvasViewport(),
                  activeSurfacePainter: BitmapSurfacePainter(
                    surface: live,
                    showTransparentBackground: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final painter = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(TheFrameAsItStands),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((paint) => paint.painter)
          .whereType<CustomPainter>()
          .first;
      return (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        const size = Size(4, 4);
        painter.paint(Canvas(recorder, Offset.zero & size), size);
        final image = await recorder.endRecording().toImage(4, 4);
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
    }

    const stored = CanvasLayerImageRequest(frameKey: key, opacity: 1);
    const drawing = CanvasActiveLayerRow(opacity: 1);

    testWidgets('a clipped row shows by the base\'s alpha', (tester) async {
      expectClipped(
        await render(tester, clipped(stored, drawing), live: over(red)),
        red.sublist(0, 3),
      );
    });

    testWidgets('in multiply it reads the base\'s whole colour, and lays by '
        'its alpha', (tester) async {
      expectClipped(
        await render(
          tester,
          clipped(stored, drawing, blendMode: LayerBlendMode.multiply),
          live: over(blue),
        ),
        blueOnGrey,
      );
    });

    testWidgets('the group lays at the base\'s strength', (tester) async {
      expectClipped(
        await render(
          tester,
          clipped(stored, drawing, opacity: 0.5),
          live: over(red),
        ),
        red.sublist(0, 3),
        strength: 0.5,
      );
    });
  });
}

/// A 4×4 surface holding [row0] along its top row: each x → its RGBA.
BitmapSurface _surface(Map<int, List<int>> row0) {
  final pixels = Uint8List(4 * 4 * 4);
  for (final MapEntry(key: x, value: rgba) in row0.entries) {
    pixels.setAll(x * 4, rgba);
  }
  return BitmapSurface(
    canvasSize: const CanvasSize(width: 4, height: 4),
    tileSize: 4,
    tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 4, pixels: pixels)},
  );
}

/// Each channel of [rgb], give or take what a half alpha rounds away.
Matcher _near(List<int> rgb) => pairwiseCompare<num, num>(
  rgb,
  (expected, actual) => (expected - actual).abs() <= 3,
  'within 3 of',
);

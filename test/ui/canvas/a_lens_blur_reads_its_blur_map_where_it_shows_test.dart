@Tags(['impeller'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart' show LayerPlacement;
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/composite_tree_paint.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🗣️I-132-Q21 a (유저 2026-10-28): a camera lens blur reads its blur map's
/// row where that row shows — and so where the row it blurs shows it, each
/// lying where its own pose lays it.
///
/// The map is black left of [seam] and white from it; the row it blurs, a
/// checker moved [shift] to the right. With the focal distance at black,
/// what lies left of the seam on the canvas is drawn sharp, the pixel
/// itself, and what lies right of it at the blur's whole radius — on the
/// canvas's own road and on the camera's, the export's. Read where the
/// blurred row's own pixels lie instead, the seam would stand [shift] over.
void main() {
  setUpAll(IrisBlurShader.load);

  const width = 64;
  const height = 32;
  const canvasSize = CanvasSize(width: width, height: height);
  const seam = 32;
  const shift = 8.0;
  const map = LayerId('map');
  const shifted = LayerPlacement(1, 0, 0, 1, shift, 0);
  const cel = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('checker'),
    frameId: FrameId('f'),
  );
  const mapCel = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: map,
    frameId: FrameId('f'),
  );
  const page = (
    canvasSize: canvasSize,
    pasteboardReach: PasteboardReach.whole,
    paintPaper: false,
    paperBackground: ProjectBackground.defaultBackground,
  );

  BitmapSurface surfaceOf(List<int> Function(int x, int y) rgbaAt) {
    final pixels = Uint8List(width * width * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        pixels.setAll((y * width + x) * 4, rgbaAt(x, y));
      }
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: width,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(size: width, pixels: pixels),
      },
    );
  }

  final checker = surfaceOf(
    (x, y) => (x ~/ 2 + y ~/ 2).isEven
        ? const [0xE0, 0x40, 0x20, 0xFF]
        : const [0x20, 0x40, 0xE0, 0xFF],
  );
  final depth = surfaceOf(
    (x, _) => x < seam ? const [0, 0, 0, 0xFF] : const [0xFF, 0xFF, 0xFF, 0xFF],
  );

  /// A lens blur of radius 4, its blur map [map] where [mapped] — read by
  /// its luma, in focus at black.
  ResolvedLayerEffect lens({required bool mapped}) => ResolvedLayerEffect(
    kind: EffectKind.cameraLensBlur,
    values: [
      for (final spec in EffectKind.cameraLensBlur.parameters)
        if (spec.id == 'blurRadius') 4 else spec.defaultValue,
    ],
    layers: {if (mapped) 'blurMapLayer': map},
  );

  /// The three pictures each road is asked for: the checker as it is
  /// (`sharp`), blurred with no map (`uniform`), and blurred by the map.
  List<ResolvedLayerEffect> chainOf(String scene) => switch (scene) {
    'sharp' => const [],
    _ => [lens(mapped: scene == 'mapped')],
  };

  /// [mapped] against [sharp] left of the seam and [uniform] right of it,
  /// byte for byte — and the fixture holding something to tell apart.
  Future<void> expectReadWhereItShows(
    Future<Uint8List> Function(String scene) drawn,
  ) async {
    final sharp = await drawn('sharp');
    final uniform = await drawn('uniform');
    final mapped = await drawn('mapped');
    var unlikeLeft = 0;
    var unlikeRight = 0;
    final off = <String>[];
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final at = (y * width + x) * 4;
        final want = x < seam ? sharp : uniform;
        for (var c = 0; c < 4; c += 1) {
          if (sharp[at + c] != uniform[at + c]) {
            x < seam ? unlikeLeft++ : unlikeRight++;
          }
          if (mapped[at + c] != want[at + c] && off.length < 8) {
            off.add('($x, $y)[$c] ${mapped[at + c]} != ${want[at + c]}');
          }
        }
      }
    }
    expect(unlikeLeft, greaterThan(0), reason: 'fixture: the blur shows');
    expect(unlikeRight, greaterThan(0), reason: 'fixture: the blur shows');
    expect(off, isEmpty);
  }

  Future<Uint8List> bytesOf(WidgetTester tester, ui.Image image) async =>
      (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();

  testWidgets('on the canvas\'s own road', (tester) async {
    Future<Uint8List> drawn(String scene) async {
      final row = CompositeLeaf<CanvasStackRow>(
        CanvasLayerImageRequest(
          frameKey: cel,
          opacity: 1,
          placement: shifted,
          effects: chainOf(scene),
        ),
      );
      final frame = stackedFrameOf(
        [
          if (scene == 'mapped')
            CompositeReadsRows(
              node: row,
              rows: {
                map: [
                  const CompositeLeaf(
                    CanvasLayerImageRequest(frameKey: mapCel, opacity: 1),
                  ),
                ],
              },
            )
          else
            row,
        ],
        page: page,
        surfaceOf: (key) => key == cel ? checker : depth,
      );
      final recorder = ui.PictureRecorder();
      frame.drawing.draw(Canvas(recorder));
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      addTearDown(image.dispose);
      return bytesOf(tester, image);
    }

    await expectReadWhereItShows(drawn);
  });

  // What a folder reads is part of what it draws: the picture of it a
  // frame holds is kept under both ([CompositeReadsRows]).
  testWidgets('🚨a folder that reads a map is held with the map it read — '
      'the map drawn on since, the folder is drawn again', (tester) async {
    final held = HeldSubtreeRasters(bytes: () => 1 << 20);
    addTearDown(held.clear);
    final flipped = surfaceOf(
      (x, _) =>
          x < seam ? const [0xFF, 0xFF, 0xFF, 0xFF] : const [0, 0, 0, 0xFF],
    );
    var drawnOn = false;
    final nodes = <CompositeNode<CanvasStackRow>>[
      CompositeReadsRows(
        node: CompositeGroup(
          children: [
            const CompositeLeaf(
              CanvasLayerImageRequest(frameKey: cel, opacity: 1),
            ),
          ],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          effects: [lens(mapped: true)],
        ),
        rows: {
          map: [
            const CompositeLeaf(
              CanvasLayerImageRequest(frameKey: mapCel, opacity: 1),
            ),
          ],
        },
      ),
    ];
    StackedFrame frameOf({bool? keeps}) => stackedFrameOf(
      nodes,
      page: page,
      surfaceOf: (key) => key == cel
          ? checker
          : drawnOn
          ? flipped
          : depth,
      held: switch (keeps) {
        final keeps? => (
          pictures: (
            rasters: held,
            keeps: keeps,
            below: keeps ? BelowThePen.whole : BelowThePen.inCells,
          ),
          revisionOf: (key) => key == mapCel && drawnOn ? 2 : 1,
        ),
        null => null,
      },
    );
    Future<Uint8List> drawn(StackedFrame frame) async {
      final recorder = ui.PictureRecorder();
      frame.drawing.draw(Canvas(recorder)..clipRect(frame.drawing.extent));
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      addTearDown(image.dispose);
      return bytesOf(tester, image);
    }

    await drawn(frameOf(keeps: true));
    expect(held.length, 1, reason: '⛔premise: the folder was kept');
    debugSubtreeRasterCount = 0;
    await drawn(frameOf(keeps: false));
    expect(debugSubtreeRasterCount, 0, reason: '⛔premise: it is cut from');

    drawnOn = true;
    final again = await drawn(frameOf(keeps: false));
    expect(again, await drawn(frameOf()));
  });

  testWidgets('on the camera\'s road, the export\'s', (tester) async {
    const service = CameraFrameRenderService(background: Color(0x00000000));
    Future<Uint8List> drawn(String scene) async {
      final row = CompositeLeaf(
        CutFrameCompositeLayer(
          surface: checker,
          opacity: 1,
          placement: shifted,
          effects: chainOf(scene),
        ),
      );
      final image = (await tester.runAsync(
        () => service.renderThroughCamera(
          canvasSize: canvasSize,
          nodes: [
            if (scene == 'mapped')
              CompositeReadsRows(
                node: row,
                rows: {
                  map: [
                    CompositeLeaf(
                      CutFrameCompositeLayer(surface: depth, opacity: 1),
                    ),
                  ],
                },
              )
            else
              row,
          ],
          pose: CameraPose(center: CanvasPoint(x: width / 2, y: height / 2)),
          cameraFrameSize: canvasSize,
        ),
      ))!;
      addTearDown(image.dispose);
      return bytesOf(tester, image);
    }

    await expectReadWhereItShows(drawn);
  });
}

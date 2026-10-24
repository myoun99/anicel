import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cel_number_letters.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/camera_frame_corners.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement, placementMatrix;
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart'
    show subtreeBufferBounds;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/text/cel_number_paint.dart' show celNumberExtent;

import '../../helpers/placement_reading.dart';

/// 🗣️I-65 (유저 2026-10-24): a CEL NUMBER is written over its row's
/// picture where the row lies — it moves with the layer's transform (Q2 a:
/// 「그림과 함께 움직인다」) — and, 「납품 셀에도 셀번호 적는 거야」 (08-07),
/// into the delivered cel even with the FX off (Q2 메모: 「fx체크해제해도
/// 셀출력시 내보냄」).
void main() {
  const canvas = CanvasSize(width: 320, height: 240);
  const cutId = CutId('cut');
  const layerId = LayerId('a');
  final drawing = Frame(
    id: const FrameId('f1'),
    duration: 1,
    strokes: const [],
    name: '1',
  );

  final number = LayerEffect(
    id: const EffectId('number'),
    kind: EffectKind.celNumber,
    parameters: {'red': EffectParameter(value: 255)},
  );
  final blur = LayerEffect(
    id: const EffectId('blur'),
    kind: EffectKind.blur,
    parameters: {
      'blurX': EffectParameter(value: 4),
      'blurY': EffectParameter(value: 4),
    },
  );

  Layer row(List<LayerEffect> effects, {TransformTrack? transform}) => Layer(
    id: layerId,
    name: 'A',
    frames: [drawing],
    timeline: {0: TimelineExposure.drawing(drawing.id, length: 4)},
    effects: effects,
    transformTrack: transform,
  );

  /// The letters' pixels of a straight RGBA picture [width] wide: how many
  /// are red, how many of those are partly there, and where their middle
  /// is — the mean of their pixels' middles.
  ({int count, int soft, CanvasPoint middle}) redOf(
    Uint8List rgba,
    int width,
  ) {
    var count = 0;
    var soft = 0;
    var x = 0.0;
    var y = 0.0;
    for (var at = 0; at < rgba.length; at += 4) {
      final (r, g, b, a) = (rgba[at], rgba[at + 1], rgba[at + 2], rgba[at + 3]);
      if (a == 0 || r < 128 || g > 100 || b > 100) {
        continue;
      }
      count += 1;
      if (a < 255) {
        soft += 1;
      }
      x += (at ~/ 4) % width + 0.5;
      y += (at ~/ 4) ~/ width + 0.5;
    }
    return (
      count: count,
      soft: soft,
      middle: count == 0
          ? CanvasPoint(x: -1, y: -1)
          : CanvasPoint(x: x / count, y: y / count),
    );
  }

  /// On the paper's middle: across, exactly; down, as near as the glyphs
  /// sit to the middle of their line — the box the letters are stood by is
  /// the line's (`TextCelLayout.inkBounds`), and a glyph is not centred in
  /// it.
  final onTheMiddle = isA<CanvasPoint>()
      .having((p) => p.x, 'x', closeTo(160, 0.5))
      .having((p) => p.y, 'y', closeTo(120, 4));

  group('through the camera', () {
    final view = cameraViewOver(
      ui.Rect.fromLTWH(0, 0, canvas.width.toDouble(), canvas.height.toDouble()),
    );

    Future<Uint8List> shot(Layer layer) async {
      final image =
          await const CameraFrameRenderService(
            background: ui.Color(0x00000000),
          ).renderThroughCamera(
            nodes: planCutFrameCompositeTree(
              cut: Cut(
                id: cutId,
                name: 'Cut',
                layers: [layer],
                duration: 4,
                canvasSize: canvas,
              ),
              frameIndex: 0,
              surfaceResolver: (_, _) => BitmapSurface(canvasSize: canvas),
            ),
            pose: view.pose,
            cameraFrameSize: view.frameSize,
          );
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      return data!.buffer.asUint8List();
    }

    testWidgets('the letters are written in the number\'s colour, their '
        'middle on the paper\'s at rest — and none without the number', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final letters = redOf(await shot(row([number])), canvas.width);
        expect(letters.count, greaterThan(100));
        expect(letters.middle, onTheMiddle);
        expect(redOf(await shot(row(const [])), canvas.width).count, 0);
      });
    });

    testWidgets('they move with the row\'s transform (Q2 a)', (tester) async {
      await tester.runAsync(() async {
        final moved = TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 220, y: 150),
          ),
        );
        final rest = redOf(await shot(row([number])), canvas.width).middle;
        final there = redOf(
          await shot(row([number], transform: moved)),
          canvas.width,
        ).middle;
        expect((there.x - rest.x, there.y - rest.y), (60, 30));
      });
    });

    testWidgets('a blur after the number softens its letters; one before '
        'it leaves them as they were', (tester) async {
      await tester.runAsync(() async {
        final plain = await shot(row([number]));
        expect(await shot(row([blur, number])), plain);
        final after = await shot(row([number, blur]));
        expect(after, isNot(plain));
        expect(
          redOf(after, canvas.width).soft,
          greaterThan(redOf(plain, canvas.width).soft),
        );
      });
    });
  });

  group('on the editing canvas', () {
    final letters = CelNumberLetters(
      text: 'A1',
      color: 0xFFFF0000,
      center: CanvasPoint(x: 160, y: 120),
      scale: CanvasPoint(x: 1, y: 1),
    );

    /// The row drawn on, at [placement], wearing [letters] as the plan
    /// lowers a cel number ([celNumberedRow]) — painted.
    Future<Uint8List> painted(
      WidgetTester tester, {
      LayerPlacement? placement,
    }) async {
      final row = CompositeLeaf<CanvasStackRow>(
        CanvasActiveLayerRow(opacity: 1, placement: placement),
      );
      final store = BrushFrameStore();
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: canvas.width.toDouble(),
                height: canvas.height.toDouble(),
                child: CanvasLayerStackView(
                  nodes: [
                    CompositeGroup(
                      children: [
                        row,
                        CompositeCelNumber(on: row, letters: letters),
                      ],
                      opacity: 1,
                      blendMode: LayerBlendMode.normal,
                      effects: const [],
                    ),
                  ],
                  imageCache: LayerFrameImageCache(frameStore: store),
                  canvasSize: canvas,
                  viewport: CanvasViewport(),
                  activeSurfacePainter: BitmapSurfacePainter(
                    surface: BitmapSurface(canvasSize: canvas),
                    showTransparentBackground: false,
                  ),
                  paintPaper: false,
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
              of: find.byType(CanvasLayerStackView),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((paint) => paint.painter)
          .whereType<CustomPainter>()
          .first;
      return (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final size = Size(canvas.width.toDouble(), canvas.height.toDouble());
        painter.paint(Canvas(recorder, Offset.zero & size), size);
        final image = await recorder.endRecording().toImage(
          canvas.width,
          canvas.height,
        );
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
    }

    testWidgets('the letters are written where they stand, and move with '
        'the row', (tester) async {
      final rest = redOf(await painted(tester), canvas.width);
      expect(rest.count, greaterThan(100));
      expect(rest.middle, onTheMiddle);
      final there = redOf(
        await painted(
          tester,
          placement: placedBy(
            TransformPose(center: CanvasPoint(x: 220, y: 150)),
            canvas,
          ),
        ),
        canvas.width,
      ).middle;
      expect((there.x - rest.middle.x, there.y - rest.middle.y), (60, 30));
    });
  });

  // A group's buffer is what its rows stand for ([subtreeBufferBounds]) —
  // so a blur after the number reads the letters where they stand past
  // the paper, as they lie with the row.
  testWidgets('a numbered row\'s buffer reaches its letters past the paper, '
      'where the row lies', (tester) async {
    final paper = ui.Rect.fromLTWH(
      0,
      0,
      canvas.width.toDouble(),
      canvas.height.toDouble(),
    );
    final letters = CelNumberLetters(
      text: 'A1',
      color: 0xFFFF0000,
      center: CanvasPoint(x: 0, y: 120),
      scale: CanvasPoint(x: 1, y: 1),
    );
    final standing = celNumberExtent(letters);
    expect(standing.left, lessThan(0), reason: 'fixture: past the paper');
    ui.Rect bufferOf(LayerPlacement? placement) {
      final row = CompositeLeaf<LayerPlacement?>(placement);
      return subtreeBufferBounds(
        CompositeGroup<LayerPlacement?>(
          children: [
            row,
            CompositeCelNumber(on: row, letters: letters),
          ],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          effects: const [],
        ),
        within: const ui.Rect.fromLTWH(-1000, -1000, 3000, 3000),
        extentOf: (_) => paper,
        placementOf: (placement) => placement,
      );
    }

    expect(bufferOf(null), paper.expandToInclude(standing));
    final moved = placedBy(
      TransformPose(center: CanvasPoint(x: 260, y: 120)),
      canvas,
    );
    final lying = placementMatrix(moved);
    expect(
      bufferOf(moved),
      MatrixUtils.transformRect(
        lying,
        paper,
      ).expandToInclude(MatrixUtils.transformRect(lying, standing)),
    );
  });

  group('in the delivered cel', () {
    /// A cut whose row wears [effects], its one drawing a black pixel in the
    /// paper's corner — a cel with no artwork is not written.
    EditorSessionManager sessionOf(List<LayerEffect> effects) {
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: canvas,
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Track',
              cuts: [
                Cut(
                  id: cutId,
                  name: 'CUT',
                  duration: 4,
                  canvasSize: canvas,
                  layers: [row(effects), createCameraLayer(cutId: cutId)],
                ),
              ],
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      );
      addTearDown(session.dispose);
      const tile = 256;
      final pixels = Uint8List(tile * tile * 4)..[3] = 255;
      final cut = session.requireActiveCut;
      session.renderCaches.brushFrameStore.storeRebuiltDisplayCache(
        key: session.brushFrameKeyForCut(cut, layerId, drawing.id),
        previewSurface: BitmapSurface(canvasSize: canvas, tileSize: tile)
            .putTiles([
              (
                coord: TileCoord(x: 0, y: 0),
                tile: BitmapTile(size: tile, pixels: pixels),
              ),
            ]),
      );
      return session;
    }

    /// The cel of [effects]'s row, the tab's FX [applyLayerFx]: its straight
    /// RGBA.
    Future<Uint8List> celOf(
      List<LayerEffect> effects, {
      bool applyLayerFx = true,
    }) async {
      final session = sessionOf(effects);
      final cut = session.requireActiveCut;
      final layer = cut.layers.firstWhere((layer) => layer.id == layerId);
      final image =
          await ExportFrameRenderer(
            session: session,
            applyLayerFx: applyLayerFx,
            background: const ui.Color(0x00000000),
          ).renderCelGroup(
            ExportCelGroupTask(
              cut: cut,
              baseLayer: layer,
              members: [layer],
              memberFrames: [drawing],
              baseFrame: drawing,
              celName: '1',
              fileName: 'A1.png',
            ),
            ExportSizeMode.canvas,
            guideColor: const ui.Color(0xFF000000),
          );
      final bytes = await image!.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      image.dispose();
      return bytes!.buffer.asUint8List();
    }

    testWidgets('the cel wears its number, on the paper\'s middle', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final letters = redOf(await celOf([number]), canvas.width);
        expect(letters.count, greaterThan(100));
        expect(letters.middle, onTheMiddle);
        expect(redOf(await celOf(const []), canvas.width).count, 0);
      });
      await tester.pumpAndSettle();
    });

    testWidgets('with the tab\'s FX off the number is still written — and '
        'the rest of the chain is not', (tester) async {
      await tester.runAsync(() async {
        expect(
          await celOf([number, blur], applyLayerFx: false),
          await celOf([number]),
        );
      });
      await tester.pumpAndSettle();
    });

    // ⚠️The number's own switch is my reading of 「fx 체크」 too — asked as
    // I-65-Q3 (recommended a: both).
    testWidgets('with the number\'s own switch off it is still written', (
      tester,
    ) async {
      await tester.runAsync(() async {
        expect(
          await celOf([number.copyWith(enabled: false)]),
          await celOf([number]),
        );
      });
      await tester.pumpAndSettle();
    });
  });
}

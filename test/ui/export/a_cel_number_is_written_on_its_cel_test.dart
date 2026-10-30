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
import 'package:anicel/src/models/export_spec.dart' show ExportLayerFx;
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
import '../../helpers/the_frame_as_it_stands.dart';

/// 🗣️I-65 (유저 2026-10-24): a CEL NUMBER is written over its row's
/// picture where the row lies — it moves with the layer's transform (Q2 a:
/// 「그림과 함께 움직인다」) — and, 「납품 셀에도 셀번호 적는 거야」 (08-07),
/// into the delivered cel under the tab's 켬 and 기본만 켬 (I-65-Q3).
/// ↩️Q2 메모 wrote it under the FX off too (「fx체크해제해도 셀출력시
/// 내보냄」); Q3 made 끔 turn every fx off, the number with them.
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
    colors: {'ink': PropertyTrack<int>.empty().withKey(0, 0xFFFF0000)},
  );
  final blur = LayerEffect(
    id: const EffectId('blur'),
    kind: EffectKind.blur,
    parameters: {
      'blurriness': EffectParameter(value: 4),
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
            canvasSize: canvas,
            nodes: planCutFrameCompositeTree(
              cut: Cut(
                id: cutId,
                name: 'Cut',
                layers: [layer],
                duration: 4,
                canvasSize: canvas,
              ),
              frameIndex: 0,
              reading: (
                surfaces: (_, _) => BitmapSurface(canvasSize: canvas),
                plugins: null,
              ),
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
                child: TheFrameAsItStands(
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
              of: find.byType(TheFrameAsItStands),
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
    const attachId = LayerId('b');

    /// A cut whose row wears [effects] — with a row attached to it beside
    /// it — each drawing a black pixel in the paper's corner: a cel with no
    /// artwork is not written. [clipped], the attached row clips to the
    /// numbered one and is green all over.
    EditorSessionManager sessionOf(
      List<LayerEffect> effects, {
      bool clipped = false,
    }) {
      final attach = Layer(
        id: attachId,
        name: 'A影',
        frames: [drawing],
        timeline: {0: TimelineExposure.drawing(drawing.id, length: 4)},
        attachedToLayerId: layerId,
        clipsToBelow: clipped,
      );
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
                  layers: [
                    row(effects),
                    attach,
                    createCameraLayer(cutId: cutId),
                  ],
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
      final green = Uint8List(tile * tile * 4);
      for (var at = 0; at < green.length; at += 4) {
        green
          ..[at + 1] = 255
          ..[at + 3] = 255;
      }
      final cut = session.requireActiveCut;
      for (final id in [layerId, attachId]) {
        final all = clipped && id == attachId;
        session.renderCaches.brushFrameStore.storeRebuiltDisplayCache(
          key: session.brushFrameKeyForCut(cut, id, drawing.id),
          previewSurface: BitmapSurface(canvasSize: canvas, tileSize: tile)
              .putTiles([
                for (final (x, y)
                    in all
                        ? const [(0, 0), (1, 0), (0, 1), (1, 1)]
                        : const [(0, 0)])
                  (
                    coord: TileCoord(x: x, y: y),
                    tile: BitmapTile(size: tile, pixels: all ? green : pixels),
                  ),
              ]),
        );
      }
      return session;
    }

    /// The cel of row [of] — its base wearing [effects] — written with the
    /// tab's FX [fx]: its straight RGBA. [clipped], with the attached row
    /// clipping to it in the cel ([sessionOf]).
    Future<Uint8List> celOf(
      List<LayerEffect> effects, {
      ExportLayerFx fx = ExportLayerFx.on,
      LayerId of = layerId,
      bool clipped = false,
    }) async {
      final session = sessionOf(effects, clipped: clipped);
      final cut = session.requireActiveCut;
      final layer = cut.layers.firstWhere((layer) => layer.id == of);
      final attach = cut.layers.firstWhere((layer) => layer.id == attachId);
      final image =
          await ExportFrameRenderer(
            session: session,
            layerFx: fx,
            background: const ui.Color(0x00000000),
          ).renderCelGroup(
            ExportCelGroupTask(
              cut: cut,
              baseLayer: layer,
              members: [layer, if (clipped) attach],
              memberFrames: [drawing, if (clipped) drawing],
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

    // 🗣️I-65-Q3 (유저 2026-10-25): 「켬, 기본만 켬, 끔. 켬이랑 끔은 지금처럼
    // 전부 켜고 끄는거고, 기본만 켬은 … 셀번호나 참조fx같은것만 키고
    // 트랜스폼 포함해서 나머지 끄는것」.
    testWidgets('켬 writes the whole chain, 기본만 켬 the number alone, 끔 none '
        'of it', (tester) async {
      await tester.runAsync(() async {
        final numbered = await celOf([number]);
        final both = await celOf([number, blur]);
        expect(both, isNot(numbered), reason: '켬 blurs it');
        expect(
          await celOf([number, blur], fx: ExportLayerFx.basic),
          numbered,
        );
        expect(
          await celOf([number, blur], fx: ExportLayerFx.off),
          await celOf(const []),
        );
      });
      await tester.pumpAndSettle();
    });

    // 🗣️I-65-Q12 (유저 2026-10-27): 「레이어 행의 fx 머리도 같은 법 — 셀
    // 번호도」. ↩️Q5 「출력은 머리를 안 본다」 wrote a link switched off as
    // one switched on.
    testWidgets('a link whose own switch is off is not written — the cel '
        'number\'s neither', (tester) async {
      await tester.runAsync(() async {
        final heads = [
          number.copyWith(enabled: false),
          blur.copyWith(enabled: false),
        ];
        final bare = await celOf(const []);
        expect(await celOf(heads), bare);
        expect(await celOf(heads, fx: ExportLayerFx.basic), bare);
        expect(
          await celOf([number, blur.copyWith(enabled: false)]),
          await celOf([number]),
          reason: 'the one switched on is written',
        );
      });
      await tester.pumpAndSettle();
    });

    // 🗣️I-65-Q4 (유저 2026-10-24): 「fx 를 단 행만 적는다 — 어태치는 번호 없이
    // 나머지 fx 만 입는다」.
    testWidgets('a row attached to the numbered one wears the rest of its '
        'chain, and no number', (tester) async {
      await tester.runAsync(() async {
        final attached = await celOf([number, blur], of: attachId);
        expect(redOf(attached, canvas.width).count, 0);
        expect(attached, await celOf([blur], of: attachId));
        expect(attached, isNot(await celOf(const [], of: attachId)));
      });
      await tester.pumpAndSettle();
    });

    // I-92: a row clipped to is cut by as ONE picture, as a folder is
    // (`meetsAClip`) — the numbered row's letters with its pixels, as the
    // cut's own tree cuts it.
    testWidgets('a row clipped to the numbered one is cut by its letters '
        'too', (tester) async {
      await tester.runAsync(() async {
        final cel = await celOf([number], clipped: true);
        expect(
          redOf(cel, canvas.width).count,
          0,
          reason: 'laid over the clip, the letters would show red',
        );
        var green = 0;
        for (var at = 0; at < cel.length; at += 4) {
          if (cel[at + 1] == 255 && cel[at + 3] == 255) {
            green += 1;
          }
        }
        expect(green, greaterThan(100), reason: 'cut to the letters');
      });
      await tester.pumpAndSettle();
    });
  });
}

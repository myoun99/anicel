import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart'
    show
        EffectId,
        EffectKind,
        EffectParameter,
        LayerEffect,
        ResolvedLayerEffect;
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement, placedCorners;
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_offset.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/row_transform_box.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart'
    show debugLastSubtreeRaster;
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/se_name_tag_paint.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// F-387 (유저 2026-10-19): 「일반 그림 레이어에서는 트랜스폼fx의 헤더에 서면
/// 변형도구 ui 그대로써서 회전같은거 가능한데 se의 트랜스폼fx는 그런게안됨.
/// 그런 관련 로직 사본만든거같은데 법 통일. 같은 fx인데 다른건 말이안됨」.
///
/// An SE row's transform poses its name tag as a layer's poses its picture
/// — anchor, position, scale, turn and opacity — and the box on its header
/// is the layer's: the inside moves, a corner scales, outside turns and the
/// cross places the anchor.
void main() {
  /// The default project, its first SE row speaking at frame 0 and stood
  /// on at its transform's header.
  EditorSessionManager speaking() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    final se = s.activeTrack.seLayers.first;
    s.selectLayer(se.id);
    s.selectFrameIndex(0);
    s.seEntries.createSeEntryAtCurrentFrame(name: 'おはよう', seName: 'タモツ');
    s.standOnRow(LaneRowAddress(se.id, transformGroupHeaderLane.laneId));
    return s;
  }

  ResolvedSeNameTag tagOf(EditorSessionManager s) =>
      s.seEntries.seNameTagsForCutFrame(s.requireActiveCut, 0).single;

  Future<void> pumpArea(WidgetTester tester, EditorSessionManager s) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(true);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: s,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The warmer's debounced timers cannot be cancelled by a dispose.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  RowTransformBox boxOf(WidgetTester tester) =>
      tester.widget<RowTransformBox>(find.byType(RowTransformBox));

  /// A mouse drag through [points] of the box's viewport.
  Future<void> dragThrough(WidgetTester tester, List<Offset> points) async {
    final origin = tester.getTopLeft(find.byType(RowTransformBox));
    final gesture = await tester.startGesture(
      origin + points.first,
      kind: PointerDeviceKind.mouse,
    );
    for (final point in points.skip(1)) {
      await gesture.moveTo(origin + point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  void expectCorners(
    List<CanvasPoint> actual,
    List<CanvasPoint> expected,
    String why,
  ) {
    expect(actual, hasLength(expected.length), reason: why);
    for (var i = 0; i < expected.length; i += 1) {
      expect(actual[i].x, closeTo(expected[i].x, 1e-6), reason: '$why ($i)');
      expect(actual[i].y, closeTo(expected[i].y, 1e-6), reason: '$why ($i)');
    }
  }

  /// Where [tag]'s own point — its name box's centre — lies on the canvas.
  CanvasPoint onTheCanvas(ResolvedSeNameTag tag) => tag.placement.apply(
    CanvasPoint(x: tag.content.position!.dx, y: tag.content.position!.dy),
  );

  testWidgets('🎯outside the tag, on stage, turns the row — and the box '
      'turns with the tag, framing it where the painter lays it', (
    tester,
  ) async {
    final s = speaking();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final box = boxOf(tester);
    expect(box.scale, isNotNull, reason: 'a corner scales, as a layer\'s');
    expect(box.cross, isNotNull, reason: 'the cross places the anchor');

    // A quarter of a circle clockwise about the pivot, well outside the
    // tag's box.
    final pivot = box.viewport.canvasToViewportOffset(box.pose.center);
    const radius = 160.0;
    await dragThrough(tester, [
      for (var step = 0; step <= 8; step += 1)
        pivot +
            Offset(
              radius * math.sin(step * math.pi / 16),
              -radius * math.cos(step * math.pi / 16),
            ),
    ]);
    await tester.pumpAndSettle();

    final rotation = s.activeTrack.seLayers.first.transformTrack.rotation
        .keyAt(0)!
        .value;
    expect(rotation, closeTo(90, 1), reason: 'a key at the playhead');

    final tag = tagOf(s);
    final framed = placedCorners(
      tag.placement,
      seNameTagBoxBounds(tag, canvasSize: s.requireActiveCut.canvasSize),
    );
    expectCorners(boxOf(tester).corners, framed, 'the turned tag');
    expect(
      framed[1].x - framed[0].x,
      closeTo(0, 2),
      reason: '⛔premise: a quarter turn stands the top edge upright',
    );
    await drain(tester);
  });

  testWidgets('the cross keys the anchor and the tag hangs off it, as a '
      'layer\'s picture does', (tester) async {
    final s = speaking();
    addTearDown(s.dispose);
    await pumpArea(tester, s);
    final before = onTheCanvas(tagOf(s));
    final box = boxOf(tester);
    final cross = box.viewport.canvasToViewportOffset(box.cross!.at);
    final start = box.viewport.viewportOffsetToCanvas(cross);
    final end = box.viewport.viewportOffsetToCanvas(
      cross + const Offset(40, 0),
    );
    final travel = end.x - start.x;

    await dragThrough(tester, [
      for (var step = 0; step <= 4; step += 1)
        cross + Offset(10.0 * step, 0),
    ]);
    await tester.pumpAndSettle();

    final se = s.activeTrack.seLayers.first;
    expect(se.transformTrack.anchorPoint.keyAt(0), isNotNull);
    expect(se.transformTrack.position.keyAt(0), isNull, reason: 'alone');
    final after = onTheCanvas(tagOf(s));
    expect(
      after.x,
      closeTo(before.x - travel, 1),
      reason: 'the anchor went right, so the tag hangs further left of it',
    );
    expect(after.y, closeTo(before.y, 1));
    await drain(tester);
  });

  testWidgets('a tag with its row\'s effects rasters at the scale the '
      'canvas shows it, as a folder does', (tester) async {
    final s = speaking();
    addTearDown(s.dispose);
    final se = s.activeTrack.seLayers.first;
    s.effectsAndFx.updateLayerEffects(se.id, [
      LayerEffect(
        id: const EffectId('blur'),
        kind: EffectKind.blur,
        parameters: {'blurX': EffectParameter(value: 2)},
      ),
    ]);
    await pumpArea(tester, s);
    // The same window in logical pixels, at twice the device pixels.
    tester.view.physicalSize = const Size(3200, 2000);
    tester.view.devicePixelRatio = 2;
    debugLastSubtreeRaster = null;
    await tester.pump();

    expect(debugLastSubtreeRaster, isNotNull, reason: 'one picture');
    expect(
      debugLastSubtreeRaster!.rasterScale,
      boxOf(tester).viewport.zoom * 2,
      reason: 'device pixels per canvas pixel',
    );
    await drain(tester);
  });

  group('the painter lays a tag as its row does', () {
    const size = CanvasSize(width: 600, height: 200);

    Future<int> alphaAt(ResolvedSeNameTag tag, int x, int y) async {
      final recorder = ui.PictureRecorder();
      paintSeNameTags(
        ui.Canvas(recorder),
        tags: [tag],
        canvasSize: size,
        rasterScale: 1,
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(size.width, size.height);
      picture.dispose();
      final rgba = (await image.toByteData())!;
      image.dispose();
      return rgba.getUint8((y * size.width + x) * 4 + 3);
    }

    /// The pixel at [at] with [tag] painted over [under].
    Future<ui.Color> colourAt(
      ResolvedSeNameTag tag,
      Offset at, {
      ui.Color under = const ui.Color(0x00000000),
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(under, ui.BlendMode.src);
      paintSeNameTags(
        canvas,
        tags: [tag],
        canvasSize: size,
        rasterScale: 1,
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(size.width, size.height);
      picture.dispose();
      final rgba = (await image.toByteData())!;
      image.dispose();
      final i = (at.dy.round() * size.width + at.dx.round()) * 4;
      return ui.Color.fromARGB(
        rgba.getUint8(i + 3),
        rgba.getUint8(i),
        rgba.getUint8(i + 1),
        rgba.getUint8(i + 2),
      );
    }

    ResolvedSeNameTag tag({
      LayerPlacement inShot = const LayerPlacement.identity(),
      double opacity = 1,
      LayerBlendMode blendMode = LayerBlendMode.normal,
      List<ResolvedLayerEffect> effects = const [],
    }) => ResolvedSeNameTag(
      layerId: 's1',
      widthBudget: 400,
      shot: const LayerPlacement.identity(),
      inShot: inShot,
      opacity: opacity,
      blendMode: blendMode,
      effects: effects,
      content: const TextCelContent(
        text: 'A',
        style: SeNameTag.defaultStyle,
        position: Offset(100, 100),
      ),
    );

    test('through the row\'s placement in its shot', () async {
      final moved = tag(inShot: const LayerPlacement(1, 0, 0, 1, 300, 0));
      expect(await alphaAt(moved, 400, 100), 255, reason: '300 along');
      expect(await alphaAt(moved, 100, 100), 0);
    });

    test('at the row\'s opacity — as one picture', () async {
      expect(await alphaAt(tag(opacity: 0.5), 100, 100), closeTo(128, 2));
      expect(await alphaAt(tag(opacity: 0), 100, 100), 0);
    });

    // F-387 (유저 2026-10-19): 「다른것도 확인해서 통일」 — the rest of the
    // row's fx reach the tag as a layer's reach its picture.
    Rect tagBox() => seNameTagBoxBounds(tag(), canvasSize: size);
    // In the box's pad, where no letter is: the box's own red.
    Offset inTheBox() => tagBox().topLeft + const Offset(2, 2);

    test('through the row\'s blur — past the box, as a layer\'s spreads',
        () async {
      final beside = tagBox().centerRight + const Offset(4, 0);
      expect((await colourAt(tag(), beside)).a, 0);
      final blurred = tag(
        effects: [
          ResolvedLayerEffect(kind: EffectKind.blur, values: const [12, 12]),
        ],
      );
      expect((await colourAt(blurred, beside)).a, greaterThan(0));
    });

    test('through the row\'s colour', () async {
      final red = await colourAt(tag(), inTheBox());
      expect(red.r, greaterThan(red.g + 0.2), reason: 'the box is red');
      final grey = await colourAt(
        tag(
          effects: [
            ResolvedLayerEffect(
              kind: EffectKind.hueSaturation,
              values: const [0, -100, 0],
            ),
          ],
        ),
        inTheBox(),
      );
      expect(grey.r, closeTo(grey.g, 0.02), reason: 'desaturated');
      expect(grey.g, closeTo(grey.b, 0.02));
    });

    test('in the row\'s blend, over what is under it', () async {
      const blue = ui.Color(0xFF0000FF);
      final over = await colourAt(tag(), inTheBox(), under: blue);
      expect(over.r, greaterThan(0.7), reason: 'normal: the box covers');
      final multiplied = await colourAt(
        tag(blendMode: LayerBlendMode.multiply),
        inTheBox(),
        under: blue,
      );
      expect(multiplied.r, lessThan(0.05), reason: 'red × no red');
      expect(multiplied.b, closeTo(0x5C / 255, 0.03), reason: 'its blue');
    });

    test('through the row\'s colour key — a picture of its own', () async {
      await ColourKeyShader.load();
      final keyed = tag(
        effects: [
          ResolvedLayerEffect(
            kind: EffectKind.deleteColor,
            values: const [0xC9, 0x5C, 0x5C, 8, 100],
          ),
        ],
      );
      expect((await colourAt(tag(), inTheBox())).a, 1);
      expect(
        (await colourAt(keyed, inTheBox())).a,
        0,
        reason: 'the box was its key colour',
      );
    });
  });
}

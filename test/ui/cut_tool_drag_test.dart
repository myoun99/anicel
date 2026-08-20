import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/cut_piece_stamp.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';

import '../helpers/brush_canvas_fixture.dart';

/// The cut tool driven through real pointer input.
///
/// The pure lift is pinned next door in cut_piece_lift_test; what this file
/// is for is the WIRING — that a drag with a cut variant armed reaches the
/// slot at all, and that it leaves the selection alone on the way.
void main() {
  const layerKey = ValueKey<String>('canvas-selection-layer');

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 8,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  Future<
    ({
      BrushFrameEditingCoordinator coordinator,
      CanvasSelectionCommands commands,
      CutPieceSlot slot,
      Future<void> Function(
        CanvasTool tool, {
        CanvasShapeKind? shape,
        BrushBlendMode? stampBlend,
        double? stampOpacity,
      })
      setTool,
    })
  >
  pumpPanel(
    WidgetTester tester, {
    required CanvasTool tool,
    CanvasShapeKind shapeKind = CanvasShapeKind.rect,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final history = HistoryManager();
    final commands = CanvasSelectionCommands();
    final slot = CutPieceSlot();

    Future<void> pumpWith(
      CanvasTool next, {
      CanvasShapeKind? shape,
      BrushBlendMode? stampBlend,
      double? stampOpacity,
    }) async {
      // Both verbs get the same outline: a test picks one shape and the
      // panel reads whichever field the active verb owns.
      final outline = shape ?? shapeKind;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              historyManager: history,
              brushToolState: BrushToolState.defaults.copyWith(
                tool: next,
                selectShape: outline,
                cutShape: outline,
                cutStampBlendMode: stampBlend,
                cutStampOpacity: stampOpacity,
              ),
              selectionCommands: commands,
              cutPieceSlot: slot,
              // ⚠️An EXPLICIT render 1.0. These cases map screen offsets to
              // canvas coordinates one for one, and an uncontrolled panel
              // now opens at the IDENTITY — one artwork pixel per DEVICE
              // pixel — which is a render zoom of 1/3 on the 3x test view.
              viewport: CanvasViewport(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // Ink to cut: a wide bar across the middle of the canvas.
    coordinator.commitSourceStroke(
      sourceDabs: [for (var x = 10; x <= 90; x += 2) dab(x.toDouble(), 40)],
    );
    await pumpWith(tool);
    return (
      coordinator: coordinator,
      commands: commands,
      slot: slot,
      setTool: pumpWith,
    );
  }

  Future<void> dragOnLayer(
    WidgetTester tester,
    Offset from,
    Offset to,
  ) async {
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(
      origin + from,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveTo(origin + (from + to) / 2);
    await tester.pump();
    await gesture.moveTo(origin + to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a cut variant still mounts the selection layer', (tester) async {
    // It rides the same drag surface; that is the whole reason the marquee
    // geometry is not duplicated anywhere.
    await pumpPanel(tester, tool: CanvasTool.cut);
    expect(find.byKey(layerKey), findsOneWidget);
  });

  testWidgets('the stamp variant does NOT mount it', (tester) async {
    await pumpPanel(tester, tool: CanvasTool.cutStamp);
    expect(find.byKey(layerKey), findsNothing);
  });

  testWidgets('a rectangle cut fills the slot', (tester) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    expect(env.slot.isEmpty, isTrue);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    expect(env.slot.isNotEmpty, isTrue);
    expect(env.slot.piece!.image.width, greaterThan(0));
  });

  testWidgets('a lasso cut fills the slot too', (tester) async {
    final env = await pumpPanel(
      tester,
      tool: CanvasTool.cut,
      shapeKind: CanvasShapeKind.lasso,
    );
    // The path has to BEND: a lasso dragged in a straight line is a
    // zero-area polygon, and enclosing nothing is correctly nothing to cut.
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(
      origin + const Offset(10, 10),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    for (final point in const [
      Offset(90, 10),
      Offset(90, 70),
      Offset(10, 70),
    ]) {
      await gesture.moveTo(origin + point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(env.slot.isNotEmpty, isTrue);
  });

  testWidgets('a lasso dragged in a straight line cuts nothing', (
    tester,
  ) async {
    // It encloses no area, so there is nothing under it — and the slot
    // must not be blanked on the way to finding that out.
    final env = await pumpPanel(
      tester,
      tool: CanvasTool.cut,
      shapeKind: CanvasShapeKind.lasso,
    );
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    expect(env.slot.isEmpty, isTrue);
  });

  testWidgets('cutting leaves the selection completely alone', (tester) async {
    // 유저 확정: "잘라내기는 잘라내기만이야. 그러니 선택으로 남지 않아."
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    expect(env.commands.region, isNull);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    expect(env.slot.isNotEmpty, isTrue, reason: 'the cut happened');
    expect(env.commands.region, isNull, reason: 'and made no selection');
  });

  testWidgets('an EXISTING selection survives a cut untouched', (tester) async {
    // A selection made with the select tool still clips painting, so a cut
    // must not quietly redraw or drop it.
    final env = await pumpPanel(tester, tool: CanvasTool.select);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(60, 60));
    final selected = env.commands.region;
    expect(selected, isNotNull);

    await env.setTool(CanvasTool.cut);
    await dragOnLayer(tester, const Offset(20, 20), const Offset(90, 70));
    expect(env.slot.isNotEmpty, isTrue);
    expect(env.commands.region, same(selected));
  });

  testWidgets('cutting again replaces the held piece', (tester) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    final first = env.slot.piece;
    await dragOnLayer(tester, const Offset(20, 20), const Offset(80, 60));
    expect(env.slot.piece, isNot(same(first)));
  });

  testWidgets('the piece survives switching tools and back', (tester) async {
    // The slot outlives the tool — the whole point is cutting here and
    // stamping somewhere else later.
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    final piece = env.slot.piece;
    expect(piece, isNotNull);

    await env.setTool(CanvasTool.brush);
    await env.setTool(CanvasTool.cutStamp);
    expect(env.slot.piece, same(piece));
  });

  testWidgets('clicking with the stamp tile drops the piece, at once', (
    tester,
  ) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    // Cut the painted bar.
    await dragOnLayer(tester, const Offset(10, 30), const Offset(90, 50));
    expect(env.slot.isNotEmpty, isTrue);

    await env.setTool(CanvasTool.cutStamp);
    final before = surfacePixelRgba(
      env.coordinator.currentSurfaceOf(env.coordinator.activeFrameKey),
      30,
      140,
    );
    expect(before ?? 0, 0, reason: 'blank before the stamp');

    // A tap far below the bar, on empty cel.
    final canvas = find.byType(BrushCanvasPanel);
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(30, 140));
    await tester.pump();

    final after = surfacePixelRgba(
      env.coordinator.currentSurfaceOf(env.coordinator.activeFrameKey),
      30,
      140,
    );
    // Committed immediately — no confirm step, nothing floating.
    expect(after ?? 0, isNot(0));
  });

  // TS8: 유저 — "스탬프모드에서는 블렌드모드 살리기로하지않았나? 지금
  // 사라지니까 존재하도록. 위합성 아래합성버튼은 없애고 어차피 블렌드모드에
  // 노말/배경 모드 있으니까 그거활용".
  testWidgets('the stamp composites through the tool blend — erase CLEARS', (
    tester,
  ) async {
    // 🚨The trap this pins: erase is a flag on the DAB, not a blend mode.
    // Passing the mode alone sends the stamp down the ordinary path with
    // the flag false, and the piece gets PAINTED where it should have cut a
    // hole. That has now been the same mistake in three places (bucket,
    // shape fill, stamp), which is why all three stamp routes go through
    // one commit method.
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 30), const Offset(90, 50));
    expect(env.slot.isNotEmpty, isTrue);

    await env.setTool(CanvasTool.cutStamp, stampBlend: BrushBlendMode.erase);
    // On the bar, so there is something to remove.
    final canvas = find.byType(BrushCanvasPanel);
    expect(
      surfacePixelRgba(
            env.coordinator.currentSurfaceOf(env.coordinator.activeFrameKey),
            50,
            40,
          ) ??
          0,
      isNot(0),
      reason: 'ink to erase',
    );

    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(50, 40));
    await tester.pump();

    expect(
      surfacePixelRgba(
            env.coordinator.currentSurfaceOf(env.coordinator.activeFrameKey),
            50,
            40,
          ) ??
          0,
      0,
      reason: 'the piece cut a hole instead of painting itself',
    );
  });

  testWidgets('Behind is what the "paste below" button used to be', (
    tester,
  ) async {
    // The two buttons were spelling `color` and `behind` by hand. With the
    // blend list open to the stamp they are two of its entries, and this is
    // the entry that has to still mean what the button meant.
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 30), const Offset(90, 50));

    // Paint one blue pixel where the piece will land, then paste behind: the
    // pixel that is already there wins.
    env.coordinator.commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 50, y: 40),
          color: 0xFF0000FF,
          size: 2,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.square,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
    await tester.pump();
    await env.setTool(CanvasTool.cutStamp, stampBlend: BrushBlendMode.behind);
    env.slot.pasteAtOrigin();
    await tester.pump();

    final landed = surfacePixelRgba(
      env.coordinator.currentSurfaceOf(env.coordinator.activeFrameKey),
      50,
      40,
    );
    expect(
      landed,
      // RGBA order, as the surface stores it: still the blue pixel.
      0x0000FFFF,
      reason: 'behind leaves what is already there in front',
    );
  });

  testWidgets('clicking with an EMPTY slot does nothing', (tester) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cutStamp);
    expect(env.slot.isEmpty, isTrue);
    final canvas = find.byType(BrushCanvasPanel);
    await tester.tapAt(tester.getTopLeft(canvas) + const Offset(30, 140));
    await tester.pump();
    expect(
      surfacePixelRgba(
            env.coordinator.currentSurfaceOf(env.coordinator.activeFrameKey),
            30,
            140,
          ) ??
          0,
      0,
    );
  });

  testWidgets('dragging with the stamp tile draws a trail of stamps', (
    tester,
  ) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 30), const Offset(90, 50));
    expect(env.slot.isNotEmpty, isTrue);

    await env.setTool(CanvasTool.cutStamp);
    final origin = tester.getTopLeft(find.byType(BrushCanvasPanel));
    final gesture = await tester.startGesture(
      origin + const Offset(20, 150),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    // Far enough to demand several stamps.
    for (var x = 40; x <= 200; x += 20) {
      await gesture.moveTo(origin + Offset(x.toDouble(), 150));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    final surface = env.coordinator.currentSurfaceOf(
      env.coordinator.activeFrameKey,
    );
    // The far end of the drag is painted, which the press alone could not
    // have done.
    expect(surfacePixelRgba(surface, 190, 150) ?? 0, isNot(0));
  });

  testWidgets('a stamp drag stops when the pointer lifts', (tester) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 30), const Offset(90, 50));
    await env.setTool(CanvasTool.cutStamp);

    final origin = tester.getTopLeft(find.byType(BrushCanvasPanel));
    final gesture = await tester.startGesture(
      origin + const Offset(20, 150),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // A move after the lift must not keep laying stamps: the drag's
    // anchor is cleared on release.
    await gesture.moveTo(origin + const Offset(200, 150));
    await tester.pump();
    final surface = env.coordinator.currentSurfaceOf(
      env.coordinator.activeFrameKey,
    );
    expect(surfacePixelRgba(surface, 195, 150) ?? 0, 0);
  });

  testWidgets('paste at origin puts the piece back where it was cut', (
    tester,
  ) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 30), const Offset(90, 50));
    expect(env.slot.isNotEmpty, isTrue);

    // Erase the bar the piece came from, then paste it back.
    final origin = env.slot.piece!;
    env.coordinator.commitSourceStroke(
      sourceDabs: [for (var x = 10; x <= 90; x += 2) dab(x.toDouble(), 40)],
      blendMode: BrushBlendMode.erase,
    );
    await tester.pump();

    env.slot.pasteAtOrigin();
    await tester.pump();

    final surface = env.coordinator.currentSurfaceOf(
      env.coordinator.activeFrameKey,
    );
    // Somewhere inside the piece's own footprint is painted again.
    expect(
      surfacePixelRgba(
            surface,
            origin.originLeft + origin.image.width ~/ 2,
            origin.originTop + origin.image.height ~/ 2,
          ) ??
          0,
      isNot(0),
    );
  });

  testWidgets('paste at origin presses at the STAMP tool\'s opacity', (
    tester,
  ) async {
    // 유저 2026-08-15: "제자리 붙여넣기도 불투명도 반영하도록."
    //
    // TP3 gave the stamp an opacity and left this route at a hardcoded
    // 100%, on the reading that "original position" and "original picture"
    // are one idea. They are — but that idea is the POSE (size and flip),
    // which decides WHICH picture lands. Opacity decides how hard it
    // presses, and that belongs to the tool on every route it puts pixels
    // down through.
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 30), const Offset(90, 50));
    final piece = env.slot.piece!;
    final x = piece.originLeft + piece.image.width ~/ 2;
    final y = piece.originTop + piece.image.height ~/ 2;

    int alphaAt() =>
        (surfacePixelRgba(
              env.coordinator.currentSurfaceOf(env.coordinator.activeFrameKey),
              x,
              y,
            ) ??
            0) &
        0xFF;

    // The bar the piece came from, wiped, so the paste lands on nothing and
    // the alpha that comes back is the stamp's own.
    //
    // 🚨`erase` rides the DAB, not the blend mode — passing the mode alone
    // PAINTS the dabs instead of clearing with them, which is the trap the
    // three stamp routes share one funnel to avoid. Here it would have made
    // the reading below meaningless.
    Future<void> wipe() async {
      env.coordinator.commitSourceStroke(
        sourceDabs: [
          for (var px = 10; px <= 90; px += 2)
            dab(px.toDouble(), 40).copyWith(erase: true),
        ],
        blendMode: BrushBlendMode.erase,
      );
      await tester.pump();
    }

    await wipe();
    expect(alphaAt(), 0, reason: 'nothing underneath to confuse the reading');

    await env.setTool(CanvasTool.cutStamp, stampOpacity: 0.5);
    env.slot.pasteAtOrigin();
    await tester.pump();
    final half = alphaAt();
    expect(half, greaterThan(0), reason: 'it still lands');

    await wipe();
    await env.setTool(CanvasTool.cutStamp, stampOpacity: 1);
    env.slot.pasteAtOrigin();
    await tester.pump();
    final full = alphaAt();

    expect(full, greaterThan(half), reason: 'the setting is read, not ignored');
    expect(
      half,
      closeTo(full / 2, 2),
      reason: 'and it is the number itself, not a fade someone invented',
    );
  });

  testWidgets('the cursor preview wears the stamp opacity', (tester) async {
    // ⛔Not the ghosting the user had removed ("그냥 심플하게 … 프리뷰만
    // 띄워") — that one was a made-up constant that lied about a stamp
    // landing at full force. This is the number the click will press with,
    // so showing it is the same rule that removed the fade.
    final env = await pumpPanel(tester, tool: CanvasTool.cutStamp);
    await env.setTool(CanvasTool.cutStamp, stampOpacity: 0.4);
    env.slot.hold(
      CutPiece(
        image: BrushStampImage(
          id: 'p',
          width: 20,
          height: 12,
          rgba: Uint8List(20 * 12 * 4)..fillRange(0, 20 * 12 * 4, 200),
        ),
        originLeft: 4,
        originTop: 6,
      ),
    );
    await tester.pump();

    final origin = tester.getTopLeft(find.byType(BrushCanvasPanel));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + const Offset(120, 160));
    await tester.pump();
    await gesture.moveTo(origin + const Offset(120, 160));
    await tester.pump();

    expect(
      tester
          .widget<CutPieceCursorOverlay>(find.byType(CutPieceCursorOverlay))
          .opacity,
      0.4,
    );
  });

  testWidgets('what was held lands byte-for-byte, in the same place', (
    tester,
  ) async {
    // 유저: "들고 있던 거랑 찍을 때랑 위치나 내용이 바이트 단위로 동일하게."
    //
    // The object-level contract is pinned next door (an unposed piece
    // hands back the very same BrushStampImage). This is the end of the
    // chain the user actually sees: cut, wipe the source, put it back, and
    // the cel is what it was — every channel of every pixel.
    final env = await pumpPanel(tester, tool: CanvasTool.cut);

    List<int> footprint(int left, int top, int width, int height) {
      final surface = env.coordinator.currentSurfaceOf(
        env.coordinator.activeFrameKey,
      );
      return [
        for (var y = top; y < top + height; y += 1)
          for (var x = left; x < left + width; x += 1)
            surfacePixelRgba(surface, x, y) ?? 0,
      ];
    }

    await dragOnLayer(tester, const Offset(10, 30), const Offset(90, 50));
    final piece = env.slot.piece!;
    final width = piece.image.width;
    final height = piece.image.height;

    // The oracle is the HELD BYTES, not the source surface. Those two are
    // not the same thing: the piece's box can be a pixel wider than the
    // mask that filled it, so a boundary pixel can carry ink on the cel and
    // nothing in the piece. What the user asked to pin is that what was
    // held is what lands.
    final held = [
      for (var index = 0; index < width * height; index += 1)
        (piece.image.rgba[index * 4] << 24) |
            (piece.image.rgba[index * 4 + 1] << 16) |
            (piece.image.rgba[index * 4 + 2] << 8) |
            piece.image.rgba[index * 4 + 3],
    ];
    expect(held.any((pixel) => pixel != 0), isTrue, reason: 'it holds ink');

    // Stamped onto blank cel, off-canvas but well inside the pasteboard
    // wall so nothing is clipped and nothing already drawn is underneath.
    const landLeft = -120;
    const landTop = -120;
    env.coordinator.commitSourceStroke(
      sourceDabs: [
        buildCutStampDab(
          piece: piece,
          center: CanvasPoint(
            x: landLeft + width / 2,
            y: landTop + height / 2,
          ),
        ),
      ],
    );
    await tester.pump();

    expect(footprint(landLeft, landTop, width, height), held);
  });

  testWidgets('the cursor preview sits where the stamp would land', (
    tester,
  ) async {
    // A preview that pointed somewhere other than the drop point would be
    // worse than none — it would teach the wrong aim.
    // The slot is filled directly rather than by cutting: this test is
    // about the overlay, and a prior mouse gesture would collide with the
    // hover pointer it needs.
    final env = await pumpPanel(tester, tool: CanvasTool.cutStamp);
    env.slot.hold(
      CutPiece(
        image: BrushStampImage(
          id: 'p',
          width: 20,
          height: 12,
          rgba: Uint8List(20 * 12 * 4)..fillRange(0, 20 * 12 * 4, 200),
        ),
        originLeft: 4,
        originTop: 6,
      ),
    );
    await tester.pump();

    final panel = find.byType(BrushCanvasPanel);
    final origin = tester.getTopLeft(panel);
    const hover = Offset(120, 160);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + hover);
    await tester.pump();
    await gesture.moveTo(origin + hover);
    await tester.pump();

    final overlay = find.byKey(
      const ValueKey<String>('cut-piece-cursor-overlay'),
    );
    expect(overlay, findsOneWidget);
    // Centre-anchored on the pointer, which is where a click drops it.
    final box = tester.getRect(overlay);
    expect(box.center.dx - origin.dx, closeTo(hover.dx, 1));
    expect(box.center.dy - origin.dy, closeTo(hover.dy, 1));
  });

  testWidgets('no piece means no cursor preview', (tester) async {
    final env = await pumpPanel(tester, tool: CanvasTool.cutStamp);
    expect(env.slot.isEmpty, isTrue);
    final origin = tester.getTopLeft(find.byType(BrushCanvasPanel));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: origin + const Offset(120, 160));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('cut-piece-cursor-overlay')),
      findsNothing,
    );
  });

  testWidgets('the paste verb goes dead when the canvas unmounts', (
    tester,
  ) async {
    // The button must stop working with the canvas rather than throw at a
    // dead State.
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 30), const Offset(90, 50));
    expect(env.slot.canPasteAtOrigin, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(env.slot.canPasteAtOrigin, isFalse);
    // And the piece is still held — losing the canvas is not losing work.
    expect(env.slot.isNotEmpty, isTrue);
  });

  testWidgets('a cut over blank cel leaves the held piece alone', (
    tester,
  ) async {
    // The slot is a long-term holder; one stray scrape must not empty it.
    final env = await pumpPanel(tester, tool: CanvasTool.cut);
    await dragOnLayer(tester, const Offset(10, 10), const Offset(90, 70));
    final piece = env.slot.piece;
    expect(piece, isNotNull);

    // Far below the painted bar.
    await dragOnLayer(tester, const Offset(10, 200), const Offset(60, 250));
    expect(env.slot.piece, same(piece));
  });
}

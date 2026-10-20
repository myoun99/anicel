import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/pill_row_clipboard.dart';

/// 🗣️F-275 (유저 2026-10-08, after the data fix): 「작동은 하는데 화면이
/// 이상함. 같은상황에서 링크독립하면 싱크어태치 그림 사라지길래 해결안된건가
/// 했는데 다른 레이어 이동하니 화면에 정상표시. 즉 링크독립이 화면을
/// 바꾸는듯? 왜 프레임을 편집하는 동작이 화면을 바꾸는 로직이 있는지
/// 근본적으로 왜 존재하는지 전혀 모르겠는데」.
///
/// The PIXELS of the editing canvas around 링크 독립: a base row standing on a
/// linked cel, a synced attach row over it whose mirror of that cel is drawn
/// blue. The unlink gives the base block a cel of its own and the attach row
/// a mirror of it carrying the same picture — what the screen shows does not
/// change, so it must not change on any frame.
void main() {
  const tile = 256;

  /// A tile of [rgba] at the cut's top-left corner.
  BitmapSurface ink(CanvasSize canvasSize, List<int> rgba) {
    final pixels = Uint8List(tile * tile * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels.setRange(i, i + 4, rgba);
    }
    return BitmapSurface(canvasSize: canvasSize, tileSize: tile).putTiles([
      (
        coord: TileCoord(x: 0, y: 0),
        tile: BitmapTile(size: tile, pixels: pixels),
      ),
    ]);
  }

  Layer rowOf(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  const red = [0xFF, 0, 0, 0xFF];
  const blue = [0, 0, 0xFF, 0xFF];
  const green = [0, 0xFF, 0, 0xFF];

  /// [row]'s cel [frame] drawn [rgba], as a stroke leaves it: its picture in
  /// the store and its revision moved.
  void draw(
    EditorSessionManager s,
    LayerId row,
    FrameId frame,
    List<int> rgba,
  ) {
    final key = s.brushFrameKeyForCut(s.requireActiveCut, row, frame);
    final store = s.renderCaches.brushFrameStore;
    store.storeBakedSurface(key, ink(s.requireActiveCut.canvasSize, rgba));
    store.markCelEdited(key);
  }

  /// The base row stood on at frame 5, a red cel linked from frame 0, and a
  /// synced attach row over it whose mirror of that cel is blue.
  EditorSessionManager linkedBaseUnderABlueAttach() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final base = s.activeLayer!.id;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    final a = rowOf(s, base).frames.single.id;
    draw(s, base, a, red);
    s.copyFrameAtCurrentFrame();
    s.selectFrameIndex(5);
    s.pasteLinkedFrameAtCurrentFrame();
    expect(rowOf(s, base).timeline[5]?.frameId, a, reason: '⛔전제: a link');

    s.folders.addAttachedLayer(AttachedPlacement.above);
    final attach = s.activeLayer!.id;
    draw(s, attach, rowOf(s, attach).baseFrameLinks[a]!, blue);
    s.selectLayer(base);
    s.selectFrameIndex(5);
    return s;
  }

  /// The base row and its blue attach at frame 0, link-duplicated as rows —
  /// the duplicates hidden, so the screen shows the originals alone.
  EditorSessionManager linkedRowsUnderABlueAttach() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final base = s.activeLayer!.id;
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    final a = rowOf(s, base).frames.single.id;
    draw(s, base, a, red);
    s.folders.addAttachedLayer(AttachedPlacement.above);
    final attach = s.activeLayer!.id;
    draw(s, attach, rowOf(s, attach).baseFrameLinks[a]!, blue);
    s.selectLayer(base);
    final originals = {for (final layer in s.requireActiveCut.layers) layer.id};
    linkDuplicateActiveRow(s);
    expect(s.layerVerbs.isLayerLinked(attach), isTrue, reason: '⛔전제');
    for (final layer in s.requireActiveCut.layers) {
      if (!originals.contains(layer.id)) {
        s.layerSwitches.toggleLayerVisibility(layer.id);
      }
    }
    s.selectLayer(base);
    s.selectFrameIndex(0);
    return s;
  }

  Future<void> pumpArea(WidgetTester tester, EditorSessionManager s) async {
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(false);
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
    await tester.pumpAndSettle();
  }

  /// How many pixels of the canvas area are [channel]'s colour alone (0 red,
  /// 1 green, 2 blue).
  Future<int> pixelsOf(WidgetTester tester, int channel) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .descendant(
            of: find.byType(EditorCanvasArea),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final image = (await tester.runAsync(boundary.toImage))!;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    image.dispose();
    var count = 0;
    for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
      if (bytes.getUint8(offset + channel) > 240 &&
          bytes.getUint8(offset + (channel + 1) % 3) < 20 &&
          bytes.getUint8(offset + (channel + 2) % 3) < 20) {
        count += 1;
      }
    }
    return count;
  }

  /// How many pixels of the canvas area are the attach row's blue.
  Future<int> bluePixels(WidgetTester tester) => pixelsOf(tester, 2);

  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  /// The attach's blue before [unlink], on the first frame after it, and
  /// once everything lands.
  Future<(int, int, int)> blueAround(
    WidgetTester tester,
    EditorSessionManager s,
    void Function() unlink,
  ) async {
    await pumpArea(tester, s);
    await drainWarming(tester);
    final shown = await bluePixels(tester);
    expect(shown, greaterThan(100), reason: '⛔전제: the attach is drawn');
    unlink();
    await tester.pump();
    final firstFrame = await bluePixels(tester);
    await drainWarming(tester);
    return (shown, firstFrame, await bluePixels(tester));
  }

  testWidgets('🚨링크 독립 leaves the attach row\'s picture on the screen — on '
      'the first frame after it, and after everything lands', (tester) async {
    final s = linkedBaseUnderABlueAttach();
    final (shown, firstFrame, landed) = await blueAround(
      tester,
      s,
      TimelineToolbarPanelContext(s).unlink,
    );
    expect(
      (firstFrame, landed),
      (shown, shown),
      reason: 'the picture is the same, so the screen is the same',
    );
  });

  testWidgets('a cel drawn over just before 링크 독립 shows what it holds now '
      '— the screen\'s picture of what it held is not its copy\'s', (
    tester,
  ) async {
    final s = linkedBaseUnderABlueAttach();
    final base = s.activeLayer!.id;
    final a = rowOf(s, base).timeline[5]!.frameId;
    final attach = s.requireActiveCut.layers
        .firstWhere((layer) => layer.baseFrameLinks.containsKey(a))
        .id;
    await pumpArea(tester, s);
    await drainWarming(tester);
    expect(await bluePixels(tester), greaterThan(100), reason: '⛔전제');

    // Drawn and unlinked before the screen has drawn the new pixels once.
    draw(s, attach, rowOf(s, attach).baseFrameLinks[a]!, green);
    TimelineToolbarPanelContext(s).unlink();
    await tester.pump();
    expect(
      await bluePixels(tester),
      0,
      reason: 'not for a frame: the blue the screen held is not the copy\'s',
    );
    await drainWarming(tester);

    expect(
      (await bluePixels(tester), await pixelsOf(tester, 1) > 100),
      (0, true),
    );
  });

  testWidgets('a ROW\'s 링크 독립 leaves its attach\'s picture on the screen '
      'too — the same picture under the row\'s own name now', (tester) async {
    final s = linkedRowsUnderABlueAttach();
    final base = s.activeLayer!.id;
    final (shown, firstFrame, landed) = await blueAround(
      tester,
      s,
      () => s.layerVerbs.unlinkLayers([base]),
    );
    expect(s.layerVerbs.isLayerLinked(base), isFalse, reason: '⛔전제');
    expect((firstFrame, landed), (shown, shown));
  });
}

@Tags(['gpu'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/viewport_point.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/a_canvas_standing_on_a_frame.dart' show noFlutterGpu;
import '../helpers/panel_finders.dart';
import '../helpers/settle_async.dart';

/// F-473 (유저 2026-10-26): 「스탬프로 들고있던게 캔버스에 남아있음. 커서로
/// 들고있던위치에서. 확인하니 들고있다가 다른프레임 이동하면 남아있음. 거기로
/// 스탬프 프리뷰를 위치시키거나, 그림을 그리면 점차 타일따라서 사라짐」.
void main() {
  const cels = ['c0', 'c1'];

  Project fixture() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.firstWhere(layerAcceptsBrushInput);
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                for (final layer in cut.layers)
                  if (layer.id == row.id)
                    layer.copyWith(
                      frames: [
                        for (final id in cels)
                          Frame(id: FrameId(id), duration: 1, strokes: const []),
                      ],
                      timeline: {
                        for (final (at, id) in cels.indexed)
                          at: TimelineExposure.drawing(FrameId(id), length: 1),
                      },
                    )
                  else
                    layer,
              ],
            ),
          ],
        ),
      ],
    );
  }

  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  Layer row(EditorSessionManager session) =>
      session.layers.firstWhere((l) => l.frames.length == cels.length);

  BrushFrameKey keyOf(EditorSessionManager session, String cel) =>
      session.brushFrameKeyForCut(
        session.requireActiveCut,
        row(session).id,
        FrameId(cel),
      );

  Future<void> settle(WidgetTester tester) =>
      lendBothClocks(tester, rounds: 12);

  /// Fills [cel]'s tile [coord] with one colour, through the coordinator.
  void paint(
    EditorSessionManager session,
    String cel,
    TileCoord coord,
    List<int> rgba,
  ) {
    final key = keyOf(session, cel);
    final coordinator = session.pixelEditing.coordinator!;
    final base = coordinator.currentSurfaceOf(key);
    final size = base.tileSize;
    coordinator.restoreSurfaceSnapshot(
      key,
      base.putTiles([
        (
          coord: coord,
          tile: BitmapTile(
            size: size,
            pixels: Uint8List.fromList([
              for (var i = 0; i < size * size; i += 1) ...rgba,
            ]),
          ),
        ),
      ]),
    );
  }

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: fixture())),
    );
    await tester.pumpAndSettle();
    final session = workspaceOf(tester).session;
    session.selectLayer(row(session).id);
    session.selectFrameIndex(0);
    await tester.pump();
    await settle(tester);
    return session;
  }

  CutPiece squareOf(List<int> rgba, {int side = 40}) => CutPiece(
    image: BrushStampImage(
      id: 'held-$side',
      width: side,
      height: side,
      rgba: Uint8List.fromList([
        for (var i = 0; i < side * side; i += 1) ...rgba,
      ]),
    ),
    originLeft: 0,
    originTop: 0,
  );

  /// Where canvas point [at] lies in the window.
  Offset windowOf(WidgetTester tester, CanvasPoint at) {
    final shell = mainCanvasPanelShell();
    final layer = find.descendant(
      of: shell,
      matching: find.byType(CanvasViewportGestureLayer),
    );
    final view = tester.widget<CanvasViewportGestureLayer>(layer).viewport;
    final onPanel = view.canvasToViewport(at);
    return tester.getTopLeft(layer) + Offset(onPanel.x, onPanel.y);
  }

  /// The canvas point under window point [at].
  CanvasPoint canvasOf(WidgetTester tester, Offset at) {
    final layer = find.descendant(
      of: mainCanvasPanelShell(),
      matching: find.byType(CanvasViewportGestureLayer),
    );
    final view = tester.widget<CanvasViewportGestureLayer>(layer).viewport;
    final onPanel = at - tester.getTopLeft(layer);
    return view.viewportToCanvas(ViewportPoint(x: onPanel.dx, y: onPanel.dy));
  }

  var shots = 0;

  /// What the window shows over [rect], RGBA row after row.
  Future<Uint8List> shot(WidgetTester tester, Rect rect) async {
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final bytes = await tester.runAsync(() async {
      const dump = String.fromEnvironment('F473_DUMP');
      if (dump.isNotEmpty) {
        final wide = await layer.toImage(rect.inflate(160));
        final png = await wide.toByteData(format: ui.ImageByteFormat.png);
        File('$dump/shot_${shots++}.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        wide.dispose();
      }
      final image = await layer.toImage(rect);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  /// Where [a] and [b] part over a [side]-wide shot: how many pixels, their
  /// box and a few — empty where they do not.
  String apart(Uint8List a, Uint8List b, int side) {
    var count = 0;
    int? left;
    int? top;
    int? right;
    int? bottom;
    final some = <String>[];
    for (var i = 0; i < a.length; i += 4) {
      final parts = [
        for (var c = 0; c < 4; c += 1) (a[i + c] - b[i + c]).abs(),
      ].any((d) => d > 2);
      if (!parts) {
        continue;
      }
      count += 1;
      final x = i ~/ 4 % side;
      final y = i ~/ 4 ~/ side;
      left = left == null || x < left ? x : left;
      top = top == null || y < top ? y : top;
      right = right == null || x > right ? x : right;
      bottom = bottom == null || y > bottom ? y : bottom;
      if (some.length < 3) {
        some.add('($x, $y) ${a.sublist(i, i + 4)} → ${b.sublist(i, i + 4)}');
      }
    }
    return count == 0
        ? ''
        : '$count px, box ($left, $top)–($right, $bottom): ${some.join('; ')}';
  }

  for (final change in [false, true]) {
    testWidgets('a stamp held over a drawn cel and the hand moved off'
        '${change ? ', the frame changed under it,' : ''} leaves nothing '
        'where it rested', (tester) async {
      final session = await pump(tester);
      final tile = session.pixelEditing.coordinator!
          .currentSurfaceOf(keyOf(session, 'c0'))
          .tileSize;
      // The middle of the canvas the artist sees, on a tile's corner: the
      // ghost crosses into the tiles round it, one of them drawn on each
      // cel.
      final seen = canvasOf(tester, visibleCanvasRect(tester).center);
      final middle = TileCoord(
        x: (seen.x / tile).round(),
        y: (seen.y / tile).round(),
      );
      paint(session, 'c0', middle, const [0, 0, 255, 255]);
      paint(session, 'c1', middle, const [0, 160, 0, 255]);
      await settle(tester);
      workspaceOf(tester).session.pixelVerbs.cutToolHand!(
        squareOf(const [255, 0, 0, 255]),
      );
      final brush = workspaceOf(tester).brushTool!;
      brush.value = brush.value.copyWith(tool: CanvasTool.cutStamp);
      await settle(tester);

      final aim = windowOf(
        tester,
        CanvasPoint(x: middle.x * tile * 1.0, y: middle.y * tile * 1.0),
      );
      final away = aim + const Offset(160, 100);
      expect(
        visibleCanvasRect(tester).contains(aim) &&
            visibleCanvasRect(tester).contains(away),
        isTrue,
        reason: '⛔premise: the hand rests on the canvas the artist sees — '
            'aim $aim away $away seen ${visibleCanvasRect(tester)} '
            'canvas $seen tile $tile',
      );
      final around = Rect.fromCenter(center: aim, width: 120, height: 120);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: away);
      await settle(tester);
      final beforeA = await shot(tester, around);
      if (change) {
        session.selectFrameIndex(1);
        await settle(tester);
      }
      final beforeHere = await shot(tester, around);
      if (change) {
        session.selectFrameIndex(0);
        await settle(tester);
      }

      await mouse.moveTo(aim);
      await settle(tester);
      expect(
        apart(beforeA, await shot(tester, around), 120),
        isNotEmpty,
        reason: 'LIVENESS: the ghost shows where the hand rests',
      );
      if (change) {
        session.selectFrameIndex(1);
        await settle(tester);
      }
      await mouse.moveTo(away);
      await settle(tester);
      expect(
        apart(beforeHere, await shot(tester, around), 120),
        isEmpty,
        reason: 'the hand moved off: nothing stays where it rested',
      );
      if (change) {
        session.selectFrameIndex(0);
        await settle(tester);
        expect(
          apart(beforeA, await shot(tester, around), 120),
          isEmpty,
          reason: 'back on the frame it rested on: nothing stays there',
        );
      }
    }, skip: noFlutterGpu != null);
  }
}

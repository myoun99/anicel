@Tags(['gpu'])
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/viewport_point.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart' show effectLaneId;

import '../helpers/a_canvas_standing_on_a_frame.dart' show noFlutterGpu;
import '../helpers/app_faces.dart';
import '../helpers/panel_finders.dart';
import '../helpers/settle_async.dart';

/// F-481 (유저 2026-10-26): 「셀 번호fx가 캔버스에 보이는건 빈 블록일때도
/// 보임 … 빈블록이라도 존재하면 보이도록 고정」 — and on such a block, 「그렸다가
/// 취소? 픽셀지우기? 해서 지운 그림이 계속 남아있음 … 재생할땐 특정그림이 있는
/// 화면이 보이고, 멈추면 특정그림 없고 셀번호fx가 보이는 상황」.
void main() {
  const cels = ['c0', 'c1'];
  const underCels = ['u0', 'u1'];
  const under = LayerId('under');

  Project fixture({bool heldUnder = false}) {
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
                  if (layer.id == row.id) ...[
                    layer.copyWith(
                      frames: [
                        for (final id in cels)
                          Frame(id: FrameId(id), duration: 1, strokes: const []),
                      ],
                      timeline: {
                        for (final (at, id) in cels.indexed)
                          at: TimelineExposure.drawing(FrameId(id), length: 1),
                      },
                    ),
                    // Drawn on every frame, so each frame is a picture and
                    // not its page alone.
                    layer.copyWith(
                      id: under,
                      name: 'U',
                      frames: [
                        for (final id in underCels)
                          Frame(id: FrameId(id), duration: 1, strokes: const []),
                      ],
                      timeline: heldUnder
                          ? {
                              0: TimelineExposure.drawing(
                                FrameId(underCels.first),
                                length: cels.length,
                              ),
                            }
                          : {
                              for (final (at, id) in underCels.indexed)
                                at: TimelineExposure.drawing(
                                  FrameId(id),
                                  length: 1,
                                ),
                            },
                    ),
                  ] else
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

  Layer row(EditorSessionManager session) => session.layers.firstWhere(
    (l) => l.frames.length == cels.length && l.id != under,
  );

  BrushFrameKey keyOf(EditorSessionManager session, String cel) =>
      session.brushFrameKeyForCut(
        session.requireActiveCut,
        underCels.contains(cel) ? under : row(session).id,
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

  /// Where the letters are looked for: on the paper the artist sees, clear
  /// of the panels over the canvas.
  const lettersAt = Offset(900, 400);

  /// The row's cel number on, standing at [lettersAt] on every frame.
  void number(WidgetTester tester, EditorSessionManager session) {
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.celNumber);
    final layer = row(session).id;
    final at = canvasOf(tester, lettersAt);
    session.laneVerbs.setLaneValueAt(
      layer,
      effectLaneId(session.commitLayerById(layer)!.effects.single.id,
          'position'),
      0,
      '${at.x.round()}, ${at.y.round()}',
      frameIsGlobal: false,
      description: 'Move',
      scaleLinked: false,
    );
  }

  /// The editor on frame 0 of the row, the row's cel number on where
  /// [numbered].
  Future<EditorSessionManager> pump(
    WidgetTester tester, {
    bool numbered = true,
    bool heldUnder = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(initialProject: fixture(heldUnder: heldUnder)),
      ),
    );
    await tester.pumpAndSettle();
    final session = workspaceOf(tester).session;
    for (final cel in underCels) {
      paint(session, cel, TileCoord(x: 1, y: 1), const [90, 90, 90, 255]);
    }
    session.selectLayer(row(session).id);
    if (numbered) {
      number(tester, session);
    }
    session.selectFrameIndex(0);
    await tester.pump();
    await settle(tester);
    return session;
  }

  /// What the window shows over [rect], RGBA row after row.
  Future<Uint8List> shot(WidgetTester tester, Rect rect) async {
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final bytes = await tester.runAsync(() async {
      final image = await layer.toImage(rect);
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  /// How many pixels [a] and [b] part at.
  int apart(Uint8List a, Uint8List b) {
    var count = 0;
    for (var i = 0; i < a.length; i += 4) {
      for (var c = 0; c < 4; c += 1) {
        if ((a[i + c] - b[i + c]).abs() > 2) {
          count += 1;
          break;
        }
      }
    }
    return count;
  }

  /// Where the letters stand ([lettersAt]) and a spot well away from them
  /// the pen draws at, both on the paper the artist sees.
  ({Rect letters, Offset pen, Rect drawn}) placesOf(
    WidgetTester tester,
    EditorSessionManager session,
  ) {
    const pen = Offset(600, 370);
    return (
      letters: Rect.fromCenter(center: lettersAt, width: 160, height: 90),
      pen: pen,
      drawn: Rect.fromLTWH(pen.dx - 16, pen.dy - 16, 96, 64),
    );
  }

  Future<void> stroke(WidgetTester tester, Offset from) async {
    final pen = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    for (var step = 1; step <= 10; step += 1) {
      await pen.moveTo(from + Offset(step * 6.0, step * 3.0));
      await tester.pump();
    }
    await pen.up();
    // Off the canvas: the brush's ring is drawn where the mouse rests.
    await pen.moveTo(const Offset(2, 2));
    await pen.removePointer();
    await tester.pump();
  }

  for (final held in [false, true]) {
    testWidgets('a stroke undone on an empty block with a cel number leaves '
        'nothing of it — on the canvas, and back on the frame'
        '${held ? ', the rows round it held over the next frame' : ''}', (
      tester,
    ) async {
      final session = await pump(tester, heldUnder: held);
      final brush = workspaceOf(tester).brushTool!;
      brush.value = brush.value.copyWith(tool: CanvasTool.brush);
      if (!held) {
        paint(session, 'c1', TileCoord(x: 0, y: 0), const [0, 160, 0, 255]);
      }
      await settle(tester);
      final places = placesOf(tester, session);
      session.selectFrameIndex(1);
      await settle(tester);
      final emptyNext = await shot(tester, places.drawn);
      session.selectFrameIndex(0);
      await settle(tester);
      final empty = await shot(tester, places.drawn);

      await stroke(tester, places.pen);
      await settle(tester);
      expect(
        apart(empty, await shot(tester, places.drawn)),
        isNonZero,
        reason: 'LIVENESS: the stroke shows',
      );
      bool drawn() => session.pixelEditing.coordinator!
          .currentSurfaceOf(keyOf(session, 'c0'))
          .showsSomething;
      expect(drawn(), isTrue, reason: '⛔premise: the stroke is on the block');
      session.undo();
      await settle(tester);
      expect(drawn(), isFalse, reason: '⛔premise: undone, the block is empty');
      expect(
        apart(empty, await shot(tester, places.drawn)),
        0,
        reason: 'undone: nothing of the stroke stays on the canvas',
      );
      session.selectFrameIndex(1);
      await settle(tester);
      expect(
        apart(emptyNext, await shot(tester, places.drawn)),
        0,
        reason: 'on the next frame: nothing of the stroke in its picture',
      );
      session.selectFrameIndex(0);
      await settle(tester);
      expect(
        apart(empty, await shot(tester, places.drawn)),
        0,
        reason: 'back on the frame: nothing of the stroke in its picture',
      );
    }, skip: noFlutterGpu != null);
  }

  testWidgets('an empty block with a cel number shows the number as a drawn '
      'one does — standing on it, back on it, and another row active', (
    tester,
  ) async {
    final session = await pump(tester, numbered: false);
    final places = placesOf(tester, session);
    final plain = await shot(tester, places.letters);
    number(tester, session);
    await settle(tester);
    final neverDrawn = await shot(tester, places.letters);
    // The block drawn on, away from where the letters stand: what the
    // letters look like where the row has a picture.
    paint(session, 'c0', TileCoord(x: 0, y: 0), const [0, 0, 255, 255]);
    await settle(tester);
    final numbered = await shot(tester, places.letters);
    expect(
      apart(plain, numbered),
      isNonZero,
      reason: 'LIVENESS: the number shows where it is looked for',
    );
    expect(
      apart(neverDrawn, numbered),
      0,
      reason: 'a block never drawn on shows its number',
    );
    paint(session, 'c0', TileCoord(x: 0, y: 0), const [0, 0, 0, 0]);
    await settle(tester);
    expect(
      session.pixelEditing.coordinator!
          .currentSurfaceOf(keyOf(session, 'c0'))
          .tiles
          .values
          .every((tile) => tile.pixels.every((byte) => byte == 0)),
      isTrue,
      reason: '⛔premise: the block holds no pixels',
    );

    expect(
      apart(numbered, await shot(tester, places.letters)),
      0,
      reason: 'standing on the empty block: its number shows',
    );
    session.selectFrameIndex(1);
    await settle(tester);
    session.selectFrameIndex(0);
    await settle(tester);
    expect(
      apart(numbered, await shot(tester, places.letters)),
      0,
      reason: 'back on the frame, its picture shown: the number shows',
    );
    final other = session.layers.firstWhere(
      (l) => l.id != row(session).id && layerAcceptsBrushInput(l),
      orElse: () => session.layers.firstWhere((l) => l.id != row(session).id),
    );
    session.selectLayer(other.id);
    await settle(tester);
    expect(
      apart(numbered, await shot(tester, places.letters)),
      0,
      reason: 'another row active: the number shows',
    );
  }, skip: noFlutterGpu != null);

  testWidgets('a block never drawn on shows its cel number however the '
      'canvas stands — its row active or another, the frame left and come '
      'back to', (tester) async {
    final session = await pump(tester);
    final places = placesOf(tester, session);
    final other = session.layers.firstWhere((l) => l.id == under);
    session.selectFrameIndex(1);
    await settle(tester);
    final seen = <String, Uint8List>{
      'its row active': await shot(tester, places.letters),
    };
    session.selectLayer(other.id);
    await settle(tester);
    seen['another row active'] = await shot(tester, places.letters);
    session.selectFrameIndex(0);
    await settle(tester);
    session.selectFrameIndex(1);
    await settle(tester);
    seen['another row active, the frame come back to'] = await shot(
      tester,
      places.letters,
    );
    session.selectLayer(row(session).id);
    await settle(tester);
    seen['its row active again'] = await shot(tester, places.letters);

    // The block drawn on, away from where the letters stand.
    paint(session, 'c1', TileCoord(x: 0, y: 0), const [0, 0, 255, 255]);
    await settle(tester);
    final numbered = await shot(tester, places.letters);
    session.selectLayer(other.id);
    await settle(tester);
    expect(
      apart(numbered, await shot(tester, places.letters)),
      0,
      reason: '⛔premise: drawn on, the number shows whichever row is active',
    );
    for (final MapEntry(key: how, value: shown) in seen.entries) {
      expect(apart(numbered, shown), 0, reason: 'never drawn on, $how');
    }
  }, skip: noFlutterGpu != null);

  // 🗣️F-489 — an unnamed drawing's number is its row's name and the mark
  // picked in Preferences, and a pick rewrites it where the canvas stands.
  testWidgets('a mark picked for the unnamed drawing rewrites its number on '
      'the canvas', (tester) async {
    addTearDown(
      () => AppFrameGridSettings.settings.value = const AppFrameGridSettings(),
    );
    // The test font sets ○ and ● as one and the same box.
    await loadTheAppFaces();
    final session = await pump(tester);
    final places = placesOf(tester, session);
    final two = await shot(tester, places.letters);

    AppFrameGridSettings.settings.value = const AppFrameGridSettings(
      unnamedMark: InbetweenMark.one,
    );
    await settle(tester);
    expect(apart(two, await shot(tester, places.letters)), greaterThan(0));

    AppFrameGridSettings.settings.value = const AppFrameGridSettings();
    await settle(tester);
    expect(apart(two, await shot(tester, places.letters)), 0);
  }, skip: noFlutterGpu != null);
}

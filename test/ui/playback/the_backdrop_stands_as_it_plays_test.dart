import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/pasteboard_bounds.dart'
    show PasteboardBounds, PasteboardSize;
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart'
    show CanvasStageColors;
import 'package:anicel/src/ui/brush/canvas_view_commands.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';

/// 🚨WHAT THE FILM LAYS UNDER ITS CUTS IS WHAT THE EDITING CANVAS SHOWS:
/// pressing nothing but where you stand changes nothing on the screen
/// (유저 09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
///
/// In a fade (fade-wash-ignores-an-absent-backdrop, 2026-10-23): a fade is
/// transparency — the cut's unit thins and what lies under it shows, on
/// the film its floor, which for an absent backdrop is the checkerboard
/// (F-114). Standing still, the editing canvas lays the same result as a
/// wash of the backdrop over the unit at the backdrop's share, and the wash
/// took the backdrop's KEPT colour whether the backdrop was there or not.
///
/// And a TRANSLUCENT backdrop shows what is behind it once (F-114: 「불투명도는
/// 체크무늬는 안되고 진짜 불투명도를 낮추는행위」 —
/// a-translucent-backdrop-lies-twice-on-the-film, 2026-10-23). The film
/// lies over the editing canvas's own planes and laid the backdrop there
/// again: it played darker than it stood, a frame with no cut showed the
/// editing cut's pasteboard through it, and the wash thinned the cut to
/// the backdrop's own colour, its alpha dropped.
void main() {
  final screen = GlobalKey();
  const translucent = 0x802040C0;

  Future<EditorSessionManager> standing(
    WidgetTester tester, {
    int? backdropArgb,
    bool backdropNone = false,
    required bool inTheFade,
  }) async {
    // One device pixel a logical one, the grid the shot is taken on.
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    if (backdropArgb != null) {
      session.projectSettings.setProjectBackdrop(backdropArgb);
    }
    if (backdropNone) {
      session.projectSettings.setProjectBackdropNone();
    }
    // A pasteboard the view can see past, for the floor beyond its wall.
    session.projectSettings.setPasteboardSize(PasteboardSize.oneAndAHalf);
    // An O.L over the cut's last six frames with no cut after it: the cut
    // thins over the backdrop there.
    final duration = session.activeCutOrNull!.duration;
    session.transitions.updateTransitionInstructions({
      duration - 6: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    session.selectFrameIndex(inTheFade ? duration - 3 : 1);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final camera = ValueNotifier<bool>(false);
    final dim = ValueNotifier<double>(0.5);
    final view = CanvasViewCommands();
    addTearDown(brushTool.dispose);
    addTearDown(camera.dispose);
    addTearDown(dim.dispose);
    final project = session.repository.requireProject();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: screen,
            // The room's colours, as the workspace says them to the floor.
            child: CanvasStageColors(
              backdropArgb: project.backdropArgb,
              pasteboardArgb: project.pasteboardArgb,
              backdropNone: project.backdropNone,
              pasteboardNone: project.pasteboardNone,
              pasteboardSize: project.pasteboardSize,
              pasteboardInUse: project.pasteboardInUse,
              child: EditorCanvasArea(
                session: session,
                brushToolState: brushTool,
                cameraViewEnabled: camera,
                cameraDimOpacity: dim,
                canvasViewCommands: view,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    view
      ..zoomStep(zoomIn: false)
      ..zoomStep(zoomIn: false);
    await tester.pumpAndSettle();
    return session;
  }

  /// The warmer's debounced timers cannot be cancelled by a dispose.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<Shot> onScreen(WidgetTester tester) async {
    final render =
        screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final shot = await tester.runAsync(() async {
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      return (rgba: data!.buffer.asUint8List(), width: width, height: height);
    });
    return shot!;
  }

  List<int> pixelAt(Shot shot, int x, int y) => shot.rgba.sublist(
    (y * shot.width + x) * 4,
    (y * shot.width + x) * 4 + 4,
  );

  /// The standing cut's paper and pasteboard on the screen.
  ({Rect paper, Rect pasteboard}) stageOnScreen(WidgetTester tester) {
    final found = find.byType(CanvasLayerStackView);
    final stack = tester.widget<CanvasLayerStackView>(found);
    final origin =
        tester.getTopLeft(found) - tester.getTopLeft(find.byKey(screen));
    final view = stack.viewport;
    Rect onTheScreen(Rect rect) => Rect.fromLTWH(
      origin.dx + view.panX + rect.left * view.zoom,
      origin.dy + view.panY + rect.top * view.zoom,
      rect.width * view.zoom,
      rect.height * view.zoom,
    );
    return (
      paper: onTheScreen(stack.canvasSize.canvasRect),
      pasteboard: onTheScreen(
        stack.canvasSize.pasteboardAt(stack.pasteboardReach).rect,
      ),
    );
  }

  /// A strip of the floor past the pasteboard's left wall, level with the
  /// paper's middle.
  Rect pastTheWall(({Rect paper, Rect pasteboard}) stage) {
    final middle = stage.paper.center.dy;
    final strip = Rect.fromLTRB(
      stage.pasteboard.left - 12,
      middle - 8,
      stage.pasteboard.left - 4,
      middle + 8,
    );
    expect(
      strip.left,
      greaterThanOrEqualTo(0),
      reason: '⛔premise: the view sees past the pasteboard\'s wall',
    );
    return strip;
  }

  /// Whether two pixels are the same past a rounding of [slack] — the wash
  /// and the film's thinning each round their own blend.
  bool near(List<int> p, List<int> q, {int slack = 1}) {
    for (var c = 0; c < 4; c += 1) {
      if ((p[c] - q[c]).abs() > slack) {
        return false;
      }
    }
    return true;
  }

  /// Where the two pictures part inside [area], as `(x, y): a → b`.
  List<String> differences(Shot a, Shot b, Rect area, {int slack = 1}) {
    final out = <String>[];
    for (var y = area.top.ceil(); y < area.bottom.floor(); y += 1) {
      for (var x = area.left.ceil(); x < area.right.floor(); x += 1) {
        final p = pixelAt(a, x, y);
        final q = pixelAt(b, x, y);
        if (!near(p, q, slack: slack) && out.length < 8) {
          out.add('($x, $y): $p → $q');
        }
      }
    }
    return out;
  }

  /// [argb] over the ground the canvas panel's shell lays.
  List<int> overTheGround(WidgetTester tester, int argb) {
    final ground = tester
        .widget<ColoredBox>(
          find
              .descendant(
                of: find.byKey(
                  const ValueKey<String>('canvas-editor-panel-shell'),
                ),
                matching: find.byType(ColoredBox),
              )
              .first,
        )
        .color;
    final seen = Color.alphaBlend(Color(argb), ground);
    int byte(double channel) => (channel * 255).round();
    return [byte(seen.r), byte(seen.g), byte(seen.b), byte(seen.a)];
  }

  Future<Shot> parkedWhereItStands(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    session.parkGlobalFrame(session.editingGlobalFrame);
    await tester.pumpAndSettle();
    expect(
      find.byType(CanvasTrackStackView),
      findsOneWidget,
      reason: '⛔premise: parked, the canvas shows the film at that frame',
    );
    return onScreen(tester);
  }

  const backdrops = {
    'there': (argb: null, none: false),
    'absent': (argb: null, none: true),
    'translucent': (argb: translucent, none: false),
  };
  for (final MapEntry(key: backdrop, value: (:argb, :none))
      in backdrops.entries) {
    testWidgets('🚨with the backdrop $backdrop, the frame you stand on in a '
        'fade is the film\'s frame', (tester) async {
      final session = await standing(
        tester,
        backdropArgb: argb,
        backdropNone: none,
        inTheFade: true,
      );
      expect(
        find.byType(CanvasTrackStackView),
        findsNothing,
        reason: '⛔premise: standing, the canvas shows the cut it edits',
      );
      // The paper's middle, a few pixels in from its edge: the cut's own
      // unit, where the fade shows what lies under it.
      final area = stageOnScreen(tester).paper.deflate(4);
      final still = await onScreen(tester);
      final film = await parkedWhereItStands(tester, session);

      if (none) {
        // Two pixels a cell apart in the paper's middle: through the
        // thinned paper the film shows the checkerboard's two cells.
        final x = area.center.dx.floor();
        final y = area.center.dy.floor();
        final a = pixelAt(film, x - (x % 16) + 4, y - (y % 16) + 4);
        final b = pixelAt(film, x - (x % 16) + 12, y - (y % 16) + 4);
        expect(
          a,
          isNot(b),
          reason: 'LIVENESS: the film shows the checkerboard through the '
              'fade',
        );
      }
      expect(
        differences(still, film, area),
        isEmpty,
        reason: 'pressing nothing but where you stand must change nothing on '
            'the screen',
      );
      await drain(tester);
    });
  }

  testWidgets('🚨a translucent backdrop shows the ground once, standing and '
      'played', (tester) async {
    final session = await standing(
      tester,
      backdropArgb: translucent,
      inTheFade: false,
    );
    final strip = pastTheWall(stageOnScreen(tester));
    final still = await onScreen(tester);
    final film = await parkedWhereItStands(tester, session);

    expect(
      differences(still, film, strip, slack: 0),
      isEmpty,
      reason: 'the film lays the floor the editing canvas shows',
    );
    final seen = pixelAt(
      still,
      strip.center.dx.floor(),
      strip.center.dy.floor(),
    );
    final once = overTheGround(tester, translucent);
    expect(
      near(seen, once),
      isTrue,
      reason: 'the backdrop is laid over the panel\'s ground once — thinner, '
          'and the ground shows: $seen, laid once $once',
    );
    await drain(tester);
  });

  testWidgets('🚨a frame with no cut lays one floor over the editing cut\'s '
      'planes', (tester) async {
    final session = await standing(
      tester,
      backdropArgb: translucent,
      inTheFade: false,
    );
    final stage = stageOnScreen(tester);
    final strip = pastTheWall(stage);
    final y = stage.paper.center.dy.floor();
    // Between the pasteboard's wall and the paper: where the editing cut
    // lays its pasteboard.
    final onThePasteboard = (
      x: ((stage.pasteboard.left + stage.paper.left) / 2).floor(),
      y: y,
    );
    // Past the last cut and its O.L's tail: the film has nothing there but
    // its floor.
    session.parkGlobalFrame(session.activeCutOrNull!.duration + 12);
    await tester.pumpAndSettle();
    expect(
      find.byType(CanvasTrackStackView),
      findsOneWidget,
      reason: '⛔premise: parked past the cut, the canvas shows the film',
    );
    final film = await onScreen(tester);

    expect(
      pixelAt(film, onThePasteboard.x, onThePasteboard.y),
      pixelAt(film, strip.center.dx.floor(), strip.center.dy.floor()),
      reason: 'one floor: nothing the editing canvas lays shows through it',
    );
    await drain(tester);
  });
}

/// A screen shot in device pixels.
typedef Shot = ({Uint8List rgba, int width, int height});

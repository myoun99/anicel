import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/pasteboard_bounds.dart' show PasteboardBounds;
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';

/// 🚨STANDING ON A FADE SHOWS WHAT THE FILM SHOWS THERE, the backdrop
/// absent too (fade-wash-ignores-an-absent-backdrop, 2026-10-23).
///
/// A fade is transparency: the cut's unit thins and what lies under it
/// shows — on the film its floor, which for an absent backdrop is the
/// checkerboard (F-114). Standing still, the editing canvas lays the same
/// result as a wash of the backdrop over the unit at the backdrop's share,
/// and the wash took the backdrop's KEPT colour whether the backdrop was
/// there or not: the frame you stand on showed a colour the film never did
/// (유저 09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
void main() {
  final screen = GlobalKey();

  Future<EditorSessionManager> standingOnTheFade(
    WidgetTester tester, {
    required bool backdropNone,
  }) async {
    // One device pixel a logical one, the grid the shot is taken on.
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    if (backdropNone) {
      session.projectSettings.setProjectBackdropNone();
    }
    // An O.L over the cut's last six frames with no cut after it: the cut
    // thins over the backdrop, and the playhead stands inside it.
    final duration = session.activeCutOrNull!.duration;
    session.transitions.updateTransitionInstructions({
      duration - 6: const InstructionEvent(instructionId: 'ol', length: 12),
    });
    session.selectFrameIndex(duration - 3);
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final camera = ValueNotifier<bool>(false);
    final dim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(camera.dispose);
    addTearDown(dim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: screen,
            child: EditorCanvasArea(
              session: session,
              brushToolState: brushTool,
              cameraViewEnabled: camera,
              cameraDimOpacity: dim,
            ),
          ),
        ),
      ),
    );
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

  /// The paper's middle on the screen, a few pixels in from its edge: the
  /// cut's own unit, where the fade shows what lies under it.
  Rect paperOnScreen(WidgetTester tester) {
    final found = find.byType(CanvasLayerStackView);
    final stack = tester.widget<CanvasLayerStackView>(found);
    final origin =
        tester.getTopLeft(found) - tester.getTopLeft(find.byKey(screen));
    final view = stack.viewport;
    final page = stack.canvasSize.canvasRect;
    return Rect.fromLTWH(
      origin.dx + view.panX + page.left * view.zoom,
      origin.dy + view.panY + page.top * view.zoom,
      page.width * view.zoom,
      page.height * view.zoom,
    ).deflate(4);
  }

  /// Where the two pictures part inside [area], as `(x, y): a → b`, past a
  /// rounding of [slack] — the wash and the film's thinning each round
  /// their own blend.
  List<String> differences(Shot a, Shot b, Rect area, {int slack = 1}) {
    final out = <String>[];
    for (var y = area.top.ceil(); y < area.bottom.floor(); y += 1) {
      for (var x = area.left.ceil(); x < area.right.floor(); x += 1) {
        final p = pixelAt(a, x, y);
        final q = pixelAt(b, x, y);
        var far = false;
        for (var c = 0; c < 4; c += 1) {
          far = far || (p[c] - q[c]).abs() > slack;
        }
        if (far && out.length < 8) {
          out.add('($x, $y): $p → $q');
        }
      }
    }
    return out;
  }

  for (final backdropNone in const [false, true]) {
    final backdrop = backdropNone ? 'absent' : 'there';
    testWidgets('🚨with the backdrop $backdrop, the frame you stand on in a '
        'fade is the film\'s frame', (tester) async {
      final session = await standingOnTheFade(
        tester,
        backdropNone: backdropNone,
      );
      expect(
        find.byType(CanvasTrackStackView),
        findsNothing,
        reason: '⛔premise: standing, the canvas shows the cut it edits',
      );
      final area = paperOnScreen(tester);
      final standing = await onScreen(tester);

      session.parkGlobalFrame(session.editingGlobalFrame);
      await tester.pumpAndSettle();
      expect(
        find.byType(CanvasTrackStackView),
        findsOneWidget,
        reason: '⛔premise: parked, the canvas shows the film at that frame',
      );
      final film = await onScreen(tester);

      if (backdropNone) {
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
        differences(standing, film, area),
        isEmpty,
        reason: 'pressing nothing but where you stand must change nothing on '
            'the screen',
      );
      await drain(tester);
    });
  }
}

/// A screen shot in device pixels.
typedef Shot = ({Uint8List rgba, int width, int height});

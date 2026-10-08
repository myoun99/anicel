import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/ui/dialogs/canvas_size_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';

import '../helpers/draw_on_current_frame.dart';
import 'flyout_test_helpers.dart' show tapCommandButton;

/// I-79 through the app: an adjust opened on the canvas stands its box and
/// pill on the canvas showing the cut, Escape closes it as its ✕ does, and
/// Enter lands it as its ✓ does — 확정 is one verb (`ConfirmVerb`), and the
/// landing waits in the same window a size typed into the window waits in.
void main() {
  Future<EditorSessionManager> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorTopStrip>(find.byType(EditorTopStrip))
        .projects
        .active;
  }

  final pill = find.byKey(const ValueKey<String>('canvas-adjust-pill'));

  /// Through the wait window, which lingers and spins.
  Future<void> pumpPastTheWait(WidgetTester tester) async {
    for (var step = 0; step < 30; step += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the size window\'s 「캔버스에서 조정」 stands the adjust on the '
      'canvas, and Escape closes it', (tester) async {
    final session = await pumpApp(tester);
    final cut = session.requireActiveCut;
    expect(pill, findsNothing, reason: '⛔전제: nothing open');

    await tapCommandButton(
      tester,
      const ValueKey<String>('resize-cut-canvas-button'),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-size-adjust-on-canvas')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CanvasSizeDialog), findsNothing, reason: 'closed');
    expect(session.canvasAdjust.isOpenOn(cut.id), isTrue);
    expect(pill, findsOneWidget, reason: 'on the canvas showing the cut');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(session.canvasAdjust.isOpen, isFalse);
    expect(pill, findsNothing);
  });

  testWidgets('🚨Enter lands the edges — the canvas takes their size, the '
      'picture moves by the edge pulled out on the left, and the adjust '
      'closes', (tester) async {
    final session = await pumpApp(tester);
    drawOnCurrentFrame(session);
    final cut = session.requireActiveCut;
    final before = cut.canvasSize;
    ({int left, int top, int rightExclusive, int bottomExclusive}) ink() {
      final drawn = session.editingCanvas.activeBrushEditorSelection!;
      final key = session.brushFrameKeyForCut(
        session.requireActiveCut,
        drawn.layerId,
        drawn.frameId,
      );
      return bitmapSurfaceContentBounds(
        session.renderCaches.brushFrameStore.bakedSurfaceOrNull(key)!,
      )!;
    }

    final inkBefore = ink();
    session.canvasAdjust
      ..begin(cut.id, before)
      ..move(
        Rect.fromLTRB(
          -10,
          0,
          before.width.toDouble(),
          before.height + 20.0,
        ),
      );
    await tester.pump();
    expect(pill, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpPastTheWait(tester);

    expect(
      session.requireActiveCut.canvasSize,
      CanvasSize(width: before.width + 10, height: before.height + 20),
    );
    expect(session.canvasAdjust.isOpen, isFalse);
    expect(pill, findsNothing);
    expect(
      ink().left,
      inkBefore.left + 10,
      reason: 'the left edge pulled out by 10 moved the picture by as much',
    );
  });

  testWidgets('an adjust left open on a cut the canvas no longer shows is let '
      'go of', (tester) async {
    final session = await pumpApp(tester);
    final cut = session.requireActiveCut;
    session.canvasAdjust.begin(cut.id, cut.canvasSize);
    await tester.pump();
    expect(pill, findsOneWidget, reason: '⛔전제: open');

    session.cutVerbs.createCut();
    await tester.pump();
    await tester.pump();
    expect(
      session.requireActiveCut.id,
      isNot(cut.id),
      reason: '⛔전제: the canvas shows another cut',
    );
    expect(session.canvasAdjust.isOpen, isFalse);
    expect(pill, findsNothing);
  });

  testWidgets('🚨Enter on an adjust whose cut is no longer shown lets it go '
      '— the cut shown keeps its canvas', (tester) async {
    final session = await pumpApp(tester);
    final cut = session.requireActiveCut;
    session.canvasAdjust
      ..begin(cut.id, cut.canvasSize)
      ..move(
        Rect.fromLTRB(
          0,
          0,
          cut.canvasSize.width + 30.0,
          cut.canvasSize.height.toDouble(),
        ),
      );
    await tester.pump();
    session.cutVerbs.createCut();
    final shown = session.requireActiveCut;
    expect(shown.id, isNot(cut.id), reason: '⛔전제: another cut is shown');
    expect(
      session.canvasAdjust.isOpen,
      isTrue,
      reason: '⛔전제: no frame has let it go yet',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpPastTheWait(tester);

    expect(session.requireActiveCut.canvasSize, shown.canvasSize);
    expect(session.canvasAdjust.isOpen, isFalse);
  });
}

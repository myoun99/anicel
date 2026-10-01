import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/device_viewport.dart';

/// fill-beyond-wall-notice (09-11, 「해당 남은거 카드로 올려주고」): the fill
/// does nothing beyond the pasteboard wall, and on an EMPTY cell the press
/// asked for a cel before anyone looked where it landed — so a press that
/// did nothing still made a block (auto-frame on) or said 「프레임이 존재하지
/// 않습니다」 (off). The view standing on the empty cell asks the fill's own
/// wall answer first now.
void main() {
  BrushDab fillDab(int color) => BrushDab(
    center: CanvasPoint(x: 4, y: 4),
    color: color,
    size: 8,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  /// An empty cell under [tool]: the view stands down in place, and every
  /// press it would draw with asks for a cel — counted, never made.
  Future<List<int>> standOnAnEmptyCell(
    WidgetTester tester,
    CanvasTool tool,
  ) async {
    final asked = <int>[];
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: BrushCanvasFixture.createCoordinator(
              frameKeys: frameKeys,
            ),
            celEditable: false,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            brushToolState: ValueNotifier(
              BrushToolState.defaults.copyWith(tool: tool),
            ),
            fillDabAt: (_, color, _) => fillDab(color),
            onPressNeedsCel: () {
              asked.add(1);
              return false;
            },
            // Far enough out that the wall — one canvas beyond each edge —
            // is on screen with room past it.
            viewport: seedFromRender(
              tester,
              CanvasViewport(zoom: 0.1, panX: 300, panY: 150),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return asked;
  }

  /// Where [point] is on screen, through the view's own viewport — the one
  /// the press reads back.
  Offset onScreen(WidgetTester tester, CanvasPoint point) {
    final view = find.byType(InteractiveBrushEditCanvasView);
    final local = tester
        .widget<InteractiveBrushEditCanvasView>(view)
        .viewport
        .canvasToViewport(point);
    final at = tester.getTopLeft(view) + Offset(local.x, local.y);
    expect(
      tester.getRect(view).contains(at),
      isTrue,
      reason: '⛔premise: the press lands on the view',
    );
    return at;
  }

  Future<void> pressAt(WidgetTester tester, Offset at) async {
    final pen = await tester.startGesture(at, kind: PointerDeviceKind.stylus);
    await tester.pump();
    await pen.up();
    await tester.pump();
  }

  const size = BrushCanvasFixture.canvasSize;
  final beyondTheWall = CanvasPoint(
    x: size.pasteboardLeft - size.width / 4,
    y: size.height / 2,
  );
  final onThePasteboard = CanvasPoint(
    x: -size.width / 4,
    y: size.height / 2,
  );

  testWidgets('a fill pressed beyond the wall asks for no cel', (
    tester,
  ) async {
    final asked = await standOnAnEmptyCell(tester, CanvasTool.fill);

    await pressAt(tester, onScreen(tester, beyondTheWall));

    expect(asked, isEmpty, reason: 'the fill does nothing there');
  });

  testWidgets('inside the wall — off the paper, on the pasteboard — it '
      'does', (tester) async {
    final asked = await standOnAnEmptyCell(tester, CanvasTool.fill);

    await pressAt(tester, onScreen(tester, onThePasteboard));

    expect(asked, hasLength(1), reason: 'a fill reaches the pasteboard');
  });

  testWidgets('the wall is the fill\'s alone: a brush pressed beyond it '
      'still asks, since its stroke can come inside', (tester) async {
    final asked = await standOnAnEmptyCell(tester, CanvasTool.brush);

    await pressAt(tester, onScreen(tester, beyondTheWall));

    expect(asked, hasLength(1));
  });
}

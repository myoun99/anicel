import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/device_viewport.dart';

/// 🚨★★★THE WAY OUT CANNOT LEAVE THE SCREEN (유저 2026-09-22) — and a pill
/// under a panel, or under the panel's own capsules, has left it. The box's
/// ✓/✕ keep out from under what lies on the floor and what stands on the
/// panel's edges, however far the box reaches past them.
void main() {
  const panelSize = Size(900, 420);
  // A timeline lying on the floor's bottom edge.
  const timeline = EdgeInsets.only(bottom: 140);

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey<String>(key)));

  /// The panel with a box open that reaches far past its bottom edge.
  Future<void> openTallBox(WidgetTester tester, {required bool onFloor}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    coordinator.commitSourceStroke(
      sourceDabs: [
        for (final at in const [30.0, 45.0, 60.0])
          BrushDab(
            center: CanvasPoint(x: at, y: at),
            color: 0xFFFF0000,
            size: 4,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: 0,
          ),
      ],
    );
    final brush = ValueNotifier(
      BrushToolState.defaults.copyWith(tool: CanvasTool.move),
    );
    addTearDown(brush.dispose);
    final commands = CanvasSelectionCommands();
    final panel = BrushCanvasPanel(
      coordinator: coordinator,
      availableFrameKeys: frameKeys,
      cacheInvalidationSink: BrushEditCacheInvalidationSink(),
      historyManager: HistoryManager(),
      brushToolState: brush,
      selectionCommands: commands,
      viewport: seedFromRender(tester, CanvasViewport()),
      floorCover: onFloor ? timeline : EdgeInsets.zero,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: panelSize,
              child: onFloor
                  ? CanvasFloorInsets(insets: timeline, child: panel)
                  : panel,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    commands.setRegion(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 20, top: 20, right: 300, bottom: 900),
      ),
    );
    await tester.pump();
    commands.beginTransform();
    await tester.pump();
    expect(commands.transformActive, isTrue, reason: '⛔전제: 상자가 열림');
  }

  testWidgets('on the floor: over the timeline lying there, and over the '
      'horizontal bar\'s capsule', (tester) async {
    await openTallBox(tester, onFloor: true);
    final panel = rectOf(tester, 'canvas-editor-panel-shell');
    final pill = rectOf(tester, 'selection-confirm-pill');
    expect(
      pill.bottom,
      lessThanOrEqualTo(panel.bottom - timeline.bottom),
      reason: '⛔타임라인 밑에 숨은 알약은 누를 수 없다',
    );
    expect(
      pill.bottom,
      lessThanOrEqualTo(rectOf(tester, 'canvas-panbar-horizontal').top),
      reason: '⛔가로 스크롤바 알약 밑에 숨은 알약도',
    );
    expect(
      pill.top,
      greaterThanOrEqualTo(rectOf(tester, 'canvas-view-pill').bottom),
      reason: '…and it keeps under the view pill\'s band',
    );
  });

  testWidgets('docked: over the panel\'s own bottom lane', (tester) async {
    await openTallBox(tester, onFloor: false);
    expect(
      rectOf(tester, 'selection-confirm-pill').bottom,
      lessThanOrEqualTo(rectOf(tester, 'canvas-panbar-horizontal').top),
    );
  });
}

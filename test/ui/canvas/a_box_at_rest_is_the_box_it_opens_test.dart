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
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/box_chrome.dart';
import 'package:anicel/src/ui/canvas/selection_ants_painter.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart'
    show InputInspectorHost;

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/device_viewport.dart';

/// The Transform tool's box before anything has opened it is the box that
/// opens: the same pill under it, the same handles on it, in every mode.
///
/// 🗣️F-585 (유저 2026-11-12): 「변형도구 아래 알약, 변형의 값이
/// 바껴야(변형시작해야) 뜨는데, 그냥 변형도구상태면 뜨도록. 대신 값이
/// 안바뀐상태면 확정/취소버튼 존재는 하되 비활성화」.
///
/// 🗣️F-586 (유저 2026-11-12): 「매쉬변형, 변형시작해야 내부 사각형들 뜨는데,
/// 그냥 매쉬변형인 상태면 뜨도록. 변형안한상태로 그것들 잡아끌어서
/// 변형한다는게 안되는게 이유.」
void main() {
  const pill = ValueKey<String>('selection-confirm-pill');
  const confirm = 'selection-move-confirm';
  const cancel = 'selection-move-cancel';
  const pillButtons = [
    'selection-move-anti-alias',
    'selection-move-flip-horizontal',
    'selection-move-flip-vertical',
    confirm,
    cancel,
  ];
  const layerKey = ValueKey<String>('canvas-selection-layer');

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFFFF0000,
    size: 4,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  // 60×60 and far enough in that the pill under it is on the view whole.
  // Under 메쉬's 3×3 grid its points stand 20 apart, the first one inside
  // at (320,220).
  final square = CanvasSelectionRegion.shape(
    CanvasSelectionShape([
      CanvasPoint(x: 300, y: 200),
      CanvasPoint(x: 360, y: 200),
      CanvasPoint(x: 360, y: 260),
      CanvasPoint(x: 300, y: 260),
    ]),
  );
  const firstInside = 5;

  /// The Transform tool in hand over a cel with ink under [square] — or
  /// with none at all — and, when [selected], [square] selected.
  Future<CanvasSelectionCommands> pumpTransformTool(
    WidgetTester tester, {
    TransformMode mode = TransformMode.normal,
    bool selected = true,
    bool inked = true,
  }) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    if (inked) {
      coordinator.commitSourceStroke(
        sourceDabs: [dab(310, 210), dab(330, 230), dab(350, 250)],
      );
    }
    final commands = CanvasSelectionCommands();
    final transform = ValueNotifier(TransformToolOptions(mode: mode));
    final brush = ValueNotifier(
      BrushToolState.defaults.copyWith(tool: CanvasTool.move),
    );
    addTearDown(transform.dispose);
    addTearDown(brush.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: InputInspectorHost(
          child: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              canvasSize: BrushCanvasFixture.canvasSize,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              historyManager: HistoryManager(),
              brushToolState: brush,
              selectionCommands: commands,
              // One canvas pixel a screen pixel: a point of the box is its
              // own place on the layer.
              viewport: seedFromRender(tester, CanvasViewport()),
              transformOptions: transform,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (selected) {
      // The channel tells the layer in a microtask: a frame later.
      commands.setRegion(square);
      await tester.pump();
      await tester.pump();
    }
    return commands;
  }

  /// The box as the layer draws it.
  SelectionTransformChrome? chromeOnScreen(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byKey(layerKey),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((paint) => paint.painter)
      .whereType<SelectionAntsPainter>()
      .first
      .transformChrome;

  VoidCallback? pressOf(WidgetTester tester, String key) =>
      tester.appIconButton(find.byKey(ValueKey<String>(key))).onPressed;

  Future<void> dragOnLayer(WidgetTester tester, Offset from, Offset to) async {
    final origin = tester.getTopLeft(find.byKey(layerKey));
    final gesture = await tester.startGesture(origin + from);
    await tester.pump();
    await gesture.moveTo(origin + to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  for (final selected in [true, false]) {
    final over = selected ? 'a selection' : 'the whole picture';

    testWidgets('the Transform tool\'s box over $over wears its pill before '
        'any transform begins — 확정 and 취소 there, and grey', (tester) async {
      final commands = await pumpTransformTool(tester, selected: selected);
      expect(commands.transformActive, isFalse, reason: 'nothing has opened');

      for (final key in pillButtons) {
        expect(
          find.descendant(
            of: find.byKey(pill),
            matching: find.byKey(ValueKey<String>(key)),
          ),
          findsOneWidget,
          reason: key,
        );
      }
      expect(pressOf(tester, confirm), isNull, reason: 'nothing to land');
      expect(pressOf(tester, cancel), isNull, reason: 'nothing to take back');
      expect(
        pressOf(tester, 'selection-move-flip-horizontal'),
        isNotNull,
        reason: 'a flip is a transform beginning',
      );
    });

    for (final mode in TransformMode.values) {
      testWidgets('at rest over $over the box wears what it opens with in '
          '$mode — its outline, its handles, its cross, and the pill where '
          'it will stand', (tester) async {
        final commands = await pumpTransformTool(
          tester,
          mode: mode,
          selected: selected,
        );
        final atRest = chromeOnScreen(tester)!;
        final pillAtRest = tester.getRect(find.byKey(pill));
        expect(commands.transformActive, isFalse, reason: 'the premise');

        commands.beginTransform();
        await tester.pump();
        expect(commands.transformActive, isTrue, reason: 'the premise');

        final open = chromeOnScreen(tester)!;
        expect(atRest.handles, open.handles);
        expect(atRest.box, open.box);
        expect(atRest.anchor, open.anchor);
        expect(tester.getRect(find.byKey(pill)), pillAtRest);
      });
    }
  }

  testWidgets('a 메쉬 box at rest shows its grid, the points inside it '
      'included', (tester) async {
    await pumpTransformTool(tester, mode: TransformMode.mesh);
    final handles = chromeOnScreen(tester)!.handles;
    expect(handles, hasLength(16), reason: '3×3 cells: 4×4 points, no grips');
    expect(
      (handles[firstInside] - const Offset(320, 220)).distance,
      lessThan(0.01),
    );
  });

  testWidgets('a point inside a 메쉬 grid is dragged from rest — the press '
      'opens the box and carries that point alone', (tester) async {
    final commands = await pumpTransformTool(tester, mode: TransformMode.mesh);
    final atRest = chromeOnScreen(tester)!.handles;

    await dragOnLayer(tester, const Offset(320, 220), const Offset(326, 215));

    expect(commands.transformActive, isTrue, reason: 'the press opened it');
    final dragged = chromeOnScreen(tester)!.handles;
    expect(
      (dragged[firstInside] - const Offset(326, 215)).distance,
      lessThan(0.01),
      reason: 'the point went with the hand',
    );
    expect(
      [
        for (var index = 0; index < dragged.length; index += 1)
          if (index != firstInside) dragged[index],
      ],
      [
        for (var index = 0; index < atRest.length; index += 1)
          if (index != firstInside) atRest[index],
      ],
      reason: 'every other point where it stood',
    );
    expect(pressOf(tester, confirm), isNotNull, reason: 'a change to land');
    expect(pressOf(tester, cancel), isNotNull, reason: 'and to take back');
  });

  testWidgets('a box opened and left as it opened keeps 취소 grey, and 취소 '
      'after a change leaves the pill standing with both grey again', (
    tester,
  ) async {
    final commands = await pumpTransformTool(tester);
    commands.beginTransform();
    await tester.pump();
    expect(commands.transformActive, isTrue, reason: 'the premise');
    expect(pressOf(tester, cancel), isNull, reason: 'nothing changed');

    commands.editTransformValues((now) => now.copyWith(tx: 12));
    await tester.pump();
    expect(pressOf(tester, cancel), isNotNull, reason: 'a change');

    await tester.tap(find.byKey(const ValueKey<String>(cancel)));
    await tester.pump();
    expect(commands.transformActive, isFalse, reason: '취소 closed the box');
    expect(find.byKey(pill), findsOneWidget, reason: 'the pill does not go');
    expect(pressOf(tester, confirm), isNull);
    expect(pressOf(tester, cancel), isNull);
  });

  testWidgets('over a cel with no picture the pill stands with every verb '
      'grey', (tester) async {
    final commands = await pumpTransformTool(
      tester,
      selected: false,
      inked: false,
    );
    expect(commands.transformActive, isFalse);
    expect(find.byKey(pill), findsOneWidget);
    for (final key in [
      'selection-move-flip-horizontal',
      'selection-move-flip-vertical',
      confirm,
      cancel,
    ]) {
      expect(pressOf(tester, key), isNull, reason: key);
    }
  });
}

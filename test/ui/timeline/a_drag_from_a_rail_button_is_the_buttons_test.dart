import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart' show LayerFxState;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/scrollable_of.dart';
import '../../helpers/timeline_host.dart';

/// A toggle column of the rail: the name its button wears on a row, what it
/// reads there, and whether turning it lays rows of its own under the row
/// (a lane twirl) — which slides the rows a sweep goes on to cross.
typedef _Column = ({
  String button,
  bool Function(EditorSessionManager s, LayerId id) on,
  bool laysRows,
});

/// 🚨F-475 (유저 2026-10-26) — A DRAG THAT STARTS ON A RAIL BUTTON IS THAT
/// BUTTON'S, IN EVERY DIRECTION, ON EVERY DEVICE:
///
/// > 「레이어에서 특정 버튼을 클릭-드래그할때 드래그를 옆으로 시작하면
/// > 스크롤이 발동됨. 클리핑버튼은 좌우로하면 정상적으로 스크롤 발동안되고,
/// > 아래로하면 드래그로 여러조작이 안됨. 비지블이나 어니언은 좌우로하면
/// > 위아래 스크롤이 발동되버리고 아래로 드래그 여러조작 가능. 법 하나로
/// > 통일하고 몇번이나 말하는지 모르겟지만 버튼에서 시작한 조작은 스크롤을
/// > 발동시키지않음. 법 하나로 통일한단건 클리핑버튼도 위아래 드래그로 여러
/// > 버튼 동시조작 가능하게하란거. 다른버튼도 조사」
///
/// So every toggle column answers the two drags alike: down the rail it
/// sweeps the column (I-1), any other way it does nothing past its own
/// press — and the rail scrolls under neither.
void main() {
  // The claim sets are global, and a sweep that ends without its release
  // would leave the next case's pointer read as already claimed.
  tearDown(debugClearValueControlPointers);

  // One finger moves the view: the mode in which a finger is NOT an edit
  // pointer on the timeline (결정 10) — and still a button's, once it lands
  // on one.
  setUp(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.navigate,
    );
  });
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  Project project() => Project(
    id: const ProjectId('f475'),
    name: 'F-475',
    createdAt: DateTime.utc(2026, 10, 27),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'C',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              for (var i = 0; i < 14; i += 1)
                Layer(id: LayerId('l$i'), name: 'L$i', frames: const []),
            ],
          ),
        ],
      ),
    ],
  );

  Future<EditorSessionManager> pump(WidgetTester tester) =>
      pumpTimelineHost(tester, project(), surface: const Size(870, 446));

  Layer layerOf(EditorSessionManager s, LayerId id) =>
      s.requireActiveCut.layers.firstWhere((layer) => layer.id == id);

  final columns = <_Column>[
    (
      button: 'timeline-layer-visibility',
      on: (s, id) => layerOf(s, id).isVisible,
      laysRows: false,
    ),
    (
      button: 'timeline-layer-onion',
      on: (s, id) => s.onionSkin.layerIds.value.contains(id),
      laysRows: false,
    ),
    (
      button: 'timeline-layer-fx',
      on: (s, id) => s.effectsAndFx.layerFxState(id) == LayerFxState.on,
      laysRows: false,
    ),
    (
      button: 'timeline-layer-clip',
      on: (s, id) => layerOf(s, id).clipsToBelow,
      laysRows: false,
    ),
    (
      button: 'timeline-layer-timesheet',
      on: (s, id) => layerOf(s, id).onTimesheet,
      laysRows: false,
    ),
    (
      button: 'timeline-lane-toggle',
      on: (s, id) => s.layerSwitches.isLayerLanesOpen(id),
      laysRows: true,
    ),
  ];

  ScrollController rows(WidgetTester tester) => scrollableOf(
    tester,
    find.byKey(const ValueKey<String>('timeline-vertical-scroll-viewport')),
  ).controller!;

  Map<LayerId, bool> read(EditorSessionManager s, _Column column) => {
    for (final layer in s.requireActiveCut.layers)
      layer.id: column.on(s, layer.id),
  };

  /// The layers whose [column] reads differently from [before].
  List<String> changedSince(
    EditorSessionManager s,
    _Column column,
    Map<LayerId, bool> before,
  ) => [
    for (final MapEntry(key: id, value: was) in before.entries)
      if (column.on(s, id) != was) id.value,
  ];

  /// A drag of [steps] from [from]; with [frameAfterPress] false its first
  /// move comes in the press's own frame, before anything is built again.
  Future<void> drag(
    WidgetTester tester,
    Offset from,
    PointerDeviceKind kind,
    List<Offset> steps, {
    bool frameAfterPress = true,
  }) async {
    final gesture = await tester.startGesture(from, kind: kind);
    if (frameAfterPress) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (final step in steps) {
      await gesture.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Sideways, and a little up: the first move is level — a mouse's
  /// scroller takes a pixel — and the rest climb less than a pen's slop.
  const sideways = [
    Offset(12, 0),
    Offset(12, -6),
    Offset(12, -6),
    Offset(12, -6),
  ];

  testWidgets('⛔CONTROL — a finger pulled up off the buttons scrolls the '
      'rows, so the measure sees a scroll where there is one', (tester) async {
    await pump(tester);
    final scroll = rows(tester);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await drag(
      tester,
      tester.getCenter(find.named('timeline-layer-name-l13')),
      PointerDeviceKind.touch,
      const [Offset(0, -30), Offset(0, -30), Offset(0, -30)],
    );
    expect(scroll.offset, greaterThan(0));
  });

  for (final kind in const [
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
  ]) {
    for (final column in columns) {
      testWidgets('${kind.name} on ${column.button}: sideways does nothing '
          'past its press, down sweeps the column — and neither scrolls', (
        tester,
      ) async {
        final s = await pump(tester);
        final scroll = rows(tester);
        final pressed = find.named('${column.button}-l13');
        expect(pressed, findsOneWidget, reason: 'premise: the button');
        final rowAt = tester.getRect(find.named('timeline-layer-row-l13'));

        var before = read(s, column);
        await drag(tester, tester.getCenter(pressed), kind, sideways);
        expect(scroll.offset, 0, reason: 'sideways from a button scrolled');
        expect(
          tester.getRect(find.named('timeline-layer-row-l13')),
          rowAt,
          reason: 'the row moved under a drag that began on its button',
        );
        expect(
          changedSince(s, column, before),
          ['l13'],
          reason:
              'the press acts on its own row, and a drag across the rail '
              'sweeps nothing',
        );

        before = read(s, column);
        final rowHeight = tester
            .getRect(find.named('timeline-layer-row-l12'))
            .height;
        await drag(
          tester,
          tester.getCenter(find.named('${column.button}-l12')),
          kind,
          [Offset(0, rowHeight), Offset(0, rowHeight)],
        );
        expect(scroll.offset, 0, reason: 'down from a button scrolled');
        final swept = changedSince(s, column, before);
        if (column.laysRows) {
          // A twirl opening lays its lanes under its row, so the rows the
          // finger goes on to cross slide down by them.
          expect(swept, contains('l12'));
          expect(swept.length, greaterThan(1), reason: 'the sweep went on');
        } else {
          expect(
            swept,
            unorderedEquals(['l12', 'l11', 'l10']),
            reason:
                '유저: 「클리핑버튼도 위아래 드래그로 여러 버튼 동시조작」 '
                '— the press, and the rows the sweep crossed',
          );
        }
      });
    }
  }

  // The sweep begins on the FIRST move and spreads what the press wrote, so
  // it reads the row as the press left it — which no frame has shown yet
  // when a fast pen's first move shares the press's frame. Every column
  // reads LIVE for that ([RailColumnSwipe]'s `_start`); a column that read
  // the row it was built with would latch the old value and sweep nothing.
  for (final column in columns.where((column) => !column.laysRows)) {
    testWidgets('${column.button}: a first move in the press\'s own frame '
        'sweeps the column too', (tester) async {
      final s = await pump(tester);
      final before = read(s, column);
      final rowHeight = tester
          .getRect(find.named('timeline-layer-row-l12'))
          .height;
      await drag(
        tester,
        tester.getCenter(find.named('${column.button}-l12')),
        PointerDeviceKind.stylus,
        [Offset(0, rowHeight), Offset(0, rowHeight)],
        frameAfterPress: false,
      );
      expect(
        changedSince(s, column, before),
        unorderedEquals(['l12', 'l11', 'l10']),
      );
    });
  }
}

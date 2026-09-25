// ONE SWEEP IS ONE UNDO (swipe-is-one-undo).
//
// 유저 2026-08-28: 「일괄로 버튼 조작하고 언두하면 바꼈던 레이어들 다 한번에
// 언두되야하는데 안됨」 — and 「일괄조작」 is what 유저 named this swipe on
// 08-24 (I-1). Measured before the fold: three rows swept down the eye
// column made three steps, and one Ctrl+Z took back one row.
//
// Each case makes an unrelated edit FIRST, and the counter-assertion is
// that it survives the one undo: a fold that reached one entry too far
// would take it back too. The storyboard case starts on a V row's eye,
// whose press writes NO step while the rows it crosses do — the case a
// fold counted back from the sweep's own writes gets wrong.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show LayerVisibilityToggleButton;

void main() {
  // The claim set is global: a sweep that ends without its release leaves
  // the pointer claimed for the next case.
  tearDown(debugClearValueControlPointers);

  testWidgets('a sweep down the timeline rail\'s eyes is one undo — and the '
      'edit before it is not part of it', (tester) async {
    final s = await _timeline(tester);
    const earlier = LayerId('l0');
    final sheetWas = _row(s, earlier).onTimesheet;
    s.layerSwitches.toggleLayerTimesheet(earlier);

    await _sweep(
      tester,
      from: find.byKey(const ValueKey<String>('timeline-layer-visibility-l4')),
      to: find.byKey(const ValueKey<String>('timeline-layer-visibility-l2')),
    );
    expect(
      _eyes(s, const ['l4', 'l3', 'l2']),
      [false, false, false],
      reason: 'the premise: the sweep hid three rows',
    );

    s.undo();
    await tester.pumpAndSettle();

    expect(
      _eyes(s, const ['l4', 'l3', 'l2']),
      [true, true, true],
      reason: 'ONE undo takes back the whole sweep',
    );
    expect(
      _row(s, earlier).onTimesheet,
      !sheetWas,
      reason: 'the edit before the sweep is its own step',
    );
    s.undo();
    expect(_row(s, earlier).onTimesheet, sheetWas);
  });

  testWidgets('a sweep that starts on a storyboard V row\'s eye — a press '
      'that writes no step — folds only what the sweep wrote', (tester) async {
    final s = await _storyboard(tester);
    const earlier = LayerId('t1-s1');
    final sheetWas = _row(s, earlier).onTimesheet;
    s.layerSwitches.toggleLayerTimesheet(earlier);
    final before = s.historyManager.undoCount;

    await _sweep(
      tester,
      from: find.byKey(
        const ValueKey<String>('storyboard-cut-visibility-t1-cut'),
      ),
      to: find.byKey(
        const ValueKey<String>('storyboard-cut-visibility-t3-cut'),
      ),
    );
    expect(
      _eyes(s, const ['t2-s1', 't3-s1']),
      [false, false],
      reason: 'the premise: the sweep crossed two tracks\' S rows',
    );
    expect(
      s.historyManager.undoCount,
      before + 1,
      reason: 'what the sweep wrote is one entry',
    );

    s.undo();
    await tester.pumpAndSettle();

    expect(
      _eyes(s, const ['t2-s1', 't3-s1']),
      [true, true],
    );
    expect(
      _row(s, earlier).onTimesheet,
      !sheetWas,
      reason:
          'the V row\'s eye wrote nothing, so a fold counting one step back '
          'from the sweep would have swallowed this edit',
    );
  });

  // F-182 (유저 2026-09-25): 「레이어 라벨 버튼 드래그 일괄조작, 원래 위치로
  // 돌아가면 원복하도록. 지금은 커서 원래 위치로 돌아가도 원복안됨. 언두는
  // 지금처럼 동일하게 손 떼면 1언두」.
  group('drawing back', () {
    testWidgets('to the press puts every row back — the pressed row keeps '
        'its press, and the release is one undo of it', (tester) async {
      final s = await _timeline(tester);
      final depth = s.historyManager.undoCount;
      final hold = await _press(tester, 'visibility', 'l4');

      await hold.to('l1');
      expect(
        _eyes(s, const ['l4', 'l3', 'l2', 'l1']),
        [false, false, false, false],
        reason: 'the premise: four rows swept',
      );
      await hold.to('l4');
      expect(
        _eyes(s, const ['l4', 'l3', 'l2', 'l1']),
        [false, true, true, true],
        reason: '「원래 위치로 돌아가면 원복」 — the press is not the sweep\'s',
      );
      expect(
        [
          for (final id in const ['l4', 'l3', 'l2', 'l1'])
            tester
                .widget<LayerVisibilityToggleButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is LayerVisibilityToggleButton &&
                        widget.keyValue == 'timeline-layer-visibility-$id',
                  ),
                )
                .isVisible,
        ],
        [false, true, true, true],
        reason: 'and the rail SHOWS it while the hand is still down',
      );
      await hold.release();

      expect(s.historyManager.undoCount, depth + 1);
      s.undo();
      await tester.pumpAndSettle();
      expect(
        _eyes(s, const ['l4', 'l3', 'l2', 'l1']),
        [true, true, true, true],
      );
      expect(
        s.historyManager.redoCount,
        1,
        reason: 'the rows drawn back from are gone, not waiting to be redone',
      );
    });

    testWidgets('upward too — the rows go back from the far end', (
      tester,
    ) async {
      final s = await _timeline(tester);
      final hold = await _press(tester, 'visibility', 'l0');

      await hold.to('l3');
      expect(
        _eyes(s, const ['l0', 'l1', 'l2', 'l3']),
        [false, false, false, false],
        reason: 'the premise: the rail draws l0 at the bottom',
      );
      await hold.to('l2');
      expect(
        _eyes(s, const ['l0', 'l1', 'l2', 'l3']),
        [false, false, false, true],
      );
      await hold.release();
    });

    testWidgets('a hand that skips rows going up gives back the far one '
        'first', (tester) async {
      final s = await _timeline(tester);
      final hold = await _press(tester, 'visibility', 'l0');

      await hold.to('l1');
      // One pointer move across two rows — a fast hand does this. The rows
      // it skipped are painted from the press outward, so the farthest is
      // the first to go back.
      await hold.jump('l3');
      expect(
        _eyes(s, const ['l0', 'l1', 'l2', 'l3']),
        [false, false, false, false],
        reason: 'the premise',
      );
      await hold.to('l2');
      expect(
        _eyes(s, const ['l0', 'l1', 'l2', 'l3']),
        [false, false, false, true],
      );
      await hold.release();
    });

    testWidgets('halfway keeps the rows still under the stretch', (
      tester,
    ) async {
      final s = await _timeline(tester);
      final hold = await _press(tester, 'visibility', 'l4');

      await hold.to('l1');
      await hold.to('l3');
      expect(
        _eyes(s, const ['l4', 'l3', 'l2', 'l1']),
        [false, false, true, true],
      );
      await hold.release();

      s.undo();
      await tester.pumpAndSettle();
      expect(
        _eyes(s, const ['l4', 'l3', 'l2', 'l1']),
        [true, true, true, true],
        reason: '1언두 — the press and every row still held',
      );
    });

    testWidgets('a MIXED fx row comes back mixed, not on', (tester) async {
      final s = await _timeline(tester);
      const mixed = LayerId('l3');
      s.selectLayer(mixed);
      s.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
      s.effectsAndFx.toggleLayerTransformFx(mixed);
      await tester.pumpAndSettle();
      expect(
        s.effectsAndFx.layerFxState(mixed),
        LayerFxState.mixed,
        reason: 'the premise',
      );
      final hold = await _press(tester, 'fx', 'l4');

      await hold.to('l2');
      expect(
        s.effectsAndFx.layerFxState(mixed),
        LayerFxState.off,
        reason: 'the premise: the sweep turned it off',
      );
      await hold.to('l4');

      expect(
        s.effectsAndFx.layerFxState(mixed),
        LayerFxState.mixed,
        reason:
            'pressing it again would have turned it ON — its own step is '
            'taken back instead',
      );
      await hold.release();
    });

    testWidgets('a control with no history comes back too — the onion', (
      tester,
    ) async {
      final s = await _timeline(tester);
      bool onion(String id) =>
          s.onionSkin.isLayerOnionSkinEnabled(LayerId(id));
      final hold = await _press(tester, 'onion', 'l4');

      await hold.to('l2');
      expect(
        [onion('l4'), onion('l3'), onion('l2')],
        [true, true, true],
        reason: 'the premise',
      );
      await hold.to('l4');
      await hold.release();

      expect([onion('l4'), onion('l3'), onion('l2')], [true, false, false]);
    });
  });
}

/// A press held on row [row]'s [column] button of the timeline rail, moved
/// row to row along the same column.
Future<_Hold> _press(
  WidgetTester tester,
  String column,
  String row,
) async {
  Offset centreOf(String row) => tester.getCenter(
    find.byKey(ValueKey<String>('timeline-layer-$column-$row')),
  );
  var at = centreOf(row);
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 16));
  Future<void> to(String row) async {
    final target = centreOf(row);
    for (var step = 1; step <= 4; step += 1) {
      await gesture.moveTo(Offset.lerp(at, target, step / 4)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    at = target;
  }

  Future<void> jump(String row) async {
    at = centreOf(row);
    await gesture.moveTo(at);
    await tester.pump(const Duration(milliseconds: 16));
  }

  Future<void> release() async {
    await gesture.up();
    await tester.pumpAndSettle();
  }

  return (to: to, jump: jump, release: release);
}

Layer _row(EditorSessionManager s, LayerId id) =>
    requireLayerAnywhere(s.repository.requireProject(), id);

/// Presses [from] and drags to [to] in small steps, so every row between is
/// crossed.
Future<void> _sweep(
  WidgetTester tester, {
  required Finder from,
  required Finder to,
}) async {
  final start = tester.getCenter(from);
  final end = tester.getCenter(to);
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 16));
  for (var step = 1; step <= 6; step += 1) {
    await gesture.moveTo(Offset.lerp(start, end, step / 6)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The app's own workspace over five plain rows, the timeline dock opened.
Future<EditorSessionManager> _timeline(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: Project(
          id: const ProjectId('sweep'),
          name: 'Sweep',
          createdAt: DateTime.utc(2026, 9, 25),
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
                    for (var i = 0; i < 5; i += 1)
                      Layer(id: LayerId('l$i'), name: 'L$i', frames: const []),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -320),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

/// The storyboard tab over three tracks, each with one S row.
Future<EditorSessionManager> _storyboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Track track(String id) => Track(
    id: TrackId(id),
    name: id,
    seLayers: [
      Layer(
        id: LayerId('$id-s1'),
        name: 'S1',
        kind: LayerKind.se,
        frames: const [],
        timeline: const {},
      ),
    ],
    cuts: [
      Cut(
        id: CutId('$id-cut'),
        name: '$id cut',
        duration: 12,
        canvasSize: const CanvasSize(width: 640, height: 360),
        layers: [
          Layer(
            id: LayerId('$id-cel'),
            name: 'A',
            frames: const [],
            timeline: const {},
          ),
        ],
      ),
    ],
  );
  final s = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('sweep'),
      name: 'Sweep',
      createdAt: DateTime.utc(2026, 9, 25),
      tracks: [track('t1'), track('t2'), track('t3')],
    ),
  );
  addTearDown(s.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: s,
          builder: (context, _) => StoryboardTabHost(
            session: s,
            pixelsPerFrame: 12,
            onPixelsPerFrameChanged: (_) {},
            showSeconds: false,
            onShowSecondsChanged: (_) {},
            thumbnailFor: null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

List<bool> _eyes(EditorSessionManager s, List<String> ids) => [
  for (final id in ids) _row(s, LayerId(id)).isVisible,
];

/// A held press: move it to another row of its column — row by row, or in
/// one pointer move — or let go.
typedef _Hold = ({
  Future<void> Function(String row) to,
  Future<void> Function(String row) jump,
  Future<void> Function() release,
});

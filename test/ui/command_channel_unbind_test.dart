import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/canvas_view_commands.dart';
import 'package:anicel/src/ui/canvas/flip_hud_controller.dart';
import 'package:anicel/src/ui/canvas/flip_hud_model.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_nav.dart';

/// 🚨★★★ 유저 피드백 #13 (2026-08-14): 「언제부턴가 **화살표 위아래나 플립
/// 위아래로 레이어이동이 안먹힘**」.
///
/// Two different inputs dying together is the clue: they do not share a
/// gesture or a key, they share a CHANNEL — the imperative bind/unbind pair
/// the workspace uses to hand its handlers up to the app shell.
///
/// ★The shape: `unbind()` clears unconditionally. Whenever the workspace is
/// rebuilt in a way that mounts the new State before disposing the old one
/// — which is what a panel moving between docks does — the order is
///
///   old.bind → new.bind → **old.dispose → unbind()**
///
/// and that last step nulls the handler the LIVE workspace just installed.
/// Nothing throws, nothing logs; the shortcut simply stops answering, which
/// is exactly 「언제부턴가 안먹힘」.
///
/// ⚠️All four channels carry it, so the fix is one law rather than four
/// patches: **a handler may only be removed by whoever installed it.**
void main() {
  test('layer nav — a stale owner\'s unbind leaves the live handler alone', () {
    final nav = TimelineLayerNavCommands();
    final calls = <String>[];
    final oldWorkspace = Object();
    final newWorkspace = Object();

    nav.bind(oldWorkspace, (_) => calls.add('old'));
    nav.bind(newWorkspace, (_) => calls.add('new'));
    nav.unbind(oldWorkspace);

    nav.step(-1);
    expect(calls, ['new']);
  });

  test('layer nav — the live owner CAN still unbind itself', () {
    final nav = TimelineLayerNavCommands();
    final calls = <String>[];
    final owner = Object();

    nav.bind(owner, (_) => calls.add('live'));
    nav.unbind(owner);

    nav.step(-1);
    expect(calls, isEmpty, reason: 'a real teardown must still tear down');
  });

  test('flip HUD — same channel, same law', () {
    final hud = FlipHudController();
    final oldWorkspace = Object();
    final newWorkspace = Object();
    FlipHudSnapshot snapshot(int mark) => FlipHudSnapshot(
      rows: const <FlipHudRow>[],
      rowIndex: mark,
      frameIndex: 0,
      frameCount: 1,
    );

    hud.bind(oldWorkspace, (_) => snapshot(1));
    hud.bind(newWorkspace, (_) => snapshot(2));
    hud.unbind(oldWorkspace);

    expect(hud.debugSnapshotFor(FlipHudAxis.row)?.rowIndex, 2);
  });

  test('canvas view commands — same channel, same law', () {
    final view = CanvasViewCommands();
    final calls = <String>[];
    final oldWorkspace = Object();
    final newWorkspace = Object();

    view.bind(
      oldWorkspace,
      rotateBy: (_) => calls.add('old'),
      toggleFlipHorizontal: () => calls.add('old'),
    );
    view.bind(
      newWorkspace,
      rotateBy: (_) => calls.add('new'),
      toggleFlipHorizontal: () => calls.add('new'),
    );
    view.unbind(oldWorkspace);

    view.rotateBy(90);
    expect(calls, ['new']);
  });

  test('canvas selection commands — same channel, same law', () {
    final selection = CanvasSelectionCommands();
    final calls = <String>[];
    final oldWorkspace = Object();
    final newWorkspace = Object();

    selection.bind(
      oldWorkspace,
      hasSelection: () => true,
      nudge: (_, _) => calls.add('old'),
      deselect: () {},
    );
    selection.bind(
      newWorkspace,
      hasSelection: () => true,
      nudge: (_, _) => calls.add('new'),
      deselect: () {},
    );
    selection.unbind(oldWorkspace);

    selection.nudge(1, 0);
    expect(calls, ['new']);
  });
}

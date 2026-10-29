// THE V ROWS TAKE A SPLITTER (유저 2026-09-25: 「그리고 동시에 슬슬 V트랙
// 위아래 스플리터 조절기능 넣자. 썸네일 크게보고싶을때용」). The app's one
// splitter rides the bottom edge of a V row's label and moves the ONE height
// every V row shares, inside its legal range — and the layout file keeps it
// the way it keeps the rail widths, absent while it is the default.
import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/project.dart' show defaultProjectCameraSize;
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/workspace_layout_store.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/collapsed_row_overlay.dart';

import '../../helpers/project_scratch_folder.dart';
import '../../helpers/settings_flyout.dart';
import '../../helpers/settle_async.dart';

const _default = StoryboardPanel.defaultTrackLaneHeight;
const _key = 'storyboardTrackLaneHeight';

Finder _splitters() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('storyboard-track-lane-splitter-');
});

Future<WorkspaceLayoutStore> _store(WidgetTester tester) async {
  // Real file IO only inside runAsync — awaited on the fake clock a
  // testWidgets body runs on, createTemp never completes.
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('v_row_splitter'),
  ))!;
  deleteAfterSessionEnds(directory);
  return WorkspaceLayoutStore(
    filePath: '${directory.path}/workspace_layout.json',
  );
}

Future<void> _openStoryboard(
  WidgetTester tester,
  WorkspaceLayoutStore store, {
  Size window = const Size(1600, 1000),
}) async {
  await tester.binding.setSurfaceSize(window);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: HomePage(layoutStore: store),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
}

/// Every V row's label height — one number, however many there are.
Set<double> _laneHeights(WidgetTester tester) {
  final labels = find.byType(StoryboardTrackLabelRow);
  return {
    for (var index = 0; index < labels.evaluate().length; index += 1)
      tester.getSize(labels.at(index)).height,
  };
}

/// The layout file once the debounced save has written what [wanted]
/// looks for — or, if it never does, the last file read.
Future<Map<String, Object?>?> _saved(
  WidgetTester tester,
  WorkspaceLayoutStore store,
  bool Function(Map<String, Object?> payload) wanted,
) async {
  // The save is debounced 800 ms behind the last change.
  await tester.pump(const Duration(milliseconds: 900));
  Map<String, Object?>? payload;
  await settleAsync(tester, () async {
    final read = await tester.runAsync<Map<String, Object?>?>(store.load);
    payload = read;
    return read != null && wanted(read);
  });
  return payload;
}

/// A mouse drag on the first V row's splitter — the mouse let go of after,
/// so a later hover (the settings drawer's) can bring its own.
Future<void> _dragSplitter(WidgetTester tester, double dy) async {
  final gesture = await tester.startGesture(
    tester.getCenter(_splitters().first),
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveBy(Offset(0, dy));
  await gesture.up();
  await gesture.removePointer();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dragging a V row\'s bottom edge moves the height every V row '
      'wears, and the layout file keeps it', (tester) async {
    final store = await _store(tester);
    await _openStoryboard(tester, store);
    expect(_laneHeights(tester), {_default}, reason: '⛔전제');
    final label = tester.getRect(find.byType(StoryboardTrackLabelRow).first);
    final splitter = tester.getRect(_splitters().first);
    expect(splitter.bottom, closeTo(label.bottom, 0.01), reason: 'its edge');
    // Let the save the tab switch scheduled land first — else it writes the
    // drag's height too, and the drag's own save is never asked for.
    final opened = await _saved(tester, store, (file) => true);
    expect(opened?[_key], isNull, reason: '⛔전제: the default is not written');

    await _dragSplitter(tester, 40);

    expect(_laneHeights(tester), {_default + 40});
    final saved = await _saved(tester, store, (file) => file[_key] != null);
    expect(saved?[_key], _default + 40);
  });

  test('🗣️the ceiling is the tallest row whose picture stays sharp: the '
      'camera frame\'s height in the screen\'s pixels, and the four bands '
      '(유저 2026-09-27: 「그림이 선명한 한 최대로(카메라 프레임 높이 + 띠)」)', () {
    const bands = StoryboardPanel.minTrackLaneHeight;
    const camera = CanvasSize(width: 1920, height: 1080);
    expect(StoryboardPanel.maxTrackLaneHeightFor(camera, 1), bands + 1080);
    expect(StoryboardPanel.maxTrackLaneHeightFor(camera, 2), bands + 540);
    expect(
      StoryboardPanel.clampTrackLaneHeight(9999, ceiling: bands + 540),
      bands + 540,
    );
    expect(
      StoryboardPanel.clampTrackLaneHeight(0, ceiling: bands + 540),
      bands,
      reason: 'the floor is the bands',
    );
  });

  testWidgets('the height stops at its legal range, and the hand pays back '
      'what ran past it before the edge moves again', (tester) async {
    await _openStoryboard(tester, await _store(tester));
    // The default project's camera on this screen.
    final ceiling = StoryboardPanel.maxTrackLaneHeightFor(
      defaultProjectCameraSize,
      tester.view.devicePixelRatio,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(_splitters().first),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(Offset(0, ceiling));
    await tester.pump();
    expect(_laneHeights(tester), {ceiling});

    // The hand ran the default height and twenty more past the ceiling;
    // back by the default alone it is still twenty past. (↩️`-100`, which
    // was short of the overrun only while the default was 96.)
    await gesture.moveBy(const Offset(0, -_default));
    await tester.pump();
    expect(
      _laneHeights(tester),
      {ceiling},
      reason: 'the hand is still past the edge it ran over',
    );
    await gesture.moveBy(const Offset(0, -1000));
    await tester.pump();
    expect(_laneHeights(tester), {StoryboardPanel.minTrackLaneHeight});
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();
  });

  /// The storyboard opened on a layout that keeps the V rows at [kept] —
  /// as a layout the app wrote on a bigger camera would — in a window tall
  /// enough to show a row at today's ceiling to its bottom edge, the bottom
  /// dock grown to hold it. Answers the ceiling.
  Future<double> openKeeping(WidgetTester tester, double kept) async {
    final store = await _store(tester);
    await _openStoryboard(tester, store);
    await _dragSplitter(tester, 40);
    final written = await _saved(tester, store, (file) => file[_key] != null);
    // Closed first: closing saves the layout it holds.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    // ⛔Not inside runAsync: this save queues behind the closing one, and
    // while that is still on the disk only a pump lands it — awaited in
    // runAsync, the test hung for its ten minutes under load.
    var landed = false;
    unawaited(
      store.save({...written!, _key: kept}).then((_) => landed = true),
    );
    await settleAsync(tester, () => landed);
    expect(landed, isTrue, reason: '⛔전제: the kept height is on the file');
    await _openStoryboard(tester, store, window: const Size(1600, 1800));
    await settleAsync(tester, () => _laneHeights(tester).first != _default);
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    return StoryboardPanel.maxTrackLaneHeightFor(
      defaultProjectCameraSize,
      tester.view.devicePixelRatio,
    );
  }

  testWidgets('a height kept above today\'s ceiling is drawn at the ceiling, '
      'by the rows and by the folded row alike', (tester) async {
    final ceiling = await openKeeping(tester, 5000);
    expect(_laneHeights(tester), {ceiling});

    await tester.tap(
      find.byKey(const ValueKey<String>('floating-bottom-collapse')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<CollapsedRowOverlay>(find.byType(CollapsedRowOverlay)),
      isA<CollapsedRowOverlay>().having((row) => row.height, 'height', ceiling),
    );
  });

  testWidgets('the splitter moves a height kept above the ceiling from where '
      'the rows are drawn, not from where it was kept', (tester) async {
    final ceiling = await openKeeping(tester, 5000);
    await _dragSplitter(tester, -40);
    expect(_laneHeights(tester), {ceiling - 40});
  });

  // ⚠️No arrangement saved is the factory one, and the workspace starts so
  // — a first read that finds none and lands late puts nothing back over
  // what the hand did meanwhile (I-142, 2026-10-30: the storyboard tab
  // this file's first test opens was taken away).
  testWidgets('a first read that finds no arrangement, landing late, leaves '
      'what the hand did meanwhile', (tester) async {
    final store = _HeldLayout(await _store(tester));
    await _openStoryboard(tester, store);
    await _dragSplitter(tester, 40);
    expect(_laneHeights(tester), {_default + 40}, reason: '⛔CONTROL');

    store.answer.complete(null);
    await tester.pumpAndSettle();

    expect(_laneHeights(tester), {_default + 40});
  });

  testWidgets('the next launch opens at the saved height, and a workspace '
      'reset forgets it — back to the default, off the file', (tester) async {
    final store = await _store(tester);
    await _openStoryboard(tester, store);
    await _dragSplitter(tester, 40);
    final before = await _saved(tester, store, (file) => file[_key] != null);
    expect(before?[_key], _default + 40, reason: '⛔전제');

    // The next launch: a fresh workspace over the same file.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await _openStoryboard(tester, store);
    await settleAsync(tester, () => _laneHeights(tester).first != _default);
    expect(_laneHeights(tester), {_default + 40});

    await tapPanelsDrawerRow(tester, 'menu-window-reset-layout');
    await tester.pumpAndSettle();
    // The reset puts the docks back too, the storyboard's tab with them.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    expect(_laneHeights(tester), {_default});
    final after = await _saved(tester, store, (file) => file[_key] == null);
    expect(
      after?.containsKey(_key),
      isFalse,
      reason: 'the default is absent from the file, like a rail never dragged',
    );
  });

  testWidgets('a pull that reaches the foot of the view pans the rows, and '
      'the edge stays under the hand — the one splitter pans the scroll it '
      'stands in, as a header graph\'s grip does (I-89 ③)', (tester) async {
    await _openStoryboard(tester, await _store(tester));
    // Tall enough that the view stops growing with the rows and scrolls —
    // by 4px, with the edge 4.5px short of the band where a drag pans.
    // ↩️150 while the bar under the rows stood 16: F-440 made it the thin
    // one, and the view took the 8 it left.
    await _dragSplitter(tester, 158);
    final viewport = find.byKey(
      const ValueKey<String>('storyboard-vertical-viewport'),
    );
    // The viewport's own scroll — the first below it.
    final rows = tester
        .stateList<ScrollableState>(
          find.descendant(of: viewport, matching: find.byType(Scrollable)),
        )
        .first
        .position;
    final view = tester.getRect(viewport);
    expect(rows.pixels, 0, reason: '⛔전제');
    expect(rows.maxScrollExtent, greaterThan(0), reason: '⛔전제: it scrolls');
    var hand = tester.getCenter(_splitters().first);
    expect(
      hand.dy,
      lessThan(view.bottom - 24),
      reason: '⛔전제: short of the band where a drag pans',
    );

    final gesture = await tester.startGesture(
      hand,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    hand = Offset(hand.dx, view.bottom - 20);
    await gesture.moveTo(hand);
    await tester.pump();
    for (var step = 0; step < 6; step += 1) {
      hand = hand.translate(0, 0.5);
      await gesture.moveTo(hand);
      await tester.pump();
    }
    expect(
      _laneHeights(tester).single,
      lessThan(
        StoryboardPanel.maxTrackLaneHeightFor(
          defaultProjectCameraSize,
          tester.view.devicePixelRatio,
        ),
      ),
      reason: '⛔전제: short of the ceiling, where the edge stops',
    );
    expect(rows.pixels, greaterThan(0), reason: 'the rows panned');
    expect(
      tester.getCenter(_splitters().first).dy,
      moreOrLessEquals(hand.dy, epsilon: 1),
      reason: 'the pan is folded into the pull — the edge did not slide off',
    );
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();
  });
}

/// [WorkspaceLayoutStore] whose first read waits for [answer] — what the
/// workspace reads once its arrangement has already changed.
class _HeldLayout extends WorkspaceLayoutStore {
  _HeldLayout(WorkspaceLayoutStore on) : super(filePath: on.filePath);

  final Completer<Map<String, Object?>?> answer = Completer();

  @override
  Future<Map<String, Object?>?> load() => answer.future;
}

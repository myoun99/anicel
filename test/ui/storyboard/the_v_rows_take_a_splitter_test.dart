// THE V ROWS TAKE A SPLITTER (유저 2026-09-25: 「그리고 동시에 슬슬 V트랙
// 위아래 스플리터 조절기능 넣자. 썸네일 크게보고싶을때용」). The app's one
// splitter rides the bottom edge of a V row's label and moves the ONE height
// every V row shares, inside its legal range — and the layout file keeps it
// the way it keeps the rail widths, absent while it is the default.
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

/// Real IO steps complete in real time and continue on the fake clock:
/// alternate the two until [done] holds.
Future<void> _settleIo(WidgetTester tester, bool Function() done) async {
  for (var tries = 0; tries < 40 && !done(); tries += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
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
  bool written() => payload != null && wanted(payload);
  for (var tries = 0; tries < 40 && !written(); tries += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    payload = await tester.runAsync<Map<String, Object?>?>(store.load);
  }
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

    await gesture.moveBy(const Offset(0, -100));
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
    await tester.runAsync(() => store.save({...written!, _key: kept}));
    await _openStoryboard(tester, store, window: const Size(1600, 1800));
    await _settleIo(tester, () => _laneHeights(tester).first != _default);
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
    await _settleIo(tester, () => _laneHeights(tester).first != _default);
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
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🚨★★★EVERY CHROME BUTTON CLAIMS ITS PRESS.
///
/// The law is in CLAUDE.md and 유저 has stated it three times — 2026-08-14
/// for sliders (「슬라이더위에서 조작하기 시작하면 슬라이더조작하는거고 **그
/// 외가 스크롤인거야**」), 08-28 for buttons, and 08-29:
///
/// > 「**터치 좌표가 버튼인데 거기서 움직였다고 스크롤이 발생하는게 심각한
/// > 버그야**」
///
/// #1349 taught `EagerPanGestureRecognizer` to decline a pointer that EITHER
/// claim holds. That does nothing for a button which makes no claim at all,
/// and on 2026-08-29 fifteen of them made none: the x-sheet's lane toggle,
/// folder twirl, fill-reference and onion; the lane rows' three toggles and
/// their shared button; the legend's flyout, lanes and mute; the storyboard's
/// two lane toggles; the top strip's blend lock; and the bar's 1·2·3·4·N.
///
/// ⛔THEY WERE NOT AN OVERSIGHT LIST. `AppIconButton` claimed on its own and
/// the rail had a wrapper called `RailControlPointer` — so the law was
/// wearable in exactly two places, and every surface that was neither went
/// without. The wrapper is [ControlPressClaim] in `ui/input/` now, and this
/// file is what keeps the next surface from being the sixteenth.
///
/// 🚨THE SCAN AND THE PRESSES ARE BOTH NEEDED. The presses prove the claim
/// actually lands through the real widget tree — a wrapper outside a baked
/// [StaticRaster] or a `Tooltip` could easily not. The scan reaches the
/// buttons no test can name, which is where the next one will be.
void main() {
  setUp(debugClearValueControlPointers);
  tearDown(debugClearValueControlPointers);

  /// The app's own chrome: bars, rails, strips, pills. Dialogs, pickers and
  /// the export screens are deliberately NOT here — a grid of swatches
  /// scrolls by dragging off a swatch, and taking that away is a change
  /// nobody asked for.
  const chrome = <String>[
    'lib/src/ui/timeline/layer_label_controls.dart',
    'lib/src/ui/timeline/timeline_layer_controls_row.dart',
    'lib/src/ui/timeline/timeline_layer_controls_header.dart',
    'lib/src/ui/timeline/timeline_lane_rows.dart',
    'lib/src/ui/timeline/timeline_action_toolbar.dart',
    'lib/src/ui/timeline/xsheet_timeline_grid.dart',
    'lib/src/ui/storyboard_panel.dart',
    'lib/src/ui/menu/editor_top_strip.dart',
  ];

  /// ⛔EACH ONE IS A DECISION, and the reason is the same question every
  /// time: 「is a drag that starts here a scroll, or this widget's own
  /// verb?」. Keyed by the widget's OWN key rather than a line number, which
  /// drifts the first time anything above it is edited.
  const notControls = <String, String>{
    // 🚨THE CLAIM WOULD BREAK IT. The lane value is AE-style scrubbable and
    // its scrub IS an `EagerPanGestureRecognizer` — the very recogniser that
    // reads the claim. Wrapping it would make the value decline its own
    // drag, which is the shape of H19: one flag answering two questions.
    '-lane-value-': 'its drag is its own verb (a scrub)',
    // The row BODY, not a control. The drag that starts here is the row
    // reorder — `storyboard-track-select-` is where the V row's move begins
    // (#1349), so a claim here would undo that round.
    'storyboard-se-label-': 'row body',
    'storyboard-transition-label-': 'row body',
    'storyboard-track-select-': 'row body',
  };

  test('a chrome button that is not wrapped argues for itself', () {
    final button = RegExp(r'(^|[^A-Za-z])(IconButton|TextButton|InkWell)\(');
    final claim = RegExp(r'(ControlPressClaim|RailSwipeColumnPointer)\(');
    // A no-op `onTap` is the row/column SURFACE holding a tap recognizer in
    // the arena so scroll slop behaves as it always has — both rails say so
    // in their own comments. Claiming one would stop the panel scrolling.
    final surface = RegExp(r'onTap: \(\) \{\}');
    final bare = <String>[];
    for (final path in chrome) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (!button.hasMatch(line) || line.contains('.styleFrom')) {
          continue;
        }
        final ahead = lines
            .sublist(i, (i + 9).clamp(0, lines.length))
            .join(' ');
        if (surface.hasMatch(ahead) || notControls.keys.any(ahead.contains)) {
          continue;
        }
        var wrapped = false;
        for (var back = 0; back <= 3 && i - back >= 0; back++) {
          if (claim.hasMatch(lines[i - back])) {
            wrapped = true;
            break;
          }
        }
        if (!wrapped) {
          bare.add('$path:${i + 1}');
        }
      }
    }
    expect(
      bare,
      isEmpty,
      reason:
          'a press that lands on a control belongs to that control — mount '
          'ControlPressClaim (or RailSwipeColumnPointer, which adds the '
          'strong claim on top of it). If a drag from here is this widget\'s '
          'OWN verb, say so in notControls instead',
    );
  });

  Widget host(TimelineOrientation orientation, EditorSessionManager session) =>
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: orientation,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      );

  /// Presses [finder] and reports whether the pointer was claimed WHILE it
  /// was down — the only moment that counts, because a pan recogniser asks
  /// at `addPointer`, which happens during the down dispatch.
  Future<bool> claimedWhileDown(
    WidgetTester tester,
    Finder finder, {
    required int pointer,
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(finder),
      pointer: pointer,
    );
    final claimed = controlOwnsTap(pointer);
    await gesture.up();
    await tester.pump();
    // ⛔A claim that outlives its gesture deafens every later press handed
    // the same id, and ids are recycled.
    expect(
      controlOwnsTap(pointer),
      isFalse,
      reason: 'the claim must be released on up',
    );
    return claimed;
  }

  testWidgets('the bar\'s 1·2·3·4·N claim their press', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(host(TimelineOrientation.horizontal, session));
    await tester.pumpAndSettle();

    var pointer = 20;
    for (final id in const [
      'set-comma-1-button',
      'set-comma-2-button',
      'set-comma-3-button',
      'set-comma-4-button',
      'set-comma-n-button',
    ]) {
      final finder = find.byKey(ValueKey<String>(id));
      expect(finder, findsOneWidget, reason: '$id is not on the bar');
      expect(
        await claimedWhileDown(tester, finder, pointer: pointer++),
        isTrue,
        reason:
            '$id is a TEXT button, and the ledger that keeps hand-rolled '
            'buttons honest reads `IconButton(` — so it walked straight '
            'past the one thing that exists to notice it (F-45). These also '
            'sit inside a baked StaticRaster, which is why they are PRESSED '
            'here and not just scanned',
      );
    }
  });

  testWidgets('the x-sheet\'s column toggles claim their press', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(host(TimelineOrientation.vertical, session));
    await tester.pumpAndSettle();

    final layerId = session.activeLayerId!;
    var pointer = 40;
    // ⚠️The sheet's lane toggle and folder twirl need a layer with property
    // lanes / a group to fold, which the default project has neither of —
    // the SCAN is what covers those two. Everything nameable is driven.
    for (final id in <String>[
      'xsheet-layer-onion-$layerId',
      'xsheet-layer-fill-reference-$layerId',
    ]) {
      final finder = find.byKey(ValueKey<String>(id));
      expect(finder, findsOneWidget, reason: '$id is not on the sheet');
      expect(
        await claimedWhileDown(tester, finder, pointer: pointer++),
        isTrue,
        reason:
            '$id wore no claim at all — the only wrapper was in a RAIL file '
            'under a rail name, and the sheet is not the rail',
      );
    }
  });

  testWidgets('the storyboard\'s rail and legend claim their press too', (
    tester,
  ) async {
    // The storyboard is where the lane toggles and the legend's lanes button
    // are actually mounted — 유저 2026-08-29: 「스토리보드 fx행이든 뭐든
    // **행이면 싹 다 통일**」, and the same sentence covers the buttons ON
    // those rows.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
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

    var pointer = 55;
    for (final id in const [
      'storyboard-track-lane-toggle-default-track',
      'storyboard-se-lane-toggle-default-track-1',
      'legend-lanes-toggle',
      'legend-mute',
    ]) {
      final finder = find.byKey(ValueKey<String>(id));
      expect(finder, findsOneWidget, reason: '$id is not on the storyboard');
      expect(
        await claimedWhileDown(tester, finder, pointer: pointer++),
        isTrue,
        reason: '$id is chrome like the row beneath it',
      );
    }
  });

  testWidgets('a plain cell is NOT claimed', (tester) async {
    // ⛔THE CONTROL CASE. A predicate that claimed everything would pass
    // every assertion above and leave the panel unable to scroll at all.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(host(TimelineOrientation.horizontal, session));
    await tester.pumpAndSettle();

    final grid = find.byKey(const ValueKey<String>('timeline-frame-grid-area'));
    expect(grid, findsOneWidget);
    expect(
      await claimedWhileDown(tester, grid, pointer: 60),
      isFalse,
      reason: 'scrolling still happens — everywhere that is not a control',
    );
  });
}

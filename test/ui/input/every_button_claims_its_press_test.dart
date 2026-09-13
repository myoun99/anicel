import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// 🚨★★★EVERY BUTTON IN `lib/src/ui` CLAIMS ITS PRESS.
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
///
/// ⛔AND THE SCAN CANNOT ANSWER THE OTHER HALF: whether an ANCESTOR owns the
/// drag. Wrapping is absorbing, so a claim mounted under something whose
/// drag is its verb kills that verb — the brush library's reorder listener
/// and the onion strip's peg drag were both eaten this way, and both were
/// caught by their own behaviour tests, not by anything here. A wrap that
/// turns one of those red belongs in [notControls], not in a workaround.
void main() {
  setUp(debugClearValueControlPointers);
  tearDown(debugClearValueControlPointers);

  /// EVERY `.dart` UNDER `lib/src/ui`, not a hand-kept list.
  ///
  /// ⛔It WAS a hand-kept list of eight — bars, rails, strips, pills — with
  /// a comment saying dialogs, pickers and the export screens were left out
  /// on purpose because 「a grid of swatches scrolls by dragging off a
  /// swatch」. `git log -S` says that sentence arrived in the very commit
  /// that wrote this file (#1351): nobody asked for it, which by 절대명령 3
  /// makes it a bug, and 유저 2026-08-30 said so outright —
  ///
  /// > 「스크롤러가 발생하는 영역 안에 버튼은 최우선 확인대상이 맞는데,
  /// > **그 외 버튼도 싹 다 확인이야**. 왜냐하면 지금부터 구조 바꿔서
  /// > 스크롤 발생될수도있는거고 애초에 통일해야 구조적으로 좋으니까」
  ///
  /// The list had also quietly gone stale in its OWN yard: `layer_rail_columns`
  /// (the layer-type button), `layer_rail_window`, `project_settings_pill` and
  /// `se_layer_mixer` are timeline chrome by any reading and were bare,
  /// because they were not among the eight names.
  List<String> everyUiFile() => Directory('lib/src/ui')
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path.replaceAll(r'\', '/'))
      .where((path) => path.endsWith('.dart'))
      .toList();

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
    // 🚨THE ROW'S DRAG IS ITS REORDER, and the reorder listener sits ABOVE
    // it. `ReorderableListView` puts a `ReorderableDragStartListener` around
    // the whole row, so the claim's absorbers — mounted INSIDE — take the
    // arena first and the library could no longer be reordered at all
    // (measured: three `brush_preset_panel_test` cases went red the moment
    // this row was wrapped). Same shape as the storyboard rows above.
    'brush-preset-chip-': 'its drag is its own verb (a reorder)',
    // 🚨AND THE PEG STRIP OWNS ITS VERTICAL DRAG, one level up: 「the strip
    // owns the vertical drag; each column owns its tap」 says so in the
    // panel's own comment. A claim inside the column ate that drag and the
    // peg opacity could no longer be dragged at all (measured — the onion
    // panel's drag test went red). Same shape as the row above.
    'onion-peg-column-': 'the strip above it owns the drag',
    // ⛔SCRIMS AND GRID SURFACES, not buttons. Each covers a whole region
    // and exists so that a press ANYWHERE lands somewhere; claiming one
    // would mean the region under it could never be scrolled at all.
    'canvas-playback-view': 'a scrim over the whole view',
    'timesheet-header-edit-barrier': 'a tap-away scrim',
    '-lane-stand-cell-': 'the lane grid surface, like the frame cell',
  };

  /// The control's OWN named arguments, with everything nested inside them
  /// dropped: `onTap: silentPress(open)` reads `onTap: silentPress()`, and a
  /// child's `onTap:` further down is not this control's and is not read.
  /// [column] is just past the control's opening parenthesis.
  String ownArguments(List<String> lines, int row, int column) {
    final own = StringBuffer();
    var depth = 1;
    for (var r = row; r < lines.length; r++) {
      final text = lines[r];
      String? quote;
      for (var c = r == row ? column : 0; c < text.length; c++) {
        final char = text[c];
        if (quote != null) {
          if (char == r'\') {
            c++;
          } else if (char == quote) {
            quote = null;
          }
          continue;
        }
        if (char == "'" || char == '"') {
          quote = char;
        } else if (char == '/' && text.startsWith('//', c)) {
          break;
        } else if ('([{'.contains(char)) {
          if (depth == 1) {
            own.write(char);
          }
          depth++;
        } else if (')]}'.contains(char)) {
          depth--;
          if (depth == 0) {
            return own.toString();
          }
          if (depth == 1) {
            own.write(char);
          }
        } else if (depth == 1) {
          own.write(char);
        }
      }
      own.write(' ');
    }
    return own.toString();
  }

  /// Every control the scan counts, the claim that wraps it (null when none
  /// does) and its own arguments — the ONE walk both scans below read.
  List<({String site, String? parent, String arguments})> scannedControls() {
    final button = RegExp(
      r'(^|[^A-Za-z])(IconButton|TextButton|InkWell|GestureDetector)\(',
    );
    // A [GestureDetector] is only a BUTTON when it has an `onTap` — the
    // other twenty-odd are pans, scales and long-presses whose drag IS the
    /// verb, and a claim over one of those is the brush row's bug again.
    final tappable = RegExp('onTap:');
    // ⚠️[DragVerbClaim] counts as well, and it is not a loophole: a widget
    // that says 「the drag from here is MY verb」 mounts its own recogniser
    // for it, which is deeper than any ancestor scroller and therefore
    // registered first. The scrubbable number label is the shape — a tap
    // edits it, a horizontal drag scrubs it, and neither is a scroll.
    final claim = RegExp(
      r'(ControlPressClaim|RailSwipeColumnPointer|DragVerbClaim)\(',
    );
    // A no-op `onTap` is the row/column SURFACE holding a tap recognizer in
    // the arena so scroll slop behaves as it always has — both rails say so
    // in their own comments. Claiming one would stop the panel scrolling.
    //
    // ⚠️The window ahead is SIXTEEN lines, not nine: the frame cell's no-op
    // carries a nine-line explanation of why it is one, so a shorter window
    // read straight past it and called the grid's own surface a bare button.
    final surface = RegExp(r'onTap: \(\) \{\}');
    final controls = <({String site, String? parent, String arguments})>[];
    for (final path in everyUiFile()) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        final control = button.firstMatch(line);
        if (control == null || line.contains('.styleFrom')) {
          continue;
        }
        final ahead = lines
            .sublist(i, (i + 16).clamp(0, lines.length))
            .join(' ');
        if (line.contains('GestureDetector(') && !tappable.hasMatch(ahead)) {
          continue;
        }
        if (surface.hasMatch(ahead) || notControls.keys.any(ahead.contains)) {
          continue;
        }
        // ⛔NOT "the last three lines". The claim carries the control's
        // callback now, and a callback with a body pushes the `child:` an
        // arbitrary distance below it — twelve real wraps went unseen at
        // three. The claim is the control's PARENT, so walk back to the
        // first line indented LESS than the control's own: in formatted
        // Dart that is the line that opened the thing enclosing it.
        var parent = claim.firstMatch(line.substring(0, control.start))?[1];
        final indent = line.length - line.trimLeft().length;
        for (var back = i - 1; back >= 0 && parent == null; back--) {
          final above = lines[back];
          if (above.trim().isEmpty) {
            continue;
          }
          if (above.length - above.trimLeft().length >= indent) {
            continue;
          }
          parent = claim.firstMatch(above)?[1];
          break;
        }
        controls.add((
          site: '$path:${i + 1}',
          parent: parent,
          arguments: ownArguments(lines, i, control.end),
        ));
      }
    }
    return controls;
  }

  test('a button that is not wrapped argues for itself', () {
    final bare = [
      for (final control in scannedControls())
        if (control.parent == null) control.site,
    ];
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

  test('🚨a claimed control acts from its claim, never from its own tap', () {
    // F-120 (유저 2026-09-13): 「펜으로 레이어나 컷이나 +버튼 옆의 생성할
    // 레이어 여는 버튼같은게 작동안함. 마우스로는 작동함」. The scan above
    // passed that caret, because a claim WAS its parent. But the claim takes
    // the arena on the first movement, and that rejects every tap beneath it
    // — so a control whose verb rides its own `onTap` acts for a still mouse
    // and never for a pen, which is never still. ⇒ Under a claim, the
    // control's own callbacks are silent ([silentPress]), empty or null, and
    // the claim's `onPressed` is the one thing that acts.
    //
    // ⚠️A [DragVerbClaim] parent is not read here, and that is the scrub
    // label's shape: its tap and its drag are both its own verbs, so the
    // arena between THOSE two is the thing that decides.
    // ⚠️The spaces go INSIDE the lookahead. Outside it, `\s*` gives back the
    // space it matched and the lookahead is asked at 「 silentPress(」, which
    // is not 「silentPress(」 — every silent tap in the app read as live.
    final live = RegExp(
      r'\bon(Tap|TapUp|DoubleTap|LongPress|Pressed):'
      r'(?!\s*(silentPress\(|null\b|\(\)\s*\{\s*\}))',
    );
    final riding = [
      for (final control in scannedControls())
        if ((control.parent == 'ControlPressClaim' ||
                control.parent == 'RailSwipeColumnPointer') &&
            live.hasMatch(control.arguments))
          control.site,
    ];
    expect(
      riding,
      isEmpty,
      reason:
          'a claimed control acts from the claim\'s onPressed: a live tap '
          'beneath it is rejected the moment the hand moves, and on a press '
          'that does not move it fires a second time',
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

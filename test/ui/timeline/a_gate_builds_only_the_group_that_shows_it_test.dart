import '../../helpers/screens_left_of_the_engine.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/comma_button.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart' show PillNameCell;

/// a-gate-rebuilds-the-whole-toolbar (2026-10-24): a button's gate moving
/// builds the GROUP that shows it again, and nothing else on the bar.
///
/// 🔬The bar was cached whole on a token of every gate it showed, so one
/// flip built it all again: a drawing landing in an empty cel lit the 색
/// 편집 head and rebuilt 227 widgets of the bar, 65 of them outside the
/// shared pill the head is on — the frame pill's frame, its name, the
/// push/pull pair. Each group hears its own gates now ([toolbarGateNews]).
///
/// ⚠️The oracle is widget INSTANCE identity, control by control: a control
/// still enabled the same tells nothing of whether it was built again.
///
/// The collaborator whose list every group hears, named so
/// `tool/mutation_run.dart` runs this file for it.
Listenable newsOf(EditorSessionManager s) => toolbarGateNews(s);

/// Every control on [bar], by the key it wears, as built.
List<(String, Widget)> _controls(WidgetTester tester, Finder bar) => [
  for (final widget in tester.widgetList(
    find.descendant(
      of: bar,
      matching: find.byWidgetPredicate(
        (w) =>
            w is AppIconButton ||
            w is PillNameCell ||
            (w is CommaButton && w.key is ValueKey<String>),
      ),
    ),
  ))
    (
      switch (widget) {
        AppIconButton(:final keyValue) => keyValue,
        PillNameCell(:final keyValue) => keyValue,
        _ => (widget.key! as ValueKey<String>).value,
      },
      widget,
    ),
];

/// The controls of [before] built again by now, by key.
Set<String> _builtAgain(
  WidgetTester tester,
  Finder bar,
  List<(String, Widget)> before,
) {
  final after = _controls(tester, bar);
  expect(
    [for (final (key, _) in after) key],
    [for (final (key, _) in before) key],
    reason: 'premise: the same controls, in the same order',
  );
  return {
    for (var i = 0; i < after.length; i++)
      if (!identical(after[i].$2, before[i].$2)) after[i].$1,
  };
}

/// The keys of the controls inside the pill keyed [pillKey] on [bar].
Set<String> _keysIn(WidgetTester tester, Finder bar, String pillKey) => {
  for (final (key, _) in _controls(
    tester,
    find.descendant(of: bar, matching: find.byKey(ValueKey<String>(pillKey))),
  ))
    key,
};

void main() {
  itsTestsLeaveScreensOfTheEngine({ScreensLeft.ofAShot});
  Future<EditorSessionManager> openOnAnEmptyCel(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    return session;
  }

  /// A drawing landing in the cel the playhead stands on, the way a stroke
  /// lands: by the store, with no seek and no selection moving.
  void landADrawing(EditorSessionManager s) {
    const bytes = defaultCelTileSize * defaultCelTileSize * 4;
    s.renderCaches.brushFrameStore.storeBakedSurface(
      s.brushFrameKeyForCut(
        s.requireActiveCut,
        s.activeLayerId!,
        s.selectedFrame!.id,
      ),
      BitmapSurface(
        canvasSize: s.requireActiveCut.canvasSize,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            size: defaultCelTileSize,
            pixels: Uint8List(bytes)..fillRange(0, bytes, 0xFF),
          ),
        },
      ),
    );
  }

  bool headIsLit(WidgetTester tester, Finder bar) =>
      tester
          .widget<AppIconButton>(
            find.descendant(
              of: bar,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is AppIconButton &&
                    w.keyValue == 'shared-colour-edit-button',
              ),
            ),
          )
          .onPressed !=
      null;

  /// The 색 편집 head lights as a drawing lands on [bar]'s panel: its group
  /// is built again, and every other control on the bar stays.
  Future<void> expectTheHeadAlone(
    WidgetTester tester,
    EditorSessionManager s,
    Finder bar,
  ) async {
    expect(headIsLit(tester, bar), isFalse, reason: 'premise: an empty cel');
    final toolbar = tester.widget(bar);
    final before = _controls(tester, bar);
    landADrawing(s);
    await tester.pump();
    expect(headIsLit(tester, bar), isTrue, reason: 'the head lit');

    expect(
      _keysIn(tester, bar, 'timeline-toolbar-shared-group'),
      contains('shared-colour-edit-button'),
      reason: 'premise: the head is on the shared pill',
    );
    // 🔬Card the-shared-pill-is-first-built-on-the-first-stroke-after-launch
    // (11-20): the shared pill was one group, and the head lighting built
    // its eleven verbs again. A group is what the pill's dividers bound.
    expect(
      _builtAgain(tester, bar, before),
      {'shared-colour-edit-button'},
      reason: 'the head is a group of its own — nothing beside it changed',
    );
    expect(
      identical(tester.widget(bar), toolbar),
      isTrue,
      reason: 'and the bar around the groups is the one it was',
    );
  }

  testWidgets('the pixel board filling lights the head over a blank cel, on '
      'its own news, and builds that head alone', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    final bar = find.descendant(
      of: find.byType(TimelineTabHost),
      matching: find.byType(TimelineActionToolbar),
    );
    expect(headIsLit(tester, bar), isFalse, reason: 'premise: a blank cel');
    final before = _controls(tester, bar);

    // I-55: a paste lands on a blank cel too, so a board that holds a piece
    // opens the head — and the board's news is no notify and no seek.
    s.appClipboard.pixels.hold(
      CutPiece(
        image: BrushStampImage(
          id: 'board-probe',
          width: 2,
          height: 2,
          rgba: Uint8List(16)..fillRange(0, 16, 0xFF),
        ),
        originLeft: 0,
        originTop: 0,
      ),
    );
    await tester.pump();

    expect(headIsLit(tester, bar), isTrue, reason: 'the head heard the board');
    expect(_builtAgain(tester, bar, before), {'shared-colour-edit-button'});
  });

  Future<Finder> openTheStoryboard(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    return find.descendant(
      of: find.byType(StoryboardTabHost),
      matching: find.byType(TimelineActionToolbar),
    );
  }

  testWidgets('a drawing landing lights the 색 편집 head and builds its group '
      'alone — on the timeline', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    await expectTheHeadAlone(
      tester,
      s,
      find.descendant(
        of: find.byType(TimelineTabHost),
        matching: find.byType(TimelineActionToolbar),
      ),
    );
  });

  testWidgets('…and on the storyboard, whose bar is the same widget over its '
      'own panel', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    await expectTheHeadAlone(tester, s, await openTheStoryboard(tester));
  });

  testWidgets('the storyboard keeps its bar through a notify that moves '
      'nothing on it', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    final bar = await openTheStoryboard(tester);
    final toolbar = tester.widget(bar);
    final before = _controls(tester, bar);

    // A full session notify — the storyboard's host is built again — that
    // changes no value the bar shows.
    s.layerSwitches.toggleLayerVisibility(
      s.layers.firstWhere((layer) => layer.id != s.activeLayerId).id,
    );
    await tester.pump();

    expect(
      identical(tester.widget(bar), toolbar),
      isTrue,
      reason: 'the host keeps the bar while it is built for this session',
    );
    expect(_builtAgain(tester, bar, before), isEmpty);
  });

  testWidgets('on the storyboard the push/pull pair asks the row its rail '
      'stands on — the answer its keys read', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    final bar = await openTheStoryboard(tester);
    final asked = StoryboardToolbarPanelContext(s).shiftCurrentRow;
    expect(asked, isA<TrackRowAddress>(), reason: 'premise: the cut row');
    // Slack in front of the cut: the cut row can pull, the drawing target —
    // its block packed against frame 0 — cannot.
    s.blockShift.pushBlocks(2, currentRow: asked);
    await tester.pumpAndSettle();
    expect(s.blockShift.canPullBlocks(currentRow: asked), isTrue);
    expect(
      s.blockShift.canPullBlocks(),
      isFalse,
      reason: 'premise: that row and the drawing target answer apart',
    );

    final pull = tester.widget<AppIconButton>(
      find.descendant(
        of: bar,
        matching: find.byWidgetPredicate(
          (w) => w is AppIconButton && w.keyValue == 'pull-blocks-button',
        ),
      ),
    );
    expect(
      pull.onPressed,
      isNotNull,
      reason: 'the pair answers as the rail it is on',
    );
  });

  testWidgets('a seek into a hold builds the frame verbs it lights and '
      'nothing else on the bar', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    s.edgeDrag.setCommaForTimelineCursor(3);
    await tester.pumpAndSettle();
    final bar = find.descendant(
      of: find.byType(TimelineTabHost),
      matching: find.byType(TimelineActionToolbar),
    );
    final toolbar = tester.widget(bar);
    final before = _controls(tester, bar);

    s.selectFrameIndex(1);
    await tester.pump();

    final moved = _builtAgain(tester, bar, before);
    expect(
      moved,
      contains('new-frame-button'),
      reason: 'premise: the ＋ lights one cell into a hold (F-107)',
    );
    expect(
      moved.difference({
        'new-frame-button',
        'blank-exposure-button',
        'auto-frame-toggle-button',
        'toggle-mark-one-button',
        'toggle-mark-button',
        'mark-every-button',
      }),
      isEmpty,
      reason: "the seek moved the frame icons' gates alone",
    );
    expect(identical(tester.widget(bar), toolbar), isTrue);
  });

  // Every group bakes its words with its gates: a language switch fires no
  // session notify, and a group that left it out of its gates would go on
  // printing the language it was built in.
  testWidgets('a language switch re-words a verb in every group of the '
      'shared pill', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    final bar = find.descendant(
      of: find.byType(TimelineTabHost),
      matching: find.byType(TimelineActionToolbar),
    );
    String tooltipOf(String key) => tester
        .widget<AppIconButton>(
          find.descendant(
            of: bar,
            matching: find.byWidgetPredicate(
              (w) => w is AppIconButton && w.keyValue == key,
            ),
          ),
        )
        .tooltip;
    // One verb of each group, with the words it prints.
    final printed = {
      'shared-edit-button': () =>
          editorActionLabel(EditorActionIds.editInstance),
      'shared-delete-button': () =>
          editorActionLabel(EditorActionIds.editDelete),
      'shared-colour-edit-button': () => AppText.strings.tlSharedColourEdit,
    };
    final before = {for (final key in printed.keys) key: tooltipOf(key)};
    final settings = s.languageSettings.value;
    s.languageSettings.value = settings.copyWith(
      programLanguage: settings.programLanguage == AppLanguage.ko
          ? AppLanguage.ja
          : AppLanguage.ko,
    );
    addTearDown(() => s.languageSettings.value = settings);
    await tester.pump();

    for (final MapEntry(key: key, value: words) in printed.entries) {
      expect(
        words(),
        isNot(before[key]),
        reason: 'premise: $key prints apart in the two languages',
      );
      expect(tooltipOf(key), words(), reason: key);
    }
  });
}

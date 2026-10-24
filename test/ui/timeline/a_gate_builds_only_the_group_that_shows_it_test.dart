import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
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
            (w is TextButton && w.key is ValueKey<String>),
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

  /// The 색 편집 head lights as a drawing lands on [bar]'s panel: the shared
  /// pill is built again, and every other control on the bar stays.
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

    final shared = _keysIn(tester, bar, 'timeline-toolbar-shared-group');
    final moved = _builtAgain(tester, bar, before);
    expect(moved, contains('shared-colour-edit-button'));
    expect(
      moved.difference(shared),
      isEmpty,
      reason: 'the head is on the shared pill — nothing outside it changed',
    );
    expect(
      identical(tester.widget(bar), toolbar),
      isTrue,
      reason: 'and the bar around the groups is the one it was',
    );
  }

  testWidgets('a drawing landing lights the 색 편집 head and builds its pill '
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
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('…and on the storyboard, whose bar is the same widget over its '
      'own panel', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    await expectTheHeadAlone(
      tester,
      s,
      find.descendant(
        of: find.byType(StoryboardTabHost),
        matching: find.byType(TimelineActionToolbar),
      ),
    );
    s.playbackRig.prerenderScheduler.cancel();
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
        'toggle-mark-button',
        'mark-every-button',
      }),
      isEmpty,
      reason: "the seek moved the frame icons' gates alone",
    );
    expect(identical(tester.widget(bar), toolbar), isTrue);
    s.playbackRig.prerenderScheduler.cancel();
  });
}

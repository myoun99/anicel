import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/home_page_probes.dart';

/// The storyboard builds NO ROW past its viewport (card frame-panels-build-
/// in-one-frame ②, 2026-10-29) — by the timeline's own window over the
/// rail's one table. ↩️Every row of every track was built, seen or not.
///
/// Every S row the rail and the strips build stands at least partly inside
/// the rows' viewport, a label and its strip on one line — at the top of the
/// rows and at their end alike — and a row a pointer holds stays built while
/// the rows scroll it away.
void main() {
  /// The track the S rows stand on, as their keys name it.
  late String track;

  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  final viewport = find.byKey(
    const ValueKey<String>('storyboard-vertical-viewport'),
  );

  ScrollPosition rows(WidgetTester tester) => tester
      .stateList<ScrollableState>(
        find.descendant(of: viewport, matching: find.byType(Scrollable)),
      )
      .first
      .position;

  Finder label(int slot) =>
      find.byKey(ValueKey<String>('storyboard-se-label-$track-$slot'));

  /// The S rows the rail and the strips build, by slot: each label's rect
  /// and its strip's.
  Map<int, ({Rect label, Rect? strip})> builtSeRows(WidgetTester tester) => {
    for (var slot = 1; slot <= _seRows; slot += 1)
      if (label(slot).evaluate().isNotEmpty)
        slot: (
          label: tester.getRect(label(slot)),
          strip: switch (find.byKey(
            ValueKey<String>('storyboard-se-row-0-$slot'),
          )) {
            final strip when strip.evaluate().isNotEmpty => tester.getRect(
              strip,
            ),
            _ => null,
          },
        ),
  };

  Future<void> pumpManyRows(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = sessionOf(tester);
    session.selectLayer(
      session.layers.firstWhere((layer) => layer.kind == LayerKind.se).id,
    );
    while (session.repository
            .requireProject()
            .tracks
            .single
            .seLayers
            .length <
        _seRows) {
      session.layerStack.addLayerOfKind(LayerKind.se);
    }
    await showStoryboardPanel(tester);
    track = session.repository.requireProject().tracks.single.id.value;
  }

  testWidgets('every row the storyboard builds stands in its viewport', (
    tester,
  ) async {
    await pumpManyRows(tester);

    void expectEveryRowShown(String where) {
      final shown = tester.getRect(viewport);
      final built = builtSeRows(tester);
      expect(built, isNotEmpty, reason: '⛔전제: $where, an S row stands');
      expect(
        built.length,
        lessThan(_seRows),
        reason: '⛔전제: $where, not every S row fits the viewport',
      );
      expect(
        {
          for (final element in find
              .byWidgetPredicate(
                (widget) => switch (widget.key) {
                  ValueKey<String>(:final value) => value.startsWith(
                    'storyboard-se-row-0-',
                  ),
                  _ => false,
                },
              )
              .evaluate())
            int.parse(
              (element.widget.key! as ValueKey<String>).value.substring(
                'storyboard-se-row-0-'.length,
              ),
            ),
        },
        built.keys.toSet(),
        reason: '$where: the strips build the rows the rail builds',
      );
      for (final MapEntry(key: slot, value: row) in built.entries) {
        expect(
          row.label.overlaps(shown),
          isTrue,
          reason: '$where: S$slot\'s label at ${row.label}, the view $shown',
        );
        expect(
          row.strip?.top,
          row.label.top,
          reason: '$where: S$slot\'s strip stands on its label\'s line',
        );
      }
    }

    rows(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expectEveryRowShown('at the top');

    rows(tester).jumpTo(rows(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    expectEveryRowShown('at the end');
  });

  testWidgets('a row stands at one place in the rows whatever the scroll, '
      'its lanes twirled open under it or not', (tester) async {
    await pumpManyRows(tester);
    final session = sessionOf(tester);
    // Every third S row twirled open: units of a row and its lanes among
    // rows of one.
    final seLayers = session.layers
        .where((layer) => layer.kind == LayerKind.se)
        .toList();
    for (var index = 0; index < seLayers.length; index += 3) {
      session.layerSwitches.toggleLayerLanes(seLayers[index].id);
    }
    await tester.pumpAndSettle();
    final rail = find.byKey(
      const ValueKey<String>('storyboard-track-label-rail'),
    );

    final placed = <int, double>{};
    final position = rows(tester);
    expect(
      position.maxScrollExtent,
      greaterThan(position.viewportDimension),
      reason: '⛔전제: the rows run past the view more than once',
    );
    for (
      var offset = 0.0;
      offset <= position.maxScrollExtent;
      offset += position.viewportDimension / 3
    ) {
      position.jumpTo(offset);
      await tester.pumpAndSettle();
      final top = tester.getRect(rail).top;
      for (final MapEntry(key: slot, value: row)
          in builtSeRows(tester).entries) {
        final at = row.label.top - top;
        expect(
          at,
          moreOrLessEquals(placed.putIfAbsent(slot, () => at)),
          reason: 'S$slot at scroll $offset stands where it stood before',
        );
        expect(
          row.strip?.top,
          row.label.top,
          reason: 'S$slot\'s strip stands on its label\'s line',
        );
      }
    }
    expect(
      placed.length,
      _seRows,
      reason: '⛔전제: the scroll passed every S row',
    );
  });

  testWidgets('a row a pointer holds stays built while the rows scroll it '
      'away, and is let go of once it is released', (tester) async {
    await pumpManyRows(tester);
    rows(tester).jumpTo(rows(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    // The topmost S row the view shows whole — the press lands on it.
    final shown = tester.getRect(viewport);
    final held = [
      for (final MapEntry(key: slot, value: row) in builtSeRows(tester).entries)
        if (row.label.top >= shown.top && row.label.bottom <= shown.bottom)
          slot,
    ].reduce(math.max);
    final hand = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hand.down(tester.getCenter(label(held)));
    await tester.pump();

    rows(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      label(held),
      findsOneWidget,
      reason: 'S$held is held: the window keeps it built',
    );
    expect(
      tester.getRect(label(held)).overlaps(tester.getRect(viewport)),
      isFalse,
      reason: '⛔전제: S$held stands out of the view',
    );

    await hand.up();
    rows(tester).jumpTo(rows(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    rows(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(label(held), findsNothing, reason: 'released, S$held is let go');
  });
}

/// The S rows the track holds — more than the view shows.
const int _seRows = 30;

import '../../helpers/screens_left_of_the_engine.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edges.dart'
    show timelineRowWindowMargin;

import '../../helpers/home_page_probes.dart';

/// The storyboard builds NO ROW past a wheel notch beyond its viewport
/// ([timelineRowWindowMargin]) — by the timeline's own window over the
/// rail's one table (card frame-panels-build-in-one-frame ②, 2026-10-29).
/// ↩️Every row of every track was built, seen or not.
///
/// Every S row the rail and the strips build stands at least partly inside
/// the rows' viewport grown by that notch on each side, a label and its
/// strip on one line — at the top of the rows and at their end alike — and
/// a row a pointer holds stays built while the rows scroll it away.
///
/// 🗣️유저 2026-11-18 (a-timeline-wheel-notch-lays-out-the-rail-Q1 = B,
/// 「화면 밖 여유 행 — 늘」): the notch is built. ↩️⛔From 2026-10-29 this
/// pinned no row past the viewport itself.
void main() {
  itsTestsLeaveScreensOfTheEngine({ScreensLeft.ofAShot});
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
  ///
  /// ONE walk of the tree: a find a slot walked the whole home page some
  /// ninety times a scroll step — 93 s for one test alone (11-20).
  Map<int, ({Rect label, Rect? strip})> builtSeRows(WidgetTester tester) {
    final labelKey = 'storyboard-se-label-$track-';
    const stripKey = 'storyboard-se-row-0-';
    final labels = <int, Rect>{};
    final strips = <int, Rect>{};
    for (final element in find
        .byWidgetPredicate((widget) => widget.key is ValueKey<String>)
        .evaluate()) {
      final key = (element.widget.key! as ValueKey<String>).value;
      final (into, slot) = key.startsWith(labelKey)
          ? (labels, int.tryParse(key.substring(labelKey.length)))
          : key.startsWith(stripKey)
          ? (strips, int.tryParse(key.substring(stripKey.length)))
          : (null, null);
      if (into == null || slot == null || slot < 1 || slot > _seRows) {
        continue;
      }
      if (into.containsKey(slot)) {
        throw StateError('two widgets keyed $key');
      }
      final box = element.renderObject! as RenderBox;
      into[slot] = Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      );
    }
    return {
      for (final slot in labels.keys.toList()..sort())
        slot: (label: labels[slot]!, strip: strips[slot]),
    };
  }

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

  testWidgets('every row the storyboard builds stands within a notch of its '
      'viewport', (tester) async {
    await pumpManyRows(tester);

    void expectEveryRowShown(String where) {
      final shown = notchPast(tester.getRect(viewport));
      final built = builtSeRows(tester);
      expect(built, isNotEmpty, reason: '⛔전제: $where, an S row stands');
      expect(
        built.length,
        lessThan(_seRows),
        reason: '⛔전제: $where, not every S row fits the window',
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
          reason: '$where: S$slot\'s label at ${row.label}, the window $shown',
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

  // 🗣️유저 2026-11-18 (a-timeline-wheel-notch-lays-out-the-rail-Q2 = 1,
  // 「칸 뒤 쉬는 프레임에 짓기」): the timeline's walk, the conte's rows.
  testWidgets('a notch lays no row in its own frame, and the rows the '
      'window takes in come a row a frame after it', (tester) async {
    await pumpManyRows(tester);
    rows(tester).jumpTo(0);
    await tester.pumpAndSettle();
    Set<int> built() => builtSeRows(tester).keys.toSet();
    final before = built();
    // What lays the rows: the window's builders over the S rows — a lay of
    // the same rows is a lay too, so they are counted, not the rows.
    final first = before.reduce(math.min);
    final layers = {
      for (final row in [
        label(first),
        find.byKey(ValueKey<String>('storyboard-se-row-0-$first')),
      ])
        ...find
            .ancestor(
              of: row,
              matching: find.byType(ValueListenableBuilder<int>),
            )
            .evaluate(),
    };
    expect(layers, isNotEmpty, reason: '⛔전제: the rows have a layer');
    var laid = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (layers.contains(element)) {
        laid += 1;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    rows(tester).jumpTo(timelineRowWindowMargin);
    await tester.pump();
    expect(laid, 0, reason: 'the notch\'s own frame laid no row');
    expect(built(), before);

    final arrivals = <int>[];
    var now = before;
    for (var frame = 0; frame < 12; frame += 1) {
      await tester.pump();
      final next = built();
      arrivals.add(next.difference(now).length);
      now = next;
    }
    debugOnRebuildDirtyWidget = null;
    expect(laid, greaterThan(0), reason: 'LIVENESS: the walk\'s lays are seen');
    expect(
      arrivals.every((count) => count <= 1),
      isTrue,
      reason: 'a row a frame: $arrivals',
    );
    expect(
      arrivals.where((count) => count == 1).length,
      greaterThan(1),
      reason: 'taken in over the frames after the notch: $arrivals',
    );
    final shown = tester.getRect(viewport);
    final below = notchPast(shown).bottom;
    expect(
      builtSeRows(tester).values.where(
        (row) => row.label.top >= shown.bottom && row.label.top < below,
      ),
      isNotEmpty,
      reason: 'and the window is a notch past the view again',
    );
  });

  testWidgets('a row stands at one place in the rows whatever the scroll, '
      'its lanes twirled open under it or not, and every row the view '
      'shows is built', (tester) async {
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
    final tall = <int, double>{};
    final views =
        <({double offset, double top, double bottom, Set<int> built})>[];
    final position = rows(tester);
    expect(
      position.maxScrollExtent,
      greaterThan(position.viewportDimension),
      reason: '⛔전제: the rows run past the view more than once',
    );
    for (
      var offset = 0.0;
      offset <= position.maxScrollExtent;
      offset += _step
    ) {
      position.jumpTo(offset);
      await tester.pumpAndSettle();
      final top = tester.getRect(rail).top;
      final shown = tester.getRect(viewport);
      final built = builtSeRows(tester);
      for (final MapEntry(key: slot, value: row) in built.entries) {
        final at = row.label.top - top;
        expect(
          at,
          moreOrLessEquals(placed.putIfAbsent(slot, () => at)),
          reason: 'S$slot at scroll $offset stands where it stood before',
        );
        tall[slot] = row.label.height;
        expect(
          row.strip?.top,
          row.label.top,
          reason: 'S$slot\'s strip stands on its label\'s line',
        );
      }
      views.add((
        offset: offset,
        top: shown.top - top,
        bottom: shown.bottom - top,
        built: built.keys.toSet(),
      ));
    }
    expect(
      placed.length,
      _seRows,
      reason: '⛔전제: the scroll passed every S row',
    );
    for (final view in views) {
      for (final MapEntry(key: slot, value: at) in placed.entries) {
        if (at < view.bottom && at + tall[slot]! > view.top) {
          expect(
            view.built,
            contains(slot),
            reason: 'at scroll ${view.offset} the view shows S$slot',
          );
        }
      }
    }
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

  // ↩️검증/서피스 11-08 01:23 (card the-conte-panel-builds-the-rows-its-
  // window-reaches): a window made smaller and grown back left the rail's
  // rows past the smaller view unbuilt until the next resize, while the
  // timeline built its own at once.
  testWidgets('a view resized under rows that stand still builds the rows it '
      'now shows, as the view of that size first did', (tester) async {
    await pumpManyRows(tester);
    final shown = tester.getRect(viewport);
    final first = builtSeRows(tester).keys.toSet();

    await tester.binding.setSurfaceSize(const Size(1600, 700));
    await tester.pumpAndSettle();
    final smaller = tester.getRect(viewport);
    expect(
      smaller.height,
      lessThan(shown.height),
      reason: '⛔전제: the smaller window\'s view is shorter',
    );
    final reach = notchPast(smaller);
    for (final MapEntry(key: slot, value: row)
        in builtSeRows(tester).entries) {
      expect(
        row.label.overlaps(reach),
        isTrue,
        reason: 'shrunk, S$slot\'s label at ${row.label}, the window $reach',
      );
    }

    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(viewport),
      shown,
      reason: '⛔전제: the view stands as it first stood',
    );
    expect(
      builtSeRows(tester).keys.toSet(),
      first,
      reason: 'grown back, the view builds the S rows it built at that size',
    );
  });
}

/// The S rows the track holds — more than the view and its notches show.
const int _seRows = 30;

/// [view] grown by the notch the rows' window builds past each side of it.
Rect notchPast(Rect view) => Rect.fromLTRB(
  view.left,
  view.top - timelineRowWindowMargin,
  view.right,
  view.bottom + timelineRowWindowMargin,
);

/// One scroll step, less than a row: a row comes into the view at one end
/// while the other end's row stays, so the window's ends move one at a time.
const double _step = 13;

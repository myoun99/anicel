import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🚨I-57 (10-13, measured on the user's project): every timeline row was
/// keyed by its layer, so a cut switch threw away every row the window
/// held and built them again — 1577 elements on each crossing a scrub or a
/// play made. A row is built in a BERTH now ([RowBerths]): across cuts the
/// new cut's rows take the old rows' elements place by place, within a cut
/// a row's elements follow the row, and a hand in the rows keeps the old
/// rebuild — an edit in flight belongs to the layer it began on.
///
/// The same law on both grids (㉣): the x-sheet's columns were keyed by
/// their layers too, and its headers by nothing, so a row that left handed
/// every header after it to the next layer.
const _first = CutId('first');
const _second = CutId('second');

Layer _drawing(String id) => Layer(
  id: LayerId(id),
  name: id,
  frames: [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])],
  timeline: const {},
);

Cut _cut(CutId id, List<String> layers) => Cut(
  id: id,
  name: id.value,
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [for (final layer in layers) _drawing(layer)],
);

/// A grid as these tests read it: how its rows are named.
typedef _Grid = ({
  String name,
  bool sheet,
  String rows,
  String cells,
  String layerRow,
});

const _grids = <_Grid>[
  (
    name: 'the timeline',
    sheet: false,
    rows: 'timeline-rail-row-',
    cells: 'timeline-row-',
    layerRow: 'timeline-layer-row-',
  ),
  (
    name: 'the x-sheet',
    sheet: true,
    rows: 'xsheet-layer-row-',
    cells: 'xsheet-column-',
    layerRow: 'xsheet-layer-row-',
  ),
];

extension on _Grid {
  String get prefix => sheet ? 'xsheet' : 'timeline';

  /// The rows' own elements, the cells' and an eye in each row — the
  /// berths themselves.
  List<List<Element>> everyRow() => [
    _rows(rows),
    _rows(cells, end: '-cells'),
    _rows('$prefix-layer-visibility-'),
  ];

  Finder rowOf(String layer) =>
      find.named(sheet ? '$rows$layer' : '$rows$layer-row');

  Finder cellsOf(String layer) => find.named('$cells$layer-cells');
}

/// The timeline tab alone ([pumpTimelineHost]), as the app's window of
/// 800 × 600 laid it unless [surface] says another — the rows' berths are
/// the panel's.
Future<EditorSessionManager> _open(
  WidgetTester tester,
  _Grid grid, {
  Size surface = const Size(640, 320),
}) async {
  final session = await pumpTimelineHost(
    tester,
    Project(
      id: const ProjectId('berths'),
      name: 'Berths',
      createdAt: DateTime.utc(2026, 10, 13),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
          cuts: [
            _cut(_first, ['a1', 'a2', 'a3']),
            _cut(_second, ['b1', 'b2', 'b3']),
          ],
        ),
      ],
    ),
    surface: surface,
  );
  if (grid.sheet) {
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
  }
  return session;
}

/// The elements a family of rows is built in, in the rows' order — down
/// the rail, across the sheet.
List<Element> _rows(String family, {String end = ''}) {
  final rows = find
      .namedWhere((name) => name.startsWith(family) && name.endsWith(end))
      .evaluate()
      .toList();
  Offset at(Element row) =>
      (row.renderObject! as RenderBox).localToGlobal(Offset.zero);
  int order(Element a, Element b) {
    final (one, two) = (at(a), at(b));
    return one.dy != two.dy
        ? one.dy.compareTo(two.dy)
        : one.dx.compareTo(two.dx);
  }

  return rows..sort(order);
}

/// Whether [after] reuses none of [before]'s elements, family by family.
void _expectAfresh(List<List<Element>> before, List<List<Element>> after) {
  for (var family = 0; family < before.length; family += 1) {
    expect(
      after[family],
      hasLength(before[family].length),
      reason: 'LIVENESS: the rows stand',
    );
    expect(after[family].where(before[family].contains), isEmpty);
  }
}

void _expectKept(List<List<Element>> before, List<List<Element>> after) {
  for (var family = 0; family < before.length; family += 1) {
    expect(after[family], orderedEquals(before[family]));
  }
}

void main() {
  for (final grid in _grids) {
    group(grid.name, () {
      testWidgets('a cut switch builds the new cut\'s rows in the old rows\' '
          'elements, place by place', (tester) async {
        final session = await _open(tester, grid);
        final before = grid.everyRow();
        for (final family in before) {
          expect(
            family.length,
            greaterThanOrEqualTo(3),
            reason: 'LIVENESS: the drawings\' rows stand',
          );
        }

        session.selectCut(_second);
        await tester.pumpAndSettle();

        expect(
          find.named('${grid.layerRow}b1'),
          findsOneWidget,
          reason: 'LIVENESS: the rows show the second cut',
        );
        expect(find.named('${grid.layerRow}a1'), findsNothing);
        _expectKept(before, grid.everyRow());
      });

      group('a hand in the rows keeps the edit with its layer', () {
        // Every surface the rows stand on counts the hands on it: the
        // rail's rows (the sheet's header strip) and the cells.
        final places = <String, Offset Function(WidgetTester)>{
          'a row': (tester) =>
              tester.getCenter(find.named('${grid.prefix}-layer-name-a2')),
          'a row\'s cells': (tester) =>
              tester.getTopLeft(grid.cellsOf('a2')) + const Offset(4, 4),
        };
        for (final MapEntry(key: place, value: at) in places.entries) {
          testWidgets('a pointer down on $place builds them afresh — and '
              'once it is lifted the next switch keeps them again', (
            tester,
          ) async {
            final session = await _open(tester, grid);
            final before = grid.everyRow();
            final hand = await tester.startGesture(at(tester));

            session.selectCut(_second);
            await tester.pump();
            await tester.pump();
            final held = grid.everyRow();
            _expectAfresh(before, held);

            await hand.up();
            await tester.pumpAndSettle();
            final lifted = grid.everyRow();
            session.selectCut(_first);
            await tester.pumpAndSettle();
            _expectKept(lifted, grid.everyRow());
          });
        }

        testWidgets('a pointer the system cancels is lifted too', (
          tester,
        ) async {
          final session = await _open(tester, grid);
          final hand = await tester.startGesture(
            tester.getCenter(find.named('${grid.prefix}-layer-name-a2')),
          );
          await hand.cancel();
          await tester.pumpAndSettle();
          final before = grid.everyRow();

          session.selectCut(_second);
          await tester.pumpAndSettle();

          _expectKept(before, grid.everyRow());
        });

        testWidgets('the keyboard\'s focus in a row builds them afresh', (
          tester,
        ) async {
          // Room for the sheet's lane headers, under its layers' columns —
          // the tab as a window of 1400 × 1200 laid it.
          final session = await _open(
            tester,
            grid,
            surface: const Size(870, 546),
          );
          // A number being typed in the rows: a lane's, from its pencil.
          // ↩️It was the focus of the blend chip's ink well until that chip
          // became a rail plate (2026-10-24), which Tab passes over as every
          // rail button does (F-450-Q2) — a layer's own row holds nothing
          // the keyboard takes now.
          await tester.tap(
            find.byKey(const ValueKey<String>('legend-lanes-toggle')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.named('${grid.prefix}-lane-group-toggle-a2-transform-group'),
          );
          await tester.pumpAndSettle();
          final before = grid.everyRow();
          session.selectCut(_second);
          await tester.pumpAndSettle();
          session.selectCut(_first);
          await tester.pumpAndSettle();
          // What a switch with no hand in the rows keeps — a lane's own row
          // is built afresh either way.
          final kept = [
            for (final (index, family) in grid.everyRow().indexed)
              family.where(before[index].contains).toList(),
          ];
          for (final family in kept) {
            expect(family, isNotEmpty, reason: 'LIVENESS: rows are kept');
          }

          Finder keyed(RegExp pattern) => find.byWidgetPredicate(
            (widget) => switch (widget.key) {
              ValueKey<String>(:final value) => pattern.hasMatch(value),
              _ => false,
            },
          );
          final pencil = keyed(RegExp(r'-lane-value-a2-position-edit$'));
          await tester.ensureVisible(pencil);
          await tester.pumpAndSettle();
          await tester.tap(pencil);
          await tester.pumpAndSettle();
          final typed = find.descendant(
            of: keyed(RegExp('-lane-value-field-a2-')),
            matching: find.byType(EditableText),
          );
          expect(
            tester.widget<EditableText>(typed).focusNode.hasPrimaryFocus,
            isTrue,
            reason: 'LIVENESS: the focus is in the rows',
          );

          session.selectCut(_second);
          await tester.pumpAndSettle();

          final after = grid.everyRow();
          for (final (index, family) in kept.indexed) {
            expect(after[index].where(family.contains), isEmpty);
          }
        });
      });

      testWidgets('within a cut a row keeps its elements as the rows move, '
          'and a row that arrives never takes a stranger\'s', (tester) async {
        final session = await _open(tester, grid);
        Element row(String layer) => tester.element(grid.rowOf(layer));
        Element cells(String layer) => tester.element(grid.cellsOf(layer));
        final kept = {
          for (final layer in ['a1', 'a2', 'a3'])
            layer: (row(layer), cells(layer)),
        };

        // In ONE pass: a row leaves as another arrives, so the berth the
        // leaving row frees is there to be taken. Across two, the leaving
        // row's elements are gone before the next one is built at all.
        session.selectLayer(const LayerId('a2'));
        session.layerVerbs.deleteActiveLayer();
        session.selectLayer(const LayerId('a3'));
        session.layerStack.addLayerOfKind(LayerKind.animation);
        await tester.pumpAndSettle();
        final arrived = session.activeLayerId!.value;
        expect(
          arrived,
          isNot(anyOf('a1', 'a2', 'a3')),
          reason: 'LIVENESS: a new row arrived',
        );

        for (final layer in ['a1', 'a3']) {
          expect(row(layer), same(kept[layer]!.$1), reason: layer);
          expect(cells(layer), same(kept[layer]!.$2), reason: layer);
        }
        final gone = kept['a2']!;
        expect(row(arrived), isNot(same(gone.$1)));
        expect(cells(arrived), isNot(same(gone.$2)));
      });

      testWidgets('a selection that moves remounts nothing in the rows', (
        tester,
      ) async {
        final session = await _open(tester, grid);
        session.selectLayer(const LayerId('a1'));
        await tester.pumpAndSettle();
        final before = grid.everyRow();

        session.selectLayer(const LayerId('a3'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.named('${grid.layerRow}a3'),
            matching: find.named('${grid.prefix}-selected-layer'),
          ),
          findsOneWidget,
          reason: 'LIVENESS: the selection moved',
        );
        _expectKept(before, grid.everyRow());
      });
    });
  }
}

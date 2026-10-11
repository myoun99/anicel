import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/session/rail_view.dart';
import 'package:anicel/src/ui/timeline/lane_graph.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;

/// 🗣️F-302 (유저 2026-10-05): 「겸용컷, 레이어에서 fx 접기펼치기, 폴더/어태치
/// 접기/펼치기 버튼도 공유. 지금 겸용컷별로 독립적임. 펼친 상태 접힌 상태
/// 공유하라는것. 법통일」.
///
/// A press reaches every use of its row by itself; [RailView.followLinks]
/// is for the uses a command has just made — a row that JOINS a link group
/// wears the twirls and the folds of the group's canonical row.
void main() {
  const origin = LayerId('origin');
  const twin = LayerId('twin');
  const third = LayerId('third');
  const loner = LayerId('loner');

  LayerLinkMember use(String cut, LayerId row) => LayerLinkMember(
    trackId: const TrackId('t'),
    cutId: CutId(cut),
    layerId: row,
  );

  /// One group, its canonical row first.
  LayerLinkRegistry links(List<LayerId> rows) => LayerLinkRegistry(
    groups: [
      LayerLinkGroup(
        id: 'g',
        members: [
          for (final (index, row) in rows.indexed) use('cut-$index', row),
        ],
      ),
    ],
  );

  RailView rail() {
    final view = RailView();
    addTearDown(view.dispose);
    return view;
  }

  test('a row that joined a group wears its canonical row\'s twirl and '
      'fold', () {
    final view = rail()
      ..expandedLaneLayerIds.value = {origin, loner}
      ..collapsedAttachBaseIds.value = {origin};

    view.followLinks(links([origin, twin, third]));

    expect(view.expandedLaneLayerIds.value, {origin, twin, third, loner});
    expect(view.collapsedAttachBaseIds.value, {origin, twin, third});
  });

  test('🚨the CANONICAL row is the one followed: a joiner that stood open '
      'beside a shut canonical shuts — the group folds one way', () {
    final view = rail()
      ..expandedLaneLayerIds.value = {twin, loner}
      ..collapsedAttachBaseIds.value = {twin};

    view.followLinks(links([origin, twin]));

    expect(view.expandedLaneLayerIds.value, {loner});
    expect(view.collapsedAttachBaseIds.value, isEmpty);
  });

  test('a lane GROUP opens in every use of the row it is open in — that '
      'group, and no other', () {
    final view = rail()
      ..expandedLaneGroupKeys.value = {
        laneGroupKey(origin, 'transform-group'),
        // A group the canonical row keeps shut, open on the joiner alone.
        laneGroupKey(twin, 'fx:blur'),
        laneGroupKey(loner, 'fx:blur'),
      };

    view.followLinks(links([origin, twin]));

    expect(view.expandedLaneGroupKeys.value, {
      laneGroupKey(origin, 'transform-group'),
      laneGroupKey(twin, 'transform-group'),
      laneGroupKey(loner, 'fx:blur'),
    });
  });

  test('it answers at once for the table it last saw — a fold made since '
      'is not walked over', () {
    final view = rail();
    final table = links([origin, twin]);
    view.followLinks(table);
    var told = 0;
    view.expandedLaneLayerIds.addListener(() => told += 1);
    // Written past the presses, as a test or a reveal may: one use alone.
    view.expandedLaneLayerIds.value = {twin};
    told = 0;

    view.followLinks(table);

    expect(view.expandedLaneLayerIds.value, {twin});
    expect(told, 0);
  });

  test('sets that already agree are left as they are — nothing is told', () {
    final view = rail()
      ..expandedLaneLayerIds.value = {origin, twin}
      ..laneGraphs.value = LaneGraphsView(
        open: {
          for (final row in [origin, twin])
            laneGroupKey(row, 'transform-group'): const LaneGraph(),
        },
      );
    var told = 0;
    for (final set in <Listenable>[
      view.expandedLaneLayerIds,
      view.collapsedAttachBaseIds,
      view.expandedLaneGroupKeys,
      view.laneGraphs,
    ]) {
      set.addListener(() => told += 1);
    }

    view.followLinks(links([origin, twin]));

    expect(told, 0);
  });

  // I-89 ③: a graph and a pin are keyed by a row's lane, as an open group
  // is — so they follow a link group by the one rule; the graph with all
  // it keeps, its enlarging (③D) among it.
  test('an open GRAPH and a PIN follow the canonical row lane by lane, as '
      'its groups do', () {
    const graph = LaneGraph(
      extent: 140,
      mode: LaneGraphMode.speed,
      enlarged: true,
    );
    final view = rail()
      ..laneGraphs.value = LaneGraphsView(
        open: {
          laneGroupKey(origin, 'transform-group'): graph,
          // Open on the joiner alone: the canonical row keeps it shut.
          laneGroupKey(twin, 'fx-group:blur'): const LaneGraph(),
          laneGroupKey(loner, 'fx-group:blur'): const LaneGraph(),
        },
        pinned: {
          laneGroupKey(origin, 'position'),
          laneGroupKey(twin, 'rotation'),
          laneGroupKey(loner, 'rotation'),
        },
      );

    view.followLinks(links([origin, twin]));

    expect(view.laneGraphs.value.open, {
      laneGroupKey(origin, 'transform-group'): graph,
      laneGroupKey(twin, 'transform-group'): graph,
      laneGroupKey(loner, 'fx-group:blur'): const LaneGraph(),
    });
    expect(view.laneGraphs.value.pinned, {
      laneGroupKey(origin, 'position'),
      laneGroupKey(twin, 'position'),
      laneGroupKey(loner, 'rotation'),
    });
  });

  group('rows that wear one head (followHeads)', () {
    test('a group or a graph open on ANY row of a family is open on every '
        'row of it — a row keeps its own; a row of no family is left alone',
        () {
      const tall = LaneGraph(extent: 300);
      final view = rail()
        ..expandedLaneGroupKeys.value = {
          laneGroupKey(twin, 'transform-group'),
        }
        ..laneGraphs.value = LaneGraphsView(
          open: {
            laneGroupKey(twin, 'transform-group'): tall,
            laneGroupKey(third, 'transform-group'): const LaneGraph(),
            laneGroupKey(loner, 'fx-group:blur'): const LaneGraph(),
          },
          pinned: {laneGroupKey(origin, 'scale')},
        );

      view.followHeads([
        [origin, twin, third],
      ]);

      expect(view.expandedLaneGroupKeys.value, {
        for (final row in [origin, twin, third])
          laneGroupKey(row, 'transform-group'),
      });
      expect(view.laneGraphs.value.open, {
        laneGroupKey(origin, 'transform-group'): tall,
        laneGroupKey(twin, 'transform-group'): tall,
        laneGroupKey(third, 'transform-group'): const LaneGraph(),
        laneGroupKey(loner, 'fx-group:blur'): const LaneGraph(),
      });
      expect(view.laneGraphs.value.pinned, {
        for (final row in [origin, twin, third]) laneGroupKey(row, 'scale'),
      });
    });

    // 🚨Asked after EVERY history change, a stroke's included.
    test('nothing folded or open: the families are never read', () {
      final view = rail();
      var read = 0;
      Iterable<List<LayerId>> families() sync* {
        read += 1;
        yield [origin, twin];
      }

      view.followHeads(families());

      expect(read, 0);
    });

    test('however much is open, the families are read once', () {
      final view = rail()
        ..expandedLaneLayerIds.value = {origin}
        ..collapsedAttachBaseIds.value = {origin}
        ..expandedLaneGroupKeys.value = {laneGroupKey(origin, 'fx-group:a')}
        ..laneGraphs.value = LaneGraphsView(
          open: {laneGroupKey(origin, 'fx-group:a'): const LaneGraph()},
          pinned: {laneGroupKey(origin, 'fx:a:radius')},
        );
      var read = 0;
      Iterable<List<LayerId>> families() sync* {
        read += 1;
        yield [origin, twin];
      }

      view.followHeads(families());

      expect(read, 1);
      expect(view.laneGraphs.value.pinned, {
        laneGroupKey(origin, 'fx:a:radius'),
        laneGroupKey(twin, 'fx:a:radius'),
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_join.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/track_id.dart';

/// The join-or-open behind every link command (the audit's clone scan,
/// 2026-09-03). The first test is the one a mutant that ALWAYS opened a
/// new group survived at command level: no command test linked a third
/// cut to an already-linked pair, so the join arm went unmeasured.
void main() {
  const track = TrackId('v');
  LayerLinkMember member(String cut, String layer) => LayerLinkMember(
    trackId: track,
    cutId: CutId(cut),
    layerId: LayerId(layer),
  );

  test('an origin that already has a group takes the joiner INTO it', () {
    final groups = [
      LayerLinkGroup(
        id: 'g1',
        members: [member('c1', 'a'), member('c2', 'a2')],
      ),
      LayerLinkGroup(
        id: 'g2',
        members: [member('c1', 'b'), member('c2', 'b2')],
      ),
    ];

    final joined = linkGroupsJoined(
      groups,
      origin: member('c1', 'a'),
      joiner: member('c3', 'a3'),
      plannedGroupId: 'unused',
    );

    expect(joined.length, 2, reason: 'a third member, not a second group');
    expect(joined[0].id, 'g1');
    expect(joined[0].members, [
      member('c1', 'a'),
      member('c2', 'a2'),
      member('c3', 'a3'),
    ]);
    expect(joined[1], groups[1], reason: 'the other group is untouched');
    expect(
      groups[0].members.length,
      2,
      reason: 'the input list is not mutated',
    );
  });

  test('an origin in no group opens one under the planned id', () {
    final joined = linkGroupsJoined(
      const [],
      origin: member('c1', 'a'),
      joiner: member('c2', 'a2'),
      plannedGroupId: 'planned',
    );

    expect(joined, [
      LayerLinkGroup(
        id: 'planned',
        members: [member('c1', 'a'), member('c2', 'a2')],
      ),
    ]);
  });

  test('the canonical member is the origin — it holds the pixels', () {
    final joined = linkGroupsJoined(
      const [],
      origin: member('c9', 'z'),
      joiner: member('c1', 'z1'),
      plannedGroupId: 'p',
    );
    expect(joined.single.canonical, member('c9', 'z'));
  });

  test('no planned id for an unlinked origin is a programming error', () {
    expect(
      () => linkGroupsJoined(
        const [],
        origin: member('c1', 'a'),
        joiner: member('c2', 'a2'),
        plannedGroupId: null,
      ),
      throwsStateError,
    );
  });
}

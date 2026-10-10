import 'package:flutter/foundation.dart';

import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../timeline/lane_graph.dart' show LaneGraphsView;
import '../timeline/property_lane_model.dart'
    show laneGroupKey, parseLaneGroupKey;
import '../timeline/timeline_row_filter.dart';
import '../timeline/timeline_section_policy.dart';

/// The standing law's shape (`Standing.keepStandingShown`), for the doors
/// that seat a row outside the session's own rebuild.
typedef StandingLaw = void Function({bool reveal, bool filterSparesStanding});

/// THE RAIL'S VIEW — which layer rows the rail leaves off the screen by a
/// choice of the user's that is not the document's: the hidden sections,
/// the row filter and the folded attach groups — and which it opens up: the
/// property-lane twirls, and the graphs standing in a group's lanes' place.
/// View state: session-only, never saved, and it
/// outlives the panels that draw it (a tab switch keeps it). A FOLDER's fold
/// is not here — it is `Layer.collapsed`, the file's.
///
/// 🚨F-169 (유저 2026-09-24): 「보이는거만 선택가능하고 안보이는거 선택되는
/// 상황엔 다른 보이는레이어 선택하도록」. The three lived on the workspace, and
/// the session's hand-off — a delete, an undo — could not ask whether the row
/// it picked was on screen. It picked one inside a folded attach group, and
/// the rail unfolded that row to show where you stood. They live here so the
/// law that keeps you on a shown row ([Standing.keepStandingShown]) reads
/// the same three the grids draw by.
///
/// 🚨The twirls joined them with I-7 (a project per tab): they name LAYER
/// IDS, which are the project's — every new project's first layer has the
/// same one — so a set the workspace kept for the window twirled the layer
/// open in every tab, and undoing a twirl in one project reached a set the
/// others were reading.
class RailView {
  /// SE/camera sections hidden from the grids (the timeline toolbar's
  /// toggles, the retired section fold's replacement).
  final ValueNotifier<Set<TimelineSection>> hiddenSections = ValueNotifier(
    const <TimelineSection>{},
  );

  /// The row FILTER (R2): hides layer rows failing its facets. One filter
  /// across the surfaces (R5 #9) — the timeline, the sheet and the
  /// storyboard read this same value.
  final ValueNotifier<TimelineRowFilter> rowFilter = ValueNotifier(
    TimelineRowFilter.none,
  );

  /// Bases whose ATTACH GROUP is twirled shut (UI-R20 #9). Default open: a
  /// fresh attach layer must be visible the moment it is made.
  final ValueNotifier<Set<LayerId>> collapsedAttachBaseIds = ValueNotifier(
    const <LayerId>{},
  );

  /// Layers whose AE-style property-lane twirl-down is open. The walk
  /// reads it too: property rows are stops (R10 #19).
  final ValueNotifier<Set<LayerId>> expandedLaneLayerIds = ValueNotifier(
    const <LayerId>{},
  );

  /// LANE GROUPS twirled open inside a layer's twirl-down (AE group
  /// collapse — default collapsed). Keyed by `laneGroupKey`, because a row
  /// carries more than one group: Transform, plus one header per R6 effect.
  final ValueNotifier<Set<String>> expandedLaneGroupKeys = ValueNotifier(
    const <String>{},
  );

  /// The HEADER GRAPHS (I-89 ③): which lane groups stand open as a graph,
  /// and the lanes pinned to every graph. View state as the twirls beside
  /// it are, and followed as they are ([followLinks], [followHeads]): a
  /// graph and a pin are keyed by a row's lane, as an open group is.
  final ValueNotifier<LaneGraphsView> laneGraphs = ValueNotifier(
    LaneGraphsView.none,
  );

  /// The link table the view state below was last made to agree with.
  LayerLinkRegistry? _followed;

  /// 🗣️F-302 (유저 2026-10-05): 「겸용컷, 레이어에서 fx 접기펼치기,
  /// 폴더/어태치 접기/펼치기 버튼도 공유. 지금 겸용컷별로 독립적임. 펼친
  /// 상태 접힌 상태 공유하라는것. 법통일」 — a row that JOINED a link group
  /// wears the group's twirls and folds: its CANONICAL row's
  /// ([LayerLinkGroup.canonical] — the row a 겸용 cut was made from).
  ///
  /// A press reaches every use of its row by itself (the toggles take the
  /// row's other uses along), so the sets already agree inside every group
  /// that stood; this is for the uses a command just made — a new 겸용 cut's
  /// rows have ids nothing was ever folded by. Asked after a command, an
  /// undo and a redo, and it answers at once while [links] is the table it
  /// last saw.
  void followLinks(LayerLinkRegistry links) {
    if (identical(links, _followed)) {
      return;
    }
    _followed = links;
    for (final rows in [collapsedAttachBaseIds, expandedLaneLayerIds]) {
      final next = Set<LayerId>.of(rows.value);
      for (final group in links.groups) {
        final uses = [for (final member in group.members) member.layerId];
        if (next.contains(group.canonical.layerId)) {
          next.addAll(uses);
        } else {
          next.removeAll(uses);
        }
      }
      if (!setEquals(next, rows.value)) {
        rows.value = next;
      }
    }
    Map<String, V> likeCanonical<V>(Map<String, V> worn) =>
        _wornLikeCanonical(worn, links);
    _followLanes(likeCanonical);
  }

  /// Rows that wear ONE head though no link holds them — a track's conte
  /// rows at one seat (I-73, 유저 2026-10-08: 「콘티레이어 권고한대로 머리만
  /// 한벌 ok. 맘에드는생각이야. 겸용컷이랑 같은 느낌이네」) — fold and twirl
  /// as one, as a link group's rows do ([followLinks]).
  ///
  /// A press reaches every row of the family by itself, so inside a family
  /// that stood the sets already agree; this is for the row a command just
  /// made — a new cut's conte, an attach row added to one — which takes on
  /// what the others wear. ⚠️No row of a family is its canonical one (the
  /// head is whichever cut comes first, and a cut can be put before it), so
  /// the rule asks the family: where ANY row is in a set, every row is.
  ///
  /// [families] is read once, and only while something is folded or open:
  /// it is asked after every history change, a stroke's included.
  void followHeads(Iterable<List<LayerId>> families) {
    List<List<LayerId>>? read;
    List<List<LayerId>> every() => read ??= families.toList();
    for (final rows in [collapsedAttachBaseIds, expandedLaneLayerIds]) {
      if (rows.value.isEmpty) {
        continue;
      }
      final next = Set<LayerId>.of(rows.value);
      for (final family in every()) {
        if (family.any(next.contains)) {
          next.addAll(family);
        }
      }
      if (!setEquals(next, rows.value)) {
        rows.value = next;
      }
    }
    Map<String, V> acrossFamilies<V>(Map<String, V> worn) =>
        worn.isEmpty ? worn : _wornAcrossFamilies(worn, every());
    _followLanes(acrossFamilies);
  }

  /// What the rail keeps by a row's LANE — the groups open inside its
  /// lanes, its open graphs and its pins — made to wear what [wear] says,
  /// each told only where that changed. ONE rule for the three, so a group
  /// and the graph standing in its lanes cannot follow a row two ways.
  void _followLanes(Map<String, V> Function<V>(Map<String, V> worn) wear) {
    final groups = wear(_worn(expandedLaneGroupKeys.value)).keys.toSet();
    if (!setEquals(groups, expandedLaneGroupKeys.value)) {
      expandedLaneGroupKeys.value = groups;
    }
    final graphs = laneGraphs.value;
    final followed = graphs.copyWith(
      open: wear(graphs.open),
      pinned: wear(_worn(graphs.pinned)).keys.toSet(),
    );
    if (followed != graphs) {
      laneGraphs.value = followed;
    }
  }

  void dispose() {
    hiddenSections.dispose();
    rowFilter.dispose();
    collapsedAttachBaseIds.dispose();
    expandedLaneLayerIds.dispose();
    expandedLaneGroupKeys.dispose();
    laneGraphs.dispose();
  }
}

/// A set of keys as what its rows wear: each key, worn.
Map<String, bool> _worn(Set<String> keys) => {
  for (final key in keys) key: true,
};

/// [worn] — what rows wear, by `laneGroupKey` — with every use of a link
/// group's row wearing what its CANONICAL row wears, lane by lane, and
/// nothing of its own ([RailView.followLinks]).
Map<String, V> _wornLikeCanonical<V>(
  Map<String, V> worn,
  LayerLinkRegistry links,
) {
  final next = Map<String, V>.of(worn);
  for (final group in links.groups) {
    final uses = {for (final member in group.members) member.layerId};
    final canonical = {
      for (final MapEntry(:key, :value) in worn.entries)
        if (parseLaneGroupKey(key) case final row?
            when row.layerId == group.canonical.layerId)
          row.laneId: value,
    };
    next.removeWhere(
      (key, _) => uses.contains(parseLaneGroupKey(key)?.layerId),
    );
    for (final use in uses) {
      for (final MapEntry(key: laneId, :value) in canonical.entries) {
        next[laneGroupKey(use, laneId)] = value;
      }
    }
  }
  return next;
}

/// [worn] with every row of a family wearing, lane by lane, what any row of
/// it wears — a row keeps its own where it has one ([RailView.followHeads]):
/// a conte's Transform and effect groups, twirled on the storyboard's conte
/// row as on the timeline's (I-73 ④ⓔ), and the graphs in their place. A row
/// a command just made takes on what the others show, so the rows a
/// projection row draws do not come and go with the cut it stands in.
Map<String, V> _wornAcrossFamilies<V>(
  Map<String, V> worn,
  List<List<LayerId>> families,
) {
  final next = Map<String, V>.of(worn);
  for (final family in families) {
    final members = family.toSet();
    final across = <String, V>{};
    for (final MapEntry(:key, :value) in worn.entries) {
      if (parseLaneGroupKey(key) case final row?
          when members.contains(row.layerId)) {
        across.putIfAbsent(row.laneId, () => value);
      }
    }
    for (final member in family) {
      for (final MapEntry(key: laneId, :value) in across.entries) {
        next.putIfAbsent(laneGroupKey(member, laneId), () => value);
      }
    }
  }
  return next;
}

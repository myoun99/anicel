import 'package:flutter/foundation.dart';

import '../../models/attached_layer_resolve.dart' show canCarryAttachedLayers;
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart';
import '../../models/project.dart';
import '../../services/project_lookup.dart' show projectLayersAnywhere;
import '../timeline/lane_graph.dart' show LaneGraphsView;
import '../timeline/property_lane_model.dart'
    show laneGroupKey, parseLaneGroupKey;
import '../timeline/timeline_row_filter.dart';
import '../timeline/timeline_section_policy.dart';

/// The standing law's shape (`Standing.keepStandingShown`), for the doors
/// that seat a row outside the session's own rebuild.
typedef StandingLaw = void Function({bool reveal, bool filterSparesStanding});

/// THE RAIL'S VIEW — which layer rows the rail leaves off the screen: by a
/// choice of the user's that is not the document's, the hidden sections and
/// the row filter; by the rows' own folds, the folded attach groups — and
/// which it opens up: the property-lane twirls and their groups (the rows'
/// own too), and the graphs standing in a group's lanes' place. It outlives
/// the panels that draw it (a tab switch keeps it).
///
/// 🚨★★★F-360 (유저 2026-10-14: 「어태치레이어 분명 접은채로 저장했는데
/// 다시열면 펼쳐져있음. fx나 폴더나 이런 접음/펼침상태가 기록이 안되는건지?
/// 제대로 기록되도록」): THE FOLDS AND TWIRLS ARE THE ROWS' — `Layer.collapsed`,
/// `Layer.lanesExpanded`, `Layer.expandedLaneGroups`, the folder's path:
/// written by one command on every row of the row's head, undone, saved.
/// What is here of them is the rail's READING of the document
/// ([readFolds]), which nothing outside can write. ↩️They were view state
/// here — session-only, never saved, kept in agreement across a link group
/// and a head by [followLinks] and [followHeads] beside a folder's fold
/// that the commands carried — two ways for one fold.
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

  /// Bases whose ATTACH GROUP is twirled shut (UI-R20 #9) — the bases whose
  /// `collapsed` is set ([readFolds]). Default open: a fresh attach layer
  /// must be visible the moment it is made.
  ValueListenable<Set<LayerId>> get collapsedAttachBaseIds =>
      _collapsedAttachBaseIds;
  final _collapsedAttachBaseIds = ValueNotifier(const <LayerId>{});

  /// Layers whose AE-style property-lane twirl-down is open
  /// (`Layer.lanesExpanded`). The walk reads it too: property rows are
  /// stops (R10 #19).
  ValueListenable<Set<LayerId>> get expandedLaneLayerIds =>
      _expandedLaneLayerIds;
  final _expandedLaneLayerIds = ValueNotifier(const <LayerId>{});

  /// LANE GROUPS twirled open inside a layer's twirl-down (AE group
  /// collapse — default collapsed; `Layer.expandedLaneGroups`). Keyed by
  /// `laneGroupKey`, because a row carries more than one group: Transform,
  /// plus one header per R6 effect.
  ValueListenable<Set<String>> get expandedLaneGroupKeys =>
      _expandedLaneGroupKeys;
  final _expandedLaneGroupKeys = ValueNotifier(const <String>{});

  /// The document the three above were last read off.
  Project? _foldsReadOff;

  /// The rows' folds and twirls as [project] holds them — the three sets
  /// above, each told only where it changed. Asked after every history
  /// change, after a write outside history that opens a fold (the standing
  /// law's reveal), and when the session is made: a fold is not written
  /// anywhere else. Free while the project is the one it last read.
  void readFolds(Project? project) {
    if (identical(project, _foldsReadOff)) {
      return;
    }
    _foldsReadOff = project;
    final folded = <LayerId>{};
    final twirled = <LayerId>{};
    final groups = <String>{};
    final layers = project == null
        ? const <Layer>[]
        : projectLayersAnywhere(project);
    for (final layer in layers) {
      if (layer.collapsed && canCarryAttachedLayers(layer)) {
        folded.add(layer.id);
      }
      if (layer.lanesExpanded) {
        twirled.add(layer.id);
      }
      for (final laneId in layer.expandedLaneGroups) {
        groups.add(laneGroupKey(layer.id, laneId));
      }
    }
    _tell(_collapsedAttachBaseIds, folded);
    _tell(_expandedLaneLayerIds, twirled);
    _tell(_expandedLaneGroupKeys, groups);
  }

  static void _tell<T>(ValueNotifier<Set<T>> rows, Set<T> next) {
    if (!setEquals(next, rows.value)) {
      rows.value = next;
    }
  }

  /// The HEADER GRAPHS (I-89 ③): which lane groups stand open as a graph,
  /// and the lanes pinned to every graph. View state, followed across a
  /// link group and a head ([followLinks], [followHeads]): a graph and a
  /// pin are keyed by a row's lane, as an open group is.
  ///
  /// 🗣️A VIEW SETTING (유저 답 F-360-Q1 「보기 설정처럼 — 저장은 되고 언두는
  /// 안 됨」): the file keeps it beside the project with the zooms and the
  /// scrolls (`ProjectResume.laneGraphs`), and turning one takes no undo
  /// step and marks nothing unsaved — where the groups it stands in are the
  /// rows' folds (F-360), undone and saved with the project.
  final ValueNotifier<LaneGraphsView> laneGraphs = ValueNotifier(
    LaneGraphsView.none,
  );

  /// The STORYBOARD rail's own twirls — its S rows' audio lanes (by
  /// `StoryboardPanel.seRowKey`), its V tracks' lanes (by track id) and the
  /// Transform groups under them (by `laneGroupKey`): that rail's row keys,
  /// not a layer's lanes, so beside the timeline's sets above rather than in
  /// them.
  ///
  /// ↩️The storyboard's tab host kept them, 「lost on tab switch for now …
  /// hoist to the workspace if that stings」 — held only by the panel being
  /// kept alive. A panel is built only while it shows now (유저 2026-10-14),
  /// so here, with the timeline's, they outlive it.
  final ValueNotifier<Set<String>> storyboardSeAudioRows = ValueNotifier(
    const <String>{},
  );

  final ValueNotifier<Set<String>> storyboardTransformTracks = ValueNotifier(
    const <String>{},
  );

  final ValueNotifier<Set<String>> storyboardTransformGroups = ValueNotifier(
    const <String>{},
  );

  /// The link table the graphs were last made to agree with.
  LayerLinkRegistry? _followed;

  /// 🗣️F-302 (유저 2026-10-05): 「겸용컷, 레이어에서 fx 접기펼치기,
  /// 폴더/어태치 접기/펼치기 버튼도 공유. 지금 겸용컷별로 독립적임. 펼친
  /// 상태 접힌 상태 공유하라는것. 법통일」 — a row that JOINED a link group
  /// wears the group's graphs and pins: its CANONICAL row's
  /// ([LayerLinkGroup.canonical] — the row a 겸용 cut was made from).
  ///
  /// A press reaches every use of its row by itself (the presses take the
  /// row's other uses along), so the graphs already agree inside every
  /// group that stood; this is for the uses a command just made — a new 겸용
  /// cut's rows have ids no graph was ever opened by. Asked after a
  /// command, an undo and a redo, and it answers at once while [links] is
  /// the table it last saw.
  ///
  /// ↩️It made the rows' folds and twirls agree too, until F-360 put them on
  /// the rows: a new use is born wearing them, as it is born wearing its
  /// name.
  void followLinks(LayerLinkRegistry links) {
    if (identical(links, _followed)) {
      return;
    }
    _followed = links;
    Map<String, V> likeCanonical<V>(Map<String, V> worn) =>
        _wornLikeCanonical(worn, links);
    _followGraphs(likeCanonical);
  }

  /// Rows that wear ONE head though no link holds them — a track's conte
  /// rows at one seat (I-73, 유저 2026-10-08: 「콘티레이어 권고한대로 머리만
  /// 한벌 ok. 맘에드는생각이야. 겸용컷이랑 같은 느낌이네」) — open their
  /// graphs as one, as a link group's rows do ([followLinks]).
  ///
  /// A press reaches every row of the family by itself, so inside a family
  /// that stood the graphs already agree; this is for the row a command
  /// just made — a new cut's conte, an attach row added to one — which
  /// takes on what the others wear. ⚠️No row of a family is its canonical
  /// one (the head is whichever cut comes first, and a cut can be put
  /// before it), so the rule asks the family: where ANY row has one, every
  /// row has.
  ///
  /// [families] is read once, and only while a graph is open or a lane
  /// pinned: it is asked after every history change, a stroke's included.
  ///
  /// ↩️The folds and the twirls were followed here too, until F-360 — the
  /// row a command makes in a family wears them: a conte row its track's
  /// structure's (`ConteHead`, F-343), a camera the track's camera head
  /// (`cameraWearingHeadOf`).
  void followHeads(Iterable<List<LayerId>> families) {
    List<List<LayerId>>? read;
    List<List<LayerId>> every() => read ??= families.toList();
    Map<String, V> acrossFamilies<V>(Map<String, V> worn) =>
        worn.isEmpty ? worn : _wornAcrossFamilies(worn, every());
    _followGraphs(acrossFamilies);
  }

  /// What the rail keeps by a row's LANE — its open graphs and its pins —
  /// made to wear what [wear] says, told only where that changed. ONE rule
  /// for the two.
  ///
  /// ↩️The groups open inside a row's lanes were the third — 「ONE rule for
  /// the three, so a group and the graph standing in its lanes cannot
  /// follow a row two ways」. F-360 put the groups on the rows, so a group
  /// follows its row by the head's one command and a born row's head, and a
  /// graph — a view setting (F-360-Q1) — by this. They agree
  /// on every row that is born from another — a new use and a new conte
  /// row take the rows they come from — and on every press, which reaches
  /// both through the same head.
  void _followGraphs(Map<String, V> Function<V>(Map<String, V> worn) wear) {
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
    _collapsedAttachBaseIds.dispose();
    _expandedLaneLayerIds.dispose();
    _expandedLaneGroupKeys.dispose();
    laneGraphs.dispose();
    storyboardSeAudioRows.dispose();
    storyboardTransformTracks.dispose();
    storyboardTransformGroups.dispose();
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

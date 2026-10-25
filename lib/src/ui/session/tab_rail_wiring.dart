import 'package:flutter/foundation.dart' show immutable;

import '../../core/set_toggle.dart';
import '../../models/layer_id.dart';
import '../editor_session_manager.dart';
import '../timeline/lane_graph.dart' show LaneGraphVerbs, LaneGraphsView;
import '../timeline/timeline_row_filter.dart';
import '../timeline/timeline_section_policy.dart';
import 'session_row_button_presses.dart';

/// THE RAIL AS A TAB TAKES IT: [EditorSessionManager.railView] as it stands
/// when this is made — the twirls, the header graphs, the hidden sections,
/// the row filter, the folded attach groups — and the verbs that turn it.
/// The timeline's tab and the conte's take the same: they show one rail's
/// view (R5 #9 the filter, F-199 the sections, I-73 the folds and twirls,
/// I-89 ① the graphs).
///
/// 🗣️tests-hand-roll-the-tab-hosts-Q1 b (유저 2026-10-25: 「배선을 lib 한
/// 곳으로」). The workspace wrote this wiring once per tab; the two test
/// harnesses wrote it again, the conte's without the filter or the
/// sections; seventy test files wrote a part of it, most of them none —
/// a tab nobody shows. A host takes this or is not built.
///
/// Read when made: a tab is built again when the view moves
/// ([RailView.drawn]), and takes the view of that build.
@immutable
class TabRailWiring {
  TabRailWiring.of(this._session)
    : expandedLaneLayerIds = _session.railView.expandedLaneLayerIds.value,
      expandedLaneGroupKeys = _session.railView.expandedLaneGroupKeys.value,
      laneGraphs = _session.railView.laneGraphs.value,
      hiddenSections = _session.railView.hiddenSections.value,
      rowFilter = _session.railView.rowFilter.value,
      collapsedAttachBaseIds =
          _session.railView.collapsedAttachBaseIds.value;

  final EditorSessionManager _session;

  /// The rows' buttons as a press asks them — across the row selection when
  /// the pressed row is in it (I-32).
  SessionRowButtonPresses get _presses => SessionRowButtonPresses(_session);

  /// The rows whose property lanes are twirled down.
  final Set<LayerId> expandedLaneLayerIds;
  void toggleLayerLanes(LayerId pressed) => _presses.toggleLanes(pressed);

  /// The lane GROUPS twirled open in them, by `laneGroupKey`.
  final Set<String> expandedLaneGroupKeys;
  void toggleLaneGroup(String groupKey) => _presses.toggleLaneGroup(groupKey);

  /// The header graphs standing in a group's lanes' place, and their
  /// buttons.
  final LaneGraphsView laneGraphs;
  LaneGraphVerbs get laneGraphVerbs => _presses.laneGraphVerbs;

  /// The SE / camera sections the toolbar's toggles hide.
  final Set<TimelineSection> hiddenSections;
  void toggleSection(TimelineSection section) {
    final hidden = _session.railView.hiddenSections;
    hidden.value = toggledSet(hidden.value, section);
    // F-169: hiding the section you stand in hands the standing on.
    _session.standing.keepStandingShown();
  }

  /// The legend's row filter.
  final TimelineRowFilter rowFilter;
  void setRowFilter(TimelineRowFilter filter) {
    _session.railView.rowFilter.value = filter;
    // UI-R6 #3: a non-passing active layer moves to the nearest passing
    // layer above it (instead of lingering through the exemption).
    _session.standing.keepStandingShown(filterSparesStanding: false);
  }

  /// The bases whose attach group is folded; the base row's chevron — one
  /// chevron, a folder's fold or the attach group's (I-32).
  final Set<LayerId> collapsedAttachBaseIds;
  void toggleAttachGroup(LayerId pressed) => _presses.toggleGroupFold(pressed);
}

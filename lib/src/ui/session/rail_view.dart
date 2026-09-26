import 'package:flutter/foundation.dart';

import '../../models/layer_id.dart';
import '../timeline/timeline_row_filter.dart';
import '../timeline/timeline_section_policy.dart';

/// The standing law's shape (`Standing.keepStandingShown`), for the doors
/// that seat a row outside the session's own rebuild.
typedef StandingLaw = void Function({bool reveal, bool filterSparesStanding});

/// THE RAIL'S VIEW — which layer rows the rail leaves off the screen by a
/// choice of the user's that is not the document's: the hidden sections,
/// the row filter and the folded attach groups — and which it opens up: the
/// property-lane twirls. View state: session-only, never saved, and it
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

  void dispose() {
    hiddenSections.dispose();
    rowFilter.dispose();
    collapsedAttachBaseIds.dispose();
    expandedLaneLayerIds.dispose();
    expandedLaneGroupKeys.dispose();
  }
}

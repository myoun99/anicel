import 'package:flutter/widgets.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/tab_rail_wiring.dart';

/// THE ROWS' TWIRLS AS THE WORKSPACE WIRES THEM into a storyboard panel
/// (`workspace_tabs.dart`): the tab's own wiring ([TabRailWiring]) — read
/// off the session's rail view and turned by its presses, a row's twirl
/// being the row's (F-360): an S row's its SE row's, the timeline's row
/// too, and the V row's its track's.
///
/// ↩️A storyboard harness kept sets of its own for the S and V rows, as the
/// host did, and toggled them by hand. ↩️Then this read the session's rail
/// view itself, beside the workspace that read it too
/// (tests-hand-roll-the-tab-hosts, 2026-10-25). A test that mounts the TAB
/// pumps `pumpStoryboardHost`; this is for one that mounts the panel.
typedef StoryboardTwirls = ({
  Set<LayerId> expandedLaneLayerIds,
  ValueChanged<LayerId> onToggleLayerLanes,
  Set<String> expandedLaneGroupKeys,
  ValueChanged<String> onToggleLaneGroupKey,
  bool Function(LayerId layerId) layerLanesOpenOf,
});

/// [build] with [session]'s twirls as they stand, built again whenever one
/// moves — as the workspace builds the storyboard's tab.
Widget withStoryboardTwirls(
  EditorSessionManager session,
  Widget Function(StoryboardTwirls twirls) build,
) {
  final rail = session.railView;
  return ListenableBuilder(
    listenable: Listenable.merge([
      session,
      rail.expandedLaneLayerIds,
      rail.expandedLaneGroupKeys,
      rail.twirledTrackIds,
    ]),
    builder: (context, _) {
      final wiring = TabRailWiring.of(session);
      return build((
        expandedLaneLayerIds: wiring.expandedLaneLayerIds,
        onToggleLayerLanes: wiring.toggleLayerLanes,
        expandedLaneGroupKeys: wiring.expandedLaneGroupKeys,
        onToggleLaneGroupKey: wiring.toggleLaneGroup,
        layerLanesOpenOf: session.layerSwitches.isLayerLanesOpen,
      ));
    },
  );
}

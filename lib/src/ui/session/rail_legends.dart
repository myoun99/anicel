import '../../models/working_panel.dart';
import '../timeline/timeline_legend_menus.dart';
import '../widgets/panel_flyout.dart';

/// What each panel's rail legend opens right now — published by the panel
/// as it builds its header, and pressed one row at a time by a key on the
/// panel being worked in (I-40).
///
/// ★The rows are the ones the header shows: the panel hands over the very
/// menus its header was built with (`TimelineLayerControlsHeader.menus`),
/// counted on its own rows — the marks and kinds on them, the rows it
/// displays. ⛔Nothing counts them a second time for the key.
///
/// A panel whose header opens nothing, or that is not mounted, has nothing
/// here: a key presses only a row its menu would show.
class RailLegends {
  final Map<WorkingPanel, TimelineLegendMenus> _menus = {};

  void publish(WorkingPanel panel, TimelineLegendMenus? menus) {
    if (menus == null) {
      _menus.remove(panel);
    } else {
      _menus[panel] = menus;
    }
  }

  /// Every row [panel]'s legend would open right now.
  List<PanelFlyoutItem> rowsOf(WorkingPanel panel) =>
      _menus[panel]?.rows() ?? const [];
}

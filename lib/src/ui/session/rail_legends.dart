import '../../models/working_panel.dart';
import '../canvas/view_hand.dart';
import '../timeline/timeline_legend_menus.dart';
import '../widgets/panel_flyout.dart';

/// What each panel's rail legend opens right now — written by the panel as
/// it builds its header, and pressed one row at a time by a key on the
/// panel being worked in (I-40).
///
/// ★The rows are the ones the header shows: the panel hands over the very
/// menus its header was built with (`TimelineLayerControlsHeader.menus`),
/// counted on its own rows — the marks and kinds on them, the rows it
/// displays. ⛔Nothing counts them a second time for the key.
///
/// A panel whose header opens nothing, or that is not mounted, has nothing
/// here: a key presses only a row its menu would show.
///
/// 🚨A PANEL HOLDS ITS LEGEND UP IN A [ViewHand] (the F-419 law): a panel
/// built anew comes up before the one it replaces goes down. ↩️The panels
/// told a callback their menus at every build and null from `dispose`, so
/// the old panel's null came last and the key pressed nothing until the new
/// panel built again (card `rail-legend-menus-lost-to-an-old-goodbye`).
/// Now each mounted panel holds up its own [RailLegendHold] and writes into
/// it; the one up now is the panel that came up last.
class RailLegends {
  final Map<WorkingPanel, ViewHand<RailLegendHold>> _hands = {};

  /// The hand [panel]'s legend is held up in.
  ViewHand<RailLegendHold> handOf(WorkingPanel panel) =>
      _hands.putIfAbsent(panel, ViewHand.new);

  /// Every row [panel]'s legend would open right now.
  List<PanelFlyoutItem> rowsOf(WorkingPanel panel) =>
      _hands[panel]?.now?.menus?.rows() ?? const [];
}

/// One mounted panel's legend: the menus its header was last built with,
/// or null while that header opens nothing.
class RailLegendHold {
  TimelineLegendMenus? menus;
}

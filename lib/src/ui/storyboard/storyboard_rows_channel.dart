import '../../models/timeline_row_address.dart';
import '../canvas/flip_hud_controller.dart' show FlipHudAxis;
import '../canvas/flip_hud_model.dart';

/// What the STORYBOARD panel stacks, handed to the shell's walkers — the
/// ↑/↓ walk and the flip window — for the time the storyboard is the panel
/// being worked in (유저 2026-09-24: 「위아래 이동이 타임라인 내부로 샌다거나
/// 그런거 싹 다 해결」).
///
/// ★Bound by the panel that DRAWS the rows, from the one table its rail, its
/// bands and its select-drag already read — so the walk and the screen
/// cannot disagree about which rows exist, the rule the timeline's walk keeps
/// by reading its grids' own row builder.
///
/// ⚠️Owner-scoped, like every command channel here (유저 #13: 「화살표
/// 위아래나 플립 위아래로 레이어이동이 안먹힘」): a panel moving between docks
/// mounts its new State before it disposes the old one, so only whoever
/// bound the channel may unbind it.
class StoryboardRowsChannel {
  List<TimelineRowAddress> Function()? _rows;
  FlipHudSnapshot Function(FlipHudAxis axis)? _snapshotOf;
  Object? _owner;

  void bind(
    Object owner, {
    required List<TimelineRowAddress> Function() rows,
    required FlipHudSnapshot Function(FlipHudAxis axis) snapshotOf,
  }) {
    _owner = owner;
    _rows = rows;
    _snapshotOf = snapshotOf;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }
    _owner = null;
    _rows = null;
    _snapshotOf = null;
  }

  /// The storyboard's rows, top to bottom — every track's rows in the order
  /// the panel stacks them. Empty while no storyboard is mounted.
  List<TimelineRowAddress> get rows => _rows?.call() ?? const [];

  /// The flip window's picture of those rows; null while no storyboard is
  /// mounted.
  FlipHudSnapshot? snapshotFor(FlipHudAxis axis) => _snapshotOf?.call(axis);
}

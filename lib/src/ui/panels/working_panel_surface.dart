import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// THE SURFACE of a panel the frame verbs answer to — the timeline's, the
/// storyboard's: what touching it and losing sight of it say.
///
/// A press anywhere inside is a touch ([onTouch]; 유저 2026-08-05 「마지막으로
/// 무언가 액션이 있었던 패널을 기준으로」, 2026-09-24 「콘티패널내부의 어느
/// 공간 클릭하던」). Translucent: every child still gets its own gesture; this
/// only listens.
///
/// Whether the panel is on the screen ([onSight]) is whether it is mounted:
/// a panel is built only while it shows (유저 2026-10-14), so its tab put
/// behind another, its rail group shut and the panel closed all unmount it,
/// which says false (유저 2026-09-25 「화면에 남은 쪽이 받는다」).
///
/// ↩️The press was a `Listener` written into each host, the same lines
/// twice. The sight is the half the 09-25 answer added, beside it.
class WorkingPanelSurface extends StatefulWidget {
  const WorkingPanelSurface({
    super.key,
    required this.onTouch,
    required this.onSight,
    required this.child,
  });

  final VoidCallback onTouch;

  /// Says whether THIS surface shows its panel. A panel moving between docks
  /// has two surfaces for a frame — the new one mounts before the old one is
  /// gone — so each speaks for itself ([surface]).
  final void Function(Object surface, {required bool inSight}) onSight;
  final Widget child;

  @override
  State<WorkingPanelSurface> createState() => _WorkingPanelSurfaceState();
}

class _WorkingPanelSurfaceState extends State<WorkingPanelSurface> {
  @override
  void initState() {
    super.initState();
    _say(true);
  }

  /// Said AFTER the frame: a panel is mounted and unmounted while the tree
  /// is locked — and what hears the answer rebuilds panels outside this one.
  void _say(bool inSight) {
    final onSight = widget.onSight;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => onSight(this, inSight: inSight),
    );
  }

  @override
  void dispose() {
    _say(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => widget.onTouch(),
    child: widget.child,
  );
}

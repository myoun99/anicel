import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The app's shared "why nothing happened" channel (R26 #35/#13).
///
/// A refused action — drawing where no cel exists, switching to the
/// transform tool with nothing to transform — says so RIGHT WHERE the
/// user is looking, for about a second, and then disappears. Refusals
/// never open dialogs and never mutate anything.
///
/// The controller is UI-free on purpose: call sites just say what
/// happened, and whatever [CursorNoticeOverlay] is mounted renders it.
/// Re-skinning the notice later touches the overlay alone.
class CursorNoticeController extends ChangeNotifier {
  static const Duration defaultDuration = Duration(milliseconds: 1000);

  String? _message;
  int _revision = 0;
  Timer? _timer;

  /// The live message (null = nothing showing).
  String? get message => _message;

  /// Bumps on every [show] — lets a listener restart its animation even
  /// when the same message repeats.
  int get revision => _revision;

  void show(String message, {Duration duration = defaultDuration}) {
    _message = message;
    _revision += 1;
    _timer?.cancel();
    _timer = Timer(duration, clear);
    notifyListeners();
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    if (_message == null) {
      return;
    }
    _message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The app-wide notice channel. Static because refusals happen deep in
/// gesture code that has no business threading a controller upward —
/// the same reasoning as the panel-flash controller.
final CursorNoticeController cursorNotices = CursorNoticeController();

/// Renders [controller]'s live message next to the pointer.
///
/// Wraps the editor body: it tracks the pointer passively (a translucent
/// [Listener] plus [MouseRegion] hover, never a gesture-arena member) so
/// the notice can appear at the cursor even when the refusal came from a
/// keyboard shortcut — in that case the last known pointer position is
/// used, falling back to the center.
class CursorNoticeOverlay extends StatefulWidget {
  CursorNoticeOverlay({
    super.key,
    required this.child,
    CursorNoticeController? controller,
  }) : controller = controller ?? cursorNotices;

  final Widget child;
  final CursorNoticeController controller;

  @override
  State<CursorNoticeOverlay> createState() => _CursorNoticeOverlayState();
}

class _CursorNoticeOverlayState extends State<CursorNoticeOverlay> {
  Offset? _pointer;

  void _track(Offset position) => _pointer = position;

  @override
  void dispose() {
    // No overlay, nothing to show: dropping the live notice also cancels
    // its timer. The channel is app-wide (and outlives any one tree), so
    // a pending timer would otherwise trip the "timer still pending"
    // invariant every widget test enforces.
    widget.controller.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _track(event.localPosition),
      onPointerMove: (event) => _track(event.localPosition),
      child: MouseRegion(
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        onHover: (event) => _track(event.localPosition),
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final message = widget.controller.message;
                    if (message == null) {
                      return const SizedBox.shrink();
                    }
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final anchor =
                            _pointer ??
                            Offset(
                              constraints.maxWidth / 2,
                              constraints.maxHeight / 2,
                            );
                        // Sits just below-right of the cursor, clamped
                        // into the panel so an edge refusal still reads.
                        final left = (anchor.dx + 16).clamp(
                          8.0,
                          (constraints.maxWidth - 260).clamp(
                            8.0,
                            constraints.maxWidth,
                          ),
                        );
                        final top = (anchor.dy + 18).clamp(
                          8.0,
                          (constraints.maxHeight - 44).clamp(
                            8.0,
                            constraints.maxHeight,
                          ),
                        );
                        return Stack(
                          children: [
                            Positioned(
                              left: left.toDouble(),
                              top: top.toDouble(),
                              child: _NoticePill(
                                key: ValueKey<int>(widget.controller.revision),
                                message: message,
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticePill extends StatelessWidget {
  const _NoticePill({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      key: const ValueKey<String>('cursor-notice-fade'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 90),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Container(
        key: const ValueKey<String>('cursor-notice-pill'),
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: ShapeDecoration(
          color: colorScheme.inverseSurface.withValues(alpha: 0.92),
          shape: AppShapes.container(AppShapes.windowRadius),
          shadows: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          message,
          style: TextStyle(fontSize: 12, color: colorScheme.onInverseSurface),
        ),
      ),
    );
  }
}

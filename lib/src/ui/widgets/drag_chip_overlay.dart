import 'package:flutter/material.dart';

import 'drag_chip.dart';

/// A [DragChip] for a drag that is NOT a `Draggable` — the rail's row drag
/// runs on its own recogniser — hung where a `Draggable` with
/// `pointerDragAnchorStrategy` hangs its feedback: top-left at the pointer,
/// in the nearest overlay, taking no pointer.
///
/// 📏A step moves the chip and nothing else: the pointer rides a notifier
/// the entry listens to, and the chip itself is built once — so a drag lays
/// out one small box per step, never the panel it started in (I-39: 「하는
/// 동안 패널 리빌드 해버린다거나 하는 성능적/구조적인 면에서 개선」).
///
/// ⚠️A file of its own, apart from the chip's look: the chip is a lifted
/// well — the fill a switched-on tab wears — and not a summoned window, and
/// `one_summoned_surface_test` holds every file that summons one (an
/// `OverlayEntry` is one) to the windows' single colour.
class DragChipOverlay {
  DragChipOverlay._(this._entry, this._pointer);

  /// Hangs [items] at [globalPosition] in [context]'s overlay — or nowhere,
  /// when the tree has no overlay to hang it in (a bare widget under test).
  static DragChipOverlay? show(
    BuildContext context, {
    required List<DragChipItem> items,
    required Offset globalPosition,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return null;
    }
    final pointer = ValueNotifier<Offset>(globalPosition);
    final chip = IgnorePointer(child: DragChip(items: items));
    final entry = OverlayEntry(
      builder: (context) => ValueListenableBuilder<Offset>(
        valueListenable: pointer,
        builder: (context, global, chip) {
          final box = overlay.context.findRenderObject();
          final local = box is RenderBox && box.hasSize
              ? box.globalToLocal(global)
              : global;
          return Positioned(left: local.dx, top: local.dy, child: chip!);
        },
        child: chip,
      ),
    );
    overlay.insert(entry);
    return DragChipOverlay._(entry, pointer);
  }

  final OverlayEntry _entry;
  final ValueNotifier<Offset> _pointer;

  void moveTo(Offset globalPosition) => _pointer.value = globalPosition;

  /// Takes the chip down. Once; the overlay forgets it.
  void remove() {
    _entry
      ..remove()
      ..dispose();
    _pointer.dispose();
  }
}

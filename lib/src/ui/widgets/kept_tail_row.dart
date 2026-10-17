import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A ROW THAT KEEPS ITS TAIL: the [tail] at its own width, pinned to the
/// row's end — and where the row is narrower than that, ALL of it,
/// smaller; the [head] takes what is left, each in the middle of the row's
/// height.
///
/// 🗣️THE PAGE TURNER'S LAW, as the canvas pill keeps it
/// (`canvas-bottom-bar-overflows-at-437`): a panel too narrow for what the
/// fold kept shows all of it, smaller — never a row that runs off, never a
/// control cut away. The head is the fold, and the tail is what it keeps.
/// ⚠️Where it fits, nothing is scaled.
///
/// The head keeps [headKeeps] for itself — the place of what ITS OWN fold
/// keeps: a tab strip's list button, the one way to the tabs it folded. The
/// tail gives way before that place does; below it, nothing is promised.
///
/// ↩️Each of these rows was a `Row`, which lays a child that does not flex
/// out with all the width there is: a tail wider than the row was laid out
/// wider, and ran off it (the timeline's bar in a 360px window, a panel's
/// tab strip at 340, the top strip at 320 — measured 2026-10-14 · 15).
///
/// ⚠️A delegate, not a [LayoutBuilder], for the transport's play row's
/// reason (`_PlayRowLayout`): the row is sized while it is laid out, so
/// nothing is built again to learn a width.
class KeptTailRow extends StatelessWidget {
  const KeptTailRow({
    super.key,
    this.head,
    required this.tail,
    this.gap = 0,
    this.headKeeps = 0,
  });

  /// What takes the room the tail leaves — exactly that room. Null leaves
  /// the row's start empty and still pins the tail to its end.
  final Widget? head;

  final Widget tail;

  /// Between the head and the tail.
  final double gap;

  /// The least the [head] is left, where there is a head.
  final double headKeeps;

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _KeptTailLayout(gap: gap, headKeeps: headKeeps),
    children: [
      if (head case final head?) LayoutId(id: _Part.head, child: head),
      LayoutId(
        id: _Part.tail,
        child: FittedBox(fit: BoxFit.scaleDown, child: tail),
      ),
    ],
  );
}

enum _Part { head, tail }

class _KeptTailLayout extends MultiChildLayoutDelegate {
  _KeptTailLayout({required this.gap, required this.headKeeps});

  final double gap;
  final double headKeeps;

  @override
  void performLayout(Size size) {
    final withHead = hasChild(_Part.head);
    final kept = withHead ? headKeeps + gap : 0.0;
    final tail = layoutChild(
      _Part.tail,
      BoxConstraints(
        maxWidth: math.max(0.0, size.width - kept),
        maxHeight: size.height,
      ),
    );
    positionChild(
      _Part.tail,
      Offset(size.width - tail.width, (size.height - tail.height) / 2),
    );
    if (!withHead) {
      return;
    }
    final width = math.max(0.0, size.width - tail.width - gap);
    final head = layoutChild(
      _Part.head,
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: size.height),
    );
    positionChild(_Part.head, Offset(0, (size.height - head.height) / 2));
  }

  @override
  bool shouldRelayout(_KeptTailLayout oldDelegate) =>
      gap != oldDelegate.gap || headKeeps != oldDelegate.headKeeps;
}

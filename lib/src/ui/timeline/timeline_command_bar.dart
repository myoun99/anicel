import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/command_pill.dart';
import '../widgets/tick_layer.dart';
import 'timeline_view_cluster.dart';

/// The ONE command-bar row both frame panels wear: the host's transport and
/// action controls on the left, the shared `TimelineViewCluster` pinned
/// right, in a row of a FIXED height.
///
/// Fixed, and that is the whole point. The timeline and the storyboard used
/// to MEASURE their own bars and land on different numbers — 54 against 36
/// — and the comment each carried explained the gap as a fact about
/// Material sizing rather than as the bug it was. The app theme gives an
/// `IconButton` a compact 28; the timeline's orientation toggle was the one
/// control in either bar still wearing Material's own 8px padding around a
/// 24px glyph, so it stood taller than everything beside it and pushed the
/// row — and the panel's whole shrink floor — up with it.
///
/// A measured constant records whatever happens to be there. A stated one
/// is a size the next control has to fit into, which is what makes the two
/// panels agree by construction instead of by two people measuring.
class TimelineCommandBar extends StatelessWidget {
  const TimelineCommandBar({super.key, this.leading, required this.cluster});

  /// The row's height, padding included.
  ///
  /// 28 is what the app theme's compact density leaves an `IconButton`, and
  /// the transport is built from those; [padding] adds the other 8.
  ///
  /// At 1× — see [heightIn] for the bar where it is shown.
  static const double height = 36;

  /// What the bar adds to [height] where it is shown: the most any of its
  /// words grow under the OS text size — the pills' one line or the view
  /// cluster's (the counter's two). Still a STATED size, as above: stated
  /// in the words the bar holds instead of in pixels.
  ///
  /// 🚨text-scale-fixed-height-bars (유저 2026-09-18, 「막대가 글자 크기를
  /// 따라 자란다」 — its stated cost: 「타임라인 위 줄과 컬러 패널이
  /// 두꺼워진다」).
  static double growthIn(BuildContext context) => math.max(
    CommandPill.growthIn(context),
    TimelineViewCluster.growthIn(context),
  );

  /// The bar where it is shown — what every floor and fold that holds it
  /// asks, so it and they cannot disagree.
  static double heightIn(BuildContext context) => height + growthIn(context);

  static const EdgeInsets padding = EdgeInsets.fromLTRB(8, 4, 8, 4);

  /// The gap between the bar's edge and the first pill, on TOP of [padding].
  ///
  /// It belongs to the bar rather than to whatever is handed in, which is
  /// ⑫ (user, 2026-08-12: 「타임라인과 스토리보드의 버튼 패딩이 다르다 —
  /// 스토리보드는 컷 버튼 앞에 여백이 있는 느낌」). It was: the action
  /// toolbar carried this padding itself, so the timeline — which mounts the
  /// toolbar AS its leading — got it once, and the storyboard — which puts
  /// the toolbar in a row with two more groups and padded that row too —
  /// got it twice.
  static const double leadingInset = 2;

  /// The host's own controls (transport, actions, cut group). Null leaves
  /// the left side empty and still pins the cluster right.
  ///
  /// Handed in as a plain ROW: the bar pads it and gives it the overflow
  /// scroller. That was the other half of ⑫ — a `leading` that scrolled
  /// itself put a horizontal scroller inside this one, and the inner box
  /// wins the drag, so the storyboard's trailing groups could not be
  /// scrolled to at all.
  final Widget? leading;

  final Widget cluster;

  /// The bar's FRAME — its tick layer, padding, row and overflow scroller —
  /// one constant per shape, so every build hands the same frame back; the
  /// two pieces reach their seats in it through [_BarPieces].
  ///
  /// 🚨I-57 (10-13): the frame was made anew on every build, round a
  /// toolbar its host makes anew on every notify, and the whole bar was
  /// built again for it — the tick layer, the row and the overflow
  /// scroller with its own LayoutBuilders — while the toolbar it held
  /// handed back the same buttons. Now a new piece is its seat's rebuild.
  /// ⚠️The seat rebuilds inside the tick layer's scope, so the layer is
  /// still laid out and painted for it (counted 10-14: a notify that
  /// changed nothing rebuilt 9 widgets fewer, and laid out and painted
  /// the same) — sparing those takes a toolbar handed back whole while
  /// nothing on it changed.
  ///
  /// 🚨The bar is a TICK LAYER (I-22 ③): the counter reads the cursor,
  /// and its width moves the row — it grows into the room on its left
  /// ([TimelineViewCluster]) — so a tick lays out and paints THIS bar.
  /// Rebuilt bare, the counter laid out the dock's panel scroller and
  /// repainted the panel and the dock around it on every playback frame.
  static const Widget _frame = TickLayer(
    child: Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: leadingInset),
              // BARRED (유저, 2026-08-10: 「버튼 사라지기 시작하면 생기는
              // 스크롤바」): the app's bar exists only while the row
              // overflows and costs no layout when it does not.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _Seat(_Piece.leading),
              ),
            ),
          ),
          SizedBox(width: 8),
          _Seat(_Piece.cluster),
        ],
      ),
    ),
  );

  /// [_frame] with no leading: the cluster still pinned right.
  static const Widget _frameWithoutLeading = TickLayer(
    child: Padding(
      padding: padding,
      child: Row(
        children: [Spacer(), SizedBox(width: 8), _Seat(_Piece.cluster)],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => _BarPieces(
    leading: leading,
    cluster: cluster,
    child: SizedBox(
      height: heightIn(context),
      child: leading == null ? _frameWithoutLeading : _frame,
    ),
  );
}

/// The two pieces a bar seats.
enum _Piece { leading, cluster }

/// The pieces a [TimelineCommandBar] holds, handed to its frame's seats:
/// a seat is built again when ITS piece is a new widget, and nothing else
/// in the bar is.
class _BarPieces extends InheritedModel<_Piece> {
  const _BarPieces({
    required this.leading,
    required this.cluster,
    required super.child,
  });

  final Widget? leading;
  final Widget cluster;

  bool _moved(_BarPieces old, _Piece piece) => switch (piece) {
    _Piece.leading => !identical(old.leading, leading),
    _Piece.cluster => !identical(old.cluster, cluster),
  };

  @override
  bool updateShouldNotify(_BarPieces oldWidget) =>
      _Piece.values.any((piece) => _moved(oldWidget, piece));

  @override
  bool updateShouldNotifyDependent(
    _BarPieces oldWidget,
    Set<_Piece> dependencies,
  ) => dependencies.any((piece) => _moved(oldWidget, piece));
}

/// Where a piece sits in the bar's frame.
class _Seat extends StatelessWidget {
  const _Seat(this.piece);

  final _Piece piece;

  @override
  Widget build(BuildContext context) {
    final pieces = InheritedModel.inheritFrom<_BarPieces>(
      context,
      aspect: piece,
    )!;
    return switch (piece) {
      // Seated only in the frame that has a leading; a bar losing its
      // leading swaps the frame, and this seat goes with the old one.
      _Piece.leading => pieces.leading ?? const SizedBox.shrink(),
      _Piece.cluster => pieces.cluster,
    };
  }
}

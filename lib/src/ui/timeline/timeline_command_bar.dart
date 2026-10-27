import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/command_pill.dart';
import '../widgets/kept_tail_row.dart';
import 'timeline_view_cluster.dart';

/// The ONE command-bar row both frame panels wear, in TWO groups (F-463):
/// the panel's action controls on the left, and on the right the panel's
/// transport with the shared `TimelineViewCluster` after it, in a row of a
/// FIXED height.
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
  const TimelineCommandBar({
    super.key,
    this.transport,
    this.leading,
    required this.cluster,
  });

  /// The row's height, padding included.
  ///
  /// 28 is what the app theme's compact density leaves an `IconButton`, and
  /// the transport is built from those; [padding] adds the other 8.
  ///
  /// At 1× — see [heightIn] for the bar where it is shown.
  static const double height = 36;

  /// What the bar adds to [height] where it is shown: the most any of its
  /// words grow under the OS text size — the pills' one line or the view
  /// cluster's. Still a STATED size, as above: stated
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

  /// The panel's transport, in the bar's right group before the cluster —
  /// 🗣️F-463 (유저 2026-10-25): 「재생버튼쪽은 오른쪽에 줌쪽 버튼이랑
  /// 같은묶음. 즉 왼쪽/오른쪽 총 두 묶음으로」. Outside the overflow
  /// scroller, so a scrolled pill row does not move it, and the fold, which
  /// keeps the bar, keeps it on screen.
  ///
  /// ↩️It was KEPT at the bar's start (유저 2026-10-08, F-111-Q1 「버튼행 맨
  /// 왼쪽에 고정 — 알약 칸 밖」), and before that it stood on the region's
  /// 문턱 from 2026-08-10 (「왼쪽 정렬이면 패널을 추가할 때 재생 버튼이
  /// 밀린다」 — it had led this bar's scrolling row, and slid as the row
  /// changed shape). At the bar's end it is where it was for that reason
  /// too: 「존재할 거면 늘 그 자리에」.
  final Widget? transport;

  /// The host's own controls (actions, cut group) — the bar's left group.
  /// Null leaves the bar's start empty.
  ///
  /// Handed in as a plain ROW: the bar pads it and gives it the overflow
  /// scroller. That was the other half of ⑫ — a `leading` that scrolled
  /// itself put a horizontal scroller inside this one, and the inner box
  /// wins the drag, so the storyboard's trailing groups could not be
  /// scrolled to at all.
  final Widget? leading;

  final Widget cluster;

  /// Between each piece of the row and the next.
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) => _BarPieces(
    transport: transport,
    leading: leading,
    cluster: cluster,
    child: SizedBox(
      height: heightIn(context),
      child: switch ((transport != null, leading != null)) {
        (true, true) => const _BarFrame(transport: true, leading: true),
        (true, false) => const _BarFrame(transport: true, leading: false),
        (false, true) => const _BarFrame(transport: false, leading: true),
        (false, false) => const _BarFrame(transport: false, leading: false),
      },
    ),
  );
}

/// The bar's FRAME — its padding, row and overflow scroller — one per
/// shape, made once (a const one), so every build hands the same frame
/// back; the pieces reach their seats in it through [_BarPieces].
///
/// 🚨I-57 (10-13): the frame was made anew on every build, round a
/// toolbar its host makes anew on every notify, and the whole bar was
/// built again for it — the row and the overflow scroller with its own
/// LayoutBuilders — while the toolbar it held handed back the same
/// buttons. Now a new piece is its seat's rebuild, built in the host's
/// scope.
///
/// ↩️The bar was a TICK LAYER (I-22 ③) for the frame counter, which read
/// the cursor and moved the row with its width; F-463 took the counter
/// off. What ticks on it now ticks on a layer of its own, in a box of its
/// own size — the play button's words and the level meter.
///
/// The two groups give way as [FloorFoldRow] lays them: the pills first,
/// down to the cut pill ([FoldFloor], 「컷알약까지 최소폭」), and below
/// that both groups, smaller. In a 360px window the timeline's bar had
/// 248px for its two ends' 252 (`timeline-row-overflows-at-360`, measured
/// 2026-10-14) — a row too narrow for what it keeps shows all of it,
/// smaller, never run off.
class _BarFrame extends StatelessWidget {
  const _BarFrame({required this.transport, required this.leading});

  /// Whether the frame seats a transport, and a leading.
  final bool transport;
  final bool leading;

  @override
  Widget build(BuildContext context) => Padding(
    padding: TimelineCommandBar.padding,
    child: FloorFoldRow(
      gap: TimelineCommandBar._gap,
      headPadding: leading ? 2 * TimelineCommandBar.leadingInset : 0,
      head: leading
          ? const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: TimelineCommandBar.leadingInset,
              ),
              // BARRED (유저, 2026-08-10: 「버튼 사라지기 시작하면 생기는
              // 스크롤바」): the app's bar exists only while the row
              // overflows and costs no layout when it does not.
              // ↩️The host's controls stood on a layer of their own here
              // (I-57, 10-14): the counter and the cut name beside the zoom
              // changed their widths, moved the row, and the scroller laid
              // out at its new width painted the controls again — 🔬86
              // render objects of the storyboard's toolbar the frame after
              // every crossing. Nothing on the bar changes its width with
              // playback since F-463: the counter is gone, and the cut's
              // name is the cut pill's, in a place of its own width.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _Seat(_Piece.leading),
              ),
            )
          : const SizedBox.shrink(),
      tail: transport
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              spacing: TimelineCommandBar._gap,
              children: [_Seat(_Piece.transport), _Seat(_Piece.cluster)],
            )
          : const _Seat(_Piece.cluster),
    ),
  );
}

/// The pieces a bar seats.
enum _Piece { transport, leading, cluster }

/// The pieces a [TimelineCommandBar] holds, handed to its frame's seats:
/// a seat is built again when ITS piece is a new widget, and nothing else
/// in the bar is.
class _BarPieces extends InheritedModel<_Piece> {
  const _BarPieces({
    required this.transport,
    required this.leading,
    required this.cluster,
    required super.child,
  });

  final Widget? transport;
  final Widget? leading;
  final Widget cluster;

  bool _moved(_BarPieces old, _Piece piece) => switch (piece) {
    _Piece.transport => !identical(old.transport, transport),
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
      // Seated only in a frame that has the piece; a bar losing it swaps
      // the frame, and this seat goes with the old one.
      _Piece.transport => pieces.transport ?? const SizedBox.shrink(),
      _Piece.leading => pieces.leading ?? const SizedBox.shrink(),
      _Piece.cluster => pieces.cluster,
    };
  }
}

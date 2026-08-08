import 'package:flutter/material.dart';

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
  static const double height = 36;

  static const EdgeInsets padding = EdgeInsets.fromLTRB(8, 4, 8, 4);

  /// The host's own controls (transport, actions, cut group). Null leaves
  /// the left side empty and still pins the cluster right.
  final Widget? leading;

  final Widget cluster;

  @override
  Widget build(BuildContext context) {
    final leading = this.leading;
    return SizedBox(
      height: height,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (leading != null) Expanded(child: leading) else const Spacer(),
            const SizedBox(width: 8),
            cluster,
          ],
        ),
      ),
    );
  }
}

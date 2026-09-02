/// Boxes turned by a frame axis — ONE spelling of "along the strip" and
/// "across it" for every widget the timeline shows on both orientations.
///
/// The x-sheet is the timeline turned on its side (F-26, R10 R6), and every
/// widget that serves both used to spell the turn by hand —
/// `horizontal ? SizedBox(width: e) : SizedBox(height: e)` — a dozen times
/// per file, each a fork the ratchet counts and a place for one side to lag
/// the other. The words are the rail's slot skeleton's own: a slot has an
/// extent ALONG the strip, the strip has one ACROSS.
library;

import 'package:flutter/widgets.dart';

import '../text/vertical_writing_text.dart';

/// A box of [extent] along [axis]; the other dimension is the child's own.
SizedBox alongBox(Axis axis, double extent, {Widget? child}) =>
    axis == Axis.horizontal
    ? SizedBox(width: extent, child: child)
    : SizedBox(height: extent, child: child);

/// A box of [extent] across [axis]. The rail wraps its icon buttons in one:
/// an M3 IconButton otherwise inflates its layout box to the 48px minimum
/// tap target and overflows the row.
SizedBox acrossBox(Axis axis, double extent, {Widget? child}) =>
    axis == Axis.horizontal
    ? SizedBox(height: extent, child: child)
    : SizedBox(width: extent, child: child);

/// A stack child placed [along] the axis and [across] it, with both extents
/// — a band over a run of frames on a run of rows.
Positioned placedAlong(
  Axis axis, {
  required double along,
  required double across,
  required double alongExtent,
  required double acrossExtent,
  required Widget child,
}) => axis == Axis.horizontal
    ? Positioned(
        left: along,
        top: across,
        width: alongExtent,
        height: acrossExtent,
        child: child,
      )
    : Positioned(
        top: along,
        left: across,
        height: alongExtent,
        width: acrossExtent,
        child: child,
      );

/// A stack child spanning the WHOLE main axis at [across] — a row's strip.
Positioned stripAcross(
  Axis axis, {
  required double across,
  required double acrossExtent,
  required Widget child,
}) => axis == Axis.horizontal
    ? Positioned(
        left: 0,
        right: 0,
        top: across,
        height: acrossExtent,
        child: child,
      )
    : Positioned(
        top: 0,
        bottom: 0,
        left: across,
        width: acrossExtent,
        child: child,
      );

/// A stack child spanning the WHOLE cross axis at [along] — a grip line at
/// a frame.
Positioned stripAlong(
  Axis axis, {
  required double along,
  required double alongExtent,
  required Widget child,
}) => axis == Axis.horizontal
    ? Positioned(
        top: 0,
        bottom: 0,
        left: along,
        width: alongExtent,
        child: child,
      )
    : Positioned(
        left: 0,
        right: 0,
        top: along,
        height: alongExtent,
        child: child,
      );

/// Text a person READS, turned by the axis: across the strip it is one line
/// that ellipsises; down a column it STANDS UP — upright letters, the column
/// beginning at its top (user, 2026-08-08: the rail's left-aligned name,
/// transposed). 'Position' will not fit across 28px, and an ellipsis there
/// would have left one glyph and a dot. Three cells spelled this fork by
/// hand — the layer name, the lane group header, the lane member — before it
/// had a name.
Widget readableText(Axis axis, String text, {TextStyle? style}) =>
    axis == Axis.horizontal
    ? Text(text, overflow: TextOverflow.ellipsis, style: style)
    : ClipRect(
        child: VerticalWritingText(
          text: text,
          latinForm: VerticalLatinForm.upright,
          mainAlignment: 0,
          style: style,
        ),
      );

/// A box that states BOTH extents — [along] the axis and [across] it — a
/// spacer, or a band cell.
SizedBox sizedAlong(
  Axis axis, {
  required double along,
  required double across,
  Widget? child,
}) => axis == Axis.horizontal
    ? SizedBox(width: along, height: across, child: child)
    : SizedBox(width: across, height: along, child: child);

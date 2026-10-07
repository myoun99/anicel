import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../dashed_path.dart';
import '../../repaint_props.dart';
import '../../text/cel_text_layout.dart';
import '../../timeline/memo_token.dart';
import '../box_chrome.dart';
import 'cel_text_editing_controller.dart';
import 'cel_text_press.dart';
import 'cel_text_stage.dart';
import 'cel_text_tool.dart';

/// WHAT THE TEXT TOOL DRAWS OVER THE CANVAS (R9-rest) — the three states
/// of a text's box in the drawing 유저 took on 2026-10-06:
///
/// · NOT IN HAND — a dashed box, on every text of the cel (유저 2026-10-02:
///   「텍스트 툴을 선택했을때만 텍스트별로 박스가 떠서」);
/// · HELD BY ITS BOX — the box in the host's colour (「선택된지 알수있도록 ui
///   필요」), its handles, and the cross it is turned about: in the middle
///   of the box until a hand carries it ([celTextCrossOf]);
/// · HELD BY ITS LETTERS — the box, and in it the caret, the selected
///   letters and the line under the ones being composed.
///
/// And the box an empty drag is tracing.
///
/// The held box is the one every box on the canvas wears ([paintBoxChrome],
/// F-222). ↩️It wore no cross until 2026-10-06 — 「a text has no anchor of
/// its own to carry about」 was this file's reasoning, and not the user's:
/// the drawing they took has one. ↩️And until 2026-10-07 the cross only
/// MARKED the centre, the press table having no row for it: 유저 gave it
/// one (R9-rest-Q2 「끌어서 중심을 옮긴다」), so it is drawn where the hand
/// carried it and taken there (`celTextPressAt`).
///
/// 🚨EVERYTHING HERE IS READ OFF THE TEXT AS IT IS SHOWN — the layout its
/// plate was baked from — never off what the field holds, which can be a
/// letter ahead. So the box and the caret cannot lead the letters on the
/// cel.
class CelTextChromePainter extends CustomPainter with RepaintOnProps {
  CelTextChromePainter({
    required this.tool,
    required this.stage,
    required this.restingBoxes,
    required this.tracedBox,
    required this.caretLit,
    required this.color,
    // ⚠️The cross is told of on a line of its own: carrying it draws this
    // again and wakes nobody else (`CelTextTool.carryCross`).
  }) : super(repaint: Listenable.merge([tool, tool.crossCarried, caretLit]));

  final CelTextTool tool;
  final CelTextStage stage;

  /// The boxes of the cel's texts that are in nobody's hand, on the artwork
  /// ([CelTextTool.restingBoxesOn]).
  final List<CelTextBox> restingBoxes;

  /// The box an empty drag is tracing, on the artwork.
  final Rect? tracedBox;

  /// Whether the caret is in the lit half of its blink.
  final ValueListenable<bool> caretLit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final box in restingBoxes) {
      paintDashedOutline(
        canvas,
        Path()..addPolygon([
          for (final corner in box.corners) stage.onPanel(corner),
        ], true),
        color: _restingColor,
        dashes: _restingDashes,
      );
    }
    final traced = tracedBox;
    if (traced != null) {
      _paintBox(canvas, [
        traced.topLeft,
        traced.topRight,
        traced.bottomRight,
        traced.bottomLeft,
      ]);
    }
    final session = tool.session;
    if (session == null) {
      return;
    }
    final layout = session.shown.layout;
    final letters = tool.letters;
    if (letters != null) {
      _paintLetters(canvas, layout, letters);
    }
    // A text held by its letters is typed into: nothing of it is sized or
    // turned, so it wears neither the handles nor the cross.
    final byBox = letters == null;
    _paintBox(
      canvas,
      layout.boxCorners,
      handles: byBox ? celTextHandlesOf(layout) : const [],
      cross: byBox ? celTextCrossOf(tool, layout) : null,
    );
  }

  /// A box on the artwork, with [handles] and its [cross], as the panel
  /// shows it.
  void _paintBox(
    Canvas canvas,
    List<Offset> corners, {
    List<Offset> handles = const [],
    Offset? cross,
  }) => paintBoxChrome(
    canvas,
    (
      box: [for (final corner in corners) stage.onPanel(corner)],
      handles: [for (final handle in handles) stage.onPanel(handle)],
      anchor: cross == null ? null : stage.onPanel(cross),
    ),
    color: color,
  );

  /// The dashes of a box nobody is holding, and the gaps between them, on
  /// screen — the drawing's 「안 고름」 box: three of line, three of none.
  static const DashPattern _restingDashes = DashPattern(on: 3, off: 3);

  /// ⛔A constant, as the ants' black is: canvas chrome has to read on the
  /// artwork, and follows neither the accent — that is the box in hand —
  /// nor a theme.
  static const Color _restingColor = Color(0xFF808080);

  /// The selected letters, or with none selected the caret — and under
  /// both, the line beneath the letters being composed.
  ///
  /// 🚨DRAWN IN PANEL PIXELS, AS THE BOX IS: every point is taken out of
  /// the text's own frame, through the artwork, onto the panel
  /// ([_onPanel]), and the lines are as wide on screen as the box's
  /// whatever the zoom. ↩️They were drawn under the frame's own transform
  /// with the zoom divided back out of the stroke — by a scale read off all
  /// THREE axes, the depth's being one: zoomed out, the caret was a third
  /// of a pixel wide (found writing its test, 2026-10-06).
  void _paintLetters(
    Canvas canvas,
    CelTextLayout layout,
    CelTextEditingController letters,
  ) {
    final selection = letters.selection;
    if (!selection.isValid) {
      return;
    }
    // ⚠️A place past the shown text's last letter is its end: the field
    // can be a letter ahead of what is shown.
    final length = layout.content.text.length;
    final start = math.min(selection.start, length);
    final end = math.min(selection.end, length);
    final hairline = Paint()
      ..color = color
      ..strokeWidth = _hairlineWidth;
    Offset onPanel(Offset inText) => stage.onPanel(layout.toCanvas(inText));
    // The letters an IME is still composing wear a line under them, as a
    // field's do: which letters are not settled yet is the one thing the
    // cel's own pixels cannot say, and a syllable or a clause being
    // composed is typed blind without it.
    final composing = letters.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      for (final mark in layout.marksBeside(
        math.min(composing.start, length),
        math.min(composing.end, length),
      )) {
        canvas.drawLine(onPanel(mark.from), onPanel(mark.to), hairline);
      }
    }
    if (start < end) {
      final wash = Paint()..color = color.withValues(alpha: 0.35);
      for (final rect in layout.selectionRects(start, end)) {
        canvas.drawPath(
          Path()..addPolygon([
            onPanel(rect.topLeft),
            onPanel(rect.topRight),
            onPanel(rect.bottomRight),
            onPanel(rect.bottomLeft),
          ], true),
          wash,
        );
      }
    } else if (caretLit.value) {
      // A hairline: a rect of no width, or — across a column — of no
      // height. From its one corner to the other is the line either way.
      final caret = layout.caretRect(TextPosition(offset: end));
      canvas.drawLine(
        onPanel(caret.topLeft),
        onPanel(caret.bottomRight),
        hairline,
      );
    }
  }

  /// The caret's width on screen, and the composing line's — the stroke the
  /// box itself is drawn in.
  static const double _hairlineWidth = 1.5;

  @override
  Object get props => (
    ByIdentity(tool),
    stage,
    // A box is one object for as long as its text says the same.
    ByList(restingBoxes),
    tracedBox,
    ByIdentity(caretLit),
    color,
  );
}

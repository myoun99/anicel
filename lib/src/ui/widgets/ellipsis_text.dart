import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MouseTrackerAnnotation;

import 'app_tooltip.dart';

/// TEXT THAT ENDS IN AN ELLIPSIS WHERE ITS ROOM ENDS — and, while it is cut,
/// says the whole of itself in the app's tooltip.
///
/// 🗣️F-530 (유저 2026-11-01): 「텍스트가 잘려서 ...으로 표시되는 위젯,
/// 기본적으로 표시될땐 툴팁으로 전 문장 표시하도록. 특히 fx의 카메라렌즈흐림의
/// 키에서 발견」. ⛔So nothing else writes `TextOverflow.ellipsis`
/// (`every_cut_word_says_itself_test`): a label that ended in `…` without
/// this was a sentence nobody could read the end of.
///
/// ★A [Text], so whatever reads one reads this, and all it does not say here
/// it takes from [Text]. A word that fits says nothing, which leaves the
/// tooltip around it to answer; one that is cut answers itself, by the rule
/// that the innermost tooltip does.
class EllipsisText extends Text {
  const EllipsisText(
    super.data, {
    super.key,
    super.style,
    super.textAlign,
    super.softWrap,
    super.maxLines,
    this.whole,
  }) : super(overflow: TextOverflow.ellipsis);

  /// What [data] was already cut from, by a caller that cut it before the
  /// width had its say; where the two differ it says this however wide its
  /// room is.
  final String? whole;

  @override
  Widget build(BuildContext context) => _SaysItsWhole(
    super.build(context) as RichText,
    words: whole ?? data!,
    cutAlready: whole != null && whole != data,
  );
}

/// [Text]'s own line, set on a paragraph that can say it.
///
/// ★ONE BOX: the paragraph itself and no box around it. Every label in the
/// app stands in one of these, and a rail row's boxes are counted
/// (`a_rail_row_drops_its_forwarding_boxes_test`).
class _SaysItsWhole extends RichText {
  _SaysItsWhole(
    RichText line, {
    required this.words,
    required this.cutAlready,
  }) : super(
         text: line.text,
         textAlign: line.textAlign,
         textDirection: line.textDirection,
         softWrap: line.softWrap,
         overflow: line.overflow,
         textScaler: line.textScaler,
         maxLines: line.maxLines,
         locale: line.locale,
         strutStyle: line.strutStyle,
         textWidthBasis: line.textWidthBasis,
         textHeightBehavior: line.textHeightBehavior,
         selectionColor: line.selectionColor,
       );

  final String words;
  final bool cutAlready;

  @override
  RenderParagraph createRenderObject(BuildContext context) {
    final paragraph = _RenderSaysItsWhole(
      text,
      textDirection: textDirection ?? Directionality.of(context),
      words: words,
      cutAlready: cutAlready,
    );
    updateRenderObject(context, paragraph);
    return paragraph;
  }

  @override
  void updateRenderObject(BuildContext context, RenderParagraph renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _RenderSaysItsWhole)
      ..tooltipContext = context
      ..words = words
      ..cutAlready = cutAlready;
  }
}

/// ★No tooltip for a screen reader: the paragraph reads it the whole text
/// however little of it shows.
class _RenderSaysItsWhole extends RenderParagraph
    with SummonsTooltip, TooltipBox {
  _RenderSaysItsWhole(
    super.text, {
    required super.textDirection,
    required this.words,
    required this.cutAlready,
  });

  String words;
  bool cutAlready;

  /// The paragraph's own answer, asked as the pointer comes — a panel at
  /// rest asks nothing — and kept: the window reads its message while it
  /// builds, when the paragraph may be waiting for layout, and a paragraph
  /// answers only when it is not. ⛔Nor in [performLayout]: not until that
  /// returns.
  bool _ranOut = false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    _ranOut = didExceedMaxLines;
    return super.hitTest(result, position: position);
  }

  @override
  String get tooltipMessage => cutAlready || _ranOut ? words : '';
}

/// An [IgnorePointer] a mouse can still read: a press goes through it to
/// what lies beneath, and only what hears a hover inside it hears anything.
///
/// For words on a plate over something that is pressed — a press on the
/// plate is the canvas's — which an [IgnorePointer] would have kept from
/// ever being asked. A hand that cannot hover cannot reach them: its press
/// is the thing beneath's.
class PressesGoThrough extends SingleChildRenderObjectWidget {
  const PressesGoThrough({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPressesGoThrough();
}

class _RenderPressesGoThrough extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final inside = BoxHitTestResult();
    super.hitTest(inside, position: position);
    for (final entry in inside.path) {
      if (entry.target is MouseTrackerAnnotation) {
        result.add(HitTestEntry(entry.target));
      }
    }
    return false;
  }
}

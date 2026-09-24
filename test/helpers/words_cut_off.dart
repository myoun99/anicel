import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every paragraph under [of] that is shorter than its own text at the
/// width it was given — a word its box cuts off.
///
/// 🚨text-scale-fixed-height-bars (유저 2026-09-18, 「막대가 글자 크기를
/// 따라 자란다」) wrote this for the bars; the rail rows asked the same of
/// every word they hold (text-scale-rail-rows, 유저 2026-09-24: 「행도 글자
/// 크기를 따라 자란다」). A word that wraps in a box one line tall is cut at
/// its foot, which is this same measure.
List<String> wordsCutOff(Finder of) {
  final cut = <String>[];
  void visit(RenderObject object) {
    if (object is RenderParagraph) {
      final need = object.getMinIntrinsicHeight(object.size.width);
      if (object.size.height + 0.5 < need) {
        cut.add(
          '「${object.text.toPlainText()}」 ${object.size.height} < $need',
        );
      }
    }
    object.visitChildren(visit);
  }

  for (final element in of.evaluate()) {
    visit(element.renderObject!);
  }
  return cut;
}

/// Every one-line paragraph under [of] narrower than its own text — a word
/// its column cuts off at the side. [wordsCutOff] turned onto the other axis
/// (text-scale-rail-columns, 유저 2026-09-25: 「칸도 글자 따라 넓어진다」).
List<String> wordsCutAcross(Finder of) {
  final cut = <String>[];
  void visit(RenderObject object) {
    if (object is RenderParagraph &&
        (object.maxLines == 1 || !object.softWrap)) {
      final need = object.getMaxIntrinsicWidth(double.infinity);
      if (object.size.width + 0.5 < need) {
        cut.add('「${object.text.toPlainText()}」 ${object.size.width} < $need');
      }
    }
    object.visitChildren(visit);
  }

  for (final element in of.evaluate()) {
    visit(element.renderObject!);
  }
  return cut;
}

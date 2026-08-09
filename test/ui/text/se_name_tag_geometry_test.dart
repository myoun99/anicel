import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/text/se_name_tag_paint.dart';

/// R5 #7 — the geometry rule the user stated and then corrected twice on
/// the mockup: **the anchor is the exact geometric centre of the NAME BOX**,
/// and the dialogue hangs to its right without ever moving it.
void main() {
  const canvas = CanvasSize(width: 2340, height: 1654);
  const anchor = ui.Offset(800, 1200);

  ResolvedSeNameTag tag({String name = 'タモツ', String? line}) =>
      ResolvedSeNameTag(
        layerId: 's1',
        widthBudget: 1920,
        content: TextCelContent(
          text: name,
          style: SeNameTag.defaultStyle,
          position: anchor,
        ),
        line: line == null
            ? null
            : TextCelContent(
                text: line,
                style: SeNameTag.defaultLineStyle,
                position: anchor,
              ),
      );

  test('the box is centred EXACTLY on the anchor', () {
    final box = seNameTagBoxBounds(tag(), canvasSize: canvas);
    expect(box.center.dx, closeTo(anchor.dx, 0.001));
    expect(box.center.dy, closeTo(anchor.dy, 0.001));
    expect(box.width, greaterThan(0), reason: 'a real box, not a point');
  });

  test('turning the dialogue OFF does not move the box — this is the whole '
      'reason the anchor is the box and not the pair', () {
    final withLine = seNameTagBoxBounds(
      tag(line: 'おはようございます、今日はいい天気ですね'),
      canvasSize: canvas,
    );
    final withoutLine = seNameTagBoxBounds(tag(), canvasSize: canvas);
    expect(withLine, withoutLine);
  });

  test('a LONGER dialogue does not move the box either', () {
    final short = seNameTagBoxBounds(tag(line: 'あ'), canvasSize: canvas);
    final long = seNameTagBoxBounds(
      tag(line: 'あいうえおかきくけこさしすせそたちつてと'),
      canvasSize: canvas,
    );
    expect(short, long);
  });

  test('a longer NAME grows the box about the anchor, both ways', () {
    final short = seNameTagBoxBounds(tag(name: 'ユ'), canvasSize: canvas);
    final long = seNameTagBoxBounds(
      tag(name: 'ユキノシタ'),
      canvasSize: canvas,
    );
    expect(long.width, greaterThan(short.width));
    expect(long.center.dx, closeTo(anchor.dx, 0.001));
    expect(
      long.left,
      lessThan(short.left),
      reason: 'it grows LEFT as well — a centre is not a left edge',
    );
  });

  test('an empty name leaves a zero-size box AT the anchor, so the line '
      'still hangs off "the box\'s right edge" — one rule, not two', () {
    final box = seNameTagBoxBounds(tag(name: ''), canvasSize: canvas);
    expect(box.width, 0);
    expect(box.topLeft, anchor);
  });
}

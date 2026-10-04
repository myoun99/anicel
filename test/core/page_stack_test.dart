import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/page_stack.dart';

/// Pages one under another, as a PDF reader lays them (유저 2026-09-27,
/// F-201) — the one geometry the timesheet's stack, the conte's book and the
/// viewer's pages read.
void main() {
  const a4 = Size(595, 842);
  const gap = PageStack.defaultGap;
  const margin = PageStack.defaultMargin;

  test('pages of one size lie a gap apart inside the margin — the stack the '
      'timesheet printed before it was shared', () {
    final stack = PageStack([a4, a4, a4]);
    for (var index = 0; index < 3; index += 1) {
      expect(
        stack.pageRect(index),
        Rect.fromLTWH(margin, margin + index * (a4.height + gap), 595, 842),
      );
    }
    expect(
      stack.size,
      Size(margin * 2 + a4.width, margin * 2 + 3 * a4.height + 2 * gap),
    );
  });

  test('a page narrower than the widest stands centred on it, and the '
      'stack is as wide as the widest', () {
    const wide = Size(842, 595);
    final stack = PageStack([a4, wide, a4]);
    expect(stack.size.width, margin * 2 + wide.width);
    expect(stack.pageRect(1).left, margin);
    expect(stack.pageRect(0).left, margin + (wide.width - a4.width) / 2);
    expect(stack.pageRect(0).center.dx, stack.pageRect(1).center.dx);
    expect(stack.pageRect(2).top, stack.pageRect(1).bottom + gap);
  });

  test('a view shows the pages it meets, top to bottom, and a view of the '
      'gap alone shows none', () {
    final stack = PageStack([a4, a4, a4]);
    final second = stack.pageRect(1);
    expect(
      stack.pagesMeeting(Rect.fromLTWH(0, second.top - gap - 10, 600, 100)),
      [0, 1],
    );
    expect(stack.pagesMeeting(Rect.fromLTWH(0, second.top + 10, 600, 20)), [
      1,
    ]);
    expect(
      stack.pagesMeeting(Rect.fromLTWH(0, second.bottom + 4, 600, gap - 8)),
      isEmpty,
    );
  });

  test('a reader is on the last page that starts at or above them: a gap '
      'belongs to the page over it, and past either end to the end page', () {
    final stack = PageStack([a4, a4, a4]);
    expect(stack.pageAt(stack.pageRect(1).center.dy), 1);
    expect(stack.pageAt(stack.pageRect(1).bottom + gap / 2), 1);
    expect(stack.pageAt(stack.pageRect(2).top), 2);
    expect(stack.pageAt(-500), 0);
    expect(stack.pageAt(stack.size.height + 500), 2);
  });

  test('every page starts on a whole unit, however tall the one above it — '
      'an A4 conte page is 841.89pt', () {
    const conte = Size(595.28, 841.89);
    final stack = PageStack([conte, conte, conte]);
    for (var index = 0; index < 3; index += 1) {
      final top = stack.pageRect(index).top;
      expect(top, top.roundToDouble(), reason: 'page $index starts at $top');
    }
    expect(stack.pageRect(1).top, margin + 842 + gap);
  });

  test('past the last page the stack goes on in pages the last one\'s size '
      '— where a longer cut\'s sheet would print', () {
    final stack = PageStack([a4, a4]);
    expect(
      stack.pageRect(4),
      Rect.fromLTWH(margin, margin + 4 * (a4.height + gap), 595, 842),
    );
    expect(stack.length, 2, reason: 'asking past the end adds no page');
  });

  test('a stack scaled is the same stack in other units — every page, the '
      'gap, the margin and each page\'s place times the factor, never laid '
      'again from the scaled sizes (F-294)', () {
    const conte = Size(595.28, 841.89);
    const factor = 2480 / 595.28;
    final stack = PageStack([for (var page = 0; page < 10; page += 1) conte]);

    final scaled = stack.scaledBy(factor);

    expect(scaled.length, 10);
    expect(scaled.gap, gap * factor);
    expect(scaled.margin, margin * factor);
    // Every page, and two past the end.
    for (var index = 0; index < 12; index += 1) {
      final own = stack.pageRect(index);
      final seen = scaled.pageRect(index);
      expect(seen.left, closeTo(own.left * factor, 1e-9), reason: '$index');
      expect(seen.top, closeTo(own.top * factor, 1e-9), reason: '$index');
      expect(seen.width, closeTo(own.width * factor, 1e-9));
      expect(seen.height, closeTo(own.height * factor, 1e-9));
    }
    expect(scaled.size.width, closeTo(stack.size.width * factor, 1e-9));
    expect(scaled.size.height, closeTo(stack.size.height * factor, 1e-9));
    expect(scaled.paper.bottom, closeTo(stack.paper.bottom * factor, 1e-9));
    expect(scaled.pageAt(stack.pageRect(7).top * factor + 1), 7);
    expect(
      scaled.pagesMeeting(
        Rect.fromLTWH(0, stack.pageRect(4).top * factor + 10, 100, 20),
      ),
      [4],
    );

    // Laid again from the scaled sizes, each page would start on a whole
    // unit of the LARGER stack — and the tenth page lie over a unit away.
    final relaid = PageStack(
      [for (var page = 0; page < 10; page += 1) conte * factor],
      gap: gap * factor,
      margin: margin * factor,
    );
    expect(
      (relaid.pageRect(9).top - scaled.pageRect(9).top).abs(),
      greaterThan(1),
      reason: 'fixture: the two ways disagree',
    );
  });

  test('a stack scaled by one is itself', () {
    final stack = PageStack([a4, a4]);
    expect(identical(stack.scaledBy(1), stack), isTrue);
  });

  test('an empty stack is its margins and nothing more', () {
    final stack = PageStack(const []);
    expect(stack.length, 0);
    expect(stack.size, const Size(margin * 2, margin * 2));
    expect(stack.pagesMeeting(const Rect.fromLTWH(0, 0, 1000, 1000)), isEmpty);
  });
}

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

  test('an empty stack is its margins and nothing more', () {
    final stack = PageStack(const []);
    expect(stack.length, 0);
    expect(stack.size, const Size(margin * 2, margin * 2));
    expect(stack.pagesMeeting(const Rect.fromLTWH(0, 0, 1000, 1000)), isEmpty);
  });
}

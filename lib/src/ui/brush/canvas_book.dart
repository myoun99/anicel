import 'package:flutter/foundation.dart';

import '../../core/page_stack.dart';

/// A BOOK on a canvas-base panel: its pages laid one under another (F-201)
/// and the page its reader is on.
///
/// 🗣️유저 2026-09-27 (F-201): 「pdf리더같은거 밑으로 쭉 존재하잖아. 별개로
/// 왼쪽 알약인 페이지 넘기는 버튼은 동시존재해서 그거로 다음페이지 스냅?
/// 해서 넘길수있게」 — the conte, the timesheet's page view
/// (F-201-timesheet-pages-Q1: 「타임시트 페이지 보기도 쌓는다」) and the
/// viewer's PDFs read by this one law.
///
/// The reader's page is the HOST's to keep — the viewer's is saved with the
/// project, the timesheet's outlives its tab — and [BrushCanvasPanel] keeps
/// it true to the view: writing it IS a turn (the panel snaps the view to
/// the page), and the panel writes it back when the view leaves it.
class CanvasBook {
  const CanvasBook({required this.pages, required this.reading});

  final PageStack pages;

  /// The page the reader is on.
  final ValueNotifier<int> reading;

  /// The page the reader is on, inside the book — a stored page a shorter
  /// book no longer has reads as its last.
  int get page => pages.length == 0
      ? 0
      : reading.value.clamp(0, pages.length - 1).toInt();

  /// Turns to [page] — the page strip's ▲▼, its typed page, a playback
  /// that crossed a page. Past either end it is the end.
  void turnTo(int page) {
    if (pages.length == 0) {
      return;
    }
    reading.value = page.clamp(0, pages.length - 1).toInt();
  }
}

/// The page a reader who was on [current] is on once the view shows the
/// book from [top] to [bottom] (canvas units, down the stack): [current]
/// while that page is whole in the span — PDF readers' law — and otherwise
/// the page at [top].
///
/// ⛔Not the top alone. The last page, shorter than the window, never
/// reaches the top — the view stops at the paper's end first (F-201) — so
/// the strip could never read it, and ▼ would turn to it and read the page
/// before; and a book zoomed out to fit whole moves not at all, so no turn
/// could change what the strip read.
int pageReadAt(
  PageStack pages, {
  required int current,
  required double top,
  required double bottom,
}) {
  if (pages.length == 0) {
    return 0;
  }
  final page = current.clamp(0, pages.length - 1).toInt();
  final rect = pages.pageRect(page);
  if (rect.top >= top - _slack && rect.bottom <= bottom + _slack) {
    return page;
  }
  return pages.pageAt(top + pages.gap);
}

/// A millionth of a unit — a float's dust, not a page edge.
const double _slack = 1e-6;

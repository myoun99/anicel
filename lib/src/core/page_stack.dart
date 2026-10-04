import 'dart:math' as math;
import 'dart:ui';

/// Pages laid one under another, the way a PDF reader lays a document.
///
/// 🗣️유저 2026-09-27 (F-201): 「캔버스 베이스 패널, 뷰어든 콘티 프리뷰든
/// pdf같은거 여러페이지 동시에 볼수있게 하고싶음. pdf리더같은거 밑으로 쭉
/// 존재하잖아」. ONE geometry for every paged surface — the timesheet's
/// stack (what its sheet exports print), the conte's book and the viewer's
/// pages: [margin] round the whole, [gap] between two pages, and a page
/// narrower than the widest standing centred on it.
class PageStack {
  PageStack(
    List<Size> pages, {
    double gap = defaultGap,
    double margin = defaultMargin,
  }) : this._(
         List.unmodifiable(pages),
         _topsOf(pages, gap: gap, margin: margin),
         gap: gap,
         margin: margin,
       );

  PageStack._(
    this._pages,
    this._tops, {
    required this.gap,
    required this.margin,
  }) : _widest = _pages.fold(0.0, (wide, page) => math.max(wide, page.width));

  /// The timesheet's numbers, which the stack was first laid with.
  static const double defaultGap = 32;
  static const double defaultMargin = 24;

  final double gap;
  final double margin;

  final List<Size> _pages;
  final double _widest;

  /// Where each page starts — and, after the last, where a page past it
  /// would.
  final List<double> _tops;

  static List<double> _topsOf(
    List<Size> pages, {
    required double gap,
    required double margin,
  }) {
    // Each page starts on a whole unit — an A4 conte page is 841.89pt tall —
    // so at a whole zoom every page lies on the device grid, as the first.
    final tops = [margin];
    for (final page in pages) {
      tops.add(tops.last + page.height.ceilToDouble() + gap);
    }
    return tops;
  }

  /// This stack [factor] times as large — its pages, the gap, the margin
  /// and where each page lies: the same stack, read in units [factor] to
  /// one of its own. A sheet panel shows its book in the paper's pixels by
  /// it (`SheetCanvasPanel`, F-294).
  ///
  /// ⛔Not laid again from the pages' sizes. Each page starts on a whole
  /// unit of the stack's OWN ([_topsOf]); laid again at the larger size they
  /// would start on whole units of that one, and page after page the two
  /// stacks would come apart — the book turning to where no page is
  /// printed.
  PageStack scaledBy(double factor) => factor == 1
      ? this
      : PageStack._(
          List.unmodifiable([for (final page in _pages) page * factor]),
          [for (final top in _tops) top * factor],
          gap: gap * factor,
          margin: margin * factor,
        );

  int get length => _pages.length;

  /// The whole stack, margins included.
  Size get size {
    if (_pages.isEmpty) {
      return Size(margin * 2, margin * 2);
    }
    final last = _pages.length - 1;
    return Size(
      margin * 2 + _widest,
      _tops[last] + _pages[last].height + margin,
    );
  }

  /// The paper the pages make: from the first page's top to the last one's
  /// bottom, as wide as the widest — where a view of the stack stops
  /// (F-201). The margin round it is desk, not paper.
  Rect get paper {
    final whole = size;
    return Rect.fromLTRB(
      margin,
      margin,
      whole.width - margin,
      whole.height - margin,
    );
  }

  /// Where page [index] lies in the stack. Past the last page the stack
  /// goes on in pages the last one's size — where the sheet a longer cut
  /// would print lies (the timesheet previews a cut-end drag's rows past
  /// the document's end there).
  Rect pageRect(int index) {
    final last = _pages.length - 1;
    final page = _pages[math.min(index, last)];
    final beyond = math.max(0, index - last);
    return Rect.fromLTWH(
      margin + (_widest - page.width) / 2,
      _tops[index - beyond] + beyond * (_tops[last + 1] - _tops[last]),
      page.width,
      page.height,
    );
  }

  /// The pages [view] (a rect in the stack's space) shows any of, top to
  /// bottom.
  List<int> pagesMeeting(Rect view) => [
    for (var index = 0; index < _pages.length; index += 1)
      if (pageRect(index).overlaps(view)) index,
  ];

  /// The page a reader at height [y] is on: the last page that starts at or
  /// above it — so a gap belongs to the page over it, and heights past
  /// either end to the first or the last page.
  int pageAt(double y) {
    var low = 0;
    var high = _pages.length - 1;
    var found = 0;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (_tops[middle] <= y) {
        found = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return found;
  }
}

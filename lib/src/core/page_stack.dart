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
    this.gap = defaultGap,
    this.margin = defaultMargin,
  }) : _pages = List.unmodifiable(pages),
       _widest = pages.fold(0.0, (wide, page) => math.max(wide, page.width)),
       _tops = _topsOf(pages, gap: gap, margin: margin);

  /// The timesheet's numbers, which the stack was first laid with.
  static const double defaultGap = 32;
  static const double defaultMargin = 24;

  final double gap;
  final double margin;

  final List<Size> _pages;
  final double _widest;
  final List<double> _tops;

  static List<double> _topsOf(
    List<Size> pages, {
    required double gap,
    required double margin,
  }) {
    // Each page starts on a whole unit — an A4 conte page is 841.89pt tall —
    // so at a whole zoom every page lies on the device grid, as the first.
    final tops = <double>[];
    var top = margin;
    for (final page in pages) {
      tops.add(top);
      top += page.height.ceilToDouble() + gap;
    }
    return tops;
  }

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
      _tops[index - beyond] + beyond * (page.height.ceilToDouble() + gap),
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

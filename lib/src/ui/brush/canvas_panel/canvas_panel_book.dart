part of '../brush_canvas_panel.dart';

/// THE BOOK THE PANEL READS (F-201): which page of [BrushCanvasPanel.book]
/// its reader is on, kept true to the view — and a turn of that page,
/// carried out as a move of the view.
///
/// 🚨Here and not in each host, because the answer needs the WINDOW: 「the
/// page you turned to, while it is whole on screen」 is a question about
/// what the window shows, and only the panel knows the window. The conte
/// counted its pages from the stored view alone, and a view held at the
/// paper's end ([BrushCanvasPanel.viewLimit]) is exactly where that count
/// goes wrong — see [pageReadAt].
///
/// A collaborator of `_BrushCanvasPanelState` like the others: two fields
/// and four members of its own, reaching the panel through `_state`.
class _CanvasPanelBook {
  _CanvasPanelBook(this._state);

  final _BrushCanvasPanelState _state;

  /// The reader's notifier this panel hears turns on — remembered, as the
  /// view's is, because the prop can hand over another.
  ValueNotifier<int>? _listened;

  /// True while the panel writes the reader's page itself: hearing its own
  /// write back as a turn would snap the view to where it already is.
  bool _following = false;

  /// Hears [BrushCanvasPanel.book]'s reader — the one the widget holds now.
  void bind() {
    final reading = _state.widget.book?.reading;
    if (identical(reading, _listened)) {
      return;
    }
    _listened?.removeListener(_turned);
    _listened = reading?..addListener(_turned);
  }

  void unbind() {
    _listened?.removeListener(_turned);
    _listened = null;
  }

  /// Someone else moved the reader's page — a turn: the view goes to it,
  /// the page's top half a gap under the window's top, at the zoom the
  /// view has (F-201, 유저 2026-09-27: 「그거로 다음페이지 스냅」), and is held
  /// at the paper's ends like every other move.
  ///
  /// A view nobody has framed that the owner fits
  /// ([BrushCanvasPanel.unframedFit]) stays unframed: the owner fits the
  /// page read, so the fit follows the turn with nothing stored — the
  /// conte opens fitted to its body and turns fitted.
  void _turned() {
    final book = _state.widget.book;
    final viewport = _state._viewportState;
    if (_following ||
        book == null ||
        book.pages.length == 0 ||
        !_state.mounted ||
        (viewport.viewportNotifier.value == null &&
            _state.widget.unframedFit != null)) {
      return;
    }
    final view = viewport._viewport;
    final top = book.pages.pageRect(book.page).top - book.pages.gap / 2;
    final onScreen = view.canvasToViewport(CanvasPoint(x: 0, y: top)).y;
    viewport.setViewport(
      view.translated(
        dx: 0,
        dy: viewport._resolvedVisibleRect().top - onScreen,
      ),
    );
  }

  /// After the view moved: the reader's page as [pageReadAt] answers for
  /// the span of the book the window shows. A view nobody has framed says
  /// nothing — the host's page is the one it is fitted to.
  void followView() {
    final book = _state.widget.book;
    final viewport = _state._viewportState;
    if (book == null ||
        book.pages.length == 0 ||
        viewport.viewportNotifier.value == null) {
      return;
    }
    final view = viewport._viewport;
    final window = viewport._resolvedVisibleRect();
    final first = view.viewportToCanvas(
      ViewportPoint(x: window.left, y: window.top),
    );
    final last = view.viewportToCanvas(
      ViewportPoint(x: window.right, y: window.bottom),
    );
    final next = pageReadAt(
      book.pages,
      current: book.page,
      top: math.min(first.y, last.y),
      bottom: math.max(first.y, last.y),
    );
    if (next == book.reading.value) {
      return;
    }
    _following = true;
    book.reading.value = next;
    _following = false;
  }

  /// The page Fit frames — the reader's — or null for a canvas without a
  /// book.
  Rect? get fitRect {
    final book = _state.widget.book;
    return book == null || book.pages.length == 0
        ? null
        : book.pages.pageRect(book.page);
  }
}

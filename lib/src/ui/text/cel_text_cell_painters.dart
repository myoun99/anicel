part of 'cel_text_layout.dart';

/// THE PAINTERS OF THE CELLS OF TEXTS SET IN COLUMNS, each kept by what it
/// was made of, and shared by every layout that sets such a cell.
///
/// 🔬WHY (measured on the device — Windows, the debug build — 2026-10-07).
/// A column's letters are set one painter a cell, a pass, and a text is set
/// again at every letter typed into it. That came to ≈47 µs a cell a pass:
/// 5 ms for fifty letters, 13–20 ms for two hundred, 77 ms for eight
/// hundred outlined — on the thread that answers the keys — where the same
/// letters in lines are one paragraph and a tenth of a millisecond. But a
/// text set again is the text it was but for a letter, and a cell's painter
/// is made of nothing but its letters, their style and the paint of its
/// pass. So each is kept by exactly that ([_CellPainterKey]), and a text
/// set again makes only the painters it did not have.
///
/// 🚨NOTHING OF A PAINTER DEPENDS ON WHAT IS NOT IN ITS KEY — and it
/// cannot: a painter is made HERE, of its key and of nothing a caller holds
/// ([_painterOf]), down to the faces the engine had when it was set
/// ([CanvasLetterFaces.generation] — set before a face arrived, it was set
/// in another). So a painter kept IS the painter that would be made, and
/// what a text bakes to is, to the byte, what it bakes to set from nothing
/// (유저: 「결과 절대 바뀌면 안되는건 캔버스뿐임」 — pinned as that,
/// `a_text_in_columns_keeps_its_cells_painters_test.dart`).
///
/// ★HELD BY COUNT. Two layouts of one text are alive at once — the one
/// shown and the one wanted — and each lets go on its own: a painter is
/// disposed only when NO layout holds it and [_idleCellPainterLimit] others
/// have been let go of since.
///
/// ⚠️Lines keep none: a text in lines is one paragraph a pass, set again
/// whole whatever was typed — there is no part of it to keep.
class _CellPainters {
  _CellPainters._();

  /// The one keeping: a cell's painter is the same for every text of every
  /// cel.
  static final _CellPainters shared = _CellPainters._();

  /// The painters some layout holds.
  final Map<_CellPainterKey, _HeldCellPainter> _held = {};

  /// The painters no layout holds — the longest let go of first.
  final Map<_CellPainterKey, _HeldCellPainter> _idle = {};

  /// The painter made of [key], held once more: one that is kept, or made
  /// now. [foreground] is the paint [key] names (`key.paint`) — null for
  /// the letters' own colour.
  _HeldCellPainter hold(_CellPainterKey key, ui.Paint? foreground) {
    final kept =
        _held[key] ??
        _idle.remove(key) ??
        _HeldCellPainter._(key, _painterOf(key, foreground));
    kept._holders += 1;
    _held[key] = kept;
    return kept;
  }

  /// A cell's letters SET, for one pass: at the size of their style, in a
  /// line box one letter tall — what [paintVerticalTextCell] centres.
  ///
  /// ⛔Of [key] alone, and the paint it names. A word lying down keeps its
  /// tracking between its letters; a standing cell's is room after it
  /// ([_ColumnCell.advance]), and none of its painter's.
  static TextPainter _painterOf(_CellPainterKey key, ui.Paint? foreground) =>
      TextPainter(
        text: TextSpan(
          text: key.letters,
          style: canvasLetterTextStyle(
            key.style,
            lineHeight: 1,
            foreground: foreground,
          ).copyWith(
            letterSpacing: key.lyingDown ? key.style.letterSpacing : 0,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  /// One holder of [painter] lets go of it. With none left it is kept
  /// idle, and the idle ones past the limit — the longest idle first — are
  /// disposed.
  void letGo(_HeldCellPainter painter) {
    painter._holders -= 1;
    if (painter._holders > 0) {
      return;
    }
    _held.remove(painter.key);
    _idle[painter.key] = painter;
    while (_idle.length > _idleCellPainterLimit) {
      _idle.remove(_idle.keys.first)!.painter.dispose();
    }
  }

  /// Disposes every painter no layout holds.
  void forgetIdle() {
    for (final painter in _idle.values) {
      painter.painter.dispose();
    }
    _idle.clear();
  }
}

/// How many cell painters NO layout holds are kept for the next setting.
///
/// Enough for the texts a person goes back and forth between — a text of a
/// hundred letters, outlined, is two hundred — and a bound on what a very
/// long one leaves behind: a painter is one glyph's paragraph, a few
/// kilobytes of the engine's.
const int _idleCellPainterLimit = 1024;

/// ALL that one cell's painter is made of ([_CellPainters._painterOf]): its
/// letters, the style they wear, whether they lie down the column as a
/// word, what paints them — their own colour, or a pass's paint, named by
/// the pass ([CanvasLetterPass.key]) — and the faces the engine had.
typedef _CellPainterKey = ({
  String letters,
  TextLetterStyle style,
  bool lyingDown,
  Object paint,
  int faces,
});

/// What a cell painted in ITS OWN COLOUR is kept by, whichever pass asks —
/// and what every cell is measured on.
const Object _ownColour = #ownColour;

/// A cell's painter, kept ([_CellPainters]).
class _HeldCellPainter {
  _HeldCellPainter._(this.key, this.painter);

  final _CellPainterKey key;

  /// ⛔Read, never changed and never disposed by a holder: other layouts
  /// hold it too.
  final TextPainter painter;

  int _holders = 0;
}

/// Disposes every cell painter no layout holds, so that a test can count
/// the painters a setting makes from nothing.
@visibleForTesting
void debugForgetIdleCelTextCellPainters() => _CellPainters.shared.forgetIdle();

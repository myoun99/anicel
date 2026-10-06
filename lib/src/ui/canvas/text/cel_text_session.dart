import 'dart:async';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

import '../../../models/bitmap_surface.dart';
import '../../../models/bitmap_tile.dart';
import '../../../models/brush_frame_key.dart';
import '../../../models/canvas_size.dart';
import '../../../models/cel_text.dart';
import '../../../models/pasteboard_bounds.dart';
import '../../../models/text_cel_style.dart';
import '../../../models/tile_coord.dart';
import '../../../services/bitmap_surface_geometry.dart';
import '../../../services/brush_frame_editing_coordinator.dart';
import '../../../services/cache_invalidation_executor.dart';
import '../../../services/commands/cel_text_edit_command.dart';
import '../../text/cel_text_bake.dart';
import '../../text/cel_text_layout.dart';

/// A text as it is SHOWN: what it says, that set, and that as pixels — one
/// of each, made together, so the box, the caret and the letters on screen
/// are always of the same text.
typedef CelTextShown = ({
  CelTextContent content,
  CelTextLayout layout,
  Map<TileCoord, BitmapTile> plate,
});

/// A text as it stood when a hand took hold of it to MOVE it — what it
/// said, its pixels and the room they were in — kept for the length of the
/// drag, which is measured from here and never from the last move.
typedef CelTextMoveOrigin = ({
  CelTextContent content,
  Map<TileCoord, BitmapTile> plate,
  Rect ink,
});

/// ONE TEXT THE TEXT TOOL IS HOLDING (R9-rest): the text as its cel carries
/// it, what the person has made of it since, and what of that is on screen.
///
/// 🚨★★★IT WRITES NOTHING TO THE CEL. A text being typed, dragged or set
/// differently is shown by the canvas alone — the cel with this text laid
/// in ([shownOver]), the way an open move shows its hole — and the cel
/// hears of it once, as one step of history ([landing]). Every other view
/// of the drawing keeps showing it as it stands, which is what an edit
/// nobody has confirmed should look like from outside the tool.
///
/// 🚨★★★WHAT IS ON SCREEN IS A WHOLE TEXT, NEVER A TEXT AND A HALF. Only
/// the engine can turn letters into pixels and it answers a frame or more
/// later, so what the person WANTS ([content]) can be ahead of what is
/// SHOWN ([shown]). Nothing is drawn from the wanted text until its pixels
/// exist: the box and the caret are read off the shown one, so they cannot
/// lead the letters (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로
/// 다르면 안 되」). The newest want wins; the ones a bake overtook are never
/// set at all.
class CelTextSession extends ChangeNotifier {
  CelTextSession({
    required this.key,
    required this.canvasSize,
    required this.tileSize,
    required CelText? standing,
    required CelTextContent content,
    required TextLetterStyle nextLetterStyle,
    CelTextBaker? bake,
  }) : _standing = standing,
       _wanted = content,
       _nextLetterStyle = nextLetterStyle,
       _bake = bake ?? bakeCelTextPlate,
       _shown = _shownOf(standing, content, nextLetterStyle),
       // ⚠️A text that is not on the cel yet starts with NO letters — there
       // is then nothing of it to draw, and so nothing to wait for.
       assert(standing != null || content.isEmpty);

  static CelTextShown _shownOf(
    CelText? standing,
    CelTextContent content,
    TextLetterStyle nextLetterStyle,
  ) => standing == null
      ? (
          content: content,
          layout: layoutCelText(content, nextLetterStyle: nextLetterStyle),
          plate: const {},
        )
      : (
          content: standing.content,
          layout: layoutCelText(
            standing.content,
            nextLetterStyle: nextLetterStyle,
          ),
          plate: standing.plate,
        );

  /// The cel the text is on.
  final BrushFrameKey key;
  final CanvasSize canvasSize;
  final int tileSize;
  final CelTextBaker _bake;

  /// The text as the cel carries it — null for one that is not on it yet.
  CelText? get standing => _standing;
  CelText? _standing;

  /// Which text of the cel this is; null until a new one has landed.
  int? get textId => _standing?.id;

  /// What the person has made of the text — possibly ahead of [shown].
  CelTextContent get content => _wanted;
  CelTextContent _wanted;

  /// What is on screen.
  CelTextShown get shown => _shown;
  CelTextShown _shown;

  /// What the first letter typed into a text with none will wear.
  TextLetterStyle get nextLetterStyle => _nextLetterStyle;
  TextLetterStyle _nextLetterStyle;

  /// Whether [shown] has yet to be set again for a letter style that
  /// changed under a text with no letters.
  bool _stale = false;
  bool _baking = false;
  bool _disposed = false;
  final List<Completer<void>> _waiting = [];

  /// The last bake the engine refused, until one succeeds — what is shown
  /// then is still the last text it did make.
  Object? get failure => _failure;
  Object? _failure;

  /// Whether what is on screen is what the person wants.
  bool get settled => !_baking && !_stale && _wanted == _shown.content;

  /// Completes once [settled] — at once when it already is.
  Future<void> whenSettled() {
    if (settled || _disposed) {
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  /// Makes the text [content]: shown as soon as its pixels are made.
  void set(CelTextContent content, {TextLetterStyle? nextLetterStyle}) {
    final letters = nextLetterStyle ?? _nextLetterStyle;
    if (content == _wanted && letters == _nextLetterStyle) {
      return;
    }
    // A text with no letters is measured by the letter about to be typed,
    // so a change of that alone is a change of what is shown.
    _stale = _stale || (letters != _nextLetterStyle && content.isEmpty);
    _wanted = content;
    _nextLetterStyle = letters;
    notifyListeners();
    unawaited(_pump());
  }

  /// Shows [origin] standing ([dx], [dy]) whole pixels from where it stood
  /// — AT ONCE, by moving its pixels, where that is the same picture as
  /// setting the text again there.
  ///
  /// 🚨A TEXT DRAGGED A WHOLE NUMBER OF PIXELS IS ITS PIXELS DRAGGED: the
  /// plate is moved, not set again, so the letters keep the very pixels
  /// they were baked to and follow the hand in the frame the hand moved
  /// in. What lands is that plate — what was on screen (유저 절대규칙
  /// 2026-09-17). ⚠️Whether the engine would set the same letters to the
  /// same pixels at the new place is not asked, and not promised: a plate
  /// is what its text baked to WHERE IT WAS BAKED (`CelText.plate`).
  ///
  /// ⚠️Except at the pasteboard wall, which cuts what crosses it: a plate
  /// that was cut, or would be, is set again instead ([set]), so nothing
  /// that was cut away stays missing when the text comes back in.
  ///
  /// [over] is the cel's picture as it stands: the grid the plate is cut
  /// on.
  void showMoved(
    CelTextMoveOrigin origin,
    BitmapSurface over, {
    required int dx,
    required int dy,
  }) {
    final moved = celTextContentMoved(origin.content, dx: dx, dy: dy);
    if (_baking || !_movesWhole(origin.ink, dx: dx, dy: dy)) {
      set(moved);
      return;
    }
    if (moved == _shown.content && moved == _wanted) {
      return;
    }
    final before = _shown;
    _wanted = moved;
    _stale = false;
    _shown = (
      content: moved,
      layout: layoutCelText(moved, nextLetterStyle: _nextLetterStyle),
      plate: dx == 0 && dy == 0
          ? origin.plate
          : celTextPlateMoved(origin.plate, over, dx: dx, dy: dy),
    );
    before.layout.dispose();
    notifyListeners();
  }

  /// The text as it is shown now, for a move that starts here.
  CelTextMoveOrigin get moveOrigin => (
    content: _shown.content,
    plate: _shown.plate,
    ink: _shown.layout.inkBounds,
  );

  /// Whether a text whose pixels can be anywhere in [ink] is inside the
  /// pasteboard where it stands AND ([dx], [dy]) from there.
  bool _movesWhole(Rect ink, {required int dx, required int dy}) {
    final wall = canvasSize.pasteboardRect;
    bool inside(Rect rect) =>
        rect.left >= wall.left &&
        rect.top >= wall.top &&
        rect.right <= wall.right &&
        rect.bottom <= wall.bottom;
    return inside(ink) &&
        inside(ink.shift(Offset(dx.toDouble(), dy.toDouble())));
  }

  Future<void> _pump() async {
    if (_baking || _disposed) {
      return;
    }
    _baking = true;
    try {
      while (!_disposed && (_stale || _wanted != _shown.content)) {
        final content = _wanted;
        final letters = _nextLetterStyle;
        final layout = layoutCelText(content, nextLetterStyle: letters);
        final Map<TileCoord, BitmapTile> plate;
        try {
          // A text with no letters is not drawn ([_laidInto]): the engine
          // is not asked for the pixels of nothing.
          plate = content.isEmpty
              ? const <TileCoord, BitmapTile>{}
              : await _bake(
                  layout,
                  canvasSize: canvasSize,
                  tileSize: tileSize,
                  previous: _shown.plate,
                );
        } on Object catch (error) {
          layout.dispose();
          // The engine made no plate: what is shown is still the last text
          // it did make, and the want goes back to it rather than be asked
          // of the engine again and again.
          _failure = error;
          _wanted = _shown.content;
          _stale = false;
          break;
        }
        if (_disposed) {
          layout.dispose();
          return;
        }
        _failure = null;
        final before = _shown;
        _shown = (content: content, layout: layout, plate: plate);
        _stale = false;
        before.layout.dispose();
        notifyListeners();
      }
    } finally {
      _baking = false;
    }
    if (_disposed) {
      return;
    }
    if (settled) {
      final waiting = List.of(_waiting);
      _waiting.clear();
      for (final waiter in waiting) {
        waiter.complete();
      }
    }
    notifyListeners();
  }

  /// [cel] — the picture of this text's cel as it stands — with the text
  /// laid in AS SHOWN: in the place of the one it replaces, on top for a
  /// new one, and gone where it has no letters left.
  ///
  /// [cel] itself while the text is shown exactly as the cel carries it.
  BitmapSurface shownOver(BitmapSurface cel) {
    final memo = _shownOver;
    if (memo != null &&
        identical(memo.cel, cel) &&
        identical(memo.shown.layout, _shown.layout)) {
      return memo.surface;
    }
    final surface = _laidInto(cel);
    _shownOver = (cel: cel, shown: _shown, surface: surface);
    return surface;
  }

  ({BitmapSurface cel, CelTextShown shown, BitmapSurface surface})? _shownOver;

  BitmapSurface _laidInto(BitmapSurface cel) {
    final standing = _standing;
    final shown = _shown;
    // A text with no letters is NOT THERE — shown and landed alike
    // ([landing]): the box behind it is its letters' box.
    final draws = !shown.content.isEmpty;
    if (standing == null) {
      return draws
          ? cel.withTexts([
              ...cel.texts,
              CelText(
                id: nextCelTextId(cel.texts),
                content: shown.content,
                plate: shown.plate,
              ),
            ])
          : cel;
    }
    if (_isAsStanding(shown, standing)) {
      return cel;
    }
    return cel.withTexts([
      for (final text in cel.texts)
        if (text.id != standing.id)
          text
        else if (draws)
          CelText(id: text.id, content: shown.content, plate: shown.plate),
    ]);
  }

  /// The step that puts the text ON ITS CEL as it is shown — or null when
  /// that would change nothing: a text shown as the cel carries it, or a
  /// new one with no letters.
  ///
  /// A text left with NO letters is taken off the cel: nobody can press on
  /// a text that has nothing to press on.
  ///
  /// ⚠️What is SHOWN, not what is wanted: a step holds a whole text.
  /// [whenSettled] first, where the last want has to be in it.
  CelTextEditCommand? landing({
    required BrushFrameEditingCoordinator coordinator,
    CacheInvalidationSink? cacheInvalidationSink,
  }) {
    final standing = _standing;
    final shown = _shown;
    if (shown.content.isEmpty) {
      return standing == null
          ? null
          : CelTextEditCommand.remove(
              coordinator: coordinator,
              frameKey: key,
              id: standing.id,
              cacheInvalidationSink: cacheInvalidationSink,
            );
    }
    if (standing != null && _isAsStanding(shown, standing)) {
      return null;
    }
    return CelTextEditCommand.put(
      coordinator: coordinator,
      frameKey: key,
      id: standing?.id,
      content: shown.content,
      plate: shown.plate,
      cacheInvalidationSink: cacheInvalidationSink,
    );
  }

  /// Whether [shown] is [standing], the text as the cel carries it: what it
  /// says, and the pixels it is drawn with.
  ///
  /// ⚠️By VALUE, not by which tile objects hold the pixels. A text set
  /// differently and then back again — a colour tried and taken back in
  /// one visit — is baked afresh into tiles of its own, and it is still
  /// the text the cel carries: asked by identity it landed as a step of
  /// history that changed nothing, and one Ctrl+Z did nothing at all. (A
  /// tile that IS the cel's answers at once, `BitmapTile.==`.)
  static bool _isAsStanding(CelTextShown shown, CelText standing) =>
      shown.content == standing.content &&
      mapEquals(shown.plate, standing.plate);

  /// The cel now carries the text as [text] — the session goes on from
  /// there. Null: the text is off the cel, and the session holds a text
  /// that would be new.
  void standOn(CelText? text) {
    _standing = text;
    _shownOver = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _shown.layout.dispose();
    for (final waiter in _waiting) {
      waiter.complete();
    }
    _waiting.clear();
    super.dispose();
  }
}

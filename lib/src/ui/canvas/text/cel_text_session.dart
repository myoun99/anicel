import 'dart:async';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';

import '../../../core/laid_whole.dart';
import '../../../models/bitmap_surface.dart';
import '../../../models/bitmap_tile.dart';
import '../../../models/brush_frame_key.dart';
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
final class CelTextShown {
  /// A text as a bake made it, [plate] its pixels where they were set.
  CelTextShown({
    required this.content,
    required this.layout,
    required Map<TileCoord, BitmapTile> plate,
  }) : pixels = (plate: plate, dx: 0, dy: 0),
       _grid = null;

  /// [content] carried ([CelTextSession.showMoved]): its pixels a plate
  /// moved on [grid] — its cel's — and cut there only once that is asked.
  CelTextShown._carried({
    required this.content,
    required this.layout,
    required this.pixels,
    required ({PasteboardWall pasteboard, int tileSize}) grid,
  }) : _grid = grid;

  final CelTextContent content;
  final CelTextLayout layout;

  /// The pixels as the canvas draws them (`CelTextFloat`).
  final CelTextPixels pixels;

  final ({PasteboardWall pasteboard, int tileSize})? _grid;

  /// The pixels on the cel's own grid — what lands, and what a cel laid
  /// with this text shows.
  ///
  /// 🚨F-344: A TEXT A HAND CARRIES IS CUT ONTO THE GRID ONCE, WHEN THIS IS
  /// FIRST ASKED — at its landing — and not at every move of the hand. The
  /// canvas draws [pixels] meanwhile, which are these pixels exactly
  /// ([celTextPlateMoved] moves them as they are).
  late final Map<TileCoord, BitmapTile> plate =
      _grid == null || (pixels.dx == 0 && pixels.dy == 0)
      ? pixels.plate
      : celTextPlateMoved(
          pixels,
          canvasSize: _grid.pasteboard.canvas,
          pasteboardReach: _grid.pasteboard.reach,
          tileSize: _grid.tileSize,
        );
}

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
/// differently is shown by the canvas alone — floated over the hole it
/// left in its cel, the way an open move shows its lift (F-344,
/// `CelTextFloat`); once it is let go of and still owes its landing, laid
/// in ([shownOver]) — and the cel hears of it once, as one step of
/// history ([landing]). Every other view of the drawing keeps showing it
/// as it stands, which is what an edit nobody has confirmed should look
/// like from outside the tool.
///
/// 🚨★★★WHAT IS ON SCREEN IS A WHOLE TEXT, NEVER A TEXT AND A HALF. Only
/// the engine can turn letters into pixels and it answers a frame or more
/// later, so what the person WANTS ([content]) can be ahead of what is
/// SHOWN ([shown]). Nothing is drawn from the wanted text until its pixels
/// exist: the box and the caret are read off the shown one, so they cannot
/// lead the letters (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로
/// 다르면 안 되」). The newest want wins; the ones a bake overtook are never
/// set at all — the law of [LaidWhole], the shape tool's and the screen's.
class CelTextSession extends ChangeNotifier {
  CelTextSession({
    required this.key,
    required this.pasteboard,
    required this.tileSize,
    required CelText? standing,
    required CelTextContent content,
    required TextLetterStyle nextLetterStyle,
    CelTextBaker? bake,
  }) : _standing = standing,
       _nextLetterStyle = nextLetterStyle,
       _bake = bake ?? bakeCelTextPlate,
       // ⚠️A text that is not on the cel yet starts with NO letters — there
       // is then nothing of it to draw, and so nothing to wait for.
       assert(standing != null || content.isEmpty) {
    _texts.stand(
      _TextPiece.made(_shownOf(standing, content, nextLetterStyle)),
      content,
    );
    // A text with no letters is measured by the letter about to be typed,
    // in whatever face that is. Where that face is still on its way, what
    // is shown was measured in another, and is set again when it is here.
    if (content.isEmpty &&
        celTextFacesArriving(content, nextLetterStyle: nextLetterStyle) !=
            null) {
      _stale = true;
      _layOn(begun: _texts.layTheNewest());
    }
  }

  static CelTextShown _shownOf(
    CelText? standing,
    CelTextContent content,
    TextLetterStyle nextLetterStyle,
  ) => standing == null
      ? CelTextShown(
          content: content,
          layout: layoutCelText(content, nextLetterStyle: nextLetterStyle),
          plate: const {},
        )
      : CelTextShown(
          content: standing.content,
          layout: layoutCelText(
            standing.content,
            nextLetterStyle: nextLetterStyle,
          ),
          plate: standing.plate,
        );

  /// The cel the text is on.
  final BrushFrameKey key;

  /// The wall of the cel the text is on — what its plate is cut at.
  final PasteboardWall pasteboard;
  final int tileSize;
  final CelTextBaker _bake;

  /// The text as the cel carries it — null for one that is not on it yet.
  CelText? get standing => _standing;
  CelText? _standing;

  /// Which text of the cel this is; null until a new one has landed.
  int? get textId => _standing?.id;

  /// What the person wants, what is being made of it and what is up
  /// ([LaidWhole]): a piece is made where none is being made ([_make]).
  late final LaidWhole<CelTextContent, _TextPiece> _texts = LaidWhole(
    begin: _TextPiece.new,
    holds: (piece, content) => !_stale && piece.content == content,
  );

  /// What the person has made of the text — possibly ahead of [shown].
  CelTextContent get content => _texts.wanted!;

  /// What is on screen.
  CelTextShown get shown => _shown;
  CelTextShown get _shown => _texts.shown!.made!;

  /// What is on screen, told whenever it is another: a bake made, or a
  /// hand carried it ([showMoved]) — the one change told here alone.
  ValueListenable<CelTextShown> get showing => _showing;
  late final _Showing _showing = _Showing(() => _shown);

  /// What the first letter typed into a text with none will wear.
  TextLetterStyle get nextLetterStyle => _nextLetterStyle;
  TextLetterStyle _nextLetterStyle;

  /// Whether [shown] has yet to be set again for a letter style that
  /// changed under a text with no letters.
  bool _stale = false;
  bool _disposed = false;
  final List<Completer<void>> _waiting = [];

  /// The last bake the engine refused, until one succeeds — what is shown
  /// then is still the last text it did make.
  Object? get failure => _failure;
  Object? _failure;

  /// Whether what is on screen is what the person wants.
  bool get settled => _texts.laying == null && !_texts.behind;

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
    if (content == _texts.wanted && letters == _nextLetterStyle) {
      return;
    }
    // A text with no letters is measured by the letter about to be typed,
    // so a change of that alone is a change of what is shown.
    _stale = _stale || (letters != _nextLetterStyle && content.isEmpty);
    _nextLetterStyle = letters;
    final begun = _texts.ask(content);
    notifyListeners();
    _layOn(begun: begun);
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
  /// 🚨F-344: TOLD ON [showing] ALONE. The plate is cut onto the cel's grid
  /// once it is asked for ([CelTextShown.plate]) — at the landing — and a
  /// carry is no other text, so nobody building hears of it but whoever
  /// shows where the text stands: the settings' X and Y, the digits alone
  /// (`CelTextCommands.shownInHand`, F-164).
  void showMoved(
    CelTextMoveOrigin origin, {
    required int dx,
    required int dy,
  }) {
    final moved = celTextContentMoved(origin.content, dx: dx, dy: dy);
    if (_texts.laying != null || !_movesWhole(origin.ink, dx: dx, dy: dy)) {
      set(moved);
      return;
    }
    if (moved == _shown.content && moved == _texts.wanted) {
      return;
    }
    final before = _shown;
    _stale = false;
    _texts.stand(
      _TextPiece.made(
        CelTextShown._carried(
          content: moved,
          layout: layoutCelText(moved, nextLetterStyle: _nextLetterStyle),
          pixels: (plate: origin.plate, dx: dx, dy: dy),
          grid: (pasteboard: pasteboard, tileSize: tileSize),
        ),
      ),
      moved,
    );
    _showing.told();
    before.layout.dispose();
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
    final wall = pasteboard.rect;
    bool inside(Rect rect) =>
        rect.left >= wall.left &&
        rect.top >= wall.top &&
        rect.right <= wall.right &&
        rect.bottom <= wall.bottom;
    return inside(ink) &&
        inside(ink.shift(Offset(dx.toDouble(), dy.toDouble())));
  }

  /// Makes the piece just begun ([begun]) — or, where none was and none is
  /// being made, says the making has stopped ([_makingStopped]).
  void _layOn({required bool begun}) {
    if (begun) {
      unawaited(_make(_texts.laying!));
    } else if (_texts.laying == null && !_disposed) {
      _makingStopped();
    }
  }

  Future<void> _make(_TextPiece piece) async {
    // Letters are not set — and no plate is made of them — in a face that
    // is still on its way: they would be set in another, and that is what
    // would land.
    while (true) {
      final arriving = celTextFacesArriving(
        piece.content,
        nextLetterStyle: _nextLetterStyle,
      );
      if (arriving == null) {
        break;
      }
      await arriving;
      if (_disposed) {
        return;
      }
      if (_texts.wanted != piece.content) {
        // A newer want made while it waited is the one made.
        _texts.layingGivenUp();
        _layOn(begun: _texts.layTheNewest());
        return;
      }
    }
    final layout = layoutCelText(
      piece.content,
      nextLetterStyle: _nextLetterStyle,
    );
    final Map<TileCoord, BitmapTile> plate;
    try {
      // A text with no letters is not drawn ([_laidInto]): the engine
      // is not asked for the pixels of nothing.
      plate = piece.content.isEmpty
          ? const <TileCoord, BitmapTile>{}
          : await _bake(
              layout,
              pasteboard: pasteboard,
              tileSize: tileSize,
              previous: _shown.plate,
            );
    } on Object catch (error) {
      layout.dispose();
      if (!_disposed) {
        _refused(error);
      }
      return;
    }
    if (_disposed) {
      layout.dispose();
      return;
    }
    piece.made = CelTextShown(
      content: piece.content,
      layout: layout,
      plate: plate,
    );
    final before = _shown;
    // 🚨A WANT THAT WENT BACK TO WHAT IS ON SCREEN while this was being
    // made — a step back given it up ([standBackOn]) — is no want of it:
    // shown, it would flash for a frame before the screen went back
    // ([LaidWhole.laid], where this law now lives).
    if (_texts.laid() == null) {
      layout.dispose();
    } else {
      _shownAnew(before);
    }
    _layOn(begun: _texts.layTheNewest());
  }

  /// What is up stands in place of [before]: told, and [before] let go.
  void _shownAnew(CelTextShown before) {
    _failure = null;
    _stale = false;
    _showing.told();
    before.layout.dispose();
    notifyListeners();
  }

  /// The engine made no plate: what is shown is still the last text it did
  /// make, and the want goes back to it rather than be asked of the engine
  /// again and again — unless another was made meanwhile, which is asked
  /// next ([LaidWhole.layingGivenUp]).
  ///
  /// ↩️Till 2026-11-12 a want made meanwhile went back too: the session's
  /// own loop had one slot for both (bcaeef502), and nobody asked for it.
  void _refused(Object error) {
    _failure = error;
    if (_texts.layingGivenUp()) {
      _layOn(begun: _texts.layTheNewest());
      return;
    }
    _stale = false;
    _layOn(begun: _texts.ask(_shown.content));
  }

  /// Nothing more is being made: whoever waited for the text on screen to
  /// be the text wanted is answered, where it is, and whoever listens is
  /// told the making has stopped.
  void _makingStopped() {
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

  /// Whether what is shown is what the cel carries: this text as it
  /// stands, or — for one not on the cel yet — nothing, a text with no
  /// letters not being there ([landing]). [shownOver] is then the cel
  /// itself, and the canvas lifts nothing off it
  /// (`CelTextOnCanvas.floatingOn`).
  bool get shownAsCarried {
    final standing = _standing;
    return standing == null
        ? _shown.content.isEmpty
        : _isAsStanding(_shown, standing);
  }

  BitmapSurface _laidInto(BitmapSurface cel) {
    if (shownAsCarried) {
      return cel;
    }
    final standing = _standing;
    final shown = _shown;
    // A text with no letters is NOT THERE — shown and landed alike
    // ([landing]): the box behind it is its letters' box.
    final draws = !shown.content.isEmpty;
    if (standing == null) {
      return cel.withTexts([
        ...cel.texts,
        CelText(
          id: nextCelTextId(cel.texts),
          content: shown.content,
          plate: shown.plate,
        ),
      ]);
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

  /// The cel carries [text] again — a step of the hold taken back, or one
  /// still being set given up (F-377): the session stands on it and wants
  /// it, shown with the very pixels the cel carries.
  void standBackOn(CelText text) {
    final before = _shown;
    _standing = text;
    _shownOver = null;
    _stale = false;
    _texts.stand(
      _TextPiece.made(_shownOf(text, text.content, _nextLetterStyle)),
      text.content,
    );
    _shownAnew(before);
  }

  @override
  void dispose() {
    _disposed = true;
    _shown.layout.dispose();
    _showing.dispose();
    for (final waiter in _waiting) {
      waiter.complete();
    }
    _waiting.clear();
    super.dispose();
  }
}

/// A text a session puts up whole ([CelTextSession._texts]): what it says,
/// and — once made, or where it stands without being made — it as shown.
final class _TextPiece {
  _TextPiece(this.content);

  _TextPiece.made(CelTextShown this.made) : content = made.content;

  final CelTextContent content;
  CelTextShown? made;
}

/// What a session has up, told whenever it is another ([told]).
final class _Showing extends ChangeNotifier
    implements ValueListenable<CelTextShown> {
  _Showing(this._up);

  final CelTextShown Function() _up;

  @override
  CelTextShown get value => _up();

  void told() => notifyListeners();
}

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../models/bitmap_surface.dart';
import '../../../models/brush_frame_key.dart';
import '../../../models/canvas_point.dart';
import '../../../models/canvas_size.dart';
import '../../../models/cel_text.dart';
import '../../../models/text_cel_style.dart';
import '../../../services/brush_frame_editing_coordinator.dart';
import '../../../services/cache_invalidation_executor.dart';
import '../../../services/cel_text_edits.dart';
import '../../../services/command.dart';
import '../../../services/commands/cel_text_edit_command.dart';
import '../../../services/history_manager.dart' show HistoryMark;
import '../../brush/text_tool_options.dart';
import '../../text/cel_text_bake.dart' show CelTextBaker;
import '../../text/cel_text_layout.dart'
    show CelTextBox, celTextAwaitsAFace, celTextBoxOf;
import 'cel_text_editing_controller.dart';
import 'cel_text_session.dart';

part 'cel_text_tool_list.dart';

/// A cel a text can be set on: its key, what holds its picture, the canvas
/// it is cut for, and who is told when it changes.
typedef CelTextCel = ({
  BrushFrameKey key,
  BrushFrameEditingCoordinator coordinator,
  CanvasSize canvasSize,
  CacheInvalidationSink? cacheInvalidationSink,
});

/// How the text tool holds a text: by its BOX — it is moved, turned, sized
/// and set differently as a whole — or by its LETTERS, which the keyboard
/// then edits.
enum CelTextHold { box, letters }

/// What the text tool asks of the canvas panel it works on.
abstract interface class CelTextToolHost {
  /// What the next text starts as (the tool settings).
  TextToolOptions get options;

  /// The cel under the tool — the one a press sets a text on or takes one
  /// from. Null where none is under the playhead, or its row takes no
  /// marks.
  CelTextCel? get cel;

  /// Runs [command] as one step of history.
  ///
  /// [withCelMadeSince] is where history stood ([historyMark]) when a press
  /// made the cel this text is set on: the cel and the text are then ONE
  /// step, as a stroke and the cel made for it are (I-10, 유저 2026-08-30:
  /// 「답은 추천대로」 = merged) — while the two are still all that history
  /// has filed since.
  ///
  /// [setIn] is the families the letters of a text being SET are written
  /// in — none for a text taken off its cel: whoever keeps the project's
  /// fonts takes the ones the text was set with into the same step
  /// (`ProjectFonts.landingWith`).
  void run(
    Command command, {
    HistoryMark? withCelMadeSince,
    Set<String> setIn = const {},
  });

  /// Where history stands now — null where there is none to stand in.
  HistoryMark? get historyMark;

  /// What the tool shows on the canvas changed: the cel has to be drawn
  /// again.
  void shownChanged();
}

/// A text in the tool's hand, or on its way out of it: the session and the
/// cel it is on.
class _Holding {
  _Holding(this.session, this.cel, {this.celMadeSince});

  final CelTextSession session;
  final CelTextCel cel;

  /// For a text begun by the press that MADE its cel: where history stood
  /// then, until the text first lands — or is let go of with nothing
  /// typed, and the cel keeps the step of its own a tap leaves it
  /// (`AutoFrameForStroke.flushAutoFrameForStroke`).
  HistoryMark? celMadeSince;

  /// How far a hand has carried the box's cross off its middle
  /// ([CelTextTool.crossOffCentre]).
  ///
  /// ⛔THE HOLD'S, AND SO GONE WITH IT: a text let go of and taken again
  /// has its cross in the middle, with nothing anywhere to put back.
  Offset crossOffCentre = Offset.zero;

  /// Whether this text was let go of TO BECOME DRAWING
  /// ([CelTextTool.turnIntoDrawing]): once it has landed it is laid into
  /// its cel's drawing, and for the tool it is no text from the moment
  /// this is set ([CelTextTool.takeableOn]).
  bool becomesDrawing = false;
}

/// Tells of one thing, and holds nothing.
class _Telling extends ChangeNotifier {
  void tell() => notifyListeners();
}

/// THE TEXT TOOL'S HAND (R9-rest): the one text it holds, how it holds it,
/// and the landing of what the person made of it.
///
/// It is the panel's, not the canvas layer's: the layer comes and goes with
/// the tool, and a text let go of mid-bake still has to land.
///
/// 🚨★★★ONE HOLD, AND EVERY WAY OUT OF IT LANDS. 유저 2026-10-06 took the
/// press table as it stood: a click away, another text, Esc — each
/// CONFIRMS what was typed (there is no 「cancel」: the way back is undo,
/// one step for one visit to the letters). So whatever ends a hold — a
/// press, a key, another tool, another frame, a save — goes through
/// [confirm], and a text cannot be left half on its cel.
class CelTextTool extends ChangeNotifier {
  CelTextTool({required this.host, CelTextBaker? bake}) : _bake = bake;

  final CelTextToolHost host;
  final CelTextBaker? _bake;

  /// The text in hand, and the cel it is on.
  CelTextSession? get session => _held?.session;
  _Holding? _held;

  /// How it is held — meaningless with nothing in hand.
  CelTextHold get hold => _letters == null ? CelTextHold.box : CelTextHold.letters;

  /// The field's side of the text while its letters are held.
  CelTextEditingController? get letters => _letters;
  CelTextEditingController? _letters;

  // ── the cross ───────────────────────────────────────────────────────

  /// THE CROSS of the text in hand: how far it stands off the middle of the
  /// text's box, along the text's own lines, in canvas pixels
  /// (`CelTextBox.crossAt`). In the middle until a hand carries it
  /// ([carryCross]), and in the middle again for the next text taken.
  ///
  /// 🗣️유저 2026-10-07 (R9-rest-Q2 「끌어서 중심을 옮긴다」): 「**앵커포인트?
  /// 랑 같은 개념**인거같은데 **최대한 같은 법 쓰면서**」. The anchor point's
  /// law is 유저's of 2026-09-20, written on `TransformValues.anchorX`:
  /// 「기본값은 중심인데, 그걸 유저가 드래그해서 움직이는방식 … **앵커포인트는
  /// 회전시 앵커를 기준으로 회전**해」 while 확대/축소 is 「**항상 상자의
  /// 중심**」. So it is here: a turn goes round the cross, a corner sizes the
  /// text about the middle of its box whatever the cross was carried to.
  ///
  /// ⚠️IT IS THE HOLD'S, NOT THE TEXT'S: nothing of it is on the cel, a
  /// step of history neither takes it nor puts it back, and letting go of
  /// the text is the end of it — as closing the transform tool's box is the
  /// end of that box's anchor.
  Offset get crossOffCentre => _held?.crossOffCentre ?? Offset.zero;

  /// Carries the cross of the text in hand to [offCentre] off the middle of
  /// its box.
  ///
  /// ⛔TOLD ON ITS OWN LINE ([crossCarried]), to whoever draws the cross and
  /// to nobody else: no letter of the text is another, so neither the cel
  /// is drawn again nor the settings built again at every move of the hand.
  void carryCross(Offset offCentre) {
    final held = _held;
    if (held == null || held.crossOffCentre == offCentre) {
      return;
    }
    held.crossOffCentre = offCentre;
    _crossCarried.tell();
  }

  /// Told when the cross is carried ([carryCross]).
  Listenable get crossCarried => _crossCarried;
  final _Telling _crossCarried = _Telling();

  /// Texts let go of whose last want was still being set: shown until it
  /// is, landed then, and gone.
  final List<_Holding> _leaving = [];

  bool _disposed = false;

  // ── what the canvas shows ───────────────────────────────────────────

  /// [cel] — [key]'s picture as it stands — with every text this tool has
  /// in hand laid in as it is shown, or null when it holds none on that
  /// cel that differs from what the cel carries.
  BitmapSurface? shownSurfaceFor(BrushFrameKey key, BitmapSurface cel) {
    var surface = cel;
    for (final leaving in _leaving) {
      if (leaving.session.key == key) {
        surface = leaving.session.shownOver(surface);
      }
    }
    final held = _held;
    if (held != null && held.session.key == key) {
      surface = held.session.shownOver(surface);
    }
    return identical(surface, cel) ? null : surface;
  }

  /// Where the texts of [key]'s cel stand that are in NOBODY'S hand:
  /// [cel]'s own, but for the ones this tool speaks for — and, of those,
  /// the ones let go of that still owe a landing, as they are shown.
  ///
  /// 🗣️유저 2026-10-02: 「텍스트는 텍스트 툴을 선택했을때만 **텍스트별로
  /// 박스가 떠서** 편집가능. 화면에 텍스트박스를 선택해서(선택된지 알수있도록
  /// ui 필요.)」 — every text wears a box while the tool is in hand, and the
  /// one in hand wears its own ([session]), which says it is the one.
  List<CelTextBox> restingBoxesOn(BrushFrameKey key, BitmapSurface cel) {
    final leaving = [
      for (final holding in _leaving)
        if (holding.session.key == key) holding,
    ];
    final held = _held?.session;
    final spokenFor = {
      for (final holding in leaving) holding.session.textId,
      if (held != null && held.key == key) held.textId,
    };
    return [
      for (final text in celTextsInReach(cel))
        if (!spokenFor.contains(text.id)) celTextBoxOf(text.content),
      for (final _Holding(:session, :becomesDrawing) in leaving)
        // A text with no letters is not there, shown or landed — and one
        // on its way into the drawing is no text of the tool's any more
        // ([takeableOn]).
        if (!session.shown.content.isEmpty && !becomesDrawing)
          session.shown.layout.onCanvas,
    ];
  }

  /// The texts of [cel] a hand can take hold of now, bottom to top: the
  /// ones in reach ([celTextsInReach]) but for those let go of to become
  /// drawing ([turnIntoDrawing]) whose last want is still being set.
  ///
  /// 🚨FOR THE TOOL SUCH A TEXT IS DRAWING ALREADY — it wears no box
  /// ([restingBoxesOn]), a press finds nothing of it and the settings'
  /// list has no row for it. Taken in hand again it would be a text under
  /// the hand at the moment the drawing took it, and what the hand then
  /// landed would set it on the cel a second time, over its own pixels.
  List<CelText> takeableOn(CelTextCel cel) {
    final turning = {
      for (final holding in _leaving)
        if (holding.becomesDrawing && holding.session.key == cel.key)
          holding.session.textId,
    };
    return [
      for (final text in celTextsInReach(
        cel.coordinator.currentSurfaceOf(cel.key),
      ))
        if (!turning.contains(text.id)) text,
    ];
  }

  // ── the texts of the cel under the hand ─────────────────────────────

  /// The texts of the cel under the tool as the settings list them — named,
  /// picked and deleted from outside the canvas ([CelTextList]).
  late final CelTextList list = CelTextList._(this);

  /// The texts of the cel under the tool are others than they were — a
  /// step of history taken, another frame under the playhead: whoever lists
  /// them reads them again. (The canvas is not told: it drew the change
  /// that brought this.)
  void celTextsChanged() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ── taking hold ─────────────────────────────────────────────────────

  /// Where history stands now — what the press that makes a cel for its
  /// text takes note of first ([beginText]).
  HistoryMark? get historyMark => host.historyMark;

  /// Starts a text on [cel] at [anchor] and takes it by its letters — as
  /// wide as [wrapWidth] says, or growing with what is typed. Whatever was
  /// in hand lands first.
  ///
  /// [celMadeSince] is [historyMark] as the press that MADE [cel] found
  /// it: the text and its cel then land as one step
  /// ([CelTextToolHost.run]).
  void beginText(
    CelTextCel cel,
    CanvasPoint anchor, {
    double? wrapWidth,
    HistoryMark? celMadeSince,
  }) {
    confirm();
    final options = host.options;
    _hold(
      _Holding(
        _sessionOn(
          cel,
          standing: null,
          content: options.newTextAt(anchor, wrapWidth: wrapWidth),
        ),
        cel,
        celMadeSince: celMadeSince,
      ),
    );
    typeAt(const TextSelection.collapsed(offset: 0));
  }

  /// Takes hold of [text], one [cel] carries, by its box. Whatever else
  /// was in hand lands first; a text already in hand stays as it is.
  void takeText(CelTextCel cel, CelText text) {
    final held = _held;
    if (held != null &&
        held.session.key == cel.key &&
        held.session.textId == text.id) {
      stopTyping();
      return;
    }
    confirm();
    _hold(
      _Holding(_sessionOn(cel, standing: text, content: text.content), cel),
    );
  }

  CelTextSession _sessionOn(
    CelTextCel cel, {
    required CelText? standing,
    required CelTextContent content,
  }) => CelTextSession(
    key: cel.key,
    canvasSize: cel.canvasSize,
    tileSize: cel.coordinator.currentSurfaceOf(cel.key).tileSize,
    standing: standing,
    content: content,
    nextLetterStyle: host.options.letters,
    bake: _bake,
  );

  void _hold(_Holding holding) {
    holding.session.addListener(_sessionChanged);
    _held = holding;
    _changed();
  }

  /// Takes the text in hand by its LETTERS, the caret (or the letters
  /// selected) at [selection].
  void typeAt(TextSelection selection) {
    final session = _held?.session;
    if (session == null) {
      return;
    }
    final letters = _letters;
    if (letters != null) {
      letters.selection = selection;
      return;
    }
    _letters = CelTextEditingController(
      content: session.content,
      nextLetterStyle: session.nextLetterStyle,
      selection: selection,
    )..addListener(_lettersChanged);
    _changed();
  }

  /// Lets go of the letters and holds the text by its box again. What was
  /// typed LANDS — a visit to a text's letters is one step of history.
  void stopTyping() {
    if (!_dropLetters()) {
      return;
    }
    _landHeld(thenLetGo: false);
    _changed();
  }

  bool _dropLetters() {
    final letters = _letters;
    if (letters == null) {
      return false;
    }
    _letters = null;
    letters
      ..removeListener(_lettersChanged)
      ..dispose();
    return true;
  }

  // ── what the person makes of it ─────────────────────────────────────

  void _lettersChanged() {
    final letters = _letters;
    final session = _held?.session;
    if (letters == null || session == null) {
      return;
    }
    session.set(letters.content, nextLetterStyle: letters.nextLetterStyle);
    notifyListeners();
  }

  /// Shows the text in hand as [content] — a hand on its box mid-drag, a
  /// setting mid-slide — with [nextLetterStyle] for the letter a text with
  /// none would be typed in. Nothing lands until [landEdit].
  void showEdit(CelTextContent content, {TextLetterStyle? nextLetterStyle}) {
    final letters = _letters;
    if (letters != null) {
      letters.restyle(
        content,
        nextLetterStyle: nextLetterStyle,
        goesOn: _editGoesOn,
      );
    } else {
      _held?.session.set(content, nextLetterStyle: nextLetterStyle);
    }
    _editGoesOn = true;
  }

  /// Whether a [showEdit] is one more value of an edit already under way.
  bool _editGoesOn = false;

  /// The hand let go of the box, or the setting came to rest: what
  /// [showEdit] showed lands as one step. While the LETTERS are held it is
  /// part of that visit instead — one step back there — and lands with it.
  void landEdit() {
    _editGoesOn = false;
    if (_letters == null) {
      _landHeld(thenLetGo: false);
    }
  }

  /// A change of a LETTER setting, made on the text in hand: it reaches the
  /// letters the setting speaks for — the selected ones, or with none
  /// selected every letter ([celTextLettersSpokenFor], 유저 2026-10-02 ·
  /// 10-06).
  ///
  /// [settled] false is a value still being dragged: it shows, and lands
  /// with the one that follows it.
  void changeLetters(
    TextLetterStyle Function(TextLetterStyle style) change, {
    bool settled = true,
  }) {
    final session = _held?.session;
    if (session == null) {
      return;
    }
    final content = _contentInHand(session);
    showEdit(
      celTextRestyled(
        content,
        range: _lettersSpokenFor(content),
        change: change,
      ),
      // A text with no letters has only the letter about to be typed to
      // set.
      nextLetterStyle: content.isEmpty
          ? change(session.nextLetterStyle)
          : null,
    );
    if (settled) {
      landEdit();
    }
  }

  /// The letters of [content] a LETTER setting speaks for: the selected
  /// ones, or with none selected every letter ([celTextLettersSpokenFor],
  /// 유저 2026-10-02 · 10-06). What the settings SHOW
  /// ([letterStylesSpokenFor]) and what a change of one is MADE ON
  /// ([changeLetters]) are this one range.
  CelTextRange _lettersSpokenFor(CelTextContent content) {
    final selection = _letters?.selection;
    return celTextLettersSpokenFor(
      content,
      selectionStart: selection?.start ?? 0,
      selectionEnd: selection?.end ?? 0,
    );
  }

  /// How the letters a letter setting speaks for are set now — one style a
  /// run, in reading order, so a setting they do not agree on shows as
  /// mixed. For a text with no letters, what the first one typed will wear.
  /// Null with nothing in hand.
  List<TextLetterStyle>? get letterStylesSpokenFor {
    final session = _held?.session;
    if (session == null) {
      return null;
    }
    final content = _contentInHand(session);
    return content.isEmpty
        ? [session.nextLetterStyle]
        : celTextStylesOf(content, _lettersSpokenFor(content));
  }

  /// The text in hand as a setting finds it — null with none.
  CelTextContent? get contentInHand {
    final session = _held?.session;
    return session == null ? null : _contentInHand(session);
  }

  /// The text a setting is made on: what the FIELD holds while the letters
  /// are held, and otherwise what the session wants.
  ///
  /// ⚠️The two are one text but for a bake the engine refused: the session
  /// then takes its want back to the last text it made
  /// ([CelTextSession.failure]) while the field still holds every letter
  /// typed — and a setting made on the session's would be made on letters
  /// the field no longer has.
  CelTextContent _contentInHand(CelTextSession session) =>
      _letters?.content ?? session.content;

  /// A change of a setting of the WHOLE TEXT — its alignment, its width,
  /// its line pitch, the box behind it — made on the text in hand.
  void changeBox(
    CelTextContent Function(CelTextContent content) change, {
    bool settled = true,
  }) {
    final session = _held?.session;
    if (session == null) {
      return;
    }
    showEdit(change(_contentInHand(session)));
    if (settled) {
      landEdit();
    }
  }

  // ── letting go ──────────────────────────────────────────────────────

  /// Lands what is in hand and lets go of it.
  void confirm() {
    if (_held == null) {
      return;
    }
    _dropLetters();
    _landHeld(thenLetGo: true);
    _changed();
  }

  /// Takes the text in hand off its cel — one step — and lets go of it. A
  /// text that was never on the cel is simply gone.
  void deleteText() {
    final held = _held;
    if (held == null) {
      return;
    }
    _dropLetters();
    _held = null;
    final standing = held.session.standing;
    _retire(held.session);
    if (standing != null) {
      host.run(
        CelTextEditCommand.remove(
          coordinator: held.cel.coordinator,
          frameKey: held.cel.key,
          id: standing.id,
          cacheInvalidationSink: held.cel.cacheInvalidationSink,
        ),
      );
    }
    _changed();
  }

  /// Turns the text in hand into DRAWING and lets go of it: its pixels are
  /// the cel's drawing from then on, and it is no text any more.
  ///
  /// 🗣️유저 2026-10-06: 「텍스트 그림으로 굳히기 아이디어 좋네. … 나중에
  /// 도구설정에 등장시키기로. 동작은 텍스트 선택하면 해당 버튼 활성화색」.
  ///
  /// ★TWO STEPS, NOT ONE, where the text had something to land. Leaving
  /// the hand is [confirm] — what was typed or set lands first, the step a
  /// visit to a text always is — and turning into drawing is the step
  /// after it: one Ctrl+Z gives the text back AS A TEXT, as it was when
  /// the button was pressed, and not the cel as it was before the visit.
  ///
  /// A text whose last want is still being set turns once it is set: what
  /// turns is a whole text, as what lands is ([_landHeld]). A text with no
  /// letters is simply let go of.
  void turnIntoDrawing() {
    final held = _held;
    if (held == null) {
      return;
    }
    held.becomesDrawing = true;
    confirm();
  }

  /// Lands everything this tool holds AS IT IS SHOWN, now — for whoever
  /// cannot wait a frame: a step of history about to be taken, a panel
  /// going away. A want still being set is given up; what the person saw
  /// is what lands.
  void landNow() {
    _landAll();
    _changed();
  }

  /// Lands everything this tool holds AS IT IS SHOWN, now — and keeps in
  /// hand what is in hand: what a save a PERSON asked for takes
  /// (`ProjectFileDoor._settleWorkInFlight`; of the pen, 유저 2026-09-10:
  /// 「그냥 스트로크 커밋시키고 저장로직 발동시키면 되는거아닌가?」). The file
  /// then holds the text they were looking at when they asked, and the
  /// typing goes on: what is typed after lands when the visit ends, a step
  /// of its own.
  ///
  /// Answers whether anything landed. (Whoever draws the canvas hears of it
  /// from the text itself, which then stands on what the cel carries.)
  bool landShown() {
    var landed = false;
    for (final holding in [..._leaving, ?_held]) {
      landed = _land(holding) || landed;
    }
    return landed;
  }

  void _landAll() {
    _dropLetters();
    final held = _held;
    _held = null;
    // In the order they were let go of, the one in hand last — and each
    // out of [_leaving] before it lands, as [_landOut] asks.
    if (held != null) {
      _leaving.add(held);
    }
    while (_leaving.isNotEmpty) {
      _landOut(_leaving.removeAt(0));
    }
  }

  /// Whether anything is in hand or still owed a landing — what a step of
  /// history asks before it is taken.
  bool get holdsAnything => _held != null || _leaving.isNotEmpty;

  void _landHeld({required bool thenLetGo}) {
    final held = _held;
    if (held == null) {
      return;
    }
    // A text with no letters is nothing to go on holding: landing takes it
    // off its cel ([CelTextSession.landing]).
    final letGo = thenLetGo || held.session.content.isEmpty;
    if (letGo) {
      _held = null;
    }
    if (held.session.settled) {
      if (letGo) {
        _landOut(held);
      } else {
        _land(held);
      }
      return;
    }
    // Its last want is still being set: it stays on screen until that is,
    // and lands then — a step holds a whole text.
    if (letGo) {
      _leaving.add(held);
    }
    unawaited(_landOnceSettled(held));
  }

  Future<void> _landOnceSettled(_Holding held) async {
    await held.session.whenSettled();
    if (_disposed) {
      return;
    }
    final stillHeld = identical(_held, held);
    final leaving = _leaving.indexOf(held);
    if (!stillHeld && leaving < 0) {
      // Landed already by [landNow], or deleted.
      return;
    }
    if (stillHeld && _letters != null) {
      // The letters were taken up again before it settled: this visit goes
      // on, and lands when it ends.
      return;
    }
    if (leaving >= 0) {
      _leaving.removeAt(leaving);
      _landOut(held);
    } else {
      _land(held);
    }
    _changed();
  }

  /// THE WAY OUT OF THE HAND: lands [holding] — let go of, and out of
  /// [_leaving] — as it is shown, turns it into its cel's drawing where it
  /// was let go of for that ([turnIntoDrawing]), and is done with it.
  void _landOut(_Holding holding) {
    _land(holding);
    if (holding.becomesDrawing) {
      _turnIntoDrawing(holding);
    }
    _retire(holding.session);
  }

  /// Turns [holding]'s text — landed, so on its cel as it was shown — into
  /// the cel's drawing, as one step.
  ///
  /// 🚨THE TEXTS UNDER IT THAT IT COVERS GO WITH IT
  /// (`celSurfaceWithTextAsDrawing`), and one of those can be in this hand
  /// or still owed its landing. Each is put on the cel AS IT IS SHOWN first
  /// — what turns into drawing is what the person was looking at — and one
  /// the drawing then took is let go of with nothing more: no text is left
  /// for what it still wanted to be set on.
  void _turnIntoDrawing(_Holding holding) {
    final _Holding(:session, :cel) = holding;
    final standing = session.standing;
    if (standing == null) {
      // No letters: its landing took it off the cel, or it never was on it.
      return;
    }
    final beside = [
      for (final other in [..._leaving, ?_held])
        if (other.session.key == session.key) other,
    ];
    for (final other in beside) {
      _land(other);
    }
    host.run(
      CelTextEditCommand.intoDrawing(
        coordinator: cel.coordinator,
        frameKey: cel.key,
        id: standing.id,
        cacheInvalidationSink: cel.cacheInvalidationSink,
      ),
    );
    final left = {
      for (final text in cel.coordinator.currentSurfaceOf(cel.key).texts)
        text.id,
    };
    for (final other in beside) {
      final id = other.session.textId;
      if (id == null || left.contains(id)) {
        continue;
      }
      if (identical(other, _held)) {
        _dropLetters();
        _held = null;
      } else {
        _leaving.remove(other);
      }
      _retire(other.session);
    }
  }

  /// Puts [holding]'s text on its cel as it is shown, as one step, and
  /// stands the session on what the cel then carries. Whether there was
  /// anything to put.
  bool _land(_Holding holding) {
    final _Holding(:session, :cel) = holding;
    final command = session.landing(
      coordinator: cel.coordinator,
      cacheInvalidationSink: cel.cacheInvalidationSink,
    );
    if (command == null) {
      return false;
    }
    // The first landing of a text whose press made its cel takes the cel
    // with it; every later one is a step of its own.
    final celMadeSince = holding.celMadeSince;
    holding.celMadeSince = null;
    host.run(
      command,
      withCelMadeSince: celMadeSince,
      // What is shown is what lands ([CelTextSession.landing]) — and a
      // text with no letters is in no face.
      setIn: {
        for (final span in session.shown.content.spans) ?span.style.fontFamily,
      },
    );
    final id = command.textId;
    final texts = cel.coordinator.currentSurfaceOf(cel.key).texts;
    session.standOn(
      id == null ? null : texts.where((text) => text.id == id).firstOrNull,
    );
    return true;
  }

  void _retire(CelTextSession session) {
    session
      ..removeListener(_sessionChanged)
      ..dispose();
  }

  void _sessionChanged() => _changed();

  void _changed() {
    if (_disposed) {
      return;
    }
    host.shownChanged();
    notifyListeners();
  }

  @override
  void dispose() {
    // ⚠️Told nobody: the panel this would redraw is the one going away.
    _disposed = true;
    _landAll();
    _crossCarried.dispose();
    super.dispose();
  }
}

/// THE TEXTS OF A CEL'S PICTURE THE TOOL CAN REACH NOW, bottom to top: all
/// of them but the ones written in a face that is still on its way to the
/// engine ([celTextAwaitsAFace]).
///
/// Such a text shows from its baked plate like any other. What the tool
/// would do with it — draw its box, ask whether a press is inside it, take
/// it in hand — is measured in its letters, and until its face is here
/// those would be set in another. So for the tool it is not there yet, in
/// every place alike: the boxes ([CelTextTool.restingBoxesOn]), a press
/// (`cel_text_press`), the settings' list ([CelTextList]). Asking is what
/// sends for the face, and its arrival is told (`CanvasLetterFaces.changes`).
Iterable<CelText> celTextsInReach(BitmapSurface picture) =>
    picture.texts.where((text) => !celTextAwaitsAFace(text.content));

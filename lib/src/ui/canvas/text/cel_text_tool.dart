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
  void run(Command command, {HistoryMark? withCelMadeSince});

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
        if (holding.session.key == key) holding.session,
    ];
    final held = _held?.session;
    final spokenFor = {
      for (final session in leaving) session.textId,
      if (held != null && held.key == key) held.textId,
    };
    return [
      for (final text in celTextsInReach(cel))
        if (!spokenFor.contains(text.id)) celTextBoxOf(text.content),
      for (final session in leaving)
        // A text with no letters is not there, shown or landed.
        if (!session.shown.content.isEmpty) session.shown.layout.onCanvas,
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
    for (final holding in [..._leaving, ?held]) {
      _land(holding);
      _retire(holding.session);
    }
    _leaving.clear();
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
      _land(held);
      if (letGo) {
        _retire(held.session);
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
    _land(held);
    if (leaving >= 0) {
      _leaving.removeAt(leaving);
      _retire(held.session);
    }
    _changed();
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
    host.run(command, withCelMadeSince: celMadeSince);
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

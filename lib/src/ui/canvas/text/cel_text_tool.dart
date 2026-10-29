import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

import '../../../models/bitmap_surface.dart';
import '../../../models/brush_frame_key.dart';
import '../../../models/canvas_point.dart';
import '../../../models/cel_text.dart';
import '../../../models/text_cel_style.dart';
import '../../../services/bitmap_surface_geometry.dart'
    show celTextContentMoved;
import '../../../services/brush_frame_editing_coordinator.dart';
import '../../../services/cache_invalidation_executor.dart';
import '../../../services/cel_text_edits.dart';
import '../../../services/command.dart';
import '../../../services/commands/cel_text_edit_command.dart';
import '../../../services/history_manager.dart' show HistoryGestures;
import '../../../services/history_run.dart';
import '../../brush/text_tool_options.dart';
import '../../text/cel_text_bake.dart' show CelTextBaker;
import '../../text/cel_text_layout.dart'
    show CelTextBox, celTextAwaitsAFace, celTextBoxOf;
import 'cel_text_editing_controller.dart';
import 'cel_text_session.dart';

part 'cel_text_tool_list.dart';
part 'cel_text_tool_on_canvas.dart';
part 'cel_text_tool_way_out.dart';

/// A cel a text can be set on: its key, what holds its picture (and with
/// it the wall it is cut at), and who is told when it changes.
typedef CelTextCel = ({
  BrushFrameKey key,
  BrushFrameEditingCoordinator coordinator,
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

  /// What the hand leaves [options] as: setting a text seeds them
  /// ([TextToolOptions.seeded]), and sizing one by its corner gives the
  /// next text that size (F-342).
  set options(TextToolOptions options);

  /// The brush's colour — the next text's while the tool has none of its
  /// own ([TextToolOptions.takesTheBrushColour]). Null where there is no
  /// brush to read.
  int? get brushColour;

  /// The cel under the tool — the one a press sets a text on or takes one
  /// from. Null where none is under the playhead, or its row takes no
  /// marks.
  CelTextCel? get cel;

  /// Runs [command] as one step of history.
  ///
  /// [setIn] is the families the letters of a text being SET are written
  /// in — none for a text taken off its cel: whoever keeps the project's
  /// fonts takes the ones the text was set with into the same step
  /// (`ProjectFonts.landingWith`).
  void run(Command command, {Set<String> setIn = const {}});

  /// The history the text's steps are written in, as a hold writes them
  /// across many events — null where there is none.
  HistoryGestures? get gestures;

  /// What the canvas draws for a cel in place of its picture changed — a
  /// text taken or let go of, one let go of set or landed
  /// ([CelTextOnCanvas.shownSurfaceFor]): it has to be drawn again. What the
  /// text in hand makes of itself floats, and is told on
  /// [CelTextTool.shownInHand] instead.
  void shownChanged();
}

/// Whose step a landing of a text in hand is: the visit to its letters' —
/// a step of its own — or its BOX's ([_Holding.boxSteps]).
enum _StepOf { letters, box }

/// A text in the tool's hand, or on its way out of it: the session and the
/// cel it is on.
class _Holding {
  _Holding(
    this.session,
    this.cel, {
    required HistoryGestures? gestures,
    this.celMade,
  }) : boxSteps = gestures == null ? null : HistoryRun(gestures);

  final CelTextSession session;
  final CelTextCel cel;

  /// The steps landed while the text is held by its BOX — a carry, a turn,
  /// a corner, a setting come to rest: undo takes them back one at a time
  /// while it is ([CelTextTool.stepBack]), and they are ONE step once the
  /// box lets go of it ([closeBoxSteps]) — its letters taken up, or the
  /// text let go of. Null with no history to write in.
  ///
  /// 🗣️F-377 (유저 2026-10-17): 「변형중 언두가 직전변형 취소라던가. 끝나면
  /// 한번에 취소라던가 하듯이 변형 상태는 모두 기본적으로 그걸 따르도록.
  /// 텍스트 변형이든 뭐든」. ⚠️A visit to the letters stays a step of its
  /// own and closes the box's steps before it: F-377-Q1's recommended
  /// 「변형만 묶는다」, built ahead of its answer on 유저's 「알아서 추천대로
  /// 작업시작해줘」. ↩️Each step stayed one of its own: a text moved, sized
  /// and turned took three undos once let go.
  final HistoryRun? boxSteps;

  /// Whose step the landing this text still owes is — the oldest asked
  /// for: whatever lands once its last want is set lands in that step.
  /// Null with none owed.
  _StepOf? owed;

  /// The box lets go: what it landed is ONE step.
  void closeBoxSteps() => boxSteps?.end('Set text');

  /// For a text begun by the press that MADE its cel: the run that press
  /// began ([CelTextTool.beginRun]), which the text's first landing joins
  /// and ends — the text and its cel ONE step, I-10's answer for a stroke
  /// (유저 2026-08-30: merged) said of a text: one Ctrl+Z after typing on an
  /// empty frame leaves the frame empty again.
  ///
  /// The cel was filed when the press came up, a step of its own, as a tap
  /// leaves it (`AutoFrameForStroke.flushAutoFrameForStroke`) — the text is
  /// typed long after, so it cannot ride the press as a stroke does: the
  /// run takes that step for its own ([HistoryRun.adopt]). Null once the
  /// text has first landed; let go of with nothing typed, the cel keeps
  /// its step.
  HistoryRun? celMade;

  /// How far a hand has carried the box's cross off its middle
  /// ([CelTextTool.crossOffCentre]).
  ///
  /// ⛔THE HOLD'S, AND SO GONE WITH IT: a text let go of and taken again
  /// has its cross in the middle, with nothing anywhere to put back.
  Offset crossOffCentre = Offset.zero;

  /// The carry of the text under way ([CelTextTool.carry]): where it stood
  /// when it began — as shown, and as a setting finds it — and how far it
  /// has gone, until it lands ([CelTextTool.landEdit]).
  ({CelTextMoveOrigin origin, CelTextContent content, int dx, int dy})?
  carry;

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

  /// Whether a carry of the text in hand is under way ([carry]).
  bool get carrying => _held?.carry != null;

  /// How far the text in hand has been carried since the carry under way
  /// began, in whole pixels — nothing while none is ([carry]).
  ({int dx, int dy}) get carried {
    final carry = _held?.carry;
    return carry == null ? (dx: 0, dy: 0) : (dx: carry.dx, dy: carry.dy);
  }

  /// The text in hand shown [dx] across and [dy] down, in whole pixels,
  /// from where it stood when this carry began — by a hand on its box, or
  /// by the steps of its place in the tool settings (I-95): ONE carry,
  /// whichever moves it. Its pixels go with it rather than being set
  /// again, where they can (`CelTextSession.showMoved`); with its letters
  /// held it is set where it goes. [landEdit] lands it, and a carry after
  /// that begins where this one ended.
  void carry({required int dx, required int dy}) {
    final held = _held;
    if (held == null) {
      return;
    }
    final session = held.session;
    final from =
        held.carry ??
        (
          origin: session.moveOrigin,
          content: _contentInHand(session),
          dx: 0,
          dy: 0,
        );
    held.carry = (origin: from.origin, content: from.content, dx: dx, dy: dy);
    if (_letters != null) {
      showEdit(celTextContentMoved(from.content, dx: dx, dy: dy));
      return;
    }
    session.showMoved(from.origin, dx: dx, dy: dy);
  }

  /// The way out of the hand: the landing of what it lets go of, and the
  /// texts let go of that still owe theirs ([_CelTextWayOut]).
  late final _CelTextWayOut _wayOut = _CelTextWayOut(this);

  bool _disposed = false;

  // ── what the canvas shows ───────────────────────────────────────────

  /// What the canvas shows for what the hand holds: the cel's place, what
  /// floats over it and the boxes the texts wear ([CelTextOnCanvas]).
  late final CelTextOnCanvas onCanvas = CelTextOnCanvas._(this);

  /// What of the text in hand is on screen, told whenever it is another — a
  /// bake made, a hand carried it, another text taken. Null with none.
  ///
  /// ⛔ITS OWN LINE, for [crossCarried]'s reason: a text a hand carries is
  /// no other text, so neither the panel is built again at every move nor
  /// the settings' rows. Whoever draws the text listens here — and whoever
  /// shows where it stands, through the app's channel
  /// (`CelTextCommands.shownInHand`).
  ValueListenable<CelTextShown?> get shownInHand => _shownInHand;
  final ValueNotifier<CelTextShown?> _shownInHand = ValueNotifier(null);

  /// The texts of [cel] a hand can take hold of now, bottom to top: the
  /// ones in reach ([celTextsInReach]) but for those let go of to become
  /// drawing ([turnIntoDrawing]) whose last want is still being set.
  ///
  /// 🚨FOR THE TOOL SUCH A TEXT IS DRAWING ALREADY — it wears no box
  /// ([CelTextOnCanvas.restingBoxesOn]), a press finds nothing of it and
  /// the settings' list has no row for it. Taken in hand again it would be
  /// a text under the hand at the moment the drawing took it, and what the
  /// hand then landed would set it on the cel a second time, over its own
  /// pixels.
  List<CelText> takeableOn(CelTextCel cel) {
    final turning = {
      for (final holding in _wayOut.leaving)
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

  /// A run of history begun where it stands now — what the press that
  /// makes a cel for its text begins first ([beginText]). Null where there
  /// is no history.
  HistoryRun? beginRun() {
    final gestures = host.gestures;
    return gestures == null ? null : (HistoryRun(gestures)..begin());
  }

  /// Starts a text on [cel] at [anchor] and takes it by its letters — as
  /// wide as [wrapWidth] says and at least [minHeight] tall, or growing
  /// with what is typed. Whatever was in hand lands first.
  ///
  /// [celMade] is the run the press that MADE [cel] began ([beginRun]):
  /// the text's first landing joins it, and the two are one step.
  void beginText(
    CelTextCel cel,
    CanvasPoint anchor, {
    double? wrapWidth,
    double? minHeight,
    HistoryRun? celMade,
  }) {
    confirm();
    // The text is set in the brush's colour while the tool has none of its
    // own — and from here the tool keeps that colour (F-334-Q1).
    final options = host.options = host.options.seeded(
      brushColour: host.brushColour,
    );
    _hold(
      _Holding(
        _sessionOn(
          cel,
          standing: null,
          content: options.newTextAt(
            anchor,
            wrapWidth: wrapWidth,
            minHeight: minHeight,
          ),
        ),
        cel,
        gestures: host.gestures,
        celMade: celMade,
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
      _Holding(
        _sessionOn(cel, standing: text, content: text.content),
        cel,
        gestures: host.gestures,
      ),
    );
  }

  CelTextSession _sessionOn(
    CelTextCel cel, {
    required CelText? standing,
    required CelTextContent content,
  }) => CelTextSession(
    key: cel.key,
    pasteboard: cel.coordinator.currentSurfaceOf(cel.key).pasteboard,
    tileSize: cel.coordinator.currentSurfaceOf(cel.key).tileSize,
    standing: standing,
    content: content,
    nextLetterStyle: host.options.letters(brushColour: host.brushColour),
    bake: _bake,
  );

  void _hold(_Holding holding) {
    holding.session
      ..addListener(_sessionChanged)
      ..showing.addListener(_sessionShown);
    // Taken in hand, it is held by its box until its letters are taken.
    holding.boxSteps?.begin();
    _held = holding;
    _changed();
  }

  /// Takes the text in hand by its LETTERS, the caret (or the letters
  /// selected) at [selection].
  void typeAt(TextSelection selection) {
    final held = _held;
    if (held == null) {
      return;
    }
    final session = held.session;
    final letters = _letters;
    if (letters != null) {
      letters.selection = selection;
      return;
    }
    // The box lets go of it: its steps are ONE — and whatever it still
    // owes a landing of is the visit's now, landed when the visit ends.
    held
      ..closeBoxSteps()
      ..owed = null;
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
    _wayOut.landHeld(thenLetGo: false, of: _StepOf.letters);
    // Held by its box again — after the visit's own step.
    _held?.boxSteps?.begin();
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
  /// [showEdit] showed lands as one step of the box's — one step back while
  /// the box holds the text, and ONE with the box's others once it lets go
  /// ([_Holding.boxSteps]). While the LETTERS are held it is part of that
  /// visit instead — one step back there — and lands with it.
  void landEdit() {
    _held?.carry = null;
    _editGoesOn = false;
    if (_letters == null) {
      _wayOut.landHeld(thenLetGo: false, of: _StepOf.box);
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
  /// ([changeLetters]) are this one range — and a paragraph setting's are
  /// its paragraphs ([changeParagraphs]).
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

  /// A change of a PARAGRAPH setting — the alignment, the line pitch — made
  /// on the text in hand: it reaches the paragraphs of the letters a letter
  /// setting speaks for ([celTextParagraphsOf]) — those the selection
  /// touches, or with none selected every one.
  void changeParagraphs(
    CelTextParagraph Function(CelTextParagraph paragraph) change, {
    bool settled = true,
  }) => changeBox(
    (content) => celTextReparagraphed(
      content,
      range: celTextParagraphsOf(content, _lettersSpokenFor(content)),
      change: change,
    ),
    settled: settled,
  );

  /// How the paragraphs a paragraph setting speaks for are set now, in
  /// reading order ([changeParagraphs]). Null with nothing in hand.
  List<CelTextParagraph>? get paragraphsSpokenFor {
    final content = contentInHand;
    if (content == null) {
      return null;
    }
    final range = celTextParagraphsOf(content, _lettersSpokenFor(content));
    return content.paragraphs.sublist(range.first, range.last + 1);
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

  /// A change of a setting of the WHOLE TEXT — its width, how wide its
  /// letters are drawn, the box behind it — made on the text in hand.
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

  // ── a step back ─────────────────────────────────────────────────────

  /// Whether an undo has a step of the BOX to take back ([stepBack]): one
  /// landed while the box holds the text in hand — or one still owed, its
  /// last want still being set. (None while its letters are held: taking
  /// them up closed the box's steps, and what it still owed rides the
  /// visit — [typeAt].)
  bool get canStepBack {
    final held = _held;
    return held != null &&
        (held.owed == _StepOf.box || (held.boxSteps?.canTakeBack ?? false));
  }

  /// Takes the box's last step back and keeps the text in hand, as the
  /// transform tool's box does (F-377): one still owed is given up, and
  /// otherwise the last one landed is taken back — and no redo's: a step
  /// the hand took back inside its hold is not one it made. The text then
  /// stands as its cel carries it, with the very pixels it carries.
  void stepBack() {
    final held = _held;
    if (held == null || !canStepBack) {
      return;
    }
    if (held.owed == _StepOf.box) {
      held.owed = null;
    } else {
      held.boxSteps!.takeBack();
    }
    final session = held.session;
    final standing = held.cel.coordinator
        .currentSurfaceOf(held.cel.key)
        .texts
        .where((text) => text.id == session.textId)
        .firstOrNull;
    if (standing != null) {
      session.standBackOn(standing);
    }
    _changed();
  }

  // ── letting go ──────────────────────────────────────────────────────

  /// Lands what is in hand and lets go of it.
  void confirm() {
    if (_held == null) {
      return;
    }
    final of = _stepOfTheHand;
    _dropLetters();
    _wayOut.landHeld(thenLetGo: true, of: of);
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
    // What the box did to it before is one step, and taking it off another.
    held.closeBoxSteps();
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
  /// turns is a whole text, as what lands is ([_CelTextWayOut.landHeld]). A
  /// text with no letters is simply let go of.
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
    _wayOut.landAll();
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
  bool landShown() => _wayOut.landShown();

  /// Whether anything is in hand or still owed a landing — what a step of
  /// history asks before it is taken.
  bool get holdsAnything => _held != null || _wayOut.leaving.isNotEmpty;

  /// Whose step a landing of the text in hand is now.
  _StepOf get _stepOfTheHand =>
      _letters == null ? _StepOf.box : _StepOf.letters;

  void _retire(CelTextSession session) {
    session
      ..removeListener(_sessionChanged)
      ..showing.removeListener(_sessionShown)
      ..dispose();
  }

  /// A text this tool holds or still owes a landing made something of
  /// itself.
  ///
  /// 🚨F-344: THE PANEL IS BUILT AGAIN ONLY WHERE WHAT IT DRAWS IN THE
  /// CEL'S PLACE CHANGED ([CelTextOnCanvas.shownSurfaceFor]) — the text in
  /// hand lifted off or put back ([_lifts]), or one let go of, laid in
  /// there, set again. The text in hand floats over that
  /// ([CelTextOnCanvas.floatingOn]) and is drawn again from [shownInHand].
  void _sessionChanged() {
    if (_disposed) {
      return;
    }
    if (!_tellIfLifted() && _wayOut.leaving.isNotEmpty) {
      host.shownChanged();
    }
    notifyListeners();
  }

  void _sessionShown() {
    if (_disposed) {
      return;
    }
    _shownInHand.value = _held?.session.shown;
    _tellIfLifted();
  }

  /// Whether the text in hand is lifted off its cel: in hand, and shown as
  /// something other than what the cel carries.
  bool get _lifts => !(_held?.session.shownAsCarried ?? true);

  /// [_lifts] as the panel was last told of it.
  bool _toldLifted = false;

  /// Tells the panel when [_lifts] is not what it was told — and answers
  /// whether it did.
  bool _tellIfLifted() {
    final lifts = _lifts;
    if (lifts == _toldLifted) {
      return false;
    }
    _toldLifted = lifts;
    host.shownChanged();
    return true;
  }

  void _changed() {
    if (_disposed) {
      return;
    }
    _shownInHand.value = _held?.session.shown;
    _toldLifted = _lifts;
    host.shownChanged();
    notifyListeners();
  }

  @override
  void dispose() {
    // ⚠️Told nobody: the panel this would redraw is the one going away.
    _disposed = true;
    _wayOut.landAll();
    _crossCarried.dispose();
    _shownInHand.dispose();
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
/// every place alike: the boxes ([CelTextOnCanvas.restingBoxesOn]), a press
/// (`cel_text_press`), the settings' list ([CelTextList]). Asking is what
/// sends for the face, and its arrival is told (`CanvasLetterFaces.changes`).
Iterable<CelText> celTextsInReach(BitmapSurface picture) =>
    picture.texts.where((text) => !celTextAwaitsAFace(text.content));

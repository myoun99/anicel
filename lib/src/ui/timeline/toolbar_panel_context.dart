import 'dart:async';

import 'package:flutter/widgets.dart' show BuildContext, Listenable;

import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart' show InbetweenMark;
import '../../models/pill_subject.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart' show coveringDrawingBlockAt;
import '../../models/timeline_row_address.dart';
import '../../models/track_projection_row.dart' show trackIdOfProjectionRow;
import '../../models/track_id.dart';
import '../editor_command_actions.dart' show createActiveInstance;
import '../editor_session_manager.dart';
import '../paste_linked_asking_first.dart';
import '../paste_with_its_media.dart';
import '../session/block_naming.dart' show AutoNameCuts, AutoNameTargets;
import '../session/effects_and_fx.dart'
    show ActiveRowChain, EffectChainHolder, TrackChain;
import '../session/frame_clipboard.dart' show ClipboardPlace;
import '../session/storyboard_cursor.dart' show CommaTarget;
import '../session/what_a_copy_brings.dart' show BringsMedia;
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../storyboard_layer_policy.dart' show projectedLayerInHand;

/// B8 (2026-08-17): 상단 버튼의 패널 스코프 — the shared toolbar's layer,
/// frame, shared and fx verbs dispatch AGAINST THE PANEL THEY ARE PRESSED
/// IN, and the toolbar asks its host panel through THIS interface instead
/// of hard-reading the cut timeline's context.
///
/// The cut buttons are deliberately NOT here: the cut noun's verbs were
/// already panel-correct (the cut group keeps reading the session), and B8
/// names them as the exception.
///
/// ★One law, two speakers. The TIMELINE's answers are the session's
/// cut-local, active-layer verbs — every delegation byte-identical to what
/// the toolbar read before this interface existed. The STORYBOARD's answers
/// are its own standing row crossed with the track-global playhead
/// ([EditorSessionManager.storyboardStandingRow] ×
/// [EditorSessionManager.editingGlobalFrame]),
/// because that rail's standing row is separate state from the cut's
/// drawing target (유저 2026-07-27) — the reason every session getter the
/// toolbar used to read answered about the WRONG panel from over there.
/// ↩️A CELL band on the storyboard — its conte-block selection — is the
/// timeline's own band, and the storyboard answers it with the timeline's
/// verbs (F-186, [StoryboardToolbarPanelContext]'s `_cellBand`).
///
/// 🚨T25's law holds per member: a button's enablement and what its press
/// DOES must come from one answer, so every `can*` here has its verb beside
/// it and the storyboard's edit gate and edit dispatch share one resolver
/// ([StoryboardToolbarPanelContext.editTarget]).
abstract class ToolbarPanelContext {
  // --- LAYER pill -----------------------------------------------------------

  /// The bare `＋`: ONE kind, always, no looking first (⑥'s law) — the
  /// timeline makes an animation layer, the storyboard an S row.
  void addLayer();

  /// The `＋` band's per-kind gate and verb — the same pair, so a lit entry
  /// and a working press cannot come apart.
  bool canAddLayerOfKind(LayerKind kind);
  void addLayerOfKind(LayerKind kind);

  /// The attach entries (W5): riders on the CUT's active layer, which only
  /// the timeline panel can name.
  bool get canAddAttachedLayer;
  void addAttachedLayer(AttachedPlacement placement, {AttachedMode mode});

  /// Whether the session's ACTIVE-LAYER menu verbs (the layer menu, the
  /// frame menu's duplicates) are THIS panel's own subject.
  ///
  /// The storyboard answers false and those entries grey out honestly: its
  /// rows are tracks, S rows and the transition fixture, and none of them
  /// is the cut's active layer — a lit entry there would edit a row the
  /// panel is not even showing.
  bool get servesActiveLayerVerbs;

  /// The row whose FX LIST is THIS panel's subject — what the fx menu's adds
  /// and a paste of effects, which is an add of them, land on: the
  /// timeline's row, and on the storyboard the timeline's row a projection
  /// row stands on, as its attach entries are (F-322), or the V row stood
  /// on ([TrackChain]). Null where none is.
  ///
  /// 🗣️I-99 (유저 2026-10-14): 「콘티패널에서 콘티작업중 일부 레이어에만
  /// 트랜스폼 조정하거나 fx걸고싶은데 그게 불가능해서」. ↩️The list asked
  /// [servesActiveLayerVerbs] — one flag for two questions — and greyed out
  /// on the conte rows the storyboard shows.
  EffectChainHolder? get effectChainHolder;

  // --- FRAME pill -----------------------------------------------------------

  bool get canCreateInstance;

  /// The frame `＋`'s press — beside its gate (T25), because a KEY presses it
  /// too (I-19) and the key must do exactly what this panel's button does.
  void createInstance();

  bool get canBlankExposure;
  void blankExposure();

  /// The press of [mark]'s button — ○ mark 1 and ● mark 2 (I-130), one
  /// gate for the two.
  bool get canToggleMark;
  void toggleMark(InbetweenMark mark);

  /// The [mark] every n koma down a block, from its head (I-58) — the
  /// selection's blocks, else the block under this panel's cursor.
  bool get canMarkEvery;
  void markEvery(int every, InbetweenMark mark);

  /// The 1/2/3/4/N comma press: the selection's blocks, else THE BLOCK
  /// UNDER THIS PANEL'S CURSOR — on the storyboard that is the standing
  /// row's block at the global playhead, cut blocks included (컷블록 위
  /// 4 = 컷길이 4), one rule for every block kind. ↩️D28 handed a cut's
  /// PANEL the comma off the V row wherever the cut carried a storyboard
  /// layer; the panel takes it on the conte row now, and the V row's block
  /// is its cut again (I-73).
  ///
  /// What the press re-times — the ladder its gate, its dispatch and its
  /// window (I-24-open-entry) read alike ([StoryboardCursor]).
  CommaTarget? get commaTarget;
  bool get canSetComma;
  void setComma(int comma);

  /// D40: select the standing row's WHOLE authored span — first authored
  /// cell through last — as a range selection. On the storyboard the
  /// standing row may be the cut row, whose blocks are its cuts (컷블록도
  /// 동일 작동).
  bool get canSelectRowSpan;
  void selectRowSpan();

  /// The row the frame pill's shove (push/pull) aims at with nothing
  /// selected — null leaves the session's own rule (the active layer at the
  /// cut-local cell). One answer for the shove buttons and their keys.
  TimelineRowAddress? get shiftCurrentRow;

  // --- SHARED pill ----------------------------------------------------------

  bool get canEditInstance;

  bool get canCutRun;
  void cutRun();

  /// The pill's copy and its two pastes. ⚠️「Frame」 is the name they were
  /// given while the frame axis was all they served: since I-77 the copy
  /// takes the selected ROWS where rows are the panel's, and a paste puts
  /// down whichever the hand holds ([_ClipboardAtThePanelsPlace]).
  bool get canCopyFrame;
  void copyFrame();

  bool get canPasteIndependentFrame;
  void pasteIndependentFrame();

  bool get canPasteLinkedFrame;
  void pasteLinkedFrame();

  PillSubject get deleteSubject;
  void deleteSelectionSubject();

  /// 🚨I-45 — the link-independent button: whether this panel's press would
  /// unlink anything, and the press. One answer for both (T25's law).
  bool get canUnlink;
  void unlink();

  /// 🗣️F-455 — 복제: whether this panel's press would duplicate anything,
  /// and the press. One answer for both (T25's law).
  bool get canDuplicate;
  void duplicate();

  /// 🗣️I-78 — 병합: what this panel's press would merge — the rows, the
  /// band's blocks, or nothing ([EditorSessionManager.mergeSubjectFor]).
  /// The press asks before it bakes, so it is a window's
  /// (`mergeSelectionSubject`), handed this.
  PillSubject get mergeSubject;

  /// 🗣️I-18 — 자동 이름 지정: what this panel's press numbers, or null when
  /// there is nothing to number (the button dims). ONE answer for the gate,
  /// for the window's Apply — asked again when the number is given — and
  /// for the key (T25's law).
  AutoNameTargets? get autoNameTargets;
}

/// What each SHARED pill button does when it is pressed — null while it has
/// nothing to do.
///
/// ★ONE ANSWER FOR THE BUTTON AND ITS KEY (I-19). The pill lights from these
/// and fires them; Ctrl+X/C/V/B and Delete fire the same getters on the
/// context of the panel being worked in, so a key can never do what its
/// button would not. ↩️They fired the TIMELINE's context whichever panel you
/// were in (09-13, the one every bound film verb spoke to then — a session's
/// pick, not a ruling: the order was 「여러 단축키 기존 버튼에 연결」), and the
/// storyboard's pill answered differently from its own keys.
extension ToolbarSharedPresses on ToolbarPanelContext {
  void Function()? get cutPress => canCutRun ? cutRun : null;

  void Function()? get copyPress => canCopyFrame ? copyFrame : null;

  void Function()? get pasteIndependentPress =>
      canPasteIndependentFrame ? pasteIndependentFrame : null;

  void Function()? get pasteLinkedPress =>
      canPasteLinkedFrame ? pasteLinkedFrame : null;

  void Function()? get unlinkPress => canUnlink ? unlink : null;

  void Function()? get duplicatePress => canDuplicate ? duplicate : null;

  /// Whether 병합 has anything to merge here — the button's gate and the
  /// key's, read off the one ladder ([mergeSubject]).
  bool get canMerge => switch (mergeSubject) {
    PillSubject.layers || PillSubject.cells => true,
    PillSubject.cuts || PillSubject.nothing => false,
  };

  /// Whether 자동 이름 지정 has anything to number here — the button's gate
  /// and the key's, read off the one resolver ([autoNameTargets]).
  bool get canAutoName => autoNameTargets != null;

  /// F: the ROWS rung asks first. It inherited that from the loose layer
  /// button this pill folded in — a delete that used to confirm must not
  /// stop confirming because its button moved, or because a key pressed it.
  /// The cell rung goes straight through, as it always has.
  void Function()? deletePress({void Function()? onDeleteRowSelection}) =>
      switch (deleteSubject) {
        PillSubject.nothing => null,
        PillSubject.layers when onDeleteRowSelection != null =>
          onDeleteRowSelection,
        _ => deleteSelectionSubject,
      };
}

/// The boards the shared pill's copy takes into — one copy in hand,
/// whichever of them took it (`AppClipboard`).
enum _Board { text, rows, effects, keys, frames }

/// The clipboard's four buttons, said ONCE for both panels: a panel answers
/// only WHERE its press stands ([clipboardPlace]), and the board's verbs
/// take it from there ([ClipboardPlace]).
///
/// 🗣️F-281 (유저 2026-10-04): 「se행의 복사,붙여넣기, 타임라인패널에선 되는데
/// 콘티패널에선 se블록을 복사가 안됨. 로컬이든 글로벌이든 가능하도록 통일」.
/// ↩️The timeline pressed the session's cut-local verbs and the storyboard
/// had none of its own — 「no global-axis clipboard exists to dispatch
/// instead」 — so there the four sat dark over the very block the timeline
/// copied.
mixin _ClipboardAtThePanelsPlace implements ToolbarPanelContext {
  EditorSessionManager get session;

  /// Where a paste that brings media from another project puts up its wait
  /// window ([pasteWithItsMedia]) — the widget the press came through.
  /// Without one (a test's context) the paste lands at once, recording no
  /// carried medium it has not held.
  BuildContext? get waitIn;

  /// Where this panel's clipboard press stands — null where it stands on
  /// nothing the board serves.
  ClipboardPlace? get clipboardPlace;

  /// 🗣️I-77 (유저 2026-10-06): 「복사/붙여넣기버튼 레이어도 연결. 레이어
  /// 선택,다중선택등에서 복사 붙여넣기버튼 가능하게」 · 「타임라인의 공용
  /// 복사/독립붙여넣기/링크붙여넣기를 말한거였음」.
  ///
  /// Whether ROWS are this panel's to copy and paste — the timeline's, whose
  /// rows are the cut's layers. The storyboard's rows are tracks and their
  /// fixtures, which no board holds, so its copy stays the frame axis's.
  bool get rowsAreThisPanels;

  /// 🗣️I-123 (유저 2026-10-22): 「레이어도 타임라인 공용알약의 잘라내기 버튼
  /// 사용가능. 여러레이어 선택해서 사용한다던가 다른 규칙 참고해서 법 통일」.
  ///
  /// WHAT the cut takes is what the copy takes ([_boardTaken]): 복사 and
  /// 잘라내기 are ONE pair (「복사=원본 남기고 클립 저장 · 잘라내기=원본 지우고
  /// 클립 저장」, `FrameClipboard.canCopyAt`) — a text in hand, the selected
  /// rows or the effects their fx headers name, a lane's keys, the frame
  /// axis. Rows the copy takes claim the press even when none of them may
  /// be lifted
  /// ([LayerClipboard.canCutSelectedRows]) — the button dims rather than
  /// cut the frame under them. ↩️It asked the frame board alone: under a
  /// row selection it lifted the standing row's block while the copy beside
  /// it took the rows, with a text in hand it lifted the block of the cel
  /// the text stood on, and on a lane it sat dark over the keys the copy
  /// took (the-pill-cut-skips-text-and-keys).
  @override
  bool get canCutRun => switch (_boardTaken) {
    _Board.rows => session.layerClipboard.canCutSelectedRows,
    _Board.frames => session.clipboard.canCutAt(clipboardPlace),
    _Board.text || _Board.effects || _Board.keys => true,
    null => false,
  };

  @override
  void cutRun() {
    switch (_boardTaken) {
      case _Board.text:
        session.textClipboard.cut();
      case _Board.rows:
        session.layerClipboard.cutSelectedRows();
      case _Board.effects:
        session.effectClipboard.cut();
      case _Board.keys:
        session.keyClipboard.cut();
      case _Board.frames:
        session.clipboard.cutAt(clipboardPlace);
      case null:
        break;
    }
  }

  /// The rows-or-frames half of [_boardTaken], on the pill's one ladder
  /// ([pillSubjectOn]): the selected rows, else the frame axis —
  /// 「선택안하면 현재프레임, 선택하면 해당 선택한 소재가 기준임」 (I-45's
  /// answer, which every verb here follows). On the frame axis a LANE's
  /// keys come first, as Delete's do (F-87): standing on a lane, the frame
  /// board has no place ([FrameClipboard.timelinePlace]) and the key board
  /// answers (F-388).
  PillSubject get _copySubject => pillSubjectOn(
    cuts: false,
    layers: () => _copiesRows || session.effectClipboard.namesEffects,
    cells: () =>
        session.keyClipboard.canCopy ||
        session.clipboard.canCopyAt(clipboardPlace),
  );

  /// Whether the rows rung's copy takes the selected ROWS — ahead of the
  /// effects fx headers name on other rows beside them.
  ///
  /// ⚠️The hand holds ONE board's copy (`AppClipboard`), so a selection of
  /// rows and another row's fx header copies the rows: Delete takes both,
  /// but a paste of both would land in two places at once.
  /// 🗣️F-476-Q3 (유저 2026-10-27): 「지금대로 — 행이 먼저」.
  bool get _copiesRows =>
      rowsAreThisPanels && session.layerClipboard.canCopySelectedRows;

  /// THE BOARD the copy takes into here — and the cut lifts for — or null
  /// where they take nothing. One answer for both buttons and their keys.
  ///
  /// 🗣️I-101 (유저 2026-10-15): 「텍스트를 선택한 상태(변형박스로 변한
  /// 상태)에서 복사 가능」. A text held by its box is the THING IN HAND, and
  /// is taken ahead of every rung of the ladder — Delete's order (R9-rest:
  /// 「the thing in hand first」), which the pill's copy and its key share.
  _Board? get _boardTaken {
    if (session.textClipboard.canCopy) {
      return _Board.text;
    }
    return switch (_copySubject) {
      PillSubject.layers when _copiesRows => _Board.rows,
      PillSubject.layers => _Board.effects,
      PillSubject.cells when session.keyClipboard.canCopy => _Board.keys,
      PillSubject.cells => _Board.frames,
      PillSubject.cuts || PillSubject.nothing => null,
    };
  }

  @override
  bool get canCopyFrame => _boardTaken != null;

  @override
  void copyFrame() {
    switch (_boardTaken) {
      case _Board.text:
        session.textClipboard.copy();
      case _Board.rows:
        session.layerClipboard.copySelectedRows();
      case _Board.effects:
        session.effectClipboard.copy();
      case _Board.keys:
        session.keyClipboard.copy();
      case _Board.frames:
        session.clipboard.copyAt(clipboardPlace);
      case null:
        break;
    }
  }

  /// Whether a paste here puts down ROWS: the hand holds them, and rows are
  /// this panel's. ⛔Not asked of the selection — one copy is in hand
  /// (`AppClipboard`), so what a paste brings is already said; where it
  /// lands is the row you stand on.
  bool get _pastesRows =>
      rowsAreThisPanels && session.layerClipboard.hasLayerClipboard;

  /// Whether a paste here puts down KEYS: the hand holds them (F-388) — on
  /// the lanes the press stands on, the frame paste's way.
  bool get _pastesKeys => session.keyClipboard.holdsKeys;

  /// Whether a paste here puts down a TEXT: the hand holds one (I-101) — on
  /// the cels a held picture lands on, the pixel paste's way.
  ///
  /// ⚠️A TEXT IN HAND LIGHTS NO LINK: a text is one cel's (유저 2026-10-06:
  /// 「주인은 셀임」), so a link has nothing of it to keep — and with none,
  /// the independent paste alone is lit (F-115). 유저 2026-10-15 guessed the
  /// same: 「텍스트는 링크붙여넣기를 사용못할듯? 그래서 독립만?」 (I-101-Q2).
  /// It needs no rung of its own: the link falls to the frame board, which
  /// the text let go of when it was taken (one copy in hand).
  bool get _pastesText => session.textClipboard.holdsText;

  /// Whether a paste here puts down EFFECTS: the hand holds them (F-476-Q1)
  /// — an add of them, so onto the row the fx menu's add lands on
  /// ([effectChainHolder]). Like a text they light no link
  /// ([EffectClipboard.pasteOnto]).
  bool get _pastesEffects => session.effectClipboard.holdsEffects;

  bool get _canPasteEffects => switch (effectChainHolder) {
    final holder? => session.effectClipboard.canPasteOnto(holder),
    null => false,
  };

  @override
  bool get canPasteIndependentFrame => _pastesRows
      ? session.layerClipboard.canPasteRows
      : _pastesEffects
      ? _canPasteEffects
      : _pastesKeys
      ? session.keyClipboard.canPasteIndependent
      : _pastesText
      ? session.textClipboard.canPasteIndependent
      : session.clipboard.canPasteIndependentAt(clipboardPlace);

  /// The board an independent paste here puts down — the one whose media a
  /// paste from another project has to hold first ([pasteWithItsMedia]).
  BringsMedia get independentPasteBoard =>
      _pastesRows ? session.layerClipboard : session.clipboard;

  @override
  void pasteIndependentFrame() {
    if (_pastesEffects) {
      if (effectChainHolder case final holder?) {
        session.effectClipboard.pasteOnto(holder);
      }
      return;
    }
    if (_pastesKeys) {
      session.keyClipboard.pasteIndependent();
      return;
    }
    if (_pastesText) {
      session.textClipboard.pasteIndependent();
      return;
    }
    final board = independentPasteBoard;
    // The place is asked when the paste LANDS — after the wait, where one
    // is held.
    void paste() => identical(board, session.layerClipboard)
        ? session.layerClipboard.pasteRows()
        : session.clipboard.pasteIndependentAt(clipboardPlace);
    final context = waitIn;
    if (context == null) {
      paste();
      return;
    }
    unawaited(
      pasteWithItsMedia(
        context,
        title: editorActionLabel(EditorActionIds.editPasteIndependent),
        board: board,
        paste: paste,
      ),
    );
  }

  @override
  bool get canPasteLinkedFrame => _pastesRows
      ? session.layerClipboard.canPasteRowsLinked
      : _pastesKeys
      ? session.keyClipboard.canPasteLinked
      : session.clipboard.canPasteLinkedAt(clipboardPlace);

  /// On a row the copy was not taken from it links by NAME, and asks before
  /// it joins a name the row already holds ([pasteLinkedAskingFirst], I-71).
  /// With no window to ask in, such a paste stands down — the verb writes
  /// nothing until it is told to join.
  ///
  /// ROWS in hand are linked whole, each beside the row you stand on, and
  /// have nothing to ask. KEYS ask the same way, of a name the lane they
  /// land on already holds at another value (F-388).
  @override
  void pasteLinkedFrame() {
    if (_pastesRows) {
      session.layerClipboard.pasteRowsLinked();
      return;
    }
    final context = waitIn;
    if (context == null) {
      _pastesKeys
          ? session.keyClipboard.pasteLinked()
          : session.clipboard.pasteLinkedAt(clipboardPlace);
      return;
    }
    unawaited(
      _pastesKeys
          ? pasteLinkedKeysAskingFirst(context, session)
          : pasteLinkedAskingFirst(
              context,
              session,
              place: () => clipboardPlace,
            ),
    );
  }
}

/// 🚨Everything a gate on the bar moves with — what each group on it hears
/// ([TimelineActionToolbar]'s groups, the shift pair), on BOTH panels.
///
/// ★What a predicate READS and what its widget SUBSCRIBES to have to be the
/// same set (T17's law). Every gate reads the session, whose notify is the
/// first channel; the rest publish WITHOUT one, each on purpose.
///
/// ↩️(a-gate-rebuilds-the-whole-toolbar, 2026-10-24) This was three lists.
/// Each host cached the whole bar on a token of every gate it showed and
/// heard its own signals (the timeline's seek gate, R13-2; the storyboard's
/// cursor gate, B8), and the shared pill heard a third — so a gate flipping
/// in one group built every group again (🔬a drawing landing in an empty
/// cel, the 색 편집 head lighting: 227 widgets of the bar built again, 65 of
/// them outside the pill the head is on — 3 now). Each group hears this
/// list and is built again when ITS gates move; the hosts keep the bar
/// while it is built for the same thing.
Listenable toolbarGateNews(EditorSessionManager session) => Listenable.merge([
  // An edit: the arrangement (T17 — push opened a gap and pull stayed grey),
  // the layers, the cel under the playhead.
  session,
  // 🚨유저 #6 (2026-08-14): 「룰러로 이동할때 … 버튼 상태 바꼈으면 좋겠는데
  // 안바뀜. **효율좋게** 하는데 … 해당 인덱스에 **버튼이 있으면 한번, 없으면
  // 한번** 이런식으로?」 — a seek is no notify, and the playhead moves by a
  // committed seek, a scrub and a gap parking: one channel for all of them
  // (#10, 2026-08-21 — ↩️the committed seek alone fires on the RELEASE, so a
  // ruler drag held every answer at the frame it began on). The efficiency
  // half is the groups' own: a crossed frame costs their gates' reads and
  // builds nothing unless an ANSWER changed.
  session.playheadMoved,
  // A language switch fires no notify; every name cell and tooltip prints in
  // the program language.
  session.languageSettings,
  // The row you STAND on publishes on its own notifier (it moves per press):
  // Edit Instance, the shift pair's row and the storyboard's gates read it.
  // A claim moves it on pointer-down and never notifies ([Standing]).
  // ⛔MUTANT SURVIVES (2026-10-24): every route the suites take to a new
  // stand notifies as well; this is the one channel a claim moves it by.
  session.standing.currentRowListenable,
  // ⑨'s row selection and the three bands grow PER POINTER MOVE, which a
  // notify per move would turn into a rebuild of every panel. A band is a
  // subject claim whichever panel it was swept in (F-281: the band swept on
  // the STORYBOARD was the fifth signal, missing from the timeline's list).
  session.rowSelection,
  session.frameRangeSelection,
  session.laneRangeSelection,
  session.trackFrameRangeSelection,
  // 🚨WHETHER THE CEL HAS A DRAWING, which no selection moves: 픽셀 비우기
  // empties the cel you stand on (유저 2026-08-27: 「인덱스 이동해서 그림
  // 사라진거 확인하더라도 버튼 여전히 활성화되있고」), and a first stroke
  // lights the 색 편집 head at pen-down, as it turns the block white
  // (pen-up-dock-tail-Q2). The content's own crossing is what the
  // timeline's host was built again on (R27 #13), so its gates heard it.
  // ⛔MUTANT SURVIVES (2026-10-24) for the content's line: every crossing
  // that moves an answer bumps the tint's beside it ([LayerStack]). It
  // stays as the head reads the store: what a gate reads is what it hears.
  session.layerStack.celTintRevision,
  session.renderCaches.brushFrameStore.celContentRevision,
  // I-55: the pixel board — a copy fills it without moving anything above,
  // and the two pastes open behind it: a paste lands on a blank cel too,
  // so a board that holds a piece opens the 색 편집 head over one
  // ([PixelVerbs.canOpenColourEdit]) — with no notify and no seek.
  session.appClipboard.pixels,
  // The rows the rail draws — a section toggle, a fold, a twirl, the filter
  // — which no notify carries; the storyboard's gates ask its rows, and its
  // host was built again on them. ⛔MUTANT SURVIVES (2026-10-24): no suite
  // folds a row under a gate that reads it; it stays for the read.
  session.railView.drawn,
]);

/// The cut timeline's context: the session's own verbs, verbatim. Every
/// member is a one-line delegation on purpose — this panel's dispatch is
/// the baseline B8 pins, so the wrapper must add nothing to it.
class TimelineToolbarPanelContext
    with _ClipboardAtThePanelsPlace
    implements ToolbarPanelContext {
  const TimelineToolbarPanelContext(this.session, {this.waitIn});

  @override
  final EditorSessionManager session;

  @override
  final BuildContext? waitIn;

  /// The cut's active row at the cut's playhead.
  @override
  ClipboardPlace? get clipboardPlace => session.clipboard.timelinePlace;

  @override
  bool get rowsAreThisPanels => true;

  // ⑥ 유저 2026-08-12: 「레이어 +버튼, 선택된 레이어 기준이아니라 애니메이션
  // 레이어 생성.」 — moved here verbatim from the button.
  @override
  void addLayer() => session.layerStack.addLayerOfKind(LayerKind.animation);

  @override
  bool canAddLayerOfKind(LayerKind kind) => session.layerStack.canAddLayerOfKind(kind);

  @override
  void addLayerOfKind(LayerKind kind) => session.layerStack.addLayerOfKind(kind);

  @override
  bool get canAddAttachedLayer => session.folders.canAddAttachedLayerToActive;

  @override
  void addAttachedLayer(
    AttachedPlacement placement, {
    AttachedMode mode = AttachedMode.synced,
  }) => session.folders.addAttachedLayer(placement, mode: mode);

  @override
  bool get servesActiveLayerVerbs => true;

  @override
  EffectChainHolder? get effectChainHolder => const ActiveRowChain();

  @override
  bool get canCreateInstance => session.cellInstances.canCreateInstance;

  @override
  void createInstance() => createActiveInstance(session);

  @override
  bool get canBlankExposure => session.exposureVerbs.canBlankExposureAtCurrentFrame;

  @override
  void blankExposure() => session.exposureVerbs.blankExposureAtCurrentFrame();

  @override
  bool get canToggleMark => session.layerMarks.canToggleMarkAtCurrentFrame;

  @override
  void toggleMark(InbetweenMark mark) =>
      session.layerMarks.toggleMarkAtCurrentFrame(mark);

  @override
  bool get canMarkEvery => session.layerMarks.canMarkEvery;

  @override
  void markEvery(int every, InbetweenMark mark) =>
      session.layerMarks.markEvery(every, mark);

  @override
  CommaTarget? get commaTarget =>
      session.storyboardCursor.timelineCommaTarget();

  @override
  bool get canSetComma => commaTarget != null;

  @override
  void setComma(int comma) => session.edgeDrag.setCommaForTimelineCursor(comma);

  @override
  bool get canSelectRowSpan => session.rangeSelections.canSelectRowSpanForCurrentRow;

  @override
  void selectRowSpan() => session.rangeSelections.selectRowSpanForCurrentRow();

  @override
  TimelineRowAddress? get shiftCurrentRow => null;

  @override
  /// R5q1: CUTS are the storyboard's noun, so this panel's Edit does not
  /// reach for them — 「타임라인에서는 타임라인의 것을」.
  bool get canEditInstance =>
      session.cellInstances.editInstanceSubjectFor(cutsAreThisPanels: false) !=
      PillSubject.nothing;

  @override
  PillSubject get deleteSubject =>
      session.deleteSubjectFor(cutsAreThisPanels: false);

  @override
  void deleteSelectionSubject() =>
      session.deleteSelectionSubject(cutsAreThisPanels: false);

  @override
  bool get canUnlink => session.unlinkSubject != PillSubject.nothing;

  @override
  void unlink() => session.unlinkSelectionSubject();

  /// 🗣️F-455 (유저 2026-10-23): 「공용알약에 복제 버튼 만들고 레이어랑
  /// 컷버튼의 레이어복제/컷복제 삭제. 그리고 복제버튼, 물론 각 규칙
  /// 따르고」 — the layer pill's 레이어 복제 came here with its rule: the
  /// selected rows, else the row you stand on (유저 확정 2026-08-13:
  /// 「복제는 현재 액티브인 대상」). R5q1: cuts are the storyboard's noun, so
  /// this panel's press does not reach for them — as its delete does not.
  ///
  /// 🗣️F-476-Q1 (유저 2026-10-27): 「복제 버튼이 고른 fx 를 같은 레이어에
  /// 하나 더 만든다(바로 아래에)」 — the fx headers among the selected rows
  /// name what is selected too, after the rows as the copy takes them
  /// ([_copiesRows]).
  @override
  bool get canDuplicate =>
      session.effectClipboard.namesEffects ||
      session.layerVerbs.canDuplicateActiveLayer;

  @override
  void duplicate() => _duplicatesEffects
      ? session.effectClipboard.duplicate()
      : session.layerVerbs.duplicateActiveLayer();

  bool get _duplicatesEffects =>
      session.layerVerbs.duplicatableSelectedLayerIds().isEmpty &&
      session.effectClipboard.namesEffects;

  @override
  PillSubject get mergeSubject =>
      session.mergeSubjectFor(cutsAreThisPanels: false);

  @override
  AutoNameTargets? get autoNameTargets => session.blockNaming.timelineTargets;
}

/// What the storyboard's Edit Instance press opens — resolved ONCE
/// ([StoryboardToolbarPanelContext.editTarget]) so the button's enablement
/// and the host's dialog dispatch cannot drift apart (T25's lesson: two
/// predicates that disagree leave a lit button whose press does nothing).
sealed class StoryboardEditTarget {
  const StoryboardEditTarget();
}

/// The cut's instance: the selection's cuts, or the cut block under the
/// cursor — the same rename dialog the shared ladder's cuts rung opens.
class StoryboardEditCut extends StoryboardEditTarget {
  const StoryboardEditCut();
}

/// The selected ROWS — the shared ladder's rows rung, whose Edit is the
/// rename the timeline's opens (`renameableSelectedLayerIds`): an S row, a
/// conte row this rail selects.
///
/// 🗣️F-359 (유저 2026-10-14): 「콘티패널에서 s행선택하고 삭제/편집버튼
/// 활성화안됨. 타임라인패널은 되는데. 그러니 통일하고」. ↩️This ladder had
/// no rows rung: a selected S row fell through to the block under the
/// cursor.
class StoryboardEditRows extends StoryboardEditTarget {
  const StoryboardEditRows();
}

/// The SE block under the cursor on the standing S row, addressed on the
/// global axis (the #1113 door, [editSeEntryInstance]).
class StoryboardEditSeEntry extends StoryboardEditTarget {
  const StoryboardEditSeEntry({
    required this.layerId,
    required this.globalFrame,
  });

  final LayerId layerId;
  final int globalFrame;
}

/// The transition span under the cursor (or its creation on an empty
/// frame — that row's one-verb law, 유저 2026-08-11).
class StoryboardEditTransitionSpan extends StoryboardEditTarget {
  const StoryboardEditTransitionSpan();
}

/// A lane row's instance is its KEY — the same rename the timeline's lane
/// standing opens; lane state is session-shared, so this panel serves it
/// too.
class StoryboardEditLaneKey extends StoryboardEditTarget {
  const StoryboardEditLaneKey();
}

/// The timeline's own cells — a cell band (F-186), or the cell a projection
/// row is stood on (I-73: a conte row's panel, the camera row's key) — so
/// their Edit is the timeline's ([editSelectionInstance]).
///
/// ↩️`StoryboardEditCellBand` while the band was the only way this panel
/// held one: the conte blocks lay inside the cut block, and a press there
/// with no band stood on the cut. ↩️`StoryboardEditConteCells` while the
/// conte rows were the only projection rows.
class StoryboardEditTimelineCells extends StoryboardEditTarget {
  const StoryboardEditTimelineCells();
}

/// The storyboard's context: the standing row crossed with the track-global
/// playhead. Selections speak first, exactly as they do on the timeline's
/// ladders — and the selections this panel writes (the cut range, the S-row
/// range, the strip's cut-local range, lane spans) are the same session
/// objects, so those rungs delegate.
class StoryboardToolbarPanelContext
    with _ClipboardAtThePanelsPlace
    implements ToolbarPanelContext {
  const StoryboardToolbarPanelContext(this.session, {this.waitIn});

  @override
  final EditorSessionManager session;

  @override
  final BuildContext? waitIn;

  /// Its rows are tracks and their fixtures: no board holds one (I-77).
  @override
  bool get rowsAreThisPanels => false;

  /// The rail's ONE addable kind: an S row (track-owned SE). V tracks and
  /// the transition row are fixtures nothing can add ("disable" is the
  /// honest state B8 names), and the cut-scoped kinds belong to the
  /// timeline panel's stack, which this panel does not show.
  @override
  void addLayer() => session.layerStack.addLayerOfKind(LayerKind.se);

  @override
  bool canAddLayerOfKind(LayerKind kind) =>
      kind == LayerKind.se && session.layerStack.canAddLayerOfKind(kind);

  @override
  void addLayerOfKind(LayerKind kind) {
    if (!canAddLayerOfKind(kind)) {
      return;
    }
    session.layerStack.addLayerOfKind(kind);
  }

  /// 🗣️F-322 (유저 2026-10-09): 「지금 콘티패널에서 콘티행 섰을때 레이어
  /// 종류버튼으로 어태치레이어 추가안되니 가능하도록」.
  ///
  /// A projection row stood on holds the timeline's own row
  /// ([_projectedCell]), so its attach entries are the timeline's: a row of
  /// the conte group carries one — born on its seat in every cut of the
  /// track (`plannedAddLayerCommand`), and stood on here at that seat — and
  /// the camera refuses, as it does there. ↩️They were grey with the
  /// cut-scoped kinds (B8) while this rail showed no row of a cut.
  @override
  bool get canAddAttachedLayer => _projectedCell?.canAddAttachedLayer ?? false;

  @override
  void addAttachedLayer(
    AttachedPlacement placement, {
    AttachedMode mode = AttachedMode.synced,
  }) => _projectedCell?.addAttachedLayer(placement, mode: mode);

  @override
  bool get servesActiveLayerVerbs => false;

  /// The V row stood on holds its own chain ([TrackChain]). A projection row
  /// stood on holds the timeline's own row ([_projectedCell]), so its fx
  /// list is the timeline's there — the conte row's and each row riding it
  /// (I-99), every cut of the track wearing the chain's shape (I-73); the
  /// camera takes none, as there.
  @override
  EffectChainHolder? get effectChainHolder =>
      switch (session.storyboardStandingRow) {
        TrackRowAddress(:final trackId) => TrackChain(trackId),
        _ => _projectedCell?.effectChainHolder,
      };

  /// 🗣️F-186 (유저 2026-09-26): 「타임라인 버튼은 기본적으로 선택안한상태에선
  /// 컷블록을 대상으로 하고, 콘티블록 선택하면 지금 편집버튼같은거
  /// 활성화안되는데 활성화시키고 로직작동가능하도록」.
  ///
  /// A CELL band here is the conte row's conte-block selection — the SAME
  /// object, on the same cut-local axis, the timeline's rows sweep (the
  /// host's `stripSelect`) — and pressing the block stood the timeline on
  /// its conte row (F-187). So the frame verbs this panel has no answer of
  /// its own for — Edit, the clipboard, X, the mark, 링크 독립 — answer it
  /// with the timeline's ([TimelineToolbarPanelContext]). With no band the
  /// standing row answers, as it always has: on the V row, the cut block —
  /// and on a projection row, the cell it stands on ([_projectedCell]).
  TimelineToolbarPanelContext? get _cellBand =>
      session.cells.cellSelectionClaimsSubject
      ? TimelineToolbarPanelContext(session, waitIn: waitIn)
      : null;

  /// 🗣️I-73 (유저 2026-10-08): 「v행 아래에 콘티행 만들어서 거기서 … 콘티행에
  /// 서야 콘티행에 서도록」 · 「콘티행도 동일하게 하고싶으니까」 · 「카메라 행
  /// 범위는 키표시/이동/레인 등 모든거 콘티패널에서 가능」.
  ///
  /// A PROJECTION ROW stood on — a conte row, the camera row — is the same
  /// subject as a cell band, with no band on it: the row's cells are a cut's
  /// own layer's, and standing there seated the timeline on that layer
  /// ([Standing.layerAProjectionStandSeats]). So the frame verbs F-186 hands
  /// a band to the timeline for — Edit, the clipboard, X, the mark, 자동 이름
  /// 지정 — are the timeline's here too, at the playhead: the answers its own
  /// panel gives over the same cell.
  ///
  /// Only while that layer is the one in hand ([projectedLayerInHand]). A
  /// cut with no conte layer has no cell under a conte row, a gap has no
  /// cut, and a layer picked in the timeline since is that panel's subject,
  /// not this row's.
  TimelineToolbarPanelContext? get _projectedCell =>
      projectedLayerInHand(
            row: session.storyboardStandingRow,
            cut: session.activeCutOrNull,
            activeLayerId: session.activeLayerId,
          ) !=
          null
      ? TimelineToolbarPanelContext(session, waitIn: waitIn)
      : null;

  /// The timeline's context where this panel's subject is one of the
  /// timeline's own cells: a cell band, else a projection row stood on.
  TimelineToolbarPanelContext? get _timelinesCells =>
      _cellBand ?? _projectedCell;

  bool get _standingOnTransitionRow {
    final row = session.storyboardStandingRow;
    return row is LayerRowAddress &&
        session.isTrackTransitionLayerId(row.layerId);
  }

  /// Create on this panel: the selection rungs (track S-row gaps, lane
  /// keys, the strip's cut-local range — all this panel's own selections),
  /// then the standing row — the transition row's one-verb fusion, or a
  /// fresh SE entry on the standing S row's empty cursor frame.
  @override
  bool get canCreateInstance {
    if (session.cellInstances.canCreateInstanceForSelection) {
      return true;
    }
    if (_standingOnTransitionRow) {
      // F-105 (유저 2026-09-15, 「통일 — 편집 버튼은 빈 칸에서 꺼진다」): the ＋
      // creates; opening a covered span is the Edit button's.
      return session.transitions.canCreateTransitionSpanAtPlayhead;
    }
    // D28: on the conte row, the ＋ divides the panel under the cursor —
    // the same one-resolver pair the dispatch reads. ↩️It divided it off
    // the cut row while the panels were drawn there (I-73).
    if (session.storyboardCursor.canCreateStoryboardPanelAtCursor) {
      return true;
    }
    // Any other projection row stood on makes what the timeline's ＋ makes
    // on the same cell — the camera row a key, a row riding the conte a
    // drawing ([_projectedCell], I-73 ④).
    final projectedCell = _projectedCell;
    if (projectedCell != null) {
      return projectedCell.canCreateInstance;
    }
    return session.storyboardCursor.canCreateSeEntryAtStoryboardCursor;
  }

  /// ⑬/B8 CREATE on this panel: the selection rungs first (this panel's own
  /// selections — the S-row range, a lane span, the strip's cut-local
  /// range), then the standing row. On the transition row the two verbs are
  /// one: `editTransitionSpanInstance` creates on an empty frame and edits
  /// on a covered one (「그게아니라 인스턴스편집버튼으로 작동하도록」); on
  /// an S row the `＋` authors a fresh entry at the cursor.
  ///
  /// ↩️The two verbs are two again (F-105, 유저 2026-09-15 「통일 — 편집
  /// 버튼은 빈 칸에서 꺼진다」 · 「만약 내가 말했던거라면 철회야」): on the
  /// transition row the `＋` creates, as it does on every row.
  ///
  /// Moved here from the host so the frame-`＋` KEY presses what this
  /// panel's button presses (I-19) when the storyboard is the panel being
  /// worked in.
  @override
  void createInstance() {
    if (session.cellInstances.createInstancesForSelection()) {
      return;
    }
    if (_standingOnTransitionRow) {
      session.transitions.createTransitionSpanAtPlayhead();
      return;
    }
    // D28: on the conte row, the ＋ divides the panel under the cursor
    // (self-gated by the one cursor resolver).
    if (session.storyboardCursor.canCreateStoryboardPanelAtCursor) {
      session.storyboardCursor.createStoryboardPanelAtCursor();
      return;
    }
    // …any other projection row stood on, the timeline's ＋ on its cell —
    // behind the gate its button and its key read, as the timeline's is.
    final projectedCell = _projectedCell;
    if (projectedCell != null) {
      projectedCell.createInstance();
      return;
    }
    // Self-gated: only a standing S row with an EMPTY cursor frame authors.
    session.storyboardCursor.createSeEntryAtStoryboardCursor();
  }

  // An exposure X and a cell mark are cut-local, active-layer notions with
  // no row-addressed verb on this axis — greyed out honestly rather than
  // dispatched against the other panel's context. ↩️A cell band IS that
  // axis, so they answer it (F-186, [_cellBand]) — and so is a projection
  // row stood on (I-73, [_projectedCell]).
  @override
  bool get canBlankExposure => _timelinesCells?.canBlankExposure ?? false;

  @override
  void blankExposure() => _timelinesCells?.blankExposure();

  @override
  bool get canToggleMark => _timelinesCells?.canToggleMark ?? false;

  @override
  void toggleMark(InbetweenMark mark) => _timelinesCells?.toggleMark(mark);

  @override
  bool get canMarkEvery => _timelinesCells?.canMarkEvery ?? false;

  @override
  void markEvery(int every, InbetweenMark mark) =>
      _timelinesCells?.markEvery(every, mark);

  @override
  CommaTarget? get commaTarget =>
      session.storyboardCursor.storyboardCommaTarget();

  @override
  bool get canSetComma => commaTarget != null;

  @override
  void setComma(int comma) => session.edgeDrag.setCommaForStoryboardCursor(comma);

  /// D40's one resolver (T25): the standing row's whole span on the
  /// track's global axis — a null layerId means the CUT row, whose span is
  /// selected through the one cut-select entry point on the trackId the
  /// row itself names (never [EditorSessionManager.selectedTrackId] — the
  /// stale re-key the select path already removed).
  ({LayerId? layerId, TrackId? trackId, int anchorFrame, int headFrame})?
  get _rowSpanTarget {
    switch (session.storyboardStandingRow) {
      case TrackRowAddress(:final trackId):
        final span = session.rowSpans.trackCutSpan(trackId);
        if (span == null) {
          return null;
        }
        return (
          layerId: null,
          trackId: trackId,
          anchorFrame: span.startFrame,
          headFrame: span.endFrameExclusive - 1,
        );
      case LayerRowAddress(:final layerId):
        final span = session.rowSpans.trackRowAuthoredSpan(layerId);
        if (span == null) {
          return null;
        }
        return (
          layerId: layerId,
          trackId: null,
          anchorFrame: span.startFrame,
          headFrame: span.endFrameExclusive - 1,
        );
      case LaneRowAddress():
        // Lane keys are points with no block snap — no span to select.
        return null;
    }
  }

  /// A projection row's span is its cell's own row's, in the cut it stands
  /// in — the timeline's answer ([_projectedCell]): a sweep on this row
  /// stays inside its cut, and so does the whole of it.
  @override
  bool get canSelectRowSpan =>
      _projectedCell?.canSelectRowSpan ?? _rowSpanTarget != null;

  /// Which rail is asking: with nothing selected the frame pill's shove
  /// aims at the row THIS rail lights (a cut row shoves cuts, an S row
  /// shoves sounds, the conte row its panels), which is not the session's
  /// active-layer fallback.
  @override
  TimelineRowAddress? get shiftCurrentRow => session.selectedRow;

  @override
  void selectRowSpan() {
    final projectedCell = _projectedCell;
    if (projectedCell != null) {
      projectedCell.selectRowSpan();
      return;
    }
    final target = _rowSpanTarget;
    if (target == null) {
      return;
    }
    final layerId = target.layerId;
    if (layerId == null) {
      session.updateStoryboardCutSelectionByFrame(
        anchorGlobalFrame: target.anchorFrame,
        headGlobalFrame: target.headFrame,
        trackId: target.trackId,
      );
      return;
    }
    session.updateTrackRowRangeSelectionByFrame(
      layerId: layerId,
      anchorGlobalFrame: target.anchorFrame,
      headGlobalFrame: target.headFrame,
    );
  }

  /// THE one resolver behind the edit button: what the press would open.
  /// [canEditInstance] and the host's dispatch both read this.
  StoryboardEditTarget? get editTarget {
    // The selection speaks first — the shared ladder's own order — and its
    // cuts rung is a band that NAMES cuts, the question [deleteSubject]
    // asks. 🚨It asked whether ANY band was up, from when the V row's was
    // the only band this rail could sweep: a band over the S rows or the
    // transition row opened the ACTIVE cut's rename, a cut the band did not
    // even cover (storyboard-band-names-no-cut, 2026-09-26).
    if (session.storyboardRows.storyboardSelectedCutIds.isNotEmpty) {
      return const StoryboardEditCut();
    }
    // The rows rung, second as on the shared ladder (F-359).
    if (session.layerVerbs.renameableSelectedLayerIds().isNotEmpty) {
      return const StoryboardEditRows();
    }
    // …and a band that names rows this press would MISS claims it before
    // the standing row speaks.
    //
    // The axis here is not the session's: THIS panel's press lands on the
    // STANDING ROW (a track, an S row, a lane, the transition fixture),
    // and a cut-local band never names one of those — so any CELL band at
    // all names rows this press would miss. Without the guard it fell
    // through to the row rung below, where a TrackRowAddress cursor means
    // "rename the cut". Delete and Rename are documented as ONE ladder;
    // splitting them here left the same band dark on one button and aimed
    // at the cut on the other.
    //
    // A band of THIS rail is asked the timeline's question for the same
    // verb ([EditorSessionManager.bandNamesRowsThisPressWouldMiss]): one
    // that covers the standing row lets the press land there, at the
    // playhead; one that covers only other rows refuses it. There is no
    // band-wide rename to route to (board R8-c).
    //
    // ↩️A CELL band is the timeline's own band, so it is the timeline's Edit
    // that answers it — the same question asked of the same object, which
    // lands on the band's row at the playhead or refuses (F-186).
    final cellBand = _cellBand;
    if (cellBand != null) {
      return cellBand.canEditInstance
          ? const StoryboardEditTimelineCells()
          : null;
    }
    if (_bandMissesTheStandingRow) {
      return null;
    }
    return _standingRowEditTarget;
  }

  /// [editTarget]'s last rung: with no selection speaking, the block the
  /// standing row holds under the global playhead.
  StoryboardEditTarget? get _standingRowEditTarget {
    switch (session.storyboardStandingRow) {
      case LayerRowAddress(:final layerId)
          when session.isTrackTransitionLayerId(layerId):
        // F-105 (유저 2026-09-15, 「통일 — 편집 버튼은 빈 칸에서 꺼진다」): Edit
        // opens a span covering the playhead; creating is the ＋'s.
        return session.transitions.transitionSpanAt(session.editingGlobalFrame) !=
                null
            ? const StoryboardEditTransitionSpan()
            : null;
      case LayerRowAddress(:final layerId)
          when trackIdOfProjectionRow(layerId) != null:
        // A projection row's cell is the timeline's own, so its Edit is the
        // timeline's — the panel or the key under the playhead, or nothing
        // where the cut holds no layer there ([_projectedCell]).
        return (_projectedCell?.canEditInstance ?? false)
            ? const StoryboardEditTimelineCells()
            : null;
      case LayerRowAddress(:final layerId):
        final layer = session.trackSeGlobalLayerById(layerId);
        final frame = session.editingGlobalFrame;
        if (layer == null ||
            frame < 0 ||
            coveringDrawingBlockAt(layer.timeline, frame) == null) {
          return null;
        }
        return StoryboardEditSeEntry(layerId: layerId, globalFrame: frame);
      case LaneRowAddress():
        return session.laneVerbs.canNameLaneKeys
            ? const StoryboardEditLaneKey()
            : null;
      case TrackRowAddress():
        return session.editingSession.playheadInGap ||
                session.activeCutOrNull == null
            ? null
            : const StoryboardEditCut();
    }
  }

  @override
  bool get canEditInstance => editTarget != null;

  /// Where this panel's clipboard press stands: under a CELL band the
  /// timeline's own place — the band is the timeline's, on its axis (F-186,
  /// [_cellBand]) — and so on a projection row stood on, whose cell is the
  /// timeline's (I-73, [_projectedCell]); with neither, the S row this rail
  /// stands on at the track's playhead ([FrameClipboard.storyboardPlace],
  /// F-281).
  ///
  /// ↩️It read: 「The cell clipboard (cut / copy / the two pastes) addresses
  /// the active layer at the cut-local playhead — the timeline panel's noun;
  /// no global-axis clipboard exists to dispatch instead」, and with no cell
  /// band the four answered false outright.
  @override
  ClipboardPlace? get clipboardPlace => _timelinesCells != null
      ? session.clipboard.timelinePlace
      : session.clipboard.storyboardPlace;

  /// Delete's ladder, said of this panel: the cut selection (the session's
  /// own cuts rung), the selection-borne cell rungs (lane keys, selected
  /// blocks — this panel's lanes and strips write those), then THE BLOCK
  /// UNDER THE CURSOR, whatever its kind.
  ///
  /// 🚨The cuts rung is a band that NAMES cuts — one over the V row
  /// ([StoryboardRows.storyboardSelectedCutIds]). It used to ask whether
  /// any band was up at all, from when the V row's was the only band this
  /// rail could sweep; once the S rows and the transition row swept bands
  /// of their own, a band over them deleted the cut the session stood in —
  /// a cut the band did not even cover (transition-row-range-in-the-cut,
  /// 2026-09-26).
  @override
  PillSubject get deleteSubject {
    if (session.storyboardRows.storyboardSelectedCutIds.isNotEmpty) {
      return PillSubject.cuts;
    }
    // The rows rung, second as on the shared ladder (F-359) — its press
    // confirms first ([deletePress]).
    if (session.rowsHoldWhatDeleteTakes) {
      return PillSubject.layers;
    }
    if (session.cells.canDeleteCellForSelection) {
      return PillSubject.cells;
    }
    // A live band claims the press even when it holds nothing this panel
    // may delete — the same guard the strip's comma verb already states.
    // Without it a band the collector refuses fell through to the cursor
    // rung, where a TRACK-ROW cursor means "delete the cut".
    if (_bandClaimsThePress) {
      return PillSubject.nothing;
    }
    return session.storyboardCursor.canDeleteBlockAtStoryboardCursor
        ? PillSubject.cells
        : PillSubject.nothing;
  }

  @override
  void deleteSelectionSubject() {
    if (session.storyboardRows.storyboardSelectedCutIds.isNotEmpty ||
        session.rowsHoldWhatDeleteTakes) {
      session.deleteSelectionSubject();
      return;
    }
    if (session.cells.canDeleteCellForSelection) {
      session.cells.deleteCellAtCurrentFrame();
      return;
    }
    if (_bandClaimsThePress) {
      return;
    }
    session.storyboardCursor.deleteBlockAtStoryboardCursor();
  }

  /// A cell band, or one of this rail's own — or a LANE range.
  ///
  /// ↩️F-87: the lane range was not among them. A range over an S row's lane
  /// stands the rail on that ROW, so with no key under it the press fell to
  /// the cursor and deleted the row's sound — the lane's layer answering for
  /// the lane, the bug the timeline's ladder closed on 09-16
  /// ([CellVerbs.canDeleteCellAtCurrentFrame]).
  bool get _bandClaimsThePress =>
      session.cells.cellSelectionClaimsSubject ||
      session.trackFrameRangeSelection.value != null ||
      session.laneRangeSelection.value != null;

  /// A band of this rail that does not cover the row the press lands on.
  bool get _bandMissesTheStandingRow {
    final band = session.trackFrameRangeSelection.value;
    return band != null && !band.coversRow(session.storyboardStandingRow);
  }

  /// The cuts this panel's 링크 독립 means: its EDIT TARGET's cuts rung —
  /// the selected cut range, else the cut under the cursor on a track row.
  ///
  /// ★The storyboard's ladder is [editTarget], so the three verbs this
  /// panel resolves for itself cannot disagree about which cut is meant.
  /// 「컷이나」 (I-45) is this panel's only noun for it: a track row's blocks
  /// are cuts, and an S row holds no pictures to link (F-115).
  List<CutId> get _unlinkCutIds {
    if (editTarget is! StoryboardEditCut) {
      return const [];
    }
    final named = session.storyboardRows.storyboardSelectedCutIds;
    if (named.isNotEmpty) {
      return named;
    }
    final cut = session.activeCutOrNull;
    return cut == null ? const [] : [cut.id];
  }

  /// The cuts first, as on every ladder of this panel; with none meant, a
  /// cel of the timeline's own cells — a cell band's, or the panel the
  /// conte row is stood on — is unlinked as the timeline unlinks it
  /// ([_timelinesCells]). 🧪2026-10-08: F-186 named 링크 독립 among the
  /// band's verbs and this rung never asked it — two panels of one cel
  /// under a band lit the timeline's button and left this one dark.
  @override
  bool get canUnlink {
    final cuts = _unlinkCutIds;
    return cuts.isNotEmpty
        ? cuts.any(session.cutVerbs.cutIsLinked)
        : _timelinesCells?.canUnlink ?? false;
  }

  @override
  void unlink() {
    final cuts = _unlinkCutIds;
    if (cuts.isNotEmpty) {
      session.cutVerbs.unlinkCuts(cuts);
      return;
    }
    _timelinesCells?.unlink();
  }

  /// 🗣️F-455 — the cut pill's 컷 복제 came here, cuts being this panel's
  /// noun (R5q1): the selected cuts, else the cut you stand on (유저 확정
  /// 2026-08-13: 「복제는 현재 액티브인 대상」), as one block after them
  /// (F-455-Q1: 「선택한 컷 전부」 — `CutVerbs.duplicateActiveCut`). Under
  /// no band of cuts, the fx headers the rail selected name what is
  /// selected (F-476-Q1), as they do for its delete.
  @override
  bool get canDuplicate =>
      session.activeCutOrNull != null || session.effectClipboard.namesEffects;

  @override
  void duplicate() => _duplicatesEffects
      ? session.effectClipboard.duplicate()
      : session.cutVerbs.duplicateActiveCut();

  bool get _duplicatesEffects =>
      session.storyboardRows.storyboardSelectedCutIds.isEmpty &&
      session.effectClipboard.namesEffects;

  /// The timeline's ladder, under a band of cuts first: cuts are this
  /// panel's noun (R5q1), and no merge takes a cut.
  @override
  PillSubject get mergeSubject =>
      session.mergeSubjectFor(cutsAreThisPanels: true);

  /// 자동 이름 지정 on this panel (I-18: 「대상은 선택된 블록들(컷이나
  /// 프레임)이 있으면 선택한 대상만」). The selected cuts first; a CELL band —
  /// the strip's conte blocks — is the timeline's own, so the timeline
  /// answers it (F-186, [_cellBand]); a band of this rail over its other
  /// rows holds nothing to number and claims the press. With nothing
  /// selected, a V row's cuts from the one under the playhead to the
  /// track's last — and an S row, a lane or the transition row holds no
  /// drawings this press numbers (targets-Q1).
  @override
  AutoNameTargets? get autoNameTargets {
    final named = session.storyboardRows.storyboardSelectedCutIds;
    if (named.isNotEmpty) {
      return AutoNameCuts(named);
    }
    final cellBand = _cellBand;
    if (cellBand != null) {
      return cellBand.autoNameTargets;
    }
    if (_bandClaimsThePress) {
      return null;
    }
    return switch (session.storyboardStandingRow) {
      TrackRowAddress(:final trackId) =>
        session.blockNaming.cutsFromThePlayhead(trackId),
      // A projection row's cells are the timeline's own (I-73,
      // [_projectedCell]): numbered as that panel numbers them.
      LayerRowAddress(:final layerId)
          when trackIdOfProjectionRow(layerId) != null =>
        _projectedCell?.autoNameTargets,
      LayerRowAddress() || LaneRowAddress() => null,
    };
  }
}

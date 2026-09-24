import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../../services/editing/active_cut_helpers.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/standing_place.dart';
import '../../models/layer_folder.dart'
    show LayerFolderIndex, attachGroupBaseOf;
import '../../models/timeline_row_address.dart';
import '../../models/track_transform_lane_carrier.dart'
    show trackIdOfTransformLaneCarrier;
import '../../models/working_panel.dart';
import '../timeline/layer_timeline_display_adapter.dart'
    show horizontalLayerDisplayOrder;
import '../timeline/property_lane_model.dart'
    show LayerRowHiddenBy, layerRowHiddenBy;
import '../timeline/timeline_current_row.dart' show currentRowIsInsideGroup;
import '../timeline/timeline_section_policy.dart'
    show timelineSectionForLayerKind;
import 'playback_rig.dart';
import 'rail_view.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'visibility_solo.dart';
import 'row_selection.dart';
import 'track_se_display.dart';
import 'range_selections.dart';

/// WHERE THE USER STANDS — the cut, the row and the layer the next verb
/// is about: selecting a cut, standing on a row, selecting a layer, and
/// the row that a folded rail hands its standing to.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP
/// cut, Round 6, 2026-09-03). Measured before cutting: three fields of
/// its own (the verb row, the timeline row, the last layer per cut) and
/// ten methods that are the only writers of them; the cut-switch rebuild
/// reads them five times from the session. It names the roles it needs
/// in its constructor.
///
/// ⛔The STORYBOARD RAIL's row is the fourth field, and it lives here for
/// the same reason as the other three: it is a panel's remembered row.
/// Parked on `StoryboardRows` it made that object and this one need each
/// other to be BUILT, which is a construction cycle, not a design (G0-2,
/// 2026-09-06).
class Standing {
  Standing({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required PlaybackRig playbackRig,
    required RowSelection rowSelectionVerbs,
    required VisibilitySolo solo,
    required TrackSeDisplay trackSe,
    required RangeSelections rangeSelections,
    required RailView railView,
    required bool Function(LayerId layerId) fxEnabledOf,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _controllers = controllers,
       _internals = internals,
       _playbackRig = playbackRig,
       _rowSelectionVerbs = rowSelectionVerbs,
       _solo = solo,
       _trackSe = trackSe,
       _rangeSelections = rangeSelections,
       _railView = railView,
       _fxEnabledOf = fxEnabledOf;

  final RangeSelections _rangeSelections;

  /// What the rail leaves off the screen, and the fx answer its filter asks —
  /// the standing law's two inputs besides the stack ([keepStandingShown]).
  final RailView _railView;
  final bool Function(LayerId layerId) _fxEnabledOf;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;
  final PlaybackRig _playbackRig;
  final RowSelection _rowSelectionVerbs;
  final VisibilitySolo _solo;
  final TrackSeDisplay _trackSe;

  /// 🚨F-20 (유저 2026-08-24): 「새 레이어를 만들어도 내부 액티브 레이어가 안
  /// 바뀐다 — 그 상태에서 아래 화살표를 누르면 바로 밑이 아니라 밑의 밑이
  /// 선택된다. 🚨UI만 바꾸고 내부를 안 바꾸는 자리가 더 있는지 전수 점검」.
  ///
  /// [selectLayer] keeps the timeline's row in step with the active layer,
  /// and it is not the only way the active layer moves: Add Layer seats one
  /// straight on the controller, and a controller REBUILD seats one through
  /// `initialActiveLayerId`. After either, the row was still the old layer's
  /// — so ↓ counted from there and landed a row further than it looked, and
  /// the flip counted the old row's blocks.
  ///
  /// ⛔It CANNOT be enforced at the read (the shape tried first). A row whose
  /// layer is not the active layer is legitimate: the storyboard's rails stand
  /// on a row WITHOUT taking the cut's drawing target (유저 2026-07-27), so an
  /// S row and the active cel layer disagree on purpose there — and
  /// overriding the read put the ring on the wrong row. The two writers say
  /// it instead, each where it moved the layer.
  ///
  /// The row you just made is the subject OF THE PANEL YOU MADE IT IN: made
  /// while working in the storyboard (whose layer pill makes S rows), it is
  /// that rail's row as well — the rail shows it, so that is where you stand.
  void seatVerbRowOnActiveLayer() {
    final seated = _controllers.layerController.activeLayerId;
    if (seated == null) {
      return;
    }
    final row = LayerRowAddress(seated);
    final railStands =
        _working.value == WorkingPanel.storyboard &&
        _trackSe.isTrackOwnedRailLayerId(seated);
    if (_timelineRow == row && (!railStands || _storyboardRow == row)) {
      return;
    }
    _timelineRow = row;
    if (railStands) {
      _storyboardRow = row;
    }
    publishCurrentRow();
  }

  /// F-20, the DELETE half: a row whose layer no longer exists is not a
  /// deliberate stand anywhere — it is a dangling id. A row that still
  /// resolves is left alone.
  ///
  /// Only the TIMELINE's row is judged here, and dropping it is enough: an
  /// empty timeline row reads as the active layer's ([timelineStandingRow]).
  /// The rail's row is judged where it is read ([selectedRow] and
  /// [storyboardStandingRow] fall back to the track row when the rail no
  /// longer shows what was stored) — ↩️judging it here too un-seated a V
  /// track's lane, whose carrier is no cut layer, onto the timeline on every
  /// rebuild.
  void unseatStrandedVerbRow() {
    final strandedOwner = _timelineRow?.owningLayerId;
    if (strandedOwner != null &&
        _project.rangeLayerById(strandedOwner) == null) {
      _timelineRow = null;
      publishCurrentRow();
    }
  }

  /// WHICH PANEL the frame-axis verbs, the arrows and the bound keys answer
  /// to: the one last touched (유저 2026-08-05 「마지막으로 무언가 액션이 있었던
  /// 패널을 기준으로」; 2026-09-24 「마지막으로 만진 패널 … 위아래 이동이
  /// 타임라인 내부로 샌다거나 그런거 싹 다 해결」).
  ///
  /// ↩️There used to be a THIRD row here — the verb's own, beside the two
  /// panels' rows — and every writer copied one of the two into it. A copy is
  /// a second answer, and it drifted: one lane arm served both panels, so a
  /// timeline lane stand wrote the storyboard's row; a V track's lane was
  /// un-seated onto the timeline on every rebuild; and a program re-seat of
  /// the drawing target (a hidden row's stand-in) took the flip off the
  /// storyboard in the middle of a walk. The verb's row is READ off the panel
  /// being worked in now ([currentRow]), so it cannot name a row that panel
  /// is not standing on.
  final ValueNotifier<WorkingPanel> _working = ValueNotifier(
    WorkingPanel.timeline,
  );

  WorkingPanel get workingPanel => _working.value;

  /// Rides beside [_internals.currentRowListenable]: a claim moves the panel
  /// without a session notify, and the flip's axis has to hear it — the
  /// X-sheet runs its frames down the page, the storyboard never does.
  ValueListenable<WorkingPanel> get workingPanelListenable => _working;

  void dispose() => _working.dispose();

  /// The TIMELINE's own row, the way [_storyboardRow] is the rail's: the
  /// layer or property lane last engaged there. Kept so that returning to
  /// the timeline restores the row you were on rather than resetting to
  /// whatever the active layer happens to be. Null = the active layer's row.
  TimelineRowAddress? _timelineRow;

  /// The storyboard rail's own selected row, as picked. Null = never
  /// picked, which reads as the selected track's V row.
  TimelineRowAddress? _storyboardRow;

  /// THE selected row of the STORYBOARD's rail — exactly ONE, whichever row
  /// was picked, the way the timeline has exactly one selected layer row.
  ///
  /// State of its OWN, not a projection of [SelectionAccess.activeLayerId].
  /// The two row
  /// selections are separate things (user decision 2026-07-27): a CUT's
  /// selected row is the active layer — the drawing target, remembered per
  /// cut — while this one says which row of THIS RAIL the user is on.
  /// Deriving it is what forced the previous "only a track-SE layer names a
  /// row here" rule, which made the rail's two row kinds unequal for no
  /// reason the rail itself has.
  ///
  /// Picking a row here therefore never moves the drawing target — not for
  /// a V row (a track has no layer to select) and not for an S row.
  ///
  /// A stored row that the rail no longer shows (its track's SE slot went
  /// away) falls back to the track row rather than lighting nothing.
  TimelineRowAddress get selectedRow {
    final row = _storyboardRow;
    if (row is LayerRowAddress &&
        _trackSe.isTrackOwnedRailLayerId(row.layerId)) {
      return row;
    }
    return TrackRowAddress(_selection.selectedTrackId);
  }

  /// The row the STORYBOARD's verbs act on: [selectedRow], or a lane of a
  /// row this rail shows.
  ///
  /// 🚨★★★IT READS THE STORE. ⛔Its claim used to read [selectedRow], and
  /// that getter answers a DIFFERENT question: 「which RAIL row is lit」. A
  /// lane is a subject (R10 #19) but never a rail row, so the getter
  /// collapses it to the track — and the claim, which fires on the host's
  /// OUTERMOST pointer-down, therefore ran last on every press and un-stood
  /// you from the lane the press had just stood on. One getter answering two
  /// questions, which is the shape CLAUDE.md names: 「한 플래그가 두 질문에
  /// 답하는 것도 발명이다」.
  ///
  /// 🚨It looked fine for a year because of an accident of timing: a finger
  /// stood on the RELEASE, after the claim, so the lane survived. A mouse
  /// never did — pressing a storyboard lane band with a mouse had been
  /// leaving the ring on the track row all along, and only lifting the
  /// finger's carve-out (터치 묘화 ON) made a test say so.
  ///
  /// ↩️The storyboard's VERBS kept making the same substitution after the
  /// claim stopped: its cursor block, its ＋ and its Edit asked [selectedRow],
  /// so their lane arms — 「A lane row holds keys, not blocks」, 「Standing on
  /// one of the row's LANES answers with the row」 — could never run, and a
  /// comma pressed while standing on an S row's lane re-timed the CUT.
  ///
  /// ⛔Only a lane THIS RAIL SHOWS ([_trackSe.trackOwnedRailOwner], the
  /// question already asked of a lane's carrier elsewhere).
  TimelineRowAddress get storyboardStandingRow {
    final stored = _storyboardRow;
    return stored is LaneRowAddress &&
            _trackSe.trackOwnedRailOwner(stored.layerId) != null
        ? stored
        : selectedRow;
  }

  /// The row the TIMELINE's verbs act on: the row it last stood on, else the
  /// active layer's — with nothing picked yet the row you are on is the one
  /// you draw on. Only a cut with no layers at all falls through to the
  /// track row.
  TimelineRowAddress get timelineStandingRow {
    final stored = _timelineRow;
    if (stored != null) {
      return stored;
    }
    final layerId = _selection.activeLayerId;
    return layerId == null
        ? TrackRowAddress(_selection.selectedTrackId)
        : LayerRowAddress(layerId);
  }

  /// Stores the rail's row. Returns whether the ANSWER moved — the store
  /// and the answer differ, since a row the rail no longer shows resolves
  /// back to the track row.
  bool storeStoryboardRow(TimelineRowAddress row) {
    final before = selectedRow;
    _storyboardRow = row;
    // Picking a rail row is also engaging it, so the verb follows (R10
    // #13): the storyboard is the panel being worked in.
    _engage(WorkingPanel.storyboard);
    return selectedRow != before;
  }

  /// The panel being worked in owns the frame-axis verbs (user, 2026-08-05:
  /// "마지막으로 무언가 액션이 있었던 패널을 기준으로"). Picking a row is
  /// no longer the only way to move the flip's subject — touching the
  /// panel at all is, because that is what "I am working here" looks like.
  ///
  /// Each panel stands on the row IT remembers rather than a fresh one, so
  /// coming back to the timeline lands on the lane you left open instead
  /// of dropping to the layer row.
  ///
  /// A claim never NOTIFIES the session. It fires on pointer-DOWN, and a
  /// ruler drag's whole contract is that it stays silent per move and
  /// commits once on release. What the rails DRAW rides
  /// [_internals.currentRowListenable] instead, so the row that moved repaints its
  /// own small cells and nothing else.
  void claimTimelineRow() => _engage(WorkingPanel.timeline);

  /// The storyboard's half of the same law: touching it hands the flip, the
  /// arrows and the bound keys its rail's row.
  void claimStoryboardRow() => _engage(WorkingPanel.storyboard);

  void _engage(WorkingPanel panel) {
    _working.value = panel;
    publishCurrentRow();
  }

  /// The surfaces showing each panel on the screen right now
  /// ([panelInSight]). A panel is on the screen while any of them is — and
  /// there are two while it moves between docks, because the new one mounts
  /// before the old one is gone. A panel that never said is not on it.
  final Map<WorkingPanel, Set<Object>> _surfacesInSight = {
    for (final panel in WorkingPanel.values) panel: <Object>{},
  };

  /// 🗣️유저 2026-09-25 (the-touched-panel-out-of-sight-Q1): 「화면에 남은
  /// 쪽이 받는다」. The panel being worked in leaving the screen — its tab put
  /// behind another, its rail group shut, the panel closed — hands the work
  /// to the other panel while THAT one is on the screen. With both off it,
  /// nothing moves. Coming back is no touch: its tab, or a press inside it,
  /// claims it again.
  ///
  /// ↩️The 09-24 doors all brought a panel forward; putting it away touched
  /// nothing, so the arrows, the flip and the keys went on walking a panel
  /// nobody could see.
  void panelInSight(
    WorkingPanel panel, {
    required Object surface,
    required bool inSight,
  }) {
    final surfaces = _surfacesInSight[panel]!;
    if (inSight) {
      surfaces.add(surface);
      return;
    }
    surfaces.remove(surface);
    if (surfaces.isNotEmpty || _working.value != panel) {
      return;
    }
    final other = switch (panel) {
      WorkingPanel.timeline => WorkingPanel.storyboard,
      WorkingPanel.storyboard => WorkingPanel.timeline,
    };
    if (_surfacesInSight[other]!.isNotEmpty) {
      _engage(other);
    }
  }

  /// The row a frame-axis VERB acts on (R10 #13): the standing row of the
  /// panel being worked in.
  ///
  /// NOT the same thing as [selectedRow], and deliberately so. The user's
  /// correction when #13 was settled: a V row and a layer row are not
  /// siblings competing for one slot, they are a HIERARCHY — a V row is a
  /// cut, a layer row is a layer INSIDE a cut. So [selectedRow] keeps
  /// saying which row of the FILM is lit (and picking a layer still leaves
  /// it alone, the 2026-07-27 rule), while this says whose blocks the flip
  /// counts. Folding the two into one slot is what made picking a layer
  /// drop the rail's S-row highlight, which is not what either question
  /// was asking.
  TimelineRowAddress get currentRow => switch (_working.value) {
    WorkingPanel.timeline => timelineStandingRow,
    WorkingPanel.storyboard => storyboardStandingRow,
  };

  /// 🚨T4 — STANDING ON A ROW, as one verb.
  ///
  /// 유저 2026-08-13: 「선택된게 풀리는거, **어떤 행이든 액티브 바꾸면
  /// 풀리도록.** 지금 레이어 액티브 바꾸면 풀리는데 **트랜스폼 멤버 행
  /// 액티브로하면 안풀림**」.
  ///
  /// ★The law was right and its ADDRESS was wrong. 「클릭하면 선택이
  /// 사라진다」 was hung on the timeline host's `onSelectLayer` callback — a
  /// wrapper — so it covered the doors that happened to go through that
  /// wrapper and missed the ones that call the session directly. Standing on
  /// a property lane was one of those, and it will not be the last: a wrapper
  /// is a place, and every new door has to be told about it.
  ///
  /// A verb cannot be walked around. Every surface that means 「여기 서라」
  /// says it here, and what standing DOES is decided once.
  ///
  /// [row] is the address stood on; [frameIndex] seeks as well, for the
  /// surfaces where standing and seeking are one gesture (a lane band's
  /// cells). A label press leaves it null — a label names a ROW, and the
  /// frame stays where it was.
  /// [globalFrameIndex] is the same seek stated on the TRACK's global axis
  /// — the storyboard's rows press in global frames (C6 2026-08-17: their
  /// lane bands stand through THIS verb now instead of a hand-rolled
  /// clear-and-seek that restated the law without the T10 guard). At most
  /// one of the two frames is passed.
  /// [panel] is the panel the row is stood on IN. On the STORYBOARD's rails
  /// the row you stand on and the layer you draw on are separate states (유저
  /// 2026-07-27). It is a parameter rather than a second verb because the
  /// clearing law is the same on both panels — only whose row it is differs,
  /// and stating that difference once here beats restating the law at each
  /// call site, which is the mistake T4 was.
  /// ↩️It was a flag, `takesLayerActive`, and a flag could say only half of
  /// it: a LANE stood on in either panel went through one shared lane arm,
  /// which wrote both panels' rows at once. The panel says the whole of it.
  void standOnRow(
    TimelineRowAddress row, {
    WorkingPanel panel = WorkingPanel.timeline,
    int? frameIndex,
    int? globalFrameIndex,
  }) {
    // 🚨T10. T4's law is untouched by this: the clearing still lives INSIDE
    // the verb rather than at its call sites — scattering it was T4's whole
    // bug. What changed is that the verb now asks a question first.
    //
    // A press that lands inside the current selection stands WITHOUT
    // clearing, because that press is most likely the start of a move.
    // Measured, not assumed: with this unconditional, turning the press-pick
    // on made an SE row move stop committing — the pick wiped the very rows
    // the move was about to carry.
    //
    // ⚠️A caller that names no frame is standing on the row AT THE
    // PLAYHEAD, so that is the cell the question is about. Falling back to
    // it rather than to "no cell" is what lets the guard see a cell range
    // at all: the surfaces reach this verb through a `ValueChanged<LayerId>`
    // that carries no frame, and a null there would make the guard blind to
    // exactly the selection it exists to protect.
    if (globalFrameIndex != null
        ? !_rangeSelections.standingInsideSelection(row, globalFrameIndex, true)
        : !_rangeSelections.standingInsideSelection(
            row,
            frameIndex ?? _selection.currentFrameIndex,
          )) {
      // ⚠️The TIMELINE's four, not the marquee (F-86, 유저 「뭘 하든
      // 안사라지도록」): standing is a press about to work on THIS row, not a
      // 선택 해제 — and the artwork's selection is a tool still in hand.
      _selection.clearTimelineSelections();
    }
    switch (row) {
      case LayerRowAddress(:final layerId) when panel == WorkingPanel.timeline:
        selectLayer(layerId);
      case LaneRowAddress() when panel == WorkingPanel.timeline:
        _standOnTimelineLane(row);
      case LayerRowAddress() || LaneRowAddress():
        // The storyboard's rails: the rail's row, never the drawing target.
        selectRow(row);
      case TrackRowAddress():
        // A track row has no layer to make active, and it is the storyboard's
        // row whichever surface names it.
        selectRow(row);
    }
    if (frameIndex != null) {
      _selection.selectFrameIndex(frameIndex);
    }
    if (globalFrameIndex != null) {
      _selection.selectGlobalFrame(globalFrameIndex);
    }
  }

  /// Re-publishes [currentRow]. Idempotent and cheap: call it after
  /// anything that could move the answer rather than reasoning about which
  /// writer was the one that did.
  ///
  /// Stands down while the answer would need a TRACK it cannot have (no
  /// row engaged, no active layer, and a project that may hold no tracks
  /// yet) — there is nothing to light in that state, and asking would
  /// throw.
  void publishCurrentRow() {
    if (_internals.disposed || !_currentRowAnswers) {
      return;
    }
    _internals.currentRowListenable.value = currentRow;
  }

  /// Whether [currentRow] can answer without a TRACK the film may not have
  /// yet — the timeline with no row engaged and no active layer, or the
  /// storyboard of an empty film.
  bool get _currentRowAnswers => switch (_working.value) {
    WorkingPanel.timeline =>
      _timelineRow != null || _selection.activeLayerId != null,
    WorkingPanel.storyboard =>
      _project.repository.requireProject().tracks.isNotEmpty,
  };

  /// THE FOLD LAW (R5 #11): what disappears never keeps the selection.
  /// Folding something you are standing INSIDE hands the standing row to
  /// whatever swallowed it.
  ///
  /// Two folds already obeyed this, each in its own place and its own
  /// words — a folder taking the selection off a member
  /// ([FoldersAndAttachments.toggleLayerCollapsed], R27 #24) and an attach base taking it off an
  /// attach row (the workspace's group fold, UI-R24 #4). The fx twirl and
  /// the lane-GROUP twirl did not, so closing a Transform group left you
  /// standing on a row that was no longer on screen, and the canvas went on
  /// refusing strokes for a lane nobody could see. Four folds, one rule,
  /// one place.
  ///
  /// [laneId] null means the whole twirl-down is closing (every lane of the
  /// layer goes), so the LAYER's own row is what swallows it — or, for a V
  /// track's lanes, whose carrier is no layer, the TRACK's row. A non-null
  /// [laneId] is a GROUP header closing, and it swallows its members alone
  /// — the header itself stays on screen and is where you land.
  ///
  /// [panel] is the panel whose rail folded: each panel keeps its own
  /// twirls, so a fold hands on where THAT panel stands.
  void handOffCurrentRowOnFold(
    LayerId layerId, {
    String? laneId,
    WorkingPanel panel = WorkingPanel.timeline,
  }) {
    if (laneId == null) {
      final track = trackIdOfTransformLaneCarrier(layerId);
      handOffOnFold(
        swallower: track == null
            ? LayerRowAddress(layerId)
            : TrackRowAddress(track),
        vanished: (address) =>
            address is LaneRowAddress && address.layerId == layerId,
        panel: panel,
      );
      return;
    }
    handOffOnFold(
      swallower: LaneRowAddress(layerId, laneId),
      vanished: (address) => currentRowIsInsideGroup(address, layerId, laneId),
      panel: panel,
    );
  }

  /// An ATTACH GROUP folding shut: every row the group holds — the rows
  /// [attachGroupBaseOf] names its base for — leaves, and the BASE swallows
  /// them (UI-R24 #4).
  ///
  /// 🚨F-81 (유저 2026-09-11): 「어태치폴더에 서있는 채로 기준레이어의 접기버튼
  /// 누르면 폴더에 서있는채임. 어태치레이어에 서있을때 접으면 제대로 기준 레이어에
  /// 서있도록 바뀌는데. 이런 규칙 다른거 법 하나로 싹 통일」. The rail asked only
  /// whether the ACTIVE row was an attach row of the base, so the organizer
  /// folder — and a nested one — stayed standing after the fold took them off
  /// the screen.
  void handOffCurrentRowOnAttachFold(LayerId baseId) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return;
    }
    bool inGroup(LayerId layerId) {
      final layer = cut.layers.byId(layerId);
      return layer != null && attachGroupBaseOf(layer, cut.layers) == baseId;
    }

    handOffOnFold(
      swallower: LayerRowAddress(baseId),
      vanished: (address) => switch (address) {
        LayerRowAddress(:final layerId) => inGroup(layerId),
        LaneRowAddress(:final layerId) => inGroup(layerId),
        _ => false,
      },
    );
  }

  /// THE FOLD LAW's one body: the row selection gives what [vanished] names up
  /// to [swallower] ([RowSelection.foldRowSelection]), and when the fold took
  /// the row you stand on — or the active layer — that goes to [swallower]
  /// too.
  ///
  /// ↩️「Four folds, one rule, one place」 above was the aim more than the
  /// code: the folder fold and the attach group fold kept bodies of their own
  /// until F-81, and the attach one asked a narrower question than the fold it
  /// answered for.
  ///
  /// [panel] is the panel whose rail folded, and what the fold hands on is
  /// where THAT panel stands — not which panel you are working in. ↩️Only
  /// the timeline's twirls reached this law, so folding a storyboard row's
  /// lanes left the storyboard standing on a lane nobody could see: the
  /// window drew the row while the flip walked the lane a frame at a time,
  /// and Delete aimed at its keys.
  void handOffOnFold({
    required TimelineRowAddress swallower,
    required bool Function(TimelineRowAddress address) vanished,
    WorkingPanel panel = WorkingPanel.timeline,
  }) {
    _rowSelectionVerbs.foldRowSelection(
      vanished: vanished,
      swallower: swallower,
    );
    if (panel == WorkingPanel.storyboard) {
      // The rail's own row; the drawing target is not its business
      // (유저 2026-07-27).
      if (vanished(storyboardStandingRow)) {
        _storyboardRow = swallower;
        publishCurrentRow();
      }
      return;
    }
    final activeLayerId = _selection.activeLayerId;
    final standsInside =
        vanished(timelineStandingRow) ||
        activeLayerId != null && vanished(LayerRowAddress(activeLayerId));
    if (!standsInside) {
      return;
    }
    switch (swallower) {
      case LayerRowAddress(:final layerId):
        _seatLayer(layerId);
      case LaneRowAddress():
        _selection.clearFrameRangeSelection();
        _timelineRow = swallower;
        publishCurrentRow();
      case TrackRowAddress():
        break;
    }
  }

  /// Selects a row of the storyboard's rail by ADDRESS — the rail taps and
  /// the cells press come through here. A track row additionally promotes
  /// that track's cut under the playhead (UI-R18 #6); a layer row has no
  /// landing verb of its own, because the drawing target is not this
  /// selection's business.
  void selectRow(TimelineRowAddress row) {
    switch (row) {
      case LayerRowAddress(:final layerId):
        if (_internals.editingInteractionBusy) {
          return;
        }
        // The row lives on a track, so picking it picks that track too —
        // the rail's row selection and the track selection must not
        // disagree (the range drag that follows a press resolves its rows
        // against the SELECTED track's rail).
        final owner = _trackSe.trackOwnedRailOwner(layerId);
        var trackMoved = false;
        if (owner != null && _selection.selectedTrackId != owner.id) {
          _timeline.editingSession.setSelectedTrackId(owner.id);
          trackMoved = true;
        }
        if (storeStoryboardRow(row) || trackMoved) {
          _changes.notifyChanged();
        }
      case LaneRowAddress():
        // R10 #19: a property row is a row you can be ON. The rail's own
        // highlight resolves it to the containing V row, like any other
        // in-cut row; what moves is the verb's subject.
        //
        // ↩️This arm served the TIMELINE's lanes as well, and wrote the
        // timeline's row here beside the rail's — so a lane stood on in one
        // panel became the row the OTHER panel came back to. The timeline's
        // lanes stand through [_standOnTimelineLane] now; this is the rail's.
        //
        // R5 #12: the CELL range goes (see [_standOnTimelineLane]).
        _selection.clearFrameRangeSelection();
        if (storeStoryboardRow(row)) {
          _changes.notifyChanged();
        }
      case TrackRowAddress(:final trackId):
        _internals.selectTrackCutAtPlayhead(trackId);
    }
    // Every arm can move the drawn row, and the track arm does it through
    // a path of its own — publishing once here beats three call sites that
    // must each remember.
    publishCurrentRow();
  }

  /// Standing on a LANE in the timeline. A lane becomes the verb's subject,
  /// so Add keys that property instead of adding a cel (R10 #19) — while
  /// its LAYER stays the drawing target, taken in the same step
  /// ([_seatLayer]): standing on a property must never cost you the layer.
  ///
  /// A lane lives in the TIMELINE here, so it is the timeline's row to
  /// remember: coming back to that panel restores the lane rather than
  /// dropping to the layer it hangs under.
  ///
  /// R5 #12: and the CELL range goes. A frame range is drawn on a LAYER row,
  /// so standing on a property is always leaving the row it belongs to — but
  /// [selectLayer] runs first on this path and keeps a range whose layer has
  /// not changed, which left the band sitting on the cells while the subject
  /// was a lane. Nothing draws a frame range from a lane, so this can never
  /// drop one mid-drag.
  void _standOnTimelineLane(LaneRowAddress lane) {
    _working.value = WorkingPanel.timeline;
    _seatLayer(lane.layerId, row: lane);
    _selection.clearFrameRangeSelection();
  }

  /// The row each cut was last worked on, replayed on the way back in
  /// (user request 2026-07-26). SESSION view state on purpose: hanging it
  /// on the Cut would make picking a layer a document edit — an undo entry
  /// and a dirty file per click.
  final Map<CutId, LayerId> _lastLayerByCut = <CutId, LayerId>{};

  /// Records the layer a cut is being LEFT on — one funnel instead of a
  /// hook on every path that can move the active layer. Stale ids need no
  /// cleanup: [_internals.activeCutHasLayer] already drops a layer the cut no longer
  /// has, and the rebuild falls back to the top row.
  ///
  /// SE rows are recorded like any other: what the timeline shows for them
  /// is a cut-local PROJECTION of the track layer, so "the row this cut was
  /// left on" can name one, and the id is the same in every cut — a cut
  /// left on S1 comes back on S1 for free.
  void rememberActiveLayerForCut() {
    final cutId = _timeline.editingSession.activeCutId;
    final layerId = _selection.activeLayerId;
    if (cutId != null && layerId != null) {
      _lastLayerByCut[cutId] = layerId;
    }
  }

  void selectCut(CutId cutId) {
    if (cutId == _timeline.editingSession.activeCutId) {
      return;
    }
    // R15-⑤: never switch cuts under a live editing interaction.
    if (_internals.editingInteractionBusy) {
      return;
    }
    rememberActiveLayerForCut();
    final nextActiveLayerId = _lastLayerByCut[cutId];

    final fromGap =
        _selection.gapGlobalFrame != null ||
        _timeline.editingSession.activeCutId == null;
    // The visibility solo is cut-scoped: restore the eyes before leaving.
    if (_solo.layerVisibilitySoloEnabled) {
      _solo.exitVisibilitySolo();
    }
    _timeline.editingSession.setActiveCutId(cutId);
    // Keep the pair reconciled at the seam instead of only at read time:
    // selecting a cut selects its track, so the stored selection is right
    // the moment the cut is dropped (a gap park) rather than falling back.
    _timeline.editingSession.setSelectedTrackId(
      trackIdOfCut(_project.repository.requireProject(), cutId) ??
          _timeline.editingSession.selectedTrackId,
    );
    _selection.clearFrameRangeSelection();
    // The cut comes back on the row it was left on; never visited (or the
    // layer is gone — the rebuild's own guard) falls back to the top row.
    _controllers.rebuild(preferredActiveLayerId: nextActiveLayerId);
    // F-169: the row is the program's pick, not yours — and the rail's view
    // may have changed since you left it.
    keepStandingShown(filterSparesStanding: false);
    if (fromGap) {
      // Activating a cut FROM the gap lands on ITS first frame (UI-R10
      // #14): the stale gap-global cursor never leaks into the new cut
      // (selectFrameIndex also clears the parking).
      _selection.selectFrameIndex(0);
    }
    // Yield the warm window first, exactly as a frame seek does. A cut
    // switch used to warm immediately, which was fine while switching was
    // a click — but the V row's flip switches cuts once per press, so a
    // run of them queued a full-canvas warm per step and the run stuttered
    // on work it was about to invalidate anyway.
    _playbackRig.prerenderScheduler.notifyEditActivity();
    _changes.warmActiveCut();
    _changes.notifyChanged();
  }

  /// Selects the CUT's row — the active layer, which is the drawing target
  /// and what the timeline's rail highlights. It does not touch the
  /// storyboard rail's own [selectedRow]: the two row selections are
  /// separate (user decision 2026-07-27).
  ///
  /// Picking a layer is working in the timeline, so it engages it — R10 #13:
  /// the flip counts this layer's blocks from here.
  void selectLayer(LayerId layerId) {
    _working.value = WorkingPanel.timeline;
    _seatLayer(layerId);
  }

  /// [selectLayer] minus the engaging: the drawing target and the timeline's
  /// row move to [layerId], and the panel being worked in stays where it is.
  ///
  /// The PROGRAM's re-seats come here — a fold's swallower, an undo's walk, a
  /// hidden row's stand-in. ↩️They went through [selectLayer], so a cut
  /// switch whose remembered row happened to be hidden took the flip off the
  /// storyboard in the middle of a V-row walk: the storyboard's grammar
  /// leaking into the timeline's, which is the shape 유저 2026-09-24 named
  /// (「위아래 이동이 타임라인 내부로 샌다거나 그런거 싹 다 해결」).
  ///
  /// [row] is the timeline row to stand on when it is not the layer's own —
  /// one of its LANES, taken in the same publish, so re-standing on the
  /// lane you are on repaints nothing.
  void _seatLayer(LayerId layerId, {TimelineRowAddress? row}) {
    var changed = false;
    // A frame-range selection is single-layer (UI-R8): moving to another
    // row drops it. The lane selection follows the same rule.
    if (_selection.frameRangeSelection.value != null &&
        _selection.frameRangeSelection.value!.layerId != layerId) {
      _selection.clearFrameRangeSelection();
      changed = true;
    }
    if (_selection.laneRangeSelection.value != null &&
        _selection.laneRangeSelection.value!.layerId != layerId) {
      _rangeSelections.clearLaneRangeSelection();
      changed = true;
    }
    // ALREADY-ACTIVE IS FREE. Every timeline cell tap calls this before it
    // seeks — `select()` sends the layer and the frame — and the seek itself
    // is deliberately notify-free (it rides the cursor notifier). This was
    // not: clicking a second cell in the row you are already on announced
    // app-wide and rebuilt the whole panel, which is what made cell
    // selection feel like it lagged behind the pointer.
    if (_selection.activeLayerId != layerId) {
      _controllers.layerController.selectLayer(layerId);
      // The solo mode FOLLOWS the active layer (R4 #7) — nothing to follow
      // when the layer did not move, and re-applying it is what would have
      // fought a manual visibility toggle on every click.
      _solo.syncVisibilitySolo();
      changed = true;
    }
    // R10 #13: the TIMELINE's row moves with the layer. It does NOT touch the
    // rail's row — that stays where the user put it (2026-07-27), and it is
    // a different question: which row of the FILM is lit.
    _timelineRow = row ?? LayerRowAddress(layerId);
    // The drawn row rides its own notifier, so leaving a property lane for
    // its layer row repaints the rail even when nothing else changed —
    // "already active is free" stays true for the session notify.
    publishCurrentRow();
    if (changed) {
      _changes.notifyChanged();
    }
  }

  /// Whether standing at [from] is standing somewhere other than [there] —
  /// the question an undo asks before it takes an edit back (I-41).
  ///
  /// A different cut or frame is; a different row is only while [there]'s
  /// row is still one of the cut's rows — asked of the rows the cut SHOWS
  /// (a track SE row stands there too, and is not in the cut's document).
  /// ⚠️A row that is gone is taken back right where the cut and frame
  /// match: a walk to it would arrive nowhere, and every press after it
  /// would walk again. A place whose cut is gone is nowhere to walk to.
  bool isElsewhere(StandingPlace there, {required StandingPlace from}) {
    if (_project.cutById(there.cut) == null) {
      return false;
    }
    if (there.cut != from.cut || there.frame != from.frame) {
      return true;
    }
    final row = there.layer;
    return row != null &&
        row != from.layer &&
        _project.layerById(row) != null;
  }

  /// 🚨★★★I-41 — WALKS THE USER TO [place]: its cut, its row, its frame, and
  /// then shows the row.
  ///
  /// 🗣️유저 2026-09-24: 「그곳으로 이동해서 편집되돌리고」, with F-169's ②
  /// 「언두시에 접혀있는 레이어로 이동하면 펼치고 해당 레이어에 서게」 and ③
  /// 「스크롤밖이면 스크롤 조정」. What hides the row opens: its folders
  /// ([_openFoldersAbove]), then the rail's view of it ([keepStandingShown]
  /// with reveal), and the rails scroll it into view.
  ///
  /// ⚠️Only the cut, the row and the frame move (유저: 「화면 확대·스크롤·
  /// 선택범위·도구는 그대로」).
  void standOn(StandingPlace place) {
    if (_project.cutById(place.cut) == null) {
      return;
    }
    selectCut(place.cut);
    final row = place.layer;
    if (row != null && _project.layers.any((layer) => layer.id == row)) {
      _openFoldersAbove(row);
      // The walk moves where the timeline stands, not which panel you are
      // working in — an undo is a key, not a touch.
      _seatLayer(row);
    }
    _selection.selectFrameIndex(place.frame);
    keepStandingShown(reveal: true);
    _rangeSelections.revealSelection();
  }

  /// Opens every shut folder above [row], OUTSIDE history.
  ///
  /// ⛔A fold is an edit that undoes (유저 2026-08-29) — but this one is not
  /// the user's: it is the walk an undo makes, and written into history it
  /// would clear the redo side and make the NEXT undo re-fold the folder
  /// instead of taking the edit back, breaking both halves of I-41's
  /// answer (「다음 언두가 편집을 되돌린다」, 「리두대칭」). Decided on the
  /// I-41 card at 착수, 2026-09-24.
  void _openFoldersAbove(LayerId row) {
    final stack = _project.layers;
    final layer = stack.firstWhere((layer) => layer.id == row);
    final shut = [
      for (final folder in LayerFolderIndex(stack).ancestryOf(layer.folderId))
        if (folder.collapsed) folder.id,
    ];
    if (shut.isEmpty) {
      return;
    }
    for (final folder in shut) {
      _project.repository.updateLayer(
        layerId: folder,
        update: (layer) => layer.copyWith(collapsed: false),
      );
    }
    _changes.notifyChanged();
  }

  /// 🚨★★THE STANDING LAW (F-169, 유저 2026-09-24): ①「보이는거만 선택가능하고
  /// 안보이는거 선택되는상황엔 다른 보이는레이어 선택하도록」 ②「언두시에 접혀있는
  /// 레이어로 이동하면 펼치고 해당 레이어에 서게」.
  ///
  /// Asked after everything that can leave the active layer's row off the
  /// screen — a cut command's rebuild (a delete's hand-off, an undo, a redo),
  /// a cut switch, a new row, and the rail's own view changes — through the
  /// same [layerRowHiddenBy] the grids draw by. When the row is hidden:
  ///   - [reveal]: you WENT there — made the row, or an undo brought you back
  ///     to it. What the rail's VIEW hides it with opens: its attach group
  ///     unfolds, its section shows. A folder's fold is the document's, not
  ///     the view's, and does not open here.
  ///   - otherwise another row takes the standing: the head of the fold it
  ///     is in (the attach group's base, the outermost shut folder — the
  ///     fold law's swallower, R5 #11), else the nearest shown row ABOVE it
  ///     on screen, else the first shown row (UI-R6 #3's order). See
  ///     [_standInFor].
  ///
  /// [filterSparesStanding]: a filter never hides the row you are editing
  /// ([TimelineRowFilter.allowsRow]). False when the PROGRAM picked the row —
  /// a hand-off, a cut switch — or the filter was just set (UI-R6 #3): an
  /// exemption is not a way onto the screen.
  void keepStandingShown({
    bool reveal = false,
    bool filterSparesStanding = true,
  }) {
    final activeId = _selection.activeLayerId;
    final stack = _project.layers;
    final activeIndex = stack.indexWhere((layer) => layer.id == activeId);
    if (activeIndex == -1) {
      return;
    }
    final active = stack[activeIndex];
    final folders = LayerFolderIndex(stack);
    LayerRowHiddenBy? hiddenBy(Layer layer, {LayerId? spared}) =>
        layerRowHiddenBy(
          layer,
          folders: folders,
          attachBaseId: attachGroupBaseOf(layer, stack),
          hiddenSections: _railView.hiddenSections.value,
          rowFilter: _railView.rowFilter.value,
          collapsedAttachBaseIds: _railView.collapsedAttachBaseIds.value,
          standingLayerId: spared,
          fxEnabledOf: _fxEnabledOf,
        );
    if (hiddenBy(active, spared: filterSparesStanding ? active.id : null) ==
        null) {
      return;
    }
    // ③ (유저 2026-09-24): 「스크롤 너머의 다른 인덱스에 있는거라면 … 스크롤밖이면
    // 스크롤 조정하는것도 … 법/규칙 통일」. Either way the row you stand on
    // just came onto the screen without a pointer on it, so the rails bring
    // it into view — the law every pointerless move keeps (R5, 2026-08-09).
    if (reveal) {
      _openViewAround(active, stack);
      if (hiddenBy(active, spared: active.id) == null) {
        _rangeSelections.revealSelection();
        return;
      }
    }
    final standIn = _standInFor(active, stack, hiddenBy);
    if (standIn != null && standIn.id != active.id) {
      _seatLayer(standIn.id);
      _rangeSelections.revealSelection();
    }
  }

  /// [keepStandingShown]'s reveal: the section [layer] sits in shows, and
  /// the attach group it rides unfolds. One write each, only when shut.
  void _openViewAround(Layer layer, List<Layer> stack) {
    final section = timelineSectionForLayerKind(layer.kind);
    final hidden = _railView.hiddenSections.value;
    if (hidden.contains(section)) {
      _railView.hiddenSections.value = {...hidden}..remove(section);
    }
    final baseId = attachGroupBaseOf(layer, stack);
    final folded = _railView.collapsedAttachBaseIds.value;
    if (baseId != null && folded.contains(baseId)) {
      _railView.collapsedAttachBaseIds.value = {...folded}..remove(baseId);
    }
  }

  /// The row that stands in for hidden [layer]: the base of the attach group
  /// that folded it away, else the nearest shown row above it, else the
  /// first shown row. Null when no row is on screen.
  ///
  /// A shut FOLDER needs no arm of its own: its row sits right above its run
  /// on screen, so the nearest shown row above a member IS the outermost
  /// shut folder. An attach group's base can sit BELOW its rows (an above
  /// attach), and the fold law hands to the base wherever it sits (UI-R24
  /// #4) — a landing answers the same.
  ///
  /// Candidates are judged WITHOUT the filter's exemption — none of them is
  /// standing yet.
  Layer? _standInFor(
    Layer layer,
    List<Layer> stack,
    LayerRowHiddenBy? Function(Layer layer) hiddenBy,
  ) {
    var candidate = layer;
    if (hiddenBy(layer) == LayerRowHiddenBy.attachFold) {
      final baseId = attachGroupBaseOf(layer, stack);
      // A base never rides a group of its own, so one step is the whole way.
      final base = stack.where((row) => row.id == baseId).firstOrNull;
      if (base != null && hiddenBy(base) == null) {
        return base;
      }
      candidate = base ?? layer;
    }
    final display = horizontalLayerDisplayOrder(stack);
    final from = display.indexWhere((row) => row.id == candidate.id);
    // Screen-up = earlier in horizontal display order.
    for (var index = from - 1; index >= 0; index -= 1) {
      if (hiddenBy(display[index]) == null) {
        return display[index];
      }
    }
    return display.where((row) => hiddenBy(row) == null).firstOrNull;
  }
}

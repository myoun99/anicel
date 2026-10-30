import 'package:flutter/foundation.dart' show ValueNotifier;
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart'
    show cameraKeyFits, cameraWriteKeepsKeysIn;
import '../../models/transform_track.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/property_track.dart'
    show KeyExit, KeyPath, KeySide, KeySidesEdit, KeyTypePick, PropertyKey;
import '../../models/se_name_tag.dart' show SeNameTag, SeNameTagTrack;
import '../../models/se_sound.dart' show SeSound;
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_camera_row.dart' show isTrackCameraRow;
import '../../models/track_projection_row.dart' show projectionRowUnder;
import '../../models/track_transitions.dart' show cutDrawnFrameCount;
import '../../models/track_transform_lane_carrier.dart';
import '../../services/camera_pose_resolver.dart';
import '../../services/project_lookup.dart'
    show rowPoseSpace, rowWearsBaseComposite;
import '../storyboard_layer_policy.dart' show projectedLayerInHand;
import '../timeline/effect_lane_editing.dart'
    show
        effectLaneKeyCanRove,
        effectsWithEnabledToggled,
        effectsWithGroupReset,
        effectsWithLaneKeyToggled,
        effectsWithLaneKeysWritten,
        effectsWithLaneValueEdited,
        effectsWithRemoved,
        effectsWithTransformKeysEdited;
import '../timeline/effect_lane_policy.dart'
    show effectLaneDisplayOrder, parseEffectLaneId;
import '../timeline/reference_lane_policy.dart'
    show
        laneIsReference,
        referenceGroupLaneId,
        referenceLaneDisplayOrder,
        referenceMemberTransformLane,
        referenceScaleForm;
import '../timeline/transform_lane_editing.dart'
    show
        transformTrackWithGroupReset,
        transformTrackWithLaneKeyToggled,
        transformTrackWithLaneKeysWritten,
        transformTrackWithLaneValueEdited;
import '../timeline/scale_lane_form.dart' show scaleLaneFormOf;
import '../timeline/se_name_tag_lane_editing.dart'
    show
        seNameTagTrackWithLaneKeysWritten,
        seNameTagWithGroupReset,
        seNameTagWithLaneKeyToggled,
        seNameTagWithLaneValueEdited;
import '../timeline/se_name_tag_lane_policy.dart'
    show
        laneIsSeNameTag,
        seNameTagGroupLaneId,
        seNameTagLaneDisplayOrder,
        seNameTagLaneTakesSides,
        seNameTagLaneUsesName;
import '../timeline/se_sound_lane_editing.dart'
    show
        seSoundWithGroupReset,
        seSoundWithLaneKeyToggled,
        seSoundWithLaneKeysWritten,
        seSoundWithLaneValueEdited;
import '../timeline/se_sound_lane_policy.dart'
    show
        laneIsSeSound,
        seSoundGroupLaneId,
        seSoundLaneDisplayOrder,
        seSoundLaneUsesName;
import '../timeline/property_lane_model.dart'
    show LaneKeyValues, PropertyLaneRow, laneGroupKey;
import '../timeline/property_lanes_for_row.dart' show propertyLanesForRow;
import '../timeline/timeline_current_row.dart' show laneGroupOf;
import '../timeline/transform_lane_policy.dart'
    show
        cameraPropertyLanes,
        transformGroupHeaderLane,
        transformLaneDisplayOrder;
import '../timeline/timeline_drag_preview.dart'
    show
        LaneEditPreview,
        TimelineDragPreview,
        timelineDragPreviewGlobalLayerFor;
import 'active_cut_controllers.dart';
import 'active_cut_edits.dart';
import 'drags/lane_range_move_drag.dart' show laneIdsAMoveCarries;
import 'lane_edit_subject.dart';
import 'lane_homes.dart';
import 'row_written_by_id.dart';
import 'session_roles.dart';
import 'effects_and_fx.dart';

/// The LANE VERBS — what a verb on a transform or effect lane acts on (the
/// targets, the range, the layer and frame behind a lane row), the keys it
/// creates, names, links and removes for the selection, and the commits
/// that write a lane back — as their own object.
///
/// 🚨★★★ONE PROJECTION, BOTH WAYS (F-102, 2026-09-15). 유저: 「글로벌트랙은
/// fx든뭐던 로컬에선 글로벌을 투영해서 보여주도록? 물론 로컬에서도 조작은
/// 가능하지만. 그걸 바탕으로 근본 구조적으로 해결해줘」. A row the TRACK owns
/// is shown in a cut as a projection of the track's row: every write to its
/// keys — the lane navigator's ◆, a typed value, a canvas handle's drag, from
/// either panel — lands on the row the project holds ([laneVerbLayerFor],
/// [_laneVerbFrameAt]), and every value the cut shows is read off that same
/// row at that same frame ([laneValueSourceAt]).
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: no field of its own and eighteen
/// session members touched. It names the roles it needs in its constructor.
class LaneVerbs {
  LaneVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required TimelineRowAddress Function() currentRow,
    required bool Function() sessionDisposed,
    required ValueNotifier<TimelineDragPreview?> dragPreview,
    required EffectsAndFx effectsAndFx,
    required ChangeSink changes,
    required ActiveCutEdits activeCut,
    required void Function(
      LayerId cameraRow,
      TransformTrack track, {
      required String description,
    })
    updateCameraTrack,
    required ({Layer shown, Layer? global}) Function(Layer row) previewFormsOf,
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _controllers = controllers,
       _currentRow = currentRow,
       _sessionDisposed = sessionDisposed,
       _dragPreview = dragPreview,
       _effectsAndFx = effectsAndFx,
       _changes = changes,
       _activeCut = activeCut,
       _updateCameraTrack = updateCameraTrack,
       _previewFormsOf = previewFormsOf;

  final EffectsAndFx _effectsAndFx;
  final ChangeSink _changes;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;

  /// The row the user stands on — `Standing.currentRow`, asked when needed.
  final TimelineRowAddress Function() _currentRow;

  /// Whether the session has been disposed — a plain flag, so it comes as
  /// the question.
  final bool Function() _sessionDisposed;
  final ValueNotifier<TimelineDragPreview?> _dragPreview;

  /// The cut a lane verb reads and writes a row in ([ActiveCutEdits.cutOfRow])
  /// — the one holding it, stood in or not (I-89-Q23).
  final ActiveCutEdits _activeCut;

  /// `Camera.updateCameraTrack` — the camera row's lanes go home to the
  /// CUT holding it, not to a layer.
  ///
  /// ⚠️A closure, not the `Camera`: the camera holds the lane move, which
  /// holds these verbs, so naming it here would close a construction cycle
  /// (the ninth family's cure; ARCH-session-state, the fifteenth family —
  /// it was asked through `SessionInternals` before).
  /// ↩️F-195: the camera no longer holds the lane move — its in-flight track
  /// rides the preview channel, which the camera is handed as the notifier
  /// itself — so that cycle is gone. The closure stays: the verbs need the
  /// camera's one write, not the camera.
  final void Function(
    LayerId cameraRow,
    TransformTrack track, {
    required String description,
  })
  _updateCameraTrack;

  /// What the open cut shows of a row in flight — the preview's two forms,
  /// the pair `TrackSeDisplay.previewFormsOf` decides.
  ///
  /// 🚨THE FUNCTION, NOT THE OBJECT (2026-09-16, when the range move held
  /// it). Taking the VALUE closed a construction cycle four links long —
  /// `trackSe` builds `transitions`, `transitions` takes `camera` — and a
  /// `TrackSeDisplay Function()` left the IMPORT, which
  /// `no_import_cycles_test` reads as the same loop. The one method this
  /// calls needs neither: the record it returns is made of `Layer`.
  final ({Layer shown, Layer? global}) Function(Layer row) _previewFormsOf;

  /// The transform track that ALREADY holds [name] in this lane's naming
  /// space, or null when the name is free there.
  ///
  /// A LAYER row's space spans its 겸용 link group — the camera row's too,
  /// since it keeps the transform law (F-84, 2026-09-11). A V row's does
  /// not: a V track is held once, so there is no second use site for a name
  /// to reach.
  /// [excludeFrames] are the keys a RANGE rename is about to name: they are
  /// the ones joining, so they must not be found as the holder.
  TransformTrack? _laneTransformHoldingName(
    Layer layer,
    TransformPropertyId property,
    String name, {
    Set<int> excludeFrames = const {},
  }) {
    final track = _laneTransformTrackOf(layer);
    if (transformLaneUsesName(
      track,
      property,
      name,
      excludeFrames: excludeFrames,
    )) {
      return track;
    }
    final cutId = _activeCut.cutOfRow(layer.id);
    if (cutId == null || trackIdOfTransformLaneCarrier(layer.id) != null) {
      return null;
    }
    return _project.cutCommandCoordinator.transformTrackHoldingName(
      cutId: cutId,
      layerId: layer.id,
      property: property,
      name: name,
      excludeFramesOnSource: excludeFrames,
    );
  }

  /// The lanes a VERB acts on for a span (R9 #20): a GROUP HEADER stands
  /// for its members.
  ///
  /// #20 took the header's special case out of SELECTION — a header is a
  /// row and a drag selects the rows it drew over. This is the separate,
  /// and separately true, statement that a row's verbs act on what the row
  /// SHOWS: the header band paints its members' key union, so a move that
  /// grabs it moves those keys ("한번에 잡아 이동"). Keeping the two apart
  /// is the whole of #20 — one used to be doing the other's job.
  List<String> laneVerbTargets(
    List<String> spanLaneIds, {
    List<LayerEffect> effects = const [],
  }) {
    final targets = <String>[];
    void add(String laneId) {
      if (!targets.contains(laneId)) {
        targets.add(laneId);
      }
    }

    for (final laneId in spanLaneIds) {
      if (laneId == transformGroupHeaderLane.laneId) {
        transformLaneDisplayOrder.forEach(add);
        continue;
      }
      // The name-tag header stands for its seven members, exactly as the
      // transform header does (한번에 잡아 이동) — and the reference fx's
      // for its three (F-374).
      if (laneId == seNameTagGroupLaneId) {
        seNameTagLaneDisplayOrder.forEach(add);
        continue;
      }
      if (laneId == seSoundGroupLaneId) {
        seSoundLaneDisplayOrder.forEach(add);
        continue;
      }
      if (laneId == referenceGroupLaneId) {
        referenceLaneDisplayOrder.forEach(add);
        continue;
      }
      final address = parseEffectLaneId(laneId);
      if (address != null && address.parameterId == null) {
        for (final effect in effects) {
          if (effect.id == address.effectId) {
            effectLaneDisplayOrder(effect).forEach(add);
            break;
          }
        }
        continue;
      }
      add(laneId);
    }
    return targets;
  }

  /// The LANE range a verb should act on, or null when the subject is not
  /// a property row (R10 #19).
  ///
  /// A live lane SPAN wins; otherwise the row you are standing on, as a
  /// one-frame span at the playhead. Expressing the standing case as a
  /// span is what makes Add and Delete need no second code path — the
  /// group header's whole-member expansion and the effect-lane branch
  /// come along either way.
  TimelineLaneSelection? get laneVerbRange {
    final span = _selectedLaneSpan;
    if (span != null) {
      return span;
    }
    // 🚨A band that holds more than the camera claims the press as CELLS,
    // so no row stood on answers for it — every lane verb at once, in the
    // order the one Delete asks (F-87). ↩️Only the camera rows asked: a band
    // swept up from a lane into its layer's row left the press on that lane,
    // and ＋ keyed one frame of it and filled none of the band.
    // 🗣️one-band-no-lane-tail-Q2 (유저 2026-10-27): 「칸 편집」 — so Edit and
    // the double tap open the cell's editor under such a band, and the key
    // window opens where lanes alone are selected ([_selectedLaneSpan]).
    if (bandClaimsThePress) {
      return null;
    }
    return switch (_currentRow()) {
      final LaneRowAddress lane when projectionRowUnder(lane) != null =>
        _projectedLaneSpan(lane),
      LaneRowAddress(:final layerId, :final laneId) => _standingSpan(
        layerId,
        laneId,
      ),
      // The storyboard's CAMERA row is no cut's layer: standing on it stands
      // on the camera layer it has in hand — the timeline's camera row, and
      // so its header (I-73 ④, 「타임라인의 자리 = 카메라 행」) — or on
      // nothing.
      final row when isTrackCameraRow(row) => switch (projectedLayerInHand(
        row: row,
        cut: _project.activeCutOrNull,
        activeLayerId: _selection.activeLayerId,
      )) {
        final camera? => _standingSpan(
          camera.id,
          transformGroupHeaderLane.laneId,
        ),
        null => null,
      },
      LayerRowAddress(:final layerId) when _isCameraRow(layerId) =>
        _standingSpan(layerId, transformGroupHeaderLane.laneId),
      _ => null,
    };
  }

  /// Whether a live band claims the press as CELLS ([laneVerbRange]): the
  /// cut's or the track's, where no lane span is selected — a band on the
  /// camera row alone is its header's span ([_selectedLaneSpan]). The frame
  /// board then takes the press on a lane stood on, as its row's
  /// (`FrameClipboard.timelinePlace`), and copies the band's lanes with its
  /// cells (🗣️one-band-no-lane-tail-Q1, 유저 2026-10-27: 「칸과 키를 같이
  /// 든다」). ↩️Only the cut's band claimed it: on the conte a lane stood on
  /// under the track's band still answered, and a copy there took one key
  /// at the playhead.
  bool get bandClaimsThePress =>
      _selectedLaneSpan == null &&
      (_selection.frameRangeSelection.value != null ||
          _selection.trackFrameRangeSelection.value != null);

  /// The lane span a SELECTION states — [laneVerbRange]'s, before the row
  /// stood on answers — or null where nothing is selected.
  TimelineLaneSelection? get _selectedLaneSpan {
    final span = _selection.laneRangeSelection.value;
    if (span != null) {
      return span;
    }
    // 🚨㉙ → F-17/F-84: the CAMERA row IS its transform group header — its
    // band already draws the members' union (B4) — and 유저 2026-09-11:
    // 「트랜스폼이나 카메라나 똑같으니까 법 싹 하나로 통일해줘」. So a band on
    // the camera row ALONE is a header span, and standing on it stands on
    // the header: every lane verb (name, type, add, delete) reaches the
    // camera's keys through the one path the fx header's take.
    final cells = _selection.frameRangeSelection.value;
    if (cells != null &&
        cells.spanLayerIds.length == 1 &&
        _isCameraRow(cells.spanLayerIds.single)) {
      return TimelineLaneSelection(
        layerId: cells.spanLayerIds.single,
        laneId: transformGroupHeaderLane.laneId,
        startIndex: cells.startIndex,
        endIndexExclusive: cells.endIndexExclusive,
      );
    }
    return null;
  }

  /// Whether [lane] holds a frame a key can be made on
  /// ([_keyableFrames]) — the ＋'s gate, asked of the span it presses.
  bool canCreateLaneKeysFor(TimelineLaneSelection lane) {
    final layer = laneVerbLayerFor(lane.layerId);
    return layer == null || _keyableFrames(layer, lane).isNotEmpty;
  }

  /// The frames of [lane] a key can be made on: none before frame 0, and on
  /// the CAMERA's lanes none its cut is not drawn for — 🗣️I-73-camera-row-Q2
  /// (유저 2026-10-09: 「콘티처럼 컷밖으로 못나가게 클리핑」 → `own-frames`).
  List<int> _keyableFrames(Layer layer, TimelineLaneSelection lane) {
    final cut = _transformHomeOf(layer) == _TransformHome.cutCamera
        ? _cutWriting(layer)
        : null;
    final drawn = cut == null ? null : _drawnFramesOf(cut);
    return [
      for (
        var frame = lane.startIndex;
        frame < lane.endIndexExclusive;
        frame += 1
      )
        if (drawn == null
            ? frame >= 0
            : cameraKeyFits(frame, drawnFrameCount: drawn))
          frame,
    ];
  }

  /// The cut whose camera the camera row [layer] writes as [track] — null
  /// where no cut holds the row, or where [track] puts a key out of the
  /// frames the cut is drawn for ([cameraWriteKeepsKeysIn],
  /// 🗣️I-73-camera-row-Q2). The commit and a drag's preview both ask it,
  /// so what a drag shows is what the press keeps; a paste keeps its keys
  /// in by itself ([_cameraLastFrameOf]).
  Cut? _cutTakingCamera(Layer layer, TransformTrack track) {
    final cut = _cutWriting(layer);
    return cut != null &&
            cameraWriteKeepsKeysIn(
              cut.camera.track,
              track,
              drawnFrameCount: _drawnFramesOf(cut),
            )
        ? cut
        : null;
  }

  /// The last frame a paste may leave a key on [layer]: on the camera row,
  /// whose lanes are its cut's camera's, the cut's last drawn frame; else
  /// none ([laneKeysSpliced]).
  /// 🗣️F-388-Q3 (유저 2026-10-22): 「끝 키는 끝에 남고, 밖으로 밀린 나머지는
  /// 버린다」. ↩️A paste that pushed a key past the end was refused whole,
  /// its buttons dark (F-388, 관제 10-22).
  int? _cameraLastFrameOf(Layer layer) {
    final cut = _transformHomeOf(layer) == _TransformHome.cutCamera
        ? _cutWriting(layer)
        : null;
    return cut == null ? null : _drawnFramesOf(cut) - 1;
  }

  /// The cut [layer] is read and written in ([ActiveCutEdits.cutOfRow]):
  /// the one holding it, stood in or not — a header graph draws a line for
  /// every cut, and a cut's line is edited where it is (I-89-Q23). ↩️The
  /// cut stood in, whichever cut's row the verb was handed.
  Cut? _cutWriting(Layer layer) {
    final cutId = _activeCut.cutOfRow(layer.id);
    return cutId == null ? null : _project.cutById(cutId);
  }

  /// How many frames [cut] is DRAWN for ([cutDrawnFrameCount]): its own and
  /// the のりしろ the transitions crossing it ask — none for a cut no track
  /// holds.
  int _drawnFramesOf(Cut cut) =>
      cutDrawnFrameCount(_project.repository.requireProject(), cut.id) ??
      cut.duration;

  /// A LANE of a storyboard projection row (I-73 ④ⓔ) stood on: that lane of
  /// the layer the row has in hand ([projectedLayerInHand]) — or of nothing.
  TimelineLaneSelection? _projectedLaneSpan(LaneRowAddress lane) =>
      switch (projectedLayerInHand(
        row: projectionRowUnder(lane),
        cut: _project.activeCutOrNull,
        activeLayerId: _selection.activeLayerId,
      )) {
        final layer? => _standingSpan(layer.id, lane.laneId),
        null => null,
      };

  /// The row you are STANDING on, as a one-frame span at the playhead.
  TimelineLaneSelection _standingSpan(LayerId layerId, String laneId) =>
      _oneFrameSpan(layerId, laneId, _laneVerbFrameFor(layerId));

  /// [laneId] of [layerId] at [frame] alone, on the row's own axis.
  TimelineLaneSelection _oneFrameSpan(
    LayerId layerId,
    String laneId,
    int frame,
  ) => TimelineLaneSelection(
    layerId: layerId,
    laneId: laneId,
    startIndex: frame,
    endIndexExclusive: frame + 1,
  );

  bool _isCameraRow(LayerId layerId) =>
      laneVerbLayerFor(layerId)?.kind == LayerKind.camera;

  /// The transform track a LANE row edits: the CAMERA row's lanes live on
  /// its cut's camera ([_cutWriting]), every other row's on the layer itself.
  ///
  /// R10 R3: the lane-verb family read `layer.transformTrack` flat, so Add
  /// and Delete silently missed the camera row — which only showed once
  /// the Frame ▾ menu became the delete key's home and had to answer for
  /// the lane the marker's context menu used to.
  TransformTrack _laneTransformTrackOf(Layer layer) =>
      layer.kind == LayerKind.camera
      ? (_cutWriting(layer)?.camera.track ?? layer.transformTrack)
      : layer.transformTrack;

  /// The transform track [layer]'s lanes of one home hold: its reference
  /// fx's where [reference] says (F-374), else its own.
  TransformTrack _transformTrackAt(Layer layer, {required bool reference}) =>
      reference
      ? (layer.mediaReference?.fx ?? TransformTrack.empty())
      : _laneTransformTrackOf(layer);

  /// [track] as an edit of one home alone.
  TransformHomes _transformHomesWith(
    TransformTrack track, {
    required bool reference,
  }) => reference
      ? (own: null, reference: track)
      : (own: track, reference: null);

  /// The transform lane [laneId] is on its home's track: a reference
  /// member's is the lane it holds (F-374), every other lane itself.
  String _trackLaneOf(String laneId) =>
      referenceMemberTransformLane(laneId) ?? laneId;

  /// The layer a LANE verb READS and WRITES.
  ///
  /// ★A track-owned SE row answers with the GLOBAL layer, never the cut's
  /// display clone (user, 2026-08-09: **"글로벌 트랙이 메인이고 컷
  /// 타임라인 내부에서는 그걸 알기 쉽게 보여주기만 할 뿐"**). The lane
  /// selection is stated on that same global axis, so a span that runs
  /// past the cut edge still reaches every key it covers — reading the
  /// clone could only ever have touched the keys the current cut happens
  /// to show.
  ///
  /// This is the axis rule the frame-shift verbs already follow
  /// (`BlockShift.shiftLayerFor`, UI-R18 #1), now said once more for the lane
  /// family. R5 #8's window conversion on the way OUT retires with it:
  /// what goes in was global to begin with.
  /// ★And a V TRACK's own lane rows answer with a CARRIER layer — the
  /// track's transform and chain wearing the carrier id, the very shape
  /// the rails already draw those rows with ([_vLaneCarrier]). Without it
  /// the verbs looked the carrier up as a layer, found nothing, and
  /// reported "no keys here": Delete then fell through to the CEL path and
  /// removed the active layer's drawing instead. The commit funnels below
  /// send it home to the track.
  /// ★And a row of a cut not stood in answers as itself
  /// ([RowWrittenById.rowWrittenById]), its verbs reading and writing in
  /// that cut ([_cutWriting]): a header graph's line of that cut is edited
  /// where it is (I-89-Q23).
  Layer? laneVerbLayerFor(LayerId layerId) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layerId);
    if (carrierTrackId != null) {
      final track = _project.trackById(carrierTrackId);
      return track == null
          ? null
          : Layer(
              id: layerId,
              name: 'V',
              frames: const [],
              // No transform of its own any more; the V row's lane carrier
              // exists for the EFFECT chain alone.
              effects: track.effects,
            );
    }
    return _project.rowWrittenById(layerId);
  }

  /// Whether [layer]'s fx are its base's — no lane of its own for a verb to
  /// work ([rowWearsBaseComposite]). ↩️The verbs asked 「an attach row」,
  /// which a row riding the conte is without wearing its base's (I-99).
  bool _wearsBaseFx(Layer layer) =>
      rowWearsBaseComposite(_project.repository.requireProject(), layer);

  /// The playhead as [layerId]'s own lanes key it — the frame half of
  /// [laneVerbLayerFor]. A track-SE row is on the global axis, so the
  /// cut-local cursor has to be translated before it can name a key.
  int _laneVerbFrameFor(LayerId layerId) => _laneVerbFrameAt(
    layerId,
    _controllers.timelineController.currentFrameIndex,
    frameIsGlobal: false,
  );

  /// [frameIndex] as [layerId]'s own lanes key it. [frameIsGlobal] names
  /// the axis the caller holds: the timeline panel's rails and playhead
  /// speak CUT-LOCAL frames, the storyboard's rails global ones — and only
  /// a track-SE row, whose keys live on the global axis, tells the two
  /// apart.
  int _laneVerbFrameAt(
    LayerId layerId,
    int frameIndex, {
    required bool frameIsGlobal,
  }) => frameIndex + (frameIsGlobal ? 0 : _project.rowAxisOffset(layerId));

  /// The READ half of the projection: the row a lane on [shown] resolves
  /// its VALUES against, and the frame [frameIndex] — on [shown]'s own rail —
  /// names there.
  ///
  /// A track-SE row's rail shows the cut-local clone, and the clone holds
  /// only the keys inside the cut (a key index is never negative), so its
  /// value at a cut frame is read off the TRACK's row at the global frame —
  /// where a key an earlier cut made still holds it. A drag in flight is read
  /// in its global form, so the value column follows the hand. Every other
  /// row resolves against [shown] itself, which may be a preview, on its own
  /// frames.
  ({Layer layer, int frame}) laneValueSourceAt(Layer shown, int frameIndex) {
    final global = _project.isTrackSeLayerId(shown.id)
        ? timelineDragPreviewGlobalLayerFor(
                _dragPreview.value,
                shown.id,
              ) ??
              _project.trackSeGlobalLayerById(shown.id)
        : null;
    if (global == null) {
      return (layer: shown, frame: frameIndex);
    }
    return (
      layer: global,
      frame: _laneVerbFrameAt(shown.id, frameIndex, frameIsGlobal: false),
    );
  }

  /// The lane navigator's ◆ on [laneId] of [layerId] at [frameIndex]: a key
  /// frozen at the value the lane resolves there, or the key there taken
  /// away — one undo. [frameIsGlobal]: see [_laneVerbFrameAt].
  ///
  /// 🚨★★★F-102 (2026-09-15): both panels keyed through copies of this body
  /// in their hosts, and the timeline's read the row it was SHOWN. For a
  /// track-SE row that is the cut-local clone, which had dropped every key
  /// made in an earlier cut — so keying S1 in cut 2 froze the default and,
  /// written back through the cut window, erased cut 1's key (유저 09-12:
  /// 「컷1에서 se의 트랜스폼으로 포지션 조정했는데, 그게 다른 컷2에서 값이
  /// 안바뀌어 있고 초기값인 상태로 보임」). [laneVerbLayerFor] reads the row
  /// the project holds, so there is nothing to put back.
  void toggleLaneKeyAt(
    LayerId layerId,
    String laneId,
    int frameIndex, {
    required bool frameIsGlobal,
    required String description,
  }) => _commitLaneEdit(
    _laneEditAt(
      layerId,
      laneId,
      frameIndex,
      frameIsGlobal: frameIsGlobal,
      edits: (
        nameTag: (tag, frame) =>
            seNameTagWithLaneKeyToggled(tag, laneId: laneId, frameIndex: frame),
        sound: (sound, frame) =>
            seSoundWithLaneKeyToggled(sound, laneId: laneId, frameIndex: frame),
        effects: (layer, effects, frame) => effectsWithLaneKeyToggled(
          effects,
          laneId: laneId,
          frameIndex: frame,
          paper: _paperOf(layer),
        ),
        transform: (layer, track, frame, {required reference}) =>
            _transformTrackWithKeyToggled(
              layer,
              track,
              _trackLaneOf(laneId),
              frame,
              reference: reference,
            ),
      ),
    ),
    description: description,
  );

  /// A value typed or scrubbed into [laneId] of [layerId] at [frameIndex] —
  /// one undo, on the row and at the frame [toggleLaneKeyAt] takes.
  ///
  /// It ends a scrub: the value [previewLaneValueAt] was showing is dropped
  /// in the same call that writes it, so no frame shows neither.
  ///
  /// [scaleLinked]: whether the Scale lane's chain is on — the transform
  /// tool's 「배율 연동」, the one switch (`ScaleLaneForm.typed`). Asked of
  /// every caller: a default here would be a second switch.
  void setLaneValueAt(
    LayerId layerId,
    String laneId,
    int frameIndex,
    String input, {
    required bool frameIsGlobal,
    required String description,
    required bool scaleLinked,
  }) => _commitLaneEdit(
    _laneEditAt(
      layerId,
      laneId,
      frameIndex,
      frameIsGlobal: frameIsGlobal,
      edits: _valueEdits(laneId, input, scaleLinked: scaleLinked),
    ),
    description: description,
  );

  /// A value being SCRUBBED into [laneId] of [layerId] at [frameIndex]: the
  /// edit [setLaneValueAt] would write, shown and not written (F-195).
  ///
  /// ⛔THE SAME EDIT, NOT A LOOK-ALIKE. It is computed by the very dispatch
  /// the commit runs and handed to the preview channel instead of the
  /// history, so what the drag shows is what the release keeps — the key a
  /// value makes at the playhead included. An input that changes nothing
  /// shows the committed row.
  void previewLaneValueAt(
    LayerId layerId,
    String laneId,
    int frameIndex,
    String input, {
    required bool frameIsGlobal,
    required bool scaleLinked,
  }) => _previewLaneEdit(
    _laneEditAt(
      layerId,
      laneId,
      frameIndex,
      frameIsGlobal: frameIsGlobal,
      edits: _valueEdits(laneId, input, scaleLinked: scaleLinked),
    ),
  );

  /// Drops a lane edit in flight without writing it — a scrub or a handle
  /// drag cancelled. Another drag's preview is not this verb's to drop.
  ///
  /// A handle taken away mid-drag drops its edit a frame late (a notifier
  /// cannot fire while the tree is torn down), and by then the whole
  /// session may have gone with its tab: then there is nothing to drop.
  void endLaneEditPreview() {
    if (_sessionDisposed()) {
      return;
    }
    if (_dragPreview.value is LaneEditPreview) {
      _dragPreview.value = null;
    }
  }

  /// [input] written into [laneId] — of whichever family [laneId] names.
  _LaneEdits _valueEdits(
    String laneId,
    String input, {
    required bool scaleLinked,
  }) => (
    nameTag: (tag, frame) => seNameTagWithLaneValueEdited(
      tag,
      laneId: laneId,
      frameIndex: frame,
      input: input,
    ),
    sound: (sound, frame) => seSoundWithLaneValueEdited(
      sound,
      laneId: laneId,
      frameIndex: frame,
      input: input,
    ),
    effects: (_, effects, frame) => effectsWithLaneValueEdited(
      effects,
      laneId: laneId,
      frameIndex: frame,
      input: input,
      scaleLinked: scaleLinked,
    ),
    transform: (layer, track, frame, {required reference}) =>
        transformTrackWithLaneValueEdited(
          track,
          laneId: _trackLaneOf(laneId),
          frameIndex: frame,
          input: input,
          scaleForm: reference ? referenceScaleForm : scaleLaneFormOf(layer),
          scaleLinked: scaleLinked,
          unkeyedScale: reference ? layer.mediaReference?.pose.scale : null,
        ),
  );

  /// [subject] — [layer]'s keys, or what an edit in flight leaves them at —
  /// with [values] written into the keys they name, each as the value
  /// editor writes it at its frame ([setLaneValueAt]), one after another
  /// into ONE edit: a header graph's keys moved in their values (I-3 ②).
  /// Null where none changes.
  LaneEdit? laneValuesWritten(
    Layer layer,
    LaneEditSubject subject,
    LaneKeyValues values,
  ) {
    var written = const LaneEdit();
    var now = subject;
    for (final MapEntry(key: laneId, value: inputs) in values.inputs.entries) {
      for (final MapEntry(key: frame, value: input) in inputs.entries) {
        final step = _laneEditOn(
          layer,
          now,
          (laneId: laneId, frame: frame),
          _valueEdits(laneId, input, scaleLinked: values.scaleLinked),
        );
        written = written.then(step);
        now = now.after(step);
      }
    }
    return written.isEmpty ? null : written;
  }

  /// The ONE dispatch behind every lane verb at a frame: which of a row's
  /// keyed families [laneId] names, the row and frame to edit it on, and
  /// what [edits] leaves that family at — or null when it changes nothing.
  /// Committing it and showing it are the caller's.
  ({Layer layer, LaneEdit edit})? _laneEditAt(
    LayerId layerId,
    String laneId,
    int frameIndex, {
    required bool frameIsGlobal,
    required _LaneEdits edits,
  }) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null) {
      return null;
    }
    final frame = _laneVerbFrameAt(
      layerId,
      frameIndex,
      frameIsGlobal: frameIsGlobal,
    );
    final edit = _laneEditOn(
      layer,
      laneEditSubjectOf(layer),
      (laneId: laneId, frame: frame),
      edits,
    );
    return edit.isEmpty ? null : (layer: layer, edit: edit);
  }

  /// What [edits] leaves the family of [from] that [cell]'s lane names at,
  /// on its frame of [layer]'s row — [from] the row's keys as they stand,
  /// or as an edit before this one in the same step leaves them.
  LaneEdit _laneEditOn(
    Layer layer,
    LaneEditSubject from,
    ({String laneId, int frame}) cell,
    _LaneEdits edits,
  ) {
    final (:laneId, :frame) = cell;
    // R5 #7: the name tag is a fixed FIELD on the row, so it lands through
    // its own funnel — not the transform track, not the chain.
    if (laneIsSeNameTag(laneId)) {
      return LaneEdit(
        nameTag: edits.nameTag(from.seNameTag ?? const SeNameTag(), frame),
      );
    }
    // I-140: so is the row's sound.
    if (laneIsSeSound(laneId)) {
      return LaneEdit(
        sound: edits.sound(from.seSound ?? const SeSound(), frame),
      );
    }
    if (parseEffectLaneId(laneId) != null) {
      return LaneEdit(effects: edits.effects(layer, from.effects, frame));
    }
    // A reference's fx is a transform's lanes in another home (F-374).
    final reference = laneIsReference(laneId);
    final next = edits.transform(
      layer,
      reference
          ? (from.referenceFx ?? TransformTrack.empty())
          : from.transformTrack,
      frame,
      reference: reference,
    );
    return LaneEdit(
      transform: next == null
          ? (own: null, reference: null)
          : _transformHomesWith(next, reference: reference),
    );
  }

  /// Writes [target] as one undo step — after dropping any lane edit in
  /// flight, since this is the release that edit was showing.
  void _commitLaneEdit(
    ({Layer layer, LaneEdit edit})? target, {
    required String description,
  }) {
    endLaneEditPreview();
    if (target != null) {
      _commitRowLanes(target.layer, target.edit, description: description);
    }
  }

  /// Shows [target] on the preview channel — the committed row when it is
  /// null.
  void _previewLaneEdit(({Layer layer, LaneEdit edit})? target) {
    if (target == null) {
      endLaneEditPreview();
      return;
    }
    _dragPreview.value = _laneEditPreview(target.layer, target.edit);
  }

  /// A canvas handle's drag landing on [layerId]'s transform: [edit] writes
  /// ONE key at the playhead (the AE rule), committed as one undo — and the
  /// handle's preview dropped with it.
  ///
  /// 🚨F-102: the handles wrote the ACTIVE row back as they found it, and a
  /// track-SE row's active row is its cut-local clone — so in any cut but
  /// the first, a drag put cut-local keys on the global axis and erased the
  /// keys of earlier cuts. [edit] is handed the track the project holds and
  /// the playhead on that track's own axis.
  void editLayerTransformAtPlayhead(
    LayerId layerId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit, {
    required String description,
  }) => _editAtPlayhead(
    layerId,
    edit,
    reference: false,
    description: description,
  );

  /// A canvas handle mid-drag: the edit [editLayerTransformAtPlayhead]
  /// would write at the release, shown on the preview channel (F-195) — the
  /// same [edit] of the same track at the same frame.
  void previewLayerTransformAtPlayhead(
    LayerId layerId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit,
  ) => _previewAtPlayhead(layerId, edit, reference: false);

  /// A canvas box's drag landing on [layerId]'s REFERENCE FX (I-68): the
  /// same ONE key at the playhead a transform's box writes (F-374 — 유저
  /// 「지금 움직여도 키 안생긴다거나 … 싹 통일」), one undo.
  void editReferenceFxAtPlayhead(
    LayerId layerId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit, {
    required String description,
  }) => _editAtPlayhead(
    layerId,
    edit,
    reference: true,
    description: description,
  );

  /// The reference box mid-drag: the edit [editReferenceFxAtPlayhead]
  /// would write at the release, shown on the preview channel.
  void previewReferenceFxAtPlayhead(
    LayerId layerId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit,
  ) => _previewAtPlayhead(layerId, edit, reference: true);

  /// A canvas box's drag landing on the keys effect lane [laneId] of
  /// [layerId] keeps as a transform's — where its effect stands its
  /// picture (F-477), or a point (I-132-Q12 b): the same ONE key at the
  /// playhead a transform's box writes, on the effect's own Position and
  /// Scale — one undo.
  void editEffectKeysAtPlayhead(
    LayerId layerId,
    String laneId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit, {
    required String description,
  }) => _commitLaneEdit(
    _effectKeysEditAtPlayhead(layerId, laneId, edit),
    description: description,
  );

  /// The effect's box mid-drag: the edit [editEffectKeysAtPlayhead] would
  /// write at the release, shown on the preview channel.
  void previewEffectKeysAtPlayhead(
    LayerId layerId,
    String laneId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit,
  ) => _previewLaneEdit(_effectKeysEditAtPlayhead(layerId, laneId, edit));

  /// [edit] of the keys effect lane [laneId] keeps as a transform's, at
  /// the playhead on [layerId]'s own axis — through the one dispatch every
  /// lane verb takes ([_laneEditAt]).
  ({Layer layer, LaneEdit edit})? _effectKeysEditAtPlayhead(
    LayerId layerId,
    String laneId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit,
  ) => _laneEditAt(
    layerId,
    laneId,
    _controllers.timelineController.currentFrameIndex,
    frameIsGlobal: false,
    edits: (
      nameTag: (_, _) => null,
      sound: (_, _) => null,
      effects: (_, effects, frame) => effectsWithTransformKeysEdited(
        effects,
        laneId,
        (keys) => edit(keys, frame),
      ),
      transform: (_, _, _, {required reference}) => null,
    ),
  );

  /// [edit] of [layerId]'s transform track — its reference fx's where
  /// [reference] says — at the playhead on the row's own axis, committed as
  /// one undo, any lane edit in flight dropped with it.
  void _editAtPlayhead(
    LayerId layerId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit, {
    required bool reference,
    required String description,
  }) {
    endLaneEditPreview();
    final layer = laneVerbLayerFor(layerId);
    if (layer == null) {
      return;
    }
    _commitTransformHomes(
      layer,
      _transformHomesWith(
        edit(
          _transformTrackAt(layer, reference: reference),
          _laneVerbFrameFor(layerId),
        ),
        reference: reference,
      ),
      description: description,
    );
  }

  /// [_editAtPlayhead]'s edit, shown on the preview channel and not written.
  void _previewAtPlayhead(
    LayerId layerId,
    TransformTrack Function(TransformTrack track, int frameIndex) edit, {
    required bool reference,
  }) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null) {
      return;
    }
    _dragPreview.value = _laneEditPreview(
      layer,
      LaneEdit(
        transform: _transformHomesWith(
          edit(
            _transformTrackAt(layer, reference: reference),
            _laneVerbFrameFor(layerId),
          ),
          reference: reference,
        ),
      ),
    );
  }

  /// WHAT a lane edit on [layer] edits — the homes its families land in and
  /// show in, answered by the same funnels every verb here commits and
  /// previews through. The range move asks for it ([LaneEditSubject]), and
  /// so does every verb over a span ([_laneVerbScope]).
  LaneEditSubject laneEditSubjectOf(Layer layer) => LaneEditSubject(
    transformTrack: _laneTransformTrackOf(layer),
    referenceFx: layer.mediaReference?.fx,
    effects: layer.effects,
    // The name tag (C①) only on SE rows: its write throws elsewhere. The
    // layer is GLOBAL for a track-SE row ([laneVerbLayerFor]), so the tag
    // goes home as it is.
    seNameTag: layer.kind == LayerKind.se
        ? (layer.seNameTag ?? const SeNameTag())
        : null,
    seSound: layer.kind == LayerKind.se ? layer.seSound : null,
    commit: (next, why) => _commitRowLanes(layer, next, description: why),
    preview: (next) => _laneEditPreview(layer, next),
  );

  /// An effect header's eyeball (R6): [effectId] switched on or off in
  /// [layerId]'s chain, one undo — read off the row the project holds, like
  /// every other write to the chain.
  void toggleLaneEffectEnabled(
    LayerId layerId,
    EffectId effectId, {
    required String description,
  }) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null) {
      return;
    }
    final next = effectsWithEnabledToggled(layer.effects, effectId);
    if (next != null) {
      _commitLaneEffects(layer, next, description: description);
    }
  }

  /// A group header's switch, whichever group the header names: the
  /// Transform group's is the row's own field (R8), an effect's is that
  /// effect's eyeball (R6), and a group with no switch does nothing.
  ///
  /// One dispatch for every rail that draws a header. The timeline host held
  /// it alone, so the storyboard's S rows had no switch to press (F-101).
  void toggleLaneGroupEnabled(
    LayerId layerId,
    String headerLaneId, {
    required String description,
  }) {
    if (headerLaneId == transformGroupHeaderLane.laneId) {
      _effectsAndFx.toggleLayerTransformFx(layerId);
      return;
    }
    final effectId = parseEffectLaneId(headerLaneId)?.effectId;
    if (effectId != null) {
      toggleLaneEffectEnabled(layerId, effectId, description: description);
    }
  }

  /// Whether the switch [toggleLaneGroupEnabled] flips for [headerLaneId]
  /// is on RIGHT NOW, dispatched as that flip dispatches; null where the
  /// header names no switch.
  ///
  /// 🚨A LIVE READ: a lane row built at the last frame carries a stale
  /// `groupEnabled`, and the rail's bulk-drag has to spread what the press
  /// just set. ↩️The rail read the layer's TRANSFORM flag for every lane
  /// row, so a sweep begun on an effect header spread the transform's
  /// state instead of the effect's (I-89 ①ⓒ).
  bool? isLaneGroupOn(LayerId layerId, String headerLaneId) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null) {
      return null;
    }
    if (headerLaneId == transformGroupHeaderLane.laneId) {
      return layer.transformEnabled;
    }
    final effectId = parseEffectLaneId(headerLaneId)?.effectId;
    for (final effect in layer.effects) {
      if (effect.id == effectId) {
        return effect.enabled;
      }
    }
    return null;
  }

  /// Whether [laneId] of [layerId] holds a key at [frameIndex] — what its
  /// ◆ shows — as the project holds it NOW ([_laneNowAt]). [frameIsGlobal]:
  /// see [_laneVerbFrameAt].
  ///
  /// 🚨A LIVE READ, as [isLaneGroupOn] is: the rail's bulk-drag spreads
  /// what the press just set (F-475), and a lane row built at the last
  /// frame still carries the keys from before it.
  bool? isLaneKeyedAt(
    LayerId layerId,
    String laneId,
    int frameIndex, {
    required bool frameIsGlobal,
  }) => switch (_laneNowAt(
    layerId,
    laneId,
    frameIndex,
    frameIsGlobal: frameIsGlobal,
  )) {
    (:final lane, :final frame)? => lane.keyedFrames.contains(frame),
    null => null,
  };

  /// [laneId]'s value at [frameIndex] as its row writes it
  /// ([PropertyLaneRow.valueLabel]) — read as [isLaneKeyedAt] is.
  String? laneValueAt(
    LayerId layerId,
    String laneId,
    int frameIndex, {
    required bool frameIsGlobal,
  }) => switch (_laneNowAt(
    layerId,
    laneId,
    frameIndex,
    frameIsGlobal: frameIsGlobal,
  )) {
    (:final lane, :final frame)? => lane.valueLabel?.call(frame),
    null => null,
  };

  /// [laneId] of the row [layerId] names, as the project holds it this
  /// instant ([laneVerbLayerFor]), and the frame [frameIndex] names on it —
  /// the lane its row would show if it were built now, off the lists the
  /// rails draw: the camera row's its cut's camera's
  /// ([cameraPropertyLanes]), every other row's with the lane's own group
  /// open ([propertyLanesForRow]), valued on the row itself.
  ({PropertyLaneRow lane, int frame})? _laneNowAt(
    LayerId layerId,
    String laneId,
    int frameIndex, {
    required bool frameIsGlobal,
  }) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null) {
      return null;
    }
    final group = laneGroupOf(laneId);
    final lanes = layer.kind == LayerKind.camera
        ? cameraPropertyLanes(
            layer,
            _laneTransformTrackOf(layer),
            canvasSize: _cutWriting(layer)?.canvasSize,
          )
        : propertyLanesForRow(
            layer: layer,
            rows: _cutWriting(layer)?.layers ?? const [],
            expandedGroupKeys: {
              if (group != null) laneGroupKey(layer.id, group),
            },
            valueSourceAt: (frame) => (layer: layer, frame: frame),
            poseCentre: null,
          );
    for (final lane in lanes) {
      if (lane.laneId == laneId) {
        return (
          lane: lane,
          frame: _laneVerbFrameAt(
            layerId,
            frameIndex,
            frameIsGlobal: frameIsGlobal,
          ),
        );
      }
    }
    return null;
  }

  /// [track] with [laneId]'s key at [frame] toggled — a new one frozen at
  /// the value [layer] resolves there: where its reference fx stands the
  /// picture, when [reference] says the lane is that fx's (F-374). What the
  /// navigator's ◆ and the range Create both write.
  TransformTrack? _transformTrackWithKeyToggled(
    Layer layer,
    TransformTrack track,
    String laneId,
    int frame, {
    required bool reference,
  }) {
    final pose = reference
        ? layer.mediaReference?.poseAt(frame)
        : _laneResolvedPose(layer, frame);
    if (pose == null) {
      return null;
    }
    // The camera's lanes and a reference fx's are the pose trio alone.
    final poseOnly = reference || layer.kind == LayerKind.camera;
    return transformTrackWithLaneKeyToggled(
      track,
      laneId: laneId,
      frameIndex: frame,
      resolvedPose: pose,
      resolvedAnchorPoint: poseOnly
          ? null
          : _timeline.layerAnchorPointAtFrame(layer, frame),
      resolvedOpacity: poseOnly
          ? 1
          : resolveOpacityTrackAt(layer.transformTrack.opacity, frame),
    );
  }

  /// The lane path's NAME TAG commit — the third funnel, beside
  /// [_commitTransformTrack] and [_commitLaneEffects]. The coordinator
  /// finds an SE row wherever it lives, so the tag goes home as it is.
  void _commitLaneSeNameTag(
    Layer layer,
    SeNameTag tag, {
    required String description,
  }) {
    _project.cutCommandCoordinator.setSeNameTag(
      layerId: layer.id,
      seNameTag: tag,
      description: description,
    );
    _changes.notifyChanged();
  }

  /// The lane path's SOUND commit (I-140) — the name tag's twin: the row's
  /// volume keys and its pan go home together, to the SE row wherever it
  /// lives.
  void _commitLaneSeSound(
    Layer layer,
    SeSound sound, {
    required String description,
  }) {
    _project.cutCommandCoordinator.setSeSound(
      layerId: layer.id,
      seSound: sound,
      description: description,
    );
    _changes.notifyChanged();
  }

  /// Where [layer]'s TRANSFORM lanes live — asked ONCE for the commit and
  /// the preview below, which switch on it exhaustively: a home added here
  /// is a compile error in both until each says what it does there.
  _TransformHome _transformHomeOf(Layer layer) {
    if (layer.kind == LayerKind.camera) {
      return _TransformHome.cutCamera;
    }
    // A V row's carrier has no transform to go home to any more: the row's
    // lanes are its EFFECT chain alone, so a transform edit here would be
    // writing where nothing reads.
    if (trackIdOfTransformLaneCarrier(layer.id) != null) {
      return _TransformHome.nowhere;
    }
    return _TransformHome.row;
  }

  /// The commit of a row's OWN transform lanes — the camera row goes home to
  /// the cut, a V row's carrier to nowhere, every other row to its layer.
  ///
  /// ↩️The lane MOVE spelled the camera-or-layer half of this again inline
  /// (and without the carrier's arm); it commits through here now
  /// (ARCH-session-state, the fifteenth family) — by way of
  /// [laneEditSubjectOf] since F-195, which made this private again.
  void _commitTransformTrack(
    Layer layer,
    TransformTrack track, {
    required String description,
  }) {
    switch (_transformHomeOf(layer)) {
      case _TransformHome.cutCamera:
        if (_cutTakingCamera(layer, track) != null) {
          _updateCameraTrack(layer.id, track, description: description);
        }
      case _TransformHome.nowhere:
        return;
      case _TransformHome.row:
        // No window conversion: [laneVerbLayerFor] hands these verbs the
        // GLOBAL layer for a track-SE row, so the track they edited is
        // already on the axis it belongs to. Converting here would shift it
        // twice.
        updateLayerTransformTrack(layer.id, track, description: description);
    }
  }

  /// THE commit of a row's lanes (F-374): every family [edit] changes,
  /// each through its own funnel, as ONE undo step — a span over lanes of
  /// several is one gesture.
  void _commitRowLanes(
    Layer layer,
    LaneEdit edit, {
    required String description,
  }) => _project.historyManager.runAsOneStep(description, () {
    if (edit.nameTag case final tag?) {
      _commitLaneSeNameTag(layer, tag, description: description);
    }
    if (edit.sound case final sound?) {
      _commitLaneSeSound(layer, sound, description: description);
    }
    if (edit.effects case final effects?) {
      _commitLaneEffects(layer, effects, description: description);
    }
    _commitTransformHomes(layer, edit.transform, description: description);
  });

  /// THE transform commit of a row's lanes, home by home (F-374): its own
  /// lanes through [_commitTransformTrack], a reference row's fx through
  /// [_commitReferenceFx] — one undo step for the two.
  void _commitTransformHomes(
    Layer layer,
    TransformHomes next, {
    required String description,
  }) => _project.historyManager.runAsOneStep(description, () {
    if (next.own case final own?) {
      _commitTransformTrack(layer, own, description: description);
    }
    if (next.reference case final fx?) {
      _commitReferenceFx(layer, fx, description: description);
    }
  });

  /// The REFERENCE FX's commit (F-374): its keys written the moment they
  /// change, as every fx's are. The file is not laid again — the canvas
  /// moves the picture from where it was laid to where the keys stand it
  /// (`referenceMoveAt`), as a transform fx moves its row.
  ///
  /// 🗣️F-374-Q1 (유저 2026-10-17, 「트랜스폼처럼 화면에서 옮긴다」): 「굳이
  /// 다시 그릴필요도없고 그래봣자 더 선명해지지도않음」. ↩️Where the keys
  /// stood the picture still, the file was laid there again and folded into
  /// the same undo step once it landed.
  void _commitReferenceFx(
    Layer layer,
    TransformTrack fx, {
    required String description,
  }) {
    if (layer.mediaReference == null) {
      return;
    }
    _project.cutCommandCoordinator.updateLayerReferenceFx(
      layerId: layer.id,
      fx: fx,
      description: description,
    );
    _changes.notifyChanged();
  }

  /// [edit] on [layer] as a lane edit in flight shows it — the twin of
  /// [_commitRowLanes], home for home: a V row's chain is its TRACK's, the
  /// row's own lanes show where [_ownTransformPreview] says, and every
  /// other family rides on the row, so one row carries them all in flight.
  /// Null where it shows nothing, and where the commit would refuse it: a
  /// range move holds there.
  TimelineDragPreview? _laneEditPreview(Layer layer, LaneEdit edit) {
    final effects = edit.effects;
    final carrierTrackId = trackIdOfTransformLaneCarrier(layer.id);
    if (carrierTrackId != null) {
      return effects == null
          ? null
          : LaneEditPreview.track(
              trackId: carrierTrackId,
              trackEffects: effects,
            );
    }
    var row = effects == null ? layer : layer.copyWith(effects: effects);
    if (edit.nameTag case final tag?) {
      row = row.copyWith(seNameTag: tag);
    }
    if (edit.sound case final sound?) {
      row = row.copyWith(seSound: sound);
    }
    final reference = layer.mediaReference;
    if (edit.transform.reference case final fx? when reference != null) {
      row = row.copyWith(mediaReference: reference.copyWith(fx: fx));
    }
    final own = edit.transform.own;
    return own == null ? _rowPreview(row) : _ownTransformPreview(row, own);
  }

  /// [track] on [layer] as a lane edit in flight shows it — the twin of
  /// [_commitTransformTrack], home for home. Null where it shows nothing,
  /// and where that commit would refuse it: a range move holds there.
  TimelineDragPreview? _ownTransformPreview(Layer layer, TransformTrack track) {
    switch (_transformHomeOf(layer)) {
      case _TransformHome.cutCamera:
        final cut = _cutTakingCamera(layer, track);
        return cut == null
            ? null
            : LaneEditPreview.camera(
                cameraCutId: cut.id,
                cameraTrack: track,
                cameraMarkerLayer: layer.copyWith(),
              );
      case _TransformHome.nowhere:
        return null;
      case _TransformHome.row:
        return _rowPreview(layer.copyWith(transformTrack: track));
    }
  }

  /// Replaces [layerId]'s transform track (the AE Transform lanes on every
  /// drawing layer — applied at composite time, never baked) in the cut
  /// writing it, stood in or not ([ActiveCutEdits.onCutOfRowQuietly]); one
  /// undo step, no-op when unchanged.
  ///
  /// ↩️The session's until the fifteenth family: these verbs were the one
  /// collaborator that asked for it, so it lives beside its funnel.
  /// ↩️Addressed in the cut stood in until I-89-Q23.
  void updateLayerTransformTrack(
    LayerId layerId,
    TransformTrack track, {
    String description = 'Edit layer transform',
  }) => _activeCut.onCutOfRowQuietly(
    layerId,
    (cutId) => _project.cutCommandCoordinator.updateLayerTransformTrack(
      cutId: cutId,
      layerId: layerId,
      transformTrack: track,
      description: description,
    ),
  );

  /// The lane path's EFFECT commit — the twin of [_commitTransformTrack].
  ///
  /// A funnel rather than three call sites: Add, Delete and Reset all
  /// commit chains read off the same layer, and which axis that layer is
  /// on is exactly the kind of step that gets remembered in two places out
  /// of three.
  void _commitLaneEffects(
    Layer layer,
    List<LayerEffect> effects, {
    required String description,
  }) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layer.id);
    if (carrierTrackId != null) {
      _effectsAndFx.updateTrackEffects(
        carrierTrackId,
        effects,
        description: description,
      );
      return;
    }
    _effectsAndFx.updateLayerEffects(
      layer.id,
      effects,
      description: description,
    );
  }

  /// [row] as an edit in flight leaves it, on its OWN axis: what the open cut
  /// shows of it and, for a track-owned row, the track's own form.
  ///
  /// ⛔ONE for all three families (transform, effects, name tag). The
  /// name-tag arm was fixed alone once (d524af02) and the other two went on
  /// publishing the GLOBAL row into the slot that carries the cut's display
  /// clones — so on any non-first cut every diamond of a moving track-SE row
  /// sat a cut's start to the right for the length of the drag.
  TimelineDragPreview _rowPreview(Layer row) {
    final forms = _previewFormsOf(row);
    return LaneEditPreview.row(row: forms.shown, globalRow: forms.global);
  }

  /// The lanes a verb may act on for [layer]. The CAMERA row draws only
  /// position/scale/rotation ([timelineLanesForLayer] builds its lanes
  /// without anchor and opacity), so a GROUP-header span — which expands
  /// to every transform lane — must not key two lanes that row has no way
  /// to show, move or delete.
  List<String> _laneVerbTargetsFor(Layer layer, List<String> targets) {
    if (layer.kind != LayerKind.camera) {
      return targets;
    }
    return targets
        .where((laneId) => laneId != 'anchor-point' && laneId != 'opacity')
        .toList();
  }

  /// The value a lane verb freezes at [frameIndex]. The camera's pose does
  /// not live on the camera pseudo-layer — its own transform track is
  /// permanently empty — so reading [_timeline.layerPoseAtFrame] there froze the
  /// canvas-centre identity pose and snapped the camera mid-move.
  TransformPose _laneResolvedPose(Layer layer, int frameIndex) {
    if (layer.kind != LayerKind.camera) {
      return _timeline.layerPoseAtFrame(layer, frameIndex);
    }
    final cut = _cutWriting(layer);
    if (cut == null) {
      return _timeline.layerPoseAtFrame(layer, frameIndex);
    }
    return TransformPose.ofCamera(
      resolveCameraPoseAt(
        camera: cut.camera,
        canvasSize: cut.canvasSize,
        frameIndex: frameIndex,
      ),
    );
  }

  /// Removes every key the range covers on every spanned lane, whichever
  /// home each lives in — the mirror of [createLaneKeysForSelection], one
  /// undo. Returns whether anything was there to remove.
  bool removeLaneKeysForSelection(TimelineLaneSelection lane) {
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return false;
    }
    final removed = laneKeysRemovedWhere(lane.contains);
    return _commitSpanEdit(
      scope,
      rowLaneHomesEdited(
        scope.subject,
        scope.homes,
        <T>(LaneHome<T> home) => home.edited(removed),
      ),
      description: 'Delete keys',
    );
  }

  /// [edit] of [scope]'s row committed as ONE undo step, when it changes
  /// anything. Returns whether it did.
  bool _commitSpanEdit(
    _SpanScope scope,
    LaneEdit edit, {
    required String description,
  }) {
    if (edit.isEmpty) {
      return false;
    }
    scope.subject.commit(edit, description);
    return true;
  }

  /// What every lane verb over a span settles first: the row the lane range
  /// names (an attach row stands down), the lanes the verb targets, and
  /// those lanes in the homes they live in, whichever families they are of
  /// ([RowLaneHomes], F-374). ↩️It said whether they were EFFECT lanes, and
  /// each verb then worked the effect chain or the transform, never both.
  _SpanScope? _laneVerbScope(TimelineLaneSelection lane) {
    final layer = laneVerbLayerFor(lane.layerId);
    if (layer == null || _wearsBaseFx(layer)) {
      return null;
    }
    final targets = _laneVerbTargetsFor(
      layer,
      laneVerbTargets(lane.spanLaneIds, effects: layer.effects),
    );
    final subject = laneEditSubjectOf(layer);
    return (
      layer: layer,
      targets: targets,
      subject: subject,
      homes: rowLaneHomes(subject, targets),
    );
  }

  /// The keys the LANE RANGE covers, one entry per key, each with the lane
  /// it is on and whether it may give its time up there ([canRove], I-89
  /// ④). Empty when the range holds no key at all.
  ///
  /// The naming gates and the key window's TYPE all read this, so "can I
  /// name here", "what do they already say" and "what type are they"
  /// cannot disagree about which keys the range covers.
  List<_LaneRangeKey> _laneRangeKeys() {
    final lane = laneVerbRange;
    final scope = lane == null ? null : _laneVerbScope(lane);
    if (lane == null || scope == null) {
      return const [];
    }
    final homes = scope.homes;
    // Only a position's keys walk a path, so only a transform's may rove —
    // a row's, its reference fx's, and where an effect stands its picture.
    bool roves(TransformTrack track, String laneId, int frame) =>
        transformLaneKeyCanRove(
          track,
          transformPropertyOfLaneId(laneId)!,
          frame,
        );
    return [
      ..._coveredKeys(homes.own, lane, canRove: roves),
      ..._coveredKeys(homes.reference, lane, canRove: roves),
      ..._coveredKeys(homes.effects, lane, canRove: effectLaneKeyCanRove),
      ..._coveredKeys(homes.nameTag, lane, takesSides: seNameTagLaneTakesSides),
      ..._coveredKeys(homes.sound, lane),
    ];
  }

  /// The keys [lane] covers on [home]'s lanes, each with whether it may
  /// give its time up there — none may where [canRove] does not say — and
  /// whether it takes the key window's sides: all do where [takesSides]
  /// does not say.
  static Iterable<_LaneRangeKey> _coveredKeys<T>(
    LaneHome<T> home,
    TimelineLaneSelection lane, {
    bool Function(T keys, String laneId, int frame)? canRove,
    bool Function(String laneId)? takesSides,
  }) sync* {
    for (final (:laneId, :keys, :walksAPath, shown: _)
        in home.keysWhere(lane.contains)) {
      final sided = takesSides?.call(laneId) ?? true;
      for (final MapEntry(key: frame, value: key) in keys.entries) {
        yield (
          laneId: laneId,
          key: key,
          canRove: canRove?.call(home.keys, laneId, frame) ?? false,
          takesSides: sided,
          walksAPath: walksAPath,
        );
      }
    }
  }

  /// Every lane [lane] reaches ([laneVerbTargets]), with the keys it holds
  /// inside the range by their frame from the range's first — what a copy
  /// of keys banks (F-388, [KeyClipboard]). Null where the range names no
  /// row a lane verb serves.
  List<LaneKeys>? laneKeysCopiedFrom(TimelineLaneSelection lane) {
    final homes = _laneVerbScope(lane)?.homes;
    if (homes == null) {
      return null;
    }
    return [
      for (final home in rowLaneHomesInOrder(homes))
        for (final (:laneId, :keys, :walksAPath, :shown)
            in home.keysWhere(lane.contains))
          (
            laneId: laneId,
            keys: {
              for (final MapEntry(key: frame, value: key) in keys.entries)
                frame - lane.startIndex: key,
            },
            walksAPath: walksAPath,
            shown: shown,
          ),
    ];
  }

  /// What a copy of [lane]'s keys takes ([laneKeysCopiedFrom]) and the
  /// frames it spans — null where the range names no row a lane verb
  /// serves, or holds no key in reach. The key board's copy
  /// ([KeyClipboard]) and a band's ([bandKeysOf]) alike.
  KeyCopy? keyCopyOf(TimelineLaneSelection lane) {
    final lanes = laneKeysCopiedFrom(lane);
    return lanes != null && lanes.any((lane) => lane.keys.isNotEmpty)
        ? (lanes: lanes, length: lane.lengthFrames)
        : null;
  }

  /// What a copy of the live band takes of [layerId]'s lane rows
  /// ([_bandLaneSpans]) — the keys a frame copy banks beside that row's
  /// cells (🗣️one-band-no-lane-tail-Q1: 「띠의 칸(블록)과 띠의 레인 행 키를
  /// 한 복사본에 같이 싣는다」). Null where the band holds none of its lanes,
  /// or no key on them.
  KeyCopy? bandKeysOf(LayerId layerId) {
    for (final lane in _bandLaneSpans()) {
      if (lane.layerId == layerId) {
        return keyCopyOf(lane);
      }
    }
    return null;
  }

  /// What a copy of the live band takes of the lane rows of layers whose
  /// cells it does not take ([cellRows] — those it takes with their cells,
  /// [bandKeysOf]): a layer it swept only the lanes of, and the camera row.
  ///
  /// 🗣️one-band-no-lane-tail-Q3 (유저 2026-10-27) chose 「그 레이어 자신에게」,
  /// the option that reads 「레인만 든 레이어의 키도 싣고, 붙여넣으면 같은 레이어
  /// · 같은 레인에, 띠 첫 칸에서의 간격 그대로 놓는다(카메라 행이면 서 있는 컷의
  /// 카메라)」. ↩️The copy took the keys beside the cells it took, and left
  /// these.
  List<LanesAlone> bandKeysBesides(Set<LayerId> cellRows) => [
    for (final lane in _bandLaneSpans())
      if (!cellRows.contains(lane.layerId))
        if (keyCopyOf(lane) case final keys?)
          (
            layerId: lane.layerId,
            camera: _isCameraRow(lane.layerId),
            keys: keys,
          ),
  ];

  /// The row [lanes] lands on in the cut stood in: its own layer, or the
  /// cut's camera for a camera's (Q3's option: 「서 있는 컷의 카메라」) — null
  /// where the row is another cut's (its cost: 「다른 컷에 붙여넣으면 그
  /// 레이어가 없어 그 키는 놓이지 않는다」), though a lane verb would write it
  /// there ([ActiveCutEdits.cutOfRow], I-89-Q23). A track's own row is every
  /// cut's.
  LayerId? rowOfLanesAlone(LanesAlone lanes) {
    final cut = _project.activeCutOrNull;
    final id = lanes.camera ? cut?.layers.cameraLayer?.id : lanes.layerId;
    return id != null && _activeCut.cutOfRow(id) == cut?.id ? id : null;
  }

  /// [copy]'s lanes on [layerId] from [start]: the lanes it was copied off,
  /// by their ids, over the frames it spans.
  static TimelineLaneSelection _lanesOfCopyOn(
    LayerId layerId,
    KeyCopy copy, {
    required int start,
  }) => TimelineLaneSelection(
    layerId: layerId,
    laneId: copy.lanes.first.laneId,
    startIndex: start,
    endIndexExclusive: start + copy.length,
    laneIds: [for (final lane in copy.lanes) lane.laneId],
  );

  /// [copy]'s keys put down on [layerId]'s lanes of the ids they were copied
  /// off, from [start] with the [liftCount] frames there replaced — beside
  /// the cells a paste of a band's copy lays on that row (🗣️
  /// one-band-no-lane-tail-Q1: 「붙여넣으면 서 있는 칸에 블록, 그 레이어의
  /// 같은 레인에 키」), by the key paste's own law ([_keysPastedOver]); with
  /// [keepNames], the 링크 붙여넣기's. Its own step: the caller holds the
  /// one undo.
  void pasteKeysOnRow(
    LayerId layerId,
    KeyCopy copy, {
    required ({int index, int liftCount}) at,
    required bool keepNames,
    required String description,
  }) {
    if (_keysPastedOver(
          _lanesOfCopyOn(layerId, copy, start: at.index),
          copy,
          liftCount: at.liftCount,
          keepNames: keepNames,
        )
        case final pasted?) {
      _commitSpanEdit(pasted.scope, pasted.edit, description: description);
    }
  }

  /// The names a 링크 붙여넣기 of [copy] on [layerId] ([pasteKeysOnRow])
  /// would join at another value — what it asks about first.
  Set<String> keyNamesJoinedOnRow(
    LayerId layerId,
    KeyCopy copy, {
    required ({int index, int liftCount}) at,
  }) =>
      _keysPastedOver(
        _lanesOfCopyOn(layerId, copy, start: at.index),
        copy,
        liftCount: at.liftCount,
        keepNames: true,
      )?.joins ??
      const {};

  /// The keys [copy] was taken of, off [layerId]'s lanes from [start] —
  /// what a 잘라내기 of a band lifts beside the cells it lifts: only what it
  /// banked (결정 14 ②ⓐ), leaving a hole as the cells' lift does (⑳). Its
  /// own step: the caller holds the one undo.
  void liftKeysOnRow(LayerId layerId, KeyCopy copy, {required int start}) =>
      removeLaneKeysForSelection(_lanesOfCopyOn(layerId, copy, start: start));

  /// 독립 붙여넣기 of [copy] where the press stands ([laneVerbRange]), as a
  /// frame paste puts its run down ([laneKeysSpliced]): a selection
  /// replaced, standing in at the playhead — each key unnamed, a value of
  /// its own (유저 확정, of frames: 「독립 붙여넣기 = 그냥 복제」). One undo
  /// (F-388).
  void pasteLaneKeys(KeyCopy copy) {
    if (_laneKeysPasted(copy, keepNames: false) case final pasted?) {
      _commitSpanEdit(pasted.scope, pasted.edit, description: 'Paste keys');
    }
  }

  /// Whether a paste of [copy] puts any of it down here.
  bool canPasteLaneKeys(KeyCopy copy) =>
      _laneKeysPasted(copy, keepNames: false) != null;

  /// 링크 붙여넣기 of [copy]: [pasteLaneKeys] with each key's name kept. A
  /// name the lane's naming space holds already is that name's key there,
  /// so the key pasted under it takes what it holds — as a frame pasted
  /// under a name its row holds shows the row's drawing (I-71). Where that
  /// would put down another value than the copied one and [joinTakenNames]
  /// was not given, this writes NOTHING and hands back the names, for the
  /// caller to ask about once; null when it pasted, or had nothing to do.
  ///
  /// 🗣️F-388-Q2 (유저 2026-10-20): 「이름 있는 키만 링크 — 그냥
  /// 생각할것도없이 프레임블록 복붙이랑 똑같은 규칙」: an unnamed key has no
  /// name to link by and goes down as its value.
  Set<String>? pasteLinkedLaneKeys(
    KeyCopy copy, {
    bool joinTakenNames = false,
  }) {
    final pasted = _laneKeysPasted(copy, keepNames: true);
    if (pasted == null) {
      return null;
    }
    if (!joinTakenNames && pasted.joins.isNotEmpty) {
      return pasted.joins;
    }
    _commitSpanEdit(
      pasted.scope,
      pasted.edit,
      description: 'Paste linked keys',
    );
    return null;
  }

  /// What a paste of [copy] here writes, and with [keepNames] the names it
  /// joins at another value — null where it lands nothing: one answer for
  /// the gate and the press (I-19/T25). The camera's keys stay in its cut
  /// ([_cameraLastFrameOf]).
  ({_SpanScope scope, LaneEdit edit, Set<String> joins})? _laneKeysPasted(
    KeyCopy copy, {
    required bool keepNames,
  }) {
    final lane = laneVerbRange;
    return lane == null
        ? null
        : _keysPastedOver(
            lane,
            copy,
            liftCount: _selectedLaneSpan == null ? 0 : lane.lengthFrames,
            keepNames: keepNames,
          );
  }

  /// What a paste of [copy] on [lane]'s lanes from its first frame writes,
  /// the [liftCount] frames there replaced ([laneKeysSpliced]) — null where
  /// it lands nothing. The press's lanes ([_laneKeysPasted]) and a band
  /// copy's row ([pasteKeysOnRow]) alike.
  ({_SpanScope scope, LaneEdit edit, Set<String> joins})? _keysPastedOver(
    TimelineLaneSelection lane,
    KeyCopy copy, {
    required int liftCount,
    required bool keepNames,
  }) {
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return null;
    }
    final pasted = _keysSplicedInto(
      scope,
      _keysPairedWith(copy.lanes, _pasteTargetsOf(scope.homes)),
      (
        start: lane.startIndex,
        liftCount: liftCount,
        length: copy.length,
        last: _cameraLastFrameOf(scope.layer),
      ),
      keepNames: keepNames,
    );
    return pasted.edit.isEmpty
        ? null
        : (scope: scope, edit: pasted.edit, joins: pasted.joins);
  }

  /// [paired]'s keys put in on [scope]'s lanes over [span]
  /// ([laneKeysSpliced]) — with the names they join at another value
  /// ([keepNames]).
  ({LaneEdit edit, Set<String> joins}) _keysSplicedInto(
    _SpanScope scope,
    Map<_PastedLane, Map<int, PropertyKey<Object?>>> paired,
    KeysSplice span, {
    required bool keepNames,
  }) {
    final homes = scope.homes;
    final lifted = {
      for (var frame = 0; frame < span.liftCount; frame += 1)
        span.start + frame,
    };
    final holders = _nameHoldersOf(scope);
    final joins = <String>{};
    // [home]'s lanes with their keys put down — named keys as the name's
    // key there ([heldOf]: what holds a name on a lane of it, or null).
    T? pastedOn<T>(
      LaneHome<T> home,
      PropertyKey<Object?>? Function(String laneId, String name) heldOf,
    ) => home.editedEach(
      (laneId) => switch (paired[(home: home, laneId: laneId)]) {
        null => null,
        final keys => laneKeysSpliced(
          splice: span,
          keys: {
            for (final MapEntry(key: frame, value: key) in keys.entries)
              frame: _pastedKey(
                key,
                keepNames ? (name) => heldOf(laneId, name) : null,
                joins,
              ),
          },
        ),
      },
    );
    PropertyKey<Object?>? Function(String, String) namedIn<T>(
      LaneHome<T> home,
      T? Function(String laneId, String name, Set<int> frames) holder,
    ) => (laneId, name) =>
        _keyNamed(home, laneId, holder(laneId, name, lifted), name);
    final edit = LaneEdit(
      transform: (
        own: pastedOn(homes.own, namedIn(homes.own, holders.own)),
        reference: pastedOn(
          homes.reference,
          namedIn(homes.reference, holders.reference),
        ),
      ),
      effects: pastedOn(
        homes.effects,
        (laneId, name) => holders.effects(laneId, name, lifted),
      ),
      nameTag: scope.subject.nameTagWith(
        pastedOn(homes.nameTag, namedIn(homes.nameTag, holders.nameTag)),
      ),
      sound: pastedOn(homes.sound, namedIn(homes.sound, holders.sound)),
    );
    return (edit: edit, joins: joins);
  }

  /// Every lane of [homes], each with the home it lives in — what a paste
  /// of keys pairs its lanes with ([_keysPairedWith]), in the order a copy
  /// reads them ([laneKeysCopiedFrom]).
  static List<_PastedLane> _pasteTargetsOf(RowLaneHomes homes) => [
    for (final home in rowLaneHomesInOrder(homes))
      for (final laneId in home.laneIds) (home: home, laneId: laneId),
  ];

  /// [key] as a paste puts it down: with no name kept ([heldOf] null) or
  /// none to keep, unnamed — a value of its own; under a name its lane
  /// holds already, that name's key ([_joined]); else as it was copied.
  static PropertyKey<Object?> _pastedKey(
    PropertyKey<Object?> key,
    PropertyKey<Object?>? Function(String name)? heldOf,
    Set<String> joins,
  ) {
    final name = key.name;
    if (heldOf == null || name == null) {
      return key.copyWith(name: () => null);
    }
    final held = heldOf(name);
    return held == null ? key : _joined(key, held, joins);
  }

  /// The key called [name] on [laneId] of [home]'s keys [holder] — null
  /// where nothing holds the name.
  static PropertyKey<Object?>? _keyNamed<T>(
    LaneHome<T> home,
    String laneId,
    T? holder,
    String name,
  ) => holder == null
      ? null
      : home
            .lensOf(laneId)
            ?.keysOf(holder)
            .values
            .where((key) => key.name == name)
            .firstOrNull;

  /// [key] under a name [held] already holds: the held key's value, sides,
  /// path and time, and its own name — [joins] taking the name where that
  /// is another value than the key's own.
  static PropertyKey<Object?> _joined(
    PropertyKey<Object?> key,
    PropertyKey<Object?> held,
    Set<String> joins,
  ) {
    if (held.held != key.held) {
      joins.add(key.name!);
    }
    return key.withHeld(held.held);
  }

  /// Which of [targets] takes which lane of [copied] — 🚨THE FRAME PASTE'S
  /// PAIRING (결정 14 ③ⓐ): a copied lane goes on its own lane where that is
  /// among them; where none is, ONE copied lane goes on every target (「모든
  /// 행에 같은 것을」) and several pair with them in order, as a frame copy's
  /// rows pair with a band's. A lane of another kind of data takes nothing
  /// ([_sameKind]); one of the same kind takes each number as the copied
  /// lane shows it ([LaneHome.numbersTaken] — as its own row said where it
  /// was copied, [LaneKeys.shown]).
  /// 🗣️key-paste-across-lanes-keeps-the-raw-value-Q1 (유저 2026-10-22):
  /// 「회전 · 불투명도 · 이펙트의 숫자끼리는 숫자 그대로」 — ↩️the number
  /// HELD went across, so an opacity of 78.5% put on a rotation made 0.79°,
  /// and a rotation of 19.5° held 19.5 on an opacity, past its 0–1 (shown
  /// 100% — 서피스 실기, 10-23).
  static Map<_PastedLane, Map<int, PropertyKey<Object?>>> _keysPairedWith(
    List<LaneKeys> copied,
    List<_PastedLane> targets,
  ) {
    final byId = {for (final lane in copied) lane.laneId: lane.keys};
    if (targets.any((target) => byId.containsKey(target.laneId))) {
      return {
        for (final target in targets) target: ?byId[target.laneId],
      };
    }
    LaneKeys? pairedAt(int index) =>
        copied.length == 1 ? copied.single : copied.elementAtOrNull(index);
    return {
      for (final (index, target) in targets.indexed)
        if (pairedAt(index) case final lane? when _sameKind(lane, target))
          target: target.home.numbersTaken(
            target.laneId,
            lane.keys,
            lane.shown,
          ),
    };
  }

  /// Whether keys copied on lane [from] mean on lane [to] what they meant
  /// there — AE's 「the same type of data」: a place in space
  /// ([LaneHome.walksAPath] — a position or an anchor, a reference's too,
  /// where an effect stands its picture and an effect's point) on a place,
  /// any other on any other of its value type ([laneKeysSpliced]).
  /// 🗣️key-paste-across-lanes-keeps-the-raw-value-Q1 (유저 2026-10-22):
  /// 「AE 그대로 — 같은 종류의 데이터끼리」 — a position's 1170 put on a
  /// scale made it 117000%.
  static bool _sameKind(LaneKeys from, _PastedLane to) =>
      from.walksAPath == to.home.walksAPath(to.laneId);

  /// The names the range's keys carry — null for an unnamed one.
  Set<String?> _laneRangeKeyNames() => {
    for (final (:key, laneId: _, canRove: _, takesSides: _, walksAPath: _)
        in _laneRangeKeys())
      key.name,
  };

  /// Whether the lane range has a key to name — Edit Instance's gate on a
  /// property row.
  bool get canNameLaneKeys => _laneRangeKeyNames().isNotEmpty;

  /// The name the range's keys AGREE on, or null when they disagree (or
  /// none is named) — what the rename dialog opens with.
  ///
  /// Same rule the group header shows (user 2026-07-30: "내부 이름이 전부
  /// 같으면 그 이름, 다르면 …"), said once so the field and the header
  /// cannot drift.
  String? get laneKeyNameForSelection {
    final names = _laneRangeKeyNames();
    return names.length == 1 ? names.first : null;
  }

  /// The sides of every key the range covers that takes them — what the key
  /// window's two rows open with (I-89 ②): a choice is lit where the keys
  /// all are that kind ([keySidesTogether]), so nothing is lit where they
  /// disagree, by the rule the name above follows (and the ◉ the group
  /// header draws where its members disagree). A name tag's flag holds by
  /// nature, so its keys are not asked (#902).
  List<({KeySide incoming, KeyExit outgoing})> get laneKeySidesForSelection => [
    for (final (:key, :takesSides, laneId: _, canRove: _, walksAPath: _)
        in _laneRangeKeys())
      if (takesSides) (incoming: key.incoming, outgoing: key.outgoing),
  ];

  /// The paths of the keys the range covers on a lane whose keys walk one
  /// ([walksAPath]) — what the key window's path row opens with (I-89 ④),
  /// lit where they agree as the sides are. Empty where no covered key
  /// walks a path: the row is offered and refused.
  List<KeyPath> get laneKeyPathsForSelection => [
    for (final (:key, :walksAPath, laneId: _, canRove: _, takesSides: _)
        in _laneRangeKeys())
      if (walksAPath) key.path,
  ];

  /// Whether each key the range covers that may give its time up roves
  /// ([transformLaneKeyCanRove]) — what the key window's roving row opens
  /// with (I-89 ④), lit where they agree as the sides are. Empty where no
  /// covered key may — the first and the last keep their time, and only a
  /// position's keys walk a path: the row is offered and refused.
  List<bool> get laneKeyRovingForSelection => [
    for (final (:key, :canRove, laneId: _, takesSides: _, walksAPath: _)
        in _laneRangeKeys())
      if (canRove) key.roving,
  ];

  /// Whether the sides the key window picks count on a key the range
  /// covers, the window's roving row picked as [roves] says — on every key
  /// but one whose time roves: the pace through it is the one its run's
  /// timed ends set, and its mark is the roving pill, no sides — and but a
  /// name tag's flag's, which holds by nature (#902). Where they count on
  /// none, the window's two rows are offered and refused (유저 2026-10-12:
  /// 「설정한 시작/끝 보간이 의미가 있다면 비활성화 안되는게 맞고. 의미가
  /// 없다면 비활성화 시키는게 맞겟고」).
  ///
  /// The keys are read once: the window asks again at every pick.
  bool Function(bool? roves) get laneKeySidesCountForSelection {
    final keys = _laneRangeKeys();
    return (roves) => keys.any(
      (covered) =>
          covered.takesSides &&
          (!covered.canRove || !(roves ?? covered.key.roving)),
    );
  }

  /// Names every key the LANE RANGE covers, on every lane it spans — the
  /// range form of [setLaneKeyName], committed as ONE undo step.
  ///
  /// Scope is [laneVerbRange]'s, the same one Add and Delete Key take: a
  /// live lane span, or the row you are STANDING on as a one-frame span at
  /// the playhead. Expressing the single key as a one-frame span is what
  /// makes this the ONLY naming path the UI needs (user 2026-08-10:
  /// "선택범위로 통하는 조작이 모두 다른것들이랑 동일한 로직").
  ///
  /// ★The covered keys of ONE lane end up at ONE value, which is the point
  /// rather than a side effect: a name MEANS "same value", so asking for
  /// one name across five keys is asking for exactly that. Lanes stay
  /// separate spaces, so a span across a whole pose leaves Position and
  /// Rotation each with their own single value.
  ///
  /// Returns true when [name] is ALREADY taken OUTSIDE the range and
  /// NOTHING was written — the caller asks ONCE for the whole range and
  /// then calls [linkLaneKeyNamesForSelection].
  ///
  /// [pick], when it picks anything, lands on the same keys in the same
  /// undo step — the key window's TYPE (F-17, 유저 2026-09-01: 「이름변경이랑
  /// 오른쪽에 유니언 타입 변경 두개 존재하도록」), its path and roving half on
  /// the keys that walk one (I-89 ④).
  bool setLaneKeyNamesForSelection(
    String? name, {
    KeyTypePick pick = const KeyTypePick(),
  }) => _writeLaneKeysForSelection(
    naming: (name: name, adopt: false),
    pick: pick,
  );

  /// Joins [name] across the range, ADOPTING the value it already holds —
  /// the answer to the "합칠까요?" [setLaneKeyNamesForSelection] raises.
  void linkLaneKeyNamesForSelection(
    String name, {
    KeyTypePick pick = const KeyTypePick(),
  }) => _writeLaneKeysForSelection(
    naming: (name: name, adopt: true),
    pick: pick,
  );

  /// The TYPE alone, on the keys the range covers — what the key window
  /// still owes when its name stood down (a taken name the user chose not
  /// to join): the type was confirmed in the same window.
  void setLaneKeyTypeForSelection(KeyTypePick pick) =>
      _writeLaneKeysForSelection(pick: pick);

  /// The key window's TYPE while it is being picked: what
  /// [setLaneKeyTypeForSelection] would write for [pick], shown and not
  /// written — the same write, not a look-alike, as a graph handle's in
  /// flight ([previewLaneKeySidesAt]). An empty pick shows the committed
  /// row.
  ///
  /// 🗣️F-389 (유저 2026-10-17): 「키에 관한 리니어 등 타입 편집, 세기편집이
  /// 라이브로 화면이나 그래프에도 보이도록」.
  void previewLaneKeyTypeForSelection(KeyTypePick pick) {
    final lane = laneVerbRange;
    _previewLaneEdit(
      lane == null || pick.isEmpty
          ? null
          : _laneKeysWriteOver(lane, pick: pick).edit,
    );
  }

  /// The shared body: [_laneKeysWriteOver] the lane range, committed as one
  /// undo step — or nothing, and true, when a name is taken. Stopping
  /// before any commit is what makes the confirmation honest — nothing is
  /// half-written while the dialog is up.
  bool _writeLaneKeysForSelection({
    _LaneKeyNaming? naming,
    KeyTypePick pick = const KeyTypePick(),
  }) {
    final lane = laneVerbRange;
    if (lane == null) {
      return false;
    }
    final write = _laneKeysWriteOver(lane, naming: naming, pick: pick);
    if (write.taken) {
      return true;
    }
    _commitLaneEdit(
      write.edit,
      description: switch (naming) {
        null => 'Set key type',
        (name: null, adopt: _) => 'Unname keys',
        _ => 'Name keys',
      },
    );
    return false;
  }

  /// What naming and typing the keys [lane] covers leaves its row at, on
  /// every lane it spans — the key window's write, and a graph handle's
  /// (I-89 ③) — or no edit where it changes nothing. [taken] stops it at
  /// the FIRST lane whose name is taken, unless the [naming] adopts what
  /// holds it: then there is no edit either.
  ///
  /// No [naming] leaves every name as it is: the TYPE alone — [pick]'s
  /// sides, and its path and roving time on the lanes whose keys walk one.
  ({bool taken, ({Layer layer, LaneEdit edit})? edit}) _laneKeysWriteOver(
    TimelineLaneSelection lane, {
    _LaneKeyNaming? naming,
    KeyTypePick pick = const KeyTypePick(),
  }) {
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return (taken: false, edit: null);
    }
    final layer = scope.layer;
    final homes = scope.homes;
    final holders = _nameHoldersOf(scope);
    final asked = naming?.name;
    final adopt = naming?.adopt ?? false;
    final named = naming == null
        ? null
        : (name: asked, preferredFrame: _laneVerbFrameFor(lane.layerId));

    // Every lane is READ before any is written — the keys it covers, and
    // what already holds the name ([_nameHoldersOf]) — so a taken name
    // stops the verb while the range is still untouched.
    var taken = false;
    T? written<T, H extends Object>(
      LaneHome<T> home,
      H? Function(String laneId, Set<int> frames) holderOf,
      T? Function(T keys, String laneId, Set<int> frames, H? holder) write,
    ) {
      if (taken) {
        return null;
      }
      final reads = <String, ({Set<int> frames, H? holder})>{};
      for (final laneId in home.laneIds) {
        final frames = {
          ...?home.lensOf(laneId)?.keyFrames(home.keys).where(lane.contains),
        };
        if (frames.isEmpty) {
          continue;
        }
        final holder = asked == null ? null : holderOf(laneId, frames);
        if (holder != null && !adopt) {
          taken = true;
          return null;
        }
        reads[laneId] = (frames: frames, holder: holder);
      }
      return foldedEdits(home.keys, reads.keys, (keys, laneId) {
        final read = reads[laneId]!;
        return write(keys, laneId, read.frames, read.holder);
      });
    }

    TransformTrack? transformWritten(
      TransformTrack keys,
      String laneId,
      Set<int> frames,
      TransformTrack? holder,
    ) => transformTrackWithLaneKeysWritten(
      keys,
      laneId: laneId,
      frames: frames,
      naming: named,
      adoptFrom: holder,
      pick: pick,
    );
    final edit = LaneEdit(
      transform: (
        own: written(
          homes.own,
          (laneId, frames) => holders.own(laneId, asked!, frames),
          transformWritten,
        ),
        reference: written(
          homes.reference,
          (laneId, frames) => holders.reference(laneId, asked!, frames),
          transformWritten,
        ),
      ),
      effects: written(
        homes.effects,
        (laneId, frames) => holders.effects(laneId, asked!, frames),
        (effects, laneId, frames, adopted) => effectsWithLaneKeysWritten(
          effects,
          laneId: laneId,
          frames: frames,
          naming: named,
          adopted: adopted,
          pick: pick,
        ),
      ),
      nameTag: scope.subject.nameTagWith(
        written(
          homes.nameTag,
          (laneId, frames) => holders.nameTag(laneId, asked!, frames),
          (keys, laneId, frames, holder) => seNameTagTrackWithLaneKeysWritten(
            keys,
            laneId: laneId,
            frames: frames,
            naming: named,
            adoptFrom: holder,
            pick: pick,
          ),
        ),
      ),
      sound: written(
        homes.sound,
        (laneId, frames) => holders.sound(laneId, asked!, frames),
        (sound, laneId, frames, holder) => seSoundWithLaneKeysWritten(
          sound,
          laneId: laneId,
          frames: frames,
          naming: named,
          adoptFrom: holder,
          pick: pick,
        ),
      ),
    );
    if (taken) {
      return (taken: true, edit: null);
    }
    return (
      taken: false,
      edit: edit.isEmpty ? null : (layer: layer, edit: edit),
    );
  }

  /// What already holds a name on each home's lanes of [scope], outside the
  /// frames given — the keys a key joining the name takes. Each home is its
  /// own naming space: a row's own lanes and its effects name across its
  /// 겸용 link group, a reference fx's (F-374), a name tag's and a row's
  /// 「오디오」 on themselves alone. Null where the name is free.
  ///
  /// The key window's naming reads it ([_laneKeysWriteOver]) and so does a
  /// 링크 붙여넣기 of keys ([_laneKeysPasted], F-388): one answer to 「who
  /// holds this name here」.
  _NameHolders _nameHoldersOf(_SpanScope scope) {
    final layer = scope.layer;
    final cutId = _activeCut.cutOfRow(layer.id);
    final fx = scope.homes.reference.keys;
    final tag = scope.homes.nameTag.keys;
    final sound = scope.homes.sound.keys;
    return (
      own: (laneId, name, frames) => _laneTransformHoldingName(
        layer,
        transformPropertyOfLaneId(laneId)!,
        name,
        excludeFrames: frames,
      ),
      reference: (laneId, name, frames) =>
          transformLaneUsesName(
            fx,
            transformPropertyOfLaneId(laneId)!,
            name,
            excludeFrames: frames,
          )
          ? fx
          : null,
      effects: (laneId, name, frames) => switch (parseEffectLaneId(laneId)) {
        (:final effectId, parameterId: final lane?) when cutId != null =>
          _project.cutCommandCoordinator.namedEffectKeyInSpace(
            cutId: cutId,
            layerId: layer.id,
            effectId: effectId,
            lane: lane,
            name: name,
            excludeFramesOnSource: frames,
          ),
        _ => null,
      },
      nameTag: (laneId, name, frames) =>
          seNameTagLaneUsesName(tag, laneId, name, excludeFrames: frames)
          ? tag
          : null,
      sound: (laneId, name, frames) =>
          seSoundLaneUsesName(sound, laneId, name, excludeFrames: frames)
          ? sound
          : null,
    );
  }

  /// A handle of a header graph let go (I-89 ③): [sides] on the key of
  /// [lane] at [frameIndex] — and, when the lane range holds that key, on
  /// every key it covers (I-89-Q-b), by the key window's own write — one
  /// undo, the drag's preview dropped with it. [frameIsGlobal]: see
  /// [_laneVerbFrameAt].
  void setLaneKeySidesAt(
    LaneRowAddress lane,
    int frameIndex,
    KeySidesEdit sides, {
    required bool frameIsGlobal,
  }) => _commitLaneEdit(
    _handleEdit(lane, frameIndex, sides, frameIsGlobal: frameIsGlobal),
    description: 'Set key type',
  );

  /// A handle mid-drag: the edit [setLaneKeySidesAt] would write at the
  /// release, shown and not written (F-195 — the same edit, not a
  /// look-alike).
  void previewLaneKeySidesAt(
    LaneRowAddress lane,
    int frameIndex,
    KeySidesEdit sides, {
    required bool frameIsGlobal,
  }) => _previewLaneEdit(
    _handleEdit(lane, frameIndex, sides, frameIsGlobal: frameIsGlobal),
  );

  /// The write a handle's drag makes: [sides] over the lane range when it
  /// holds the handle's key, else over that key alone, as a one-frame span
  /// on its lane.
  ({Layer layer, LaneEdit edit})? _handleEdit(
    LaneRowAddress lane,
    int frameIndex,
    KeySidesEdit sides, {
    required bool frameIsGlobal,
  }) {
    final LaneRowAddress(:layerId, :laneId) = lane;
    final frame = _laneVerbFrameAt(
      layerId,
      frameIndex,
      frameIsGlobal: frameIsGlobal,
    );
    final range = laneVerbRange;
    final span =
        range != null &&
            range.layerId == layerId &&
            range.contains(frame) &&
            (_laneVerbScope(range)?.targets.contains(laneId) ?? false)
        ? range
        : _oneFrameSpan(layerId, laneId, frame);
    return _laneKeysWriteOver(span, pick: KeyTypePick(sides: sides)).edit;
  }

  /// AE's group Reset (R5, user 2026-08-09): puts a GROUP HEADER's members
  /// back to their defaults without deleting a single key.
  ///
  /// Scope is [laneVerbRange]'s, the same one Add and Delete Key take —
  /// the playhead alone, or a live lane-range selection. What differs is
  /// what a span MEANS here: "선택범위에서 작동하면 선택한 키들 리셋", so a
  /// span resets the keys it covers and authors none, while the playhead
  /// case must write one on an animated lane (nothing else can make the
  /// value THERE the default). An unkeyed lane is left alone either way —
  /// it already sits at its default, and keying it would turn a static
  /// property into an animated one behind the user's back.
  ///
  /// [headerLaneId] names the group: the transform header resets the
  /// transform track, an `fx-group:` header its own effect, and the fixed
  /// groups' headers the SE row's name tag, its 「오디오」 and a reference
  /// row's fx.
  bool resetLaneGroup(LayerId layerId, String headerLaneId) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null || _wearsBaseFx(layer)) {
      return false;
    }
    final span = _selection.laneRangeSelection.value;
    // A span covering this very group is the only one that scopes the
    // reset: standing elsewhere with a selection alive on another row must
    // not silently retarget it.
    final scoped =
        span != null &&
        span.layerId == layerId &&
        span.spanLaneIds.contains(headerLaneId);
    final frames = scoped
        ? [for (var i = span.startIndex; i < span.endIndexExclusive; i += 1) i]
        : [_laneVerbFrameFor(layerId)];

    if (parseEffectLaneId(headerLaneId) != null) {
      final effects = effectsWithGroupReset(
        layer.effects,
        laneId: headerLaneId,
        frameIndexes: frames,
        keyedFramesOnly: scoped,
        paper: _paperOf(layer),
      );
      if (effects == null) {
        return false;
      }
      _commitLaneEffects(layer, effects, description: 'Reset group');
      return true;
    }
    // ↩️The two fixed groups drew the button and nothing answered it
    // (F-374, 유저 2026-10-17: 「참조fx에서 리셋버튼도 안먹힘」).
    if (headerLaneId == seNameTagGroupLaneId) {
      final tag = layer.kind == LayerKind.se
          ? seNameTagWithGroupReset(
              layer.seNameTag ?? const SeNameTag(),
              frameIndexes: frames,
              keyedFramesOnly: scoped,
            )
          : null;
      if (tag == null) {
        return false;
      }
      _commitLaneSeNameTag(layer, tag, description: 'Reset group');
      return true;
    }
    if (headerLaneId == seSoundGroupLaneId) {
      final sound = layer.kind == LayerKind.se
          ? seSoundWithGroupReset(
              layer.seSound,
              frameIndexes: frames,
              keyedFramesOnly: scoped,
            )
          : null;
      if (sound == null) {
        return false;
      }
      _commitLaneSeSound(layer, sound, description: 'Reset group');
      return true;
    }
    if (headerLaneId == referenceGroupLaneId) {
      return _resetReferenceGroup(layer, frames, scoped: scoped);
    }
    // The transform's goes to the middle of the space the row is posed in,
    // as an effect's goes where it stands its picture.
    return headerLaneId == transformGroupHeaderLane.laneId &&
        _resetTransformGroup(layer, frames, scoped: scoped);
  }

  /// The space [layer] is posed in ([rowPoseSpace]) — its cut's canvas,
  /// stood in or not (I-89-Q23), or the shot an S row is posed in (I-67-Q1)
  /// — whose middle its transform rests at, and where an effect of it that
  /// stands its picture rests ([effectStandPose]). Null where there is none.
  CanvasSize? _paperOf(Layer layer) => rowPoseSpace(
    _project.repository.requireProject(),
    layer,
    standing: _project.activeCutId,
  );

  /// [layer]'s reference fx back at [frames] to where an unkeyed lane of it
  /// stands — where its file was placed ([MediaReference.pose]), as a
  /// transform's reset is the identity its unkeyed lanes hold (F-374-Q2).
  bool _resetReferenceGroup(
    Layer layer,
    List<int> frames, {
    required bool scoped,
  }) {
    final reference = layer.mediaReference;
    if (reference == null) {
      return false;
    }
    final next = transformTrackWithGroupReset(
      reference.fx,
      frameIndexes: frames,
      identity: reference.pose,
      // No anchor lane: nothing is reset to it.
      defaultAnchorPoint: reference.pose.center,
      keyedFramesOnly: scoped,
    );
    if (next == null) {
      return false;
    }
    _commitTransformHomes(
      layer,
      (own: null, reference: next),
      description: 'Reset group',
    );
    return true;
  }

  /// [layer]'s transform group back to its defaults at [frames]: the middle
  /// of the space the row is posed in ([_paperOf]), which a gap has too for
  /// an S row: the storyboard's S rows reach this with no cut open since
  /// F-101. ↩️A cut's row read the canvas of the cut stood in, and in a gap
  /// had nothing to reset TO.
  bool _resetTransformGroup(
    Layer layer,
    List<int> frames, {
    required bool scoped,
  }) {
    final space = _paperOf(layer);
    if (space == null) {
      return false;
    }
    final next = transformTrackWithGroupReset(
      _laneTransformTrackOf(layer),
      frameIndexes: frames,
      identity: layerIdentityPose(space),
      defaultAnchorPoint: CanvasPoint(
        x: space.width / 2,
        y: space.height / 2,
      ),
      keyedFramesOnly: scoped,
    );
    if (next == null) {
      return false;
    }
    _commitTransformTrack(layer, next, description: 'Reset group');
    return true;
  }

  /// Whether [laneVerbRange] holds a key to delete, on a lane of any home.
  bool get laneVerbRangeHasKeys {
    final lane = laneVerbRange;
    return lane != null && _laneSpanHasKeys(lane);
  }

  /// Whether [lane] holds a key, on a lane of any home.
  bool _laneSpanHasKeys(TimelineLaneSelection lane) {
    // The same layer the verb will act on, or the answer is about a
    // different set of keys than the one Delete is about to remove: a
    // track-SE row's clone holds only this cut's, on this cut's numbers,
    // and the span is stated globally.
    final scope = _laneVerbScope(lane);
    return scope != null && rowLaneHomesKeyedWhere(scope.homes, lane.contains);
  }

  /// Whether the one Delete has something to take from [laneVerbRange]: a key
  /// under it, or — on a live RANGE — an fx header it names (F-87).
  bool get laneVerbRangeHasSomethingToDelete {
    final lane = laneVerbRange;
    return lane != null &&
        _laneSpanHasSomethingToDelete(lane, range: _laneRangeIsLive);
  }

  /// Whether [lane] holds what the one Delete takes: a key under it, or — a
  /// RANGE's — an fx header it names.
  bool _laneSpanHasSomethingToDelete(
    TimelineLaneSelection lane, {
    required bool range,
  }) =>
      _laneSpanHasKeys(lane) ||
      (range &&
          _effectsNamedByHeaders(lane.layerId, lane.spanLaneIds).isNotEmpty);

  /// Whether the span [laneVerbRange] answers with is the live lane RANGE —
  /// not the row stood on, nor the camera row's band.
  bool get _laneRangeIsLive => _selection.laneRangeSelection.value != null;

  /// 🚨F-87 — the LANES a live band holds, and only those that hold what the
  /// one Delete takes: one span per layer, over the band's frames on each
  /// row's own axis — every lane row it swept, and the CAMERA row, which IS
  /// its transform header (F-17/F-84, 유저 2026-09-11: 「트랜스폼이나 카메라나
  /// 똑같으니까 법 싹 하나로 통일해줘」).
  ///
  /// 유저 (2026-10-18): 「fx를 넘어서 뭐든 선택된 대상으로 버튼의 대상이
  /// 바껴야하는데 법 통일해서 해결하도록」 — and 08-12's 「선택 객체 하나가
  /// 종류 섞인 행들을 담고, 각 동사가 행 종류별로 알아서 처리」. A band's lane
  /// row is deleted the way a range over it is: an fx header takes its fx,
  /// every other lane its keys ([deleteForBandLanes]). ↩️Its rows were read
  /// as their layers' blocks, so a band over an fx row deleted the layer's
  /// frames and, with none, left the button grey.
  ///
  /// ⚠️A lane of a row no lane verb resolves — a storyboard projection
  /// row's, whose layer is a different cut's at every frame — holds nothing
  /// here: no single span names it.
  List<TimelineLaneSelection> get bandLanesToDelete => [
    for (final lane in _bandLaneSpans())
      if (_laneSpanHasSomethingToDelete(lane, range: true)) lane,
  ];

  /// The band's lane rows as spans ([bandLanesToDelete]) — the cut's band on
  /// its rows' own axes, the track's on the track's.
  List<TimelineLaneSelection> _bandLaneSpans() {
    final inCut = _selection.frameRangeSelection.value;
    if (inCut != null) {
      return _laneSpansOfCutBand(inCut);
    }
    final onTrack = _selection.trackFrameRangeSelection.value;
    if (onTrack != null) {
      return _laneSpansOver(
        onTrack.spanRows,
        onTrack.startFrame,
        onTrack.endFrameExclusive,
        frameIsGlobal: true,
      );
    }
    return const [];
  }

  /// The cut's [band] as its lane rows' spans, on each row's own axis.
  List<TimelineLaneSelection> _laneSpansOfCutBand(
    TimelineFrameRangeSelection band,
  ) => _laneSpansOver(
    // A band no drag swept names its layer rows alone, the camera's among
    // them.
    band.rows.isNotEmpty
        ? band.rows
        : [for (final id in band.spanLayerIds) LayerRowAddress(id)],
    band.startIndex,
    band.endIndexExclusive,
    frameIsGlobal: false,
  );

  /// 🚨H20 — the LANES a move of the live band carries: its lane rows as
  /// the one Delete reads them ([bandLanesToDelete]) — the camera row, its
  /// transform header, among them — on the row a lane verb resolves, each
  /// carrying what a drag on those lanes would ([laneIdsAMoveCarries]). The
  /// cut's band and the storyboard's track band alike ([_bandLaneSpans]).
  ///
  /// 유저 (2026-08-23): 「fx랑 블록이랑 같이 움직이게할거면 둘다 유저가
  /// 선택하게 할거니까 … 선택한 곳만 움직이게하라고」 — and 08-12's 「선택 객체
  /// 하나가 종류 섞인 행들을 담고, 각 동사가 행 종류별로 알아서 처리」.
  /// ↩️A band moved only its blocks, and the camera's keys by a resolver of
  /// their own: a band over a layer and its lanes left the keys behind, and
  /// a lane pressed inside it moved the keys alone.
  List<BandLane> bandLanesRiding() => [
    for (final span in _bandLaneSpans())
      if (laneVerbLayerFor(span.layerId) case final row?
          when !_wearsBaseFx(row))
        if (laneIdsAMoveCarries(
              laneEditSubjectOf(row),
              span,
              laneVerbTargets: laneVerbTargets,
            )
            case final laneIds?)
          (row: row, span: span, laneIds: laneIds),
  ];

  /// The lanes among [rows], gathered per layer in display order, over
  /// [start]..[endExclusive] as each layer's own lanes key it.
  List<TimelineLaneSelection> _laneSpansOver(
    List<TimelineRowAddress> rows,
    int start,
    int endExclusive, {
    required bool frameIsGlobal,
  }) {
    final lanesByLayer = <LayerId, List<String>>{};
    void add(LayerId layerId, String laneId) =>
        (lanesByLayer[layerId] ??= []).add(laneId);
    for (final row in rows) {
      switch (row) {
        case LaneRowAddress(:final layerId, :final laneId)
            when laneVerbLayerFor(layerId) != null:
          add(layerId, laneId);
        case LayerRowAddress(:final layerId) when _isCameraRow(layerId):
          add(layerId, transformGroupHeaderLane.laneId);
        case LaneRowAddress() || LayerRowAddress() || TrackRowAddress():
          break;
      }
    }
    int onAxis(LayerId layerId, int frame) =>
        _laneVerbFrameAt(layerId, frame, frameIsGlobal: frameIsGlobal);
    return [
      for (final MapEntry(key: layerId, value: laneIds)
          in lanesByLayer.entries)
        TimelineLaneSelection(
          layerId: layerId,
          laneId: laneIds.first,
          startIndex: onAxis(layerId, start),
          endIndexExclusive: onAxis(layerId, endExclusive),
          laneIds: laneIds,
        ),
    ];
  }

  /// 🚨F-87 — THE ONE DELETE ON A LANE ROW (유저 2026-09-12: 「공용 삭제버튼을
  /// 서있는곳 위치에 따라 나누도록. 트랜스폼 헤더에 서있으면 지금처럼 해당 키
  /// 삭제 그대로 두는데, 키가 없을때 삭제하면 레이어의 프레임이 삭제됨. 이런거
  /// 없도록. 법 최대한 하나로 통일 / 그리고 fx 헤더 선택범위로 선택한채로
  /// 삭제누르면 해당 fx 삭제」).
  ///
  /// A lane row is the press's subject the way a cell band is. A live RANGE
  /// over an fx header removes that effect, its keys with it; every other lane
  /// in the span loses the keys the range covers; with nothing to take the
  /// press does nothing — never the cel of the layer the lane belongs to.
  /// Standing on a header is not a range: it takes the keys at the playhead,
  /// as it always did. One undo for the whole press.
  void deleteForLaneSelection(TimelineLaneSelection lane) =>
      _deleteForLaneSpan(lane, range: _laneRangeIsLive);

  /// ＋ on the live band's LANE rows ([_bandLaneSpans]) — the camera row,
  /// its transform header, among them — each keyed the way ＋ on a range
  /// over it keys ([createLaneKeysForSelection]), inside the caller's one
  /// step, beside the band's cells.
  ///
  /// 🗣️ONE BAND (유저 2026-10-25, conte-sweep-leaves-the-lanes-out-Q1): the
  /// band holds the lanes it swept, and each verb answers its rows kind by
  /// kind (08-12). ↩️A lane selection stood beside the band and ＋ keyed
  /// that alone, leaving the band's cells unfilled.
  void createKeysForBandLanes() {
    for (final lane in _bandLaneSpans()) {
      createLaneKeysForSelection(lane);
    }
  }

  /// Whether a lane row of the live band has a frame ＋ keys
  /// ([createKeysForBandLanes]).
  bool get bandLanesTakeKeys => _bandLaneSpans().any(canCreateLaneKeysFor);

  /// The band's lanes ([bandLanesToDelete]), each deleted the way a RANGE
  /// over it is — inside the caller's one step, beside the band's blocks.
  void deleteForBandLanes(List<TimelineLaneSelection> lanes) {
    for (final lane in lanes) {
      _deleteForLaneSpan(lane, range: true);
    }
  }

  /// THE delete of one lane span ([deleteForLaneSelection]'s law): a RANGE's
  /// fx headers take their effects, and every lane left loses its keys.
  void _deleteForLaneSpan(TimelineLaneSelection lane, {required bool range}) {
    final removed = range
        ? _effectsNamedByHeaders(lane.layerId, lane.spanLaneIds)
        : const <EffectId>[];
    if (removed.isEmpty) {
      removeLaneKeysForSelection(lane);
      return;
    }
    final layer = laneVerbLayerFor(lane.layerId)!;
    _project.historyManager.runAsOneStep('Delete', () {
      _removeEffects(layer, removed);
      // The removed effects' header lanes resolve to nothing now, so the
      // same span takes only the keys on the lanes that are left.
      removeLaneKeysForSelection(lane);
    });
  }

  /// 🗣️F-476 (유저 2026-10-26): 「레이어쪽 fx 선택범위로 선택하고
  /// 삭제할수있게하라고. 물론 기본fx는 삭제못하는데 fx 추가해서 넣은거
  /// 삭제하는기능 … 삭제같은 공용버튼도 선택범위로 대상 인식하는거 fx만
  /// 빠져있는거같은데 법 통일」.
  ///
  /// The effects the rail's selected rows name by their HEADER rows, per
  /// row — what the shared delete takes of them, by the law a range over
  /// those headers is deleted by (F-87, [_effectsNamedByHeaders]), and what
  /// the pill's copy, cut and duplicate take (F-476-Q1, `EffectClipboard`).
  /// Transform is no effect, so its header names none. ↩️The rows rung
  /// counted layer rows alone (「lane rows … contribute nothing here」,
  /// 08-12) after F-87 gave the band its fx, so a rail selection of fx
  /// headers fell through to the frame axis.
  List<({Layer row, List<EffectId> effects})> get effectsNamedBySelectedRows {
    final laneIdsByRow = <LayerId, List<String>>{};
    for (final row in _selection.rowSelection.value) {
      if (row case LaneRowAddress(:final layerId, :final laneId)) {
        (laneIdsByRow[layerId] ??= []).add(laneId);
      }
    }
    return [
      for (final MapEntry(key: layerId, value: laneIds)
          in laneIdsByRow.entries)
        if (_effectsNamedByHeaders(layerId, laneIds) case final effects
            when effects.isNotEmpty)
          (row: laneVerbLayerFor(layerId)!, effects: effects),
    ];
  }

  /// Takes [named] ([effectsNamedBySelectedRows]) off their rows — as ONE
  /// [step], or a part of the caller's.
  void removeEffectsNamedByRows(
    List<({Layer row, List<EffectId> effects})> named, {
    String step = 'Remove effects',
  }) => _project.historyManager.runAsOneStep(step, () {
    for (final (:row, :effects) in named) {
      _removeEffects(row, effects);
    }
  });

  /// 🗣️F-476-Q1 (유저 2026-10-27, 「b + 복제도」): 복제 of the effects
  /// [named] — a copy of each, an effect of its own, right below it on its
  /// row, shown as an added one is ([EffectsAndFx.showEffects]). One undo.
  void duplicateEffectsNamedByRows(
    List<({Layer row, List<EffectId> effects})> named,
  ) => _project.historyManager.runAsOneStep('Duplicate effects', () {
    for (final (:row, :effects) in named) {
      final copies = {
        for (final effect in row.effects)
          if (effects.contains(effect.id))
            effect.id: effect.copyWith(
              id: _effectsAndFx.mintEffectId(row.id.value),
            ),
      };
      _commitLaneEffects(row, [
        for (final effect in row.effects) ...[effect, ?copies[effect.id]],
      ], description: 'Duplicate effects');
      _effectsAndFx.showEffects(row.id, copies.values);
    }
  });

  /// [layer]'s chain without [removed], committed as one edit.
  void _removeEffects(Layer layer, Iterable<EffectId> removed) {
    var effects = layer.effects;
    for (final effectId in removed) {
      effects = effectsWithRemoved(effects, effectId) ?? effects;
    }
    _commitLaneEffects(layer, effects, description: 'Remove effect');
  }

  /// The effects [laneIds] of [layerId]'s row name by their HEADERS — a live
  /// lane RANGE's (none for the span of the row being stood on, which is not
  /// a range), and the rail's row selection's ([effectsNamedByRows]).
  ///
  /// ↩️It read the live range itself to tell the two apart; a band's lanes
  /// are ranges too and live in no lane range, so the caller says which
  /// ([_deleteForLaneSpan]'s `range`).
  List<EffectId> _effectsNamedByHeaders(
    LayerId layerId,
    Iterable<String> laneIds,
  ) {
    final layer = laneVerbLayerFor(layerId);
    if (layer == null || _wearsBaseFx(layer)) {
      return const [];
    }
    final ids = <EffectId>[];
    for (final laneId in laneIds) {
      final address = parseEffectLaneId(laneId);
      if (address == null || address.parameterId != null) {
        continue;
      }
      if (layer.effects.any((effect) => effect.id == address.effectId)) {
        ids.add(address.effectId);
      }
    }
    return ids;
  }

  /// The lane-selection create (UI-R25 #3): a key frozen at the resolved
  /// value on every unkeyed frame of the range, on every lane it spans of
  /// every home (R26 #3, F-374) — one undo. Each key is the navigator's ◆
  /// there ([LaneHome.keyedAt]).
  void createLaneKeysForSelection(TimelineLaneSelection lane) {
    final scope = _laneVerbScope(lane);
    if (scope == null) {
      return;
    }
    final layer = scope.layer;
    final homes = scope.homes;
    final frames = _keyableFrames(layer, lane);
    final paper = _paperOf(layer);
    TransformTrack? Function(TransformTrack, String, int) transform({
      required bool reference,
    }) => (track, laneId, frame) => _transformTrackWithKeyToggled(
      layer,
      track,
      laneId,
      frame,
      reference: reference,
    );
    final tag = scope.subject.seNameTag;
    _commitSpanEdit(
      scope,
      LaneEdit(
        transform: (
          own: homes.own.keyedAt(frames, transform(reference: false)),
          reference: homes.reference.keyedAt(
            frames,
            transform(reference: true),
          ),
        ),
        effects: homes.effects.keyedAt(
          frames,
          (effects, laneId, frame) => effectsWithLaneKeyToggled(
            effects,
            laneId: laneId,
            frameIndex: frame,
            paper: paper,
          ),
        ),
        nameTag: scope.subject.nameTagWith(
          homes.nameTag.keyedAt(
            frames,
            (keys, laneId, frame) => tag == null
                ? null
                : seNameTagWithLaneKeyToggled(
                    tag.copyWith(track: keys),
                    laneId: laneId,
                    frameIndex: frame,
                  )?.track,
          ),
        ),
        sound: homes.sound.keyedAt(
          frames,
          (sound, laneId, frame) => seSoundWithLaneKeyToggled(
            sound,
            laneId: laneId,
            frameIndex: frame,
          ),
        ),
      ),
      description: 'Create keys',
    );
  }
}

/// The edits a lane verb makes of each family at a frame — null where it
/// leaves that family alone. Which one runs is [LaneVerbs]' dispatch.
typedef _LaneEdits = ({
  SeNameTag? Function(SeNameTag tag, int frame) nameTag,
  SeSound? Function(SeSound sound, int frame) sound,
  // [layer]: the row wearing [effects] — the paper they stand on
  // ([LaneVerbs._paperOf]).
  List<LayerEffect>? Function(
    Layer layer,
    List<LayerEffect> effects,
    int frame,
  )
  effects,
  // [reference]: the lane is a reference fx's (F-374), [track] that fx.
  TransformTrack? Function(
    Layer layer,
    TransformTrack track,
    int frame, {
    required bool reference,
  })
  transform,
});

/// What the key window writes of the keys' NAMES: [name] on every key the
/// range covers — null unnames them — and, where the name is held outside
/// the range, whether to [adopt] what holds it, joining it.
typedef _LaneKeyNaming = ({String? name, bool adopt});

/// A key the lane range covers ([LaneVerbs._laneRangeKeys]): the lane it is
/// on, the key, whether it may give its time up there (I-89 ④), whether
/// it takes the key window's sides — a name tag's flag holds by nature
/// (#902) — and whether its lane's keys walk a path ([LaneHome.walksAPath]).
typedef _LaneRangeKey = ({
  String laneId,
  PropertyKey<Object?> key,
  bool canRove,
  bool takesSides,
  bool walksAPath,
});

/// A layer's lanes a band holds ([LaneVerbs.bandLanesRiding]): the row the
/// verbs resolve, its span of keys, and the lanes a move of it carries.
typedef BandLane = ({
  Layer row,
  TimelineLaneSelection span,
  List<String> laneIds,
});

/// What a verb over a span settles first ([LaneVerbs._laneVerbScope]).
/// A lane a paste of keys can land on: the home it lives in, by identity,
/// and its id there ([LaneVerbs._keysPairedWith]).
typedef _PastedLane = ({LaneHome<Object?> home, String laneId});

/// What holds a name on a lane of each home ([LaneVerbs._nameHoldersOf]),
/// asked with the lane, the name and the frames left out.
typedef _NameHolders = ({
  TransformTrack? Function(String laneId, String name, Set<int> frames) own,
  TransformTrack? Function(String laneId, String name, Set<int> frames)
  reference,
  PropertyKey<Object?>? Function(String laneId, String name, Set<int> frames)
  effects,
  SeNameTagTrack? Function(String laneId, String name, Set<int> frames)
  nameTag,
  SeSound? Function(String laneId, String name, Set<int> frames) sound,
});

typedef _SpanScope = ({
  Layer layer,
  List<String> targets,
  LaneEditSubject subject,
  RowLaneHomes homes,
});

/// Where a row's TRANSFORM lanes live ([LaneVerbs._transformHomeOf]).
enum _TransformHome {
  /// The camera row's: the open cut's camera track.
  cutCamera,

  /// A V row's carrier: none since the track transform teardown.
  nowhere,

  /// Every other row's: its own.
  row,
}

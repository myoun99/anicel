import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../models/key_side.dart' show KeySidesEdit;
import '../../models/layer.dart' show Layer;
import '../../models/layer_id.dart' show LayerId;
import '../../models/timeline_row_address.dart' show LaneRowAddress;
import '../brush/transform_tool_options.dart';
import '../editor_session_manager.dart';
import 'property_lane_model.dart'
    show PropertyLaneEditCallbacks, PropertyLaneRow;

/// A rail's lane edits wired to [session] — the one wiring behind the
/// timeline's lanes and the storyboard's S rows (F-101). [frameIsGlobal] is
/// the rail's axis: a cut's rail hands cut frames, a track's rail global
/// ones, and the verbs put either on the row the project holds (F-102).
///
/// [transformOptions] is the transform tool's: a layer's Scale lane links
/// by its 「배율 연동」, read at the moment a value lands, and the chain on
/// the Scale row flips that same field — the ONE switch, shown in two
/// places (`transform-fx-scale-x-y-Q1`, 유저 2026-10-07: 「Scale 행에 사슬
/// 버튼 — 변형 도구의 「배율 연동」과 한 스위치」). A rail with no tool beside
/// it reads the tool's own defaults and has no chain to show.
PropertyLaneEditCallbacks sessionLaneEditCallbacks(
  EditorSessionManager session, {
  required bool frameIsGlobal,
  required ValueNotifier<TransformToolOptions>? transformOptions,
}) {
  bool scaleLinked() =>
      (transformOptions?.value ?? TransformToolOptions.defaults).scaleLinked;
  return PropertyLaneEditCallbacks(
    valueLink: transformOptions == null
        ? null
        : (
            changes: transformOptions,
            isOn: scaleLinked,
            toggle: () => transformOptions.value = transformOptions.value
                .copyWith(scaleLinked: !scaleLinked()),
          ),
    // The navigator toggles at the playhead, freezing the property's
    // CURRENT resolved value there (AE behavior).
    onToggleKeyAt: (layer, lane, frameIndex) =>
        session.laneVerbs.toggleLaneKeyAt(
          layer.id,
          lane.laneId,
          frameIndex,
          frameIsGlobal: frameIsGlobal,
          description: '${lane.label} keyframe at frame ${frameIndex + 1}',
        ),
    onSetValue: (layer, lane, frameIndex, input) =>
        session.laneVerbs.setLaneValueAt(
          layer.id,
          lane.laneId,
          frameIndex,
          input,
          frameIsGlobal: frameIsGlobal,
          description: 'Set ${lane.label} at frame ${frameIndex + 1}',
          scaleLinked: scaleLinked(),
        ),
    // F-195: the same edit, shown while a scrub lasts.
    onPreviewValue: (layer, lane, frameIndex, input) =>
        session.laneVerbs.previewLaneValueAt(
          layer.id,
          lane.laneId,
          frameIndex,
          input,
          frameIsGlobal: frameIsGlobal,
          scaleLinked: scaleLinked(),
        ),
    onEndPreview: session.laneVerbs.endLaneEditPreview,
    // I-89 ③: a header graph's handle — the key window's write of the type,
    // shown while the drag lasts.
    onSetKeySides: _atTheKey(
      session.laneVerbs.setLaneKeySidesAt,
      frameIsGlobal: frameIsGlobal,
    ),
    onPreviewKeySides: _atTheKey(
      session.laneVerbs.previewLaneKeySidesAt,
      frameIsGlobal: frameIsGlobal,
    ),
    // F-475: what the ◆ and a flag's ring show, read as the project stands
    // — the rail's bulk-drag spreads what a press just set.
    keyedNow: (layer, lane, frameIndex) => session.laneVerbs.isLaneKeyedAt(
      layer.id,
      lane.laneId,
      frameIndex,
      frameIsGlobal: frameIsGlobal,
    ),
    valueNow: (layer, lane, frameIndex) => session.laneVerbs.laneValueAt(
      layer.id,
      lane.laneId,
      frameIndex,
      frameIsGlobal: frameIsGlobal,
    ),
  );
}

/// [verb] of a key's sides, handed the key as a lane edit names it — its
/// row's layer, its lane and its frame on [frameIsGlobal]'s axis.
void Function(Layer layer, PropertyLaneRow lane, int frameIndex, KeySidesEdit)
_atTheKey(
  void Function(
    LaneRowAddress lane,
    int frameIndex,
    KeySidesEdit sides, {
    required bool frameIsGlobal,
  })
  verb, {
  required bool frameIsGlobal,
}) => (layer, lane, frameIndex, sides) => verb(
  LaneRowAddress(layer.id, lane.laneId),
  frameIndex,
  sides,
  frameIsGlobal: frameIsGlobal,
);

/// A media-browser sound dropped on an SE block, linked to that block by
/// [session] — the one wiring the timeline's rows and the storyboard's S rows
/// hand over (F-101). ↩️It rode in the SE audio lane's callbacks with the
/// lane's offset and fade drags, until the lane went (I-140).
void Function(LayerId layerId, int blockStartFrame, String path)
sessionSeBlockDrop(EditorSessionManager session) =>
    (layerId, blockStartFrame, path) =>
        session.mediaPool.linkMediaAssetToSeBlock(
          layerId: layerId,
          blockStartFrame: blockStartFrame,
          path: path,
        );

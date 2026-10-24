import 'dart:ui' show Offset;

import '../models/canvas_size.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../models/layer_effect.dart'
    show ResolvedLayerEffect, resolveLayerEffectsAt;
import '../models/se_name_tag.dart';
import '../models/text_cel_style.dart';
import '../models/timeline_coverage.dart';
import '../models/transform_pose.dart' show layerIdentityPose;
import 'cut_frame_composite_plan.dart'
    show layerOwnPlacementAt, resolveLayerEffectiveOpacityAt;
import 'layer_pose_matrix.dart' show LayerPlacement, placementOf;

/// PURE resolution of the on-canvas SE name tags for one (cut, frame) —
/// what the editing canvas, playback and export each draw over the
/// composited picture (R5b, §6-z15). Testable without a pixel.
///
/// Track SE rows live on the track's GLOBAL frame axis, so the caller
/// hands in the track's rows plus the cut's global start; the conversion
/// happens here and nowhere else (the [TrackSeWindow] rule).
class ResolvedSeNameTag {
  const ResolvedSeNameTag({
    required this.layerId,
    required this.content,
    required this.widthBudget,
    required this.shot,
    this.inShot = const LayerPlacement.identity(),
    this.opacity = 1,
    this.effects = const [],
    this.line,
    this.delivery,
  });

  /// The SE row the tag belongs to (its eye is the display switch).
  final String layerId;

  /// Where the SHOT — the frame the camera shows — lies on the canvas at
  /// this frame (`shotPlacement`).
  ///
  /// 🗣️I-67-Q1 (유저 2026-10-10: 「이름표를 카메라 화면 기준으로 읽는다」):
  /// the SE row's transform places the tag in the shot, so the camera's
  /// moves, zoom and turn leave it where it stands on screen. ↩️Canvas
  /// coordinates — a camera that panned away left its tags behind (I-67:
  /// 「카메라 움직이면 se블록의 이름표가 안보이게 된다」).
  final LayerPlacement shot;

  /// Where the row's transform lays the tag in the shot — its pose about
  /// its anchor point ([placementOf]), as a layer's lays its picture on the
  /// canvas. The identity for an unposed row.
  ///
  /// 🗣️F-387 (유저 2026-10-19): 「일반 그림 레이어에서는 트랜스폼fx의 헤더에
  /// 서면 변형도구 ui 그대로써서 회전같은거 가능한데 se의 트랜스폼fx는
  /// 그런게안됨 … 같은 fx인데 다른건 말이안됨」. ↩️The tag read its row's
  /// position alone, so the row's scale, turn and anchor lanes keyed values
  /// nothing drew.
  final LayerPlacement inShot;

  /// Where the tag's own space — the positions below — lies on the canvas:
  /// [inShot] in the [shot]. The painter and the canvas box both lay the
  /// tag through this, so neither can lay it elsewhere.
  LayerPlacement get placement => shot.compose(inShot);

  /// The row's effective opacity at this frame — what a layer's multiplies
  /// its picture by ([resolveLayerEffectiveOpacityAt]).
  ///
  /// The tag takes the row's opacity and effects but NOT its blend: it is
  /// drawn normal, whatever the row's blend. 🗣️F-387-Q5 (유저 2026-10-22:
  /// 「이름표는 블렌드 합성 필요없음. 그냥 일반. 노말블렌드면 됨. 아래 그림에
  /// 곱해서 보이게할 필요도 이유도 없음」). ↩️F-387 handed the tag the row's
  /// blend as well, so a multiply SE row multiplied its name into the picture
  /// under it — and an advanced blend needs that picture, which a tag drawn
  /// over the composite never holds.
  final double opacity;

  /// The row's effect chain at this frame ([resolveLayerEffectsAt]) — what
  /// a layer's picture takes before it is composited.
  ///
  /// 🗣️F-387 (유저 2026-10-19): 「다른것도 확인해서 통일」. ↩️The chain was
  /// sampled for the row's own picture, which an SE row never draws, and
  /// the tag painted after the composite took none of it: an SE row
  /// carried effects that changed nothing.
  final List<ResolvedLayerEffect> effects;

  /// The DIALOGUE run, or null when there is none to show.
  ///
  /// It carries NO usable position: where it sits depends on how wide the
  /// name box laid out, which is known only once the name is measured. The
  /// painter places it, off the box's right edge.
  final TextCelContent? line;

  /// The NAME run as a text block — the same [TextCelContent] the text
  /// layer speaks, so ONE painter draws both (ⓣ).
  ///
  /// Its position is the box's CENTRE, not the text's top-left: the
  /// dialogue hangs off the box's right edge, so the box is the thing that
  /// has to stay put when the dialogue is turned off (R5 #7).
  final TextCelContent content;

  /// The width the tag may occupy before it shrinks to fit — the shot's
  /// width, so a long line stays inside the picture instead of running
  /// off it.
  final double widthBudget;

  /// The line's DELIVERY (I-20) — ON / OFF / MONO — as a tag of its own.
  ///
  /// 🗣️유저 2026-09-30: 「해당 타입의 텍스트는 네임태그로서 화면에 보이게함.
  /// 위치는 캐릭터 이름 박스 위 중앙정렬」 — so it wears the NAME's style, and
  /// like [line] it carries no usable position: the painter centres it over
  /// the box once the box is measured. Every type shows here — ON included
  /// (「캔버스에는 표시」); only the sheets leave ON out.
  final TextCelContent? delivery;
}

/// The tags visible at the TRACK's frame [shown] — the axis the rows
/// are keyed on — in the rows' own order (first row drawn first).
///
/// A row contributes nothing when its eye is off, when no SE block covers
/// the frame, or when the covering block carries no writing at all — an
/// empty red box would say less than nothing.
///
/// ↩️It took a cut's start and a frame of the cut and added the two. Where
/// a cut's own frames stand on the track is not this function's to know —
/// they begin before the cut's place in a cut an O.L arrives into
/// (`TrackFrameAxis`), and the sum put every tag of such a cut that margin
/// early (I-73-ol-index-space).
List<ResolvedSeNameTag> resolveSeNameTagsAt({
  required List<Layer> trackSeLayers,

  /// The TRACK frame shown, and the cut whose picture the tags stand over
  /// there — each line says its delivery in it (F-386), the O.L margins'
  /// heard speaker included.
  required ({int globalFrame, CutId cutId}) shown,
  required CanvasSize cameraFrame,

  /// Where the shot lies on the canvas at this frame
  /// ([ResolvedSeNameTag.shot]).
  required LayerPlacement shot,
}) {
  final (:globalFrame, :cutId) = shown;
  if (globalFrame < 0) {
    return const [];
  }
  final budget = seNameTagWidthBudget(cameraFrame);
  final tags = <ResolvedSeNameTag>[];
  for (var rowIndex = 0; rowIndex < trackSeLayers.length; rowIndex += 1) {
    final layer = trackSeLayers[rowIndex];
    if (!layer.isVisible) {
      continue;
    }
    final covering = coveringDrawingBlockAt(layer.timeline, globalFrame);
    if (covering == null) {
      continue;
    }
    final frame = layer.frames
        .where((frame) => frame.id == covering.frameId)
        .firstOrNull;
    if (frame == null) {
      continue;
    }
    // R5 #7: resolved at the GLOBAL frame, because the tag's keys live on
    // the track-owned SE layer like every other property of that row.
    final tag = layer.seNameTag?.resolveAt(globalFrame);
    final name = frame.seName?.trim() ?? '';
    final dialogue = frame.name?.trim() ?? '';
    final showsLine = (tag?.showLine ?? true) && dialogue.isNotEmpty;
    if (name.isEmpty && !showsLine) {
      continue;
    }
    // R5 #7: the tag has NO position of its own — the SE row's TRANSFORM is
    // where it sits (user, 2026-08-09). The tag is the row's picture, drawn
    // at the SHOT's centre — where an unposed row's anchor and position
    // both stand — and the row's pose lays it, exactly as a layer's lays
    // its artwork: in the shot (I-67-Q1). ↩️The canvas centre.
    final space = layer.kind.poseSpace(shot: cameraFrame)!;
    final rest = layerIdentityPose(space).center;
    final own = layerOwnPlacementAt(
      carrier: layer,
      space: space,
      frameIndex: globalFrame,
    );
    final anchor = Offset(rest.x, rest.y);
    final nameStyle = tag?.style ?? SeNameTag.defaultStyle;
    tags.add(
      ResolvedSeNameTag(
        layerId: layer.id.value,
        widthBudget: budget,
        shot: shot,
        inShot: own == null
            ? const LayerPlacement.identity()
            : placementOf(own, space),
        opacity: resolveLayerEffectiveOpacityAt(
          layer: layer,
          frameIndex: globalFrame,
        ),
        effects: resolveLayerEffectsAt(
          effects: layer.effects,
          frameIndex: globalFrame,
        ),
        content: TextCelContent(
          text: name,
          style: nameStyle,
          position: anchor,
        ),
        delivery: TextCelContent(
          text: frame.seTypes.inCut(cutId).label,
          style: nameStyle,
          position: anchor,
        ),
        line: showsLine
            ? TextCelContent(
                text: dialogue,
                style: tag?.lineStyle ?? SeNameTag.defaultLineStyle,
                position: anchor,
              )
            : null,
      ),
    );
  }
  return tags;
}

/// A cheap identity for "what would be drawn" — display code compares it
/// to decide whether a repaint is needed without holding the tags.
Object seNameTagSignature(List<ResolvedSeNameTag> tags) => Object.hashAll([
  for (final tag in tags)
    Object.hash(
      tag.layerId,
      tag.content,
      tag.line,
      tag.delivery,
      tag.widthBudget,
      tag.shot,
      tag.inShot,
      tag.opacity,
      Object.hashAll(tag.effects),
    ),
]);

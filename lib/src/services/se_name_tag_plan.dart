import 'dart:ui' show Offset;

import '../models/canvas_size.dart';
import '../models/layer.dart';
import '../models/se_name_tag.dart';
import '../models/text_cel_style.dart';
import '../models/timeline_coverage.dart';
import '../models/transform_pose.dart' show layerIdentityPose;
import 'layer_pose_matrix.dart' show LayerPlacement;

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
    this.line,
    this.delivery,
  });

  /// The SE row the tag belongs to (its eye is the display switch).
  final String layerId;

  /// Where the tag's own space — the SHOT, the frame the camera shows —
  /// lies on the canvas at this frame (`shotPlacement`). The positions
  /// below are the shot's.
  ///
  /// 🗣️I-67-Q1 (유저 2026-10-10: 「이름표를 카메라 화면 기준으로 읽는다」):
  /// the SE row's transform places the tag in the shot, so the camera's
  /// moves, zoom and turn leave it where it stands on screen. ↩️Canvas
  /// coordinates — a camera that panned away left its tags behind (I-67:
  /// 「카메라 움직이면 se블록의 이름표가 안보이게 된다」).
  final LayerPlacement shot;

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

/// The tags visible at the TRACK's frame [globalFrame] — the axis the rows
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
  required int globalFrame,
  required CanvasSize cameraFrame,

  /// Where the shot lies on the canvas at this frame
  /// ([ResolvedSeNameTag.shot]).
  required LayerPlacement shot,
}) {
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
    // where it sits (user, 2026-08-09). Identity is the SHOT's centre, so
    // an untouched row's tag starts there and Position moves it, exactly
    // like a layer's artwork — in the shot (I-67-Q1). ↩️The canvas centre.
    final pose = layer.transformTrack.resolveAt(
      frameIndex: globalFrame,
      orElse: () => layerIdentityPose(
        layer.kind.poseSpace(shot: cameraFrame)!,
      ),
    );
    final anchor = Offset(pose.center.x, pose.center.y);
    final nameStyle = tag?.style ?? SeNameTag.defaultStyle;
    tags.add(
      ResolvedSeNameTag(
        layerId: layer.id.value,
        widthBudget: budget,
        shot: shot,
        content: TextCelContent(
          text: name,
          style: nameStyle,
          position: anchor,
        ),
        delivery: TextCelContent(
          text: frame.seType.label,
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
    ),
]);

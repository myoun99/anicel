import '../models/canvas_size.dart';
import '../models/layer.dart';
import '../models/se_name_tag.dart';
import '../models/text_cel_style.dart';
import '../models/timeline_coverage.dart';

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
    this.line,
  });

  /// The SE row the tag belongs to (its eye is the display switch).
  final String layerId;

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
}

/// The tags visible at [localFrameIndex] of a cut starting at
/// [cutStartFrame], in the rows' own order (first row drawn first).
///
/// A row contributes nothing when its eye is off, when no SE block covers
/// the frame, or when the covering block carries no writing at all — an
/// empty red box would say less than nothing.
///
/// [rowOffset] shifts the unconfigured rows' stacked defaults for the
/// tracks below this one (the multitrack stack), so two covered tracks
/// never pile their tags on one spot.
List<ResolvedSeNameTag> resolveSeNameTagsAt({
  required List<Layer> trackSeLayers,
  required int cutStartFrame,
  required int localFrameIndex,
  required CanvasSize canvas,
  required CanvasSize cameraFrame,
  int rowOffset = 0,
}) {
  if (localFrameIndex < 0) {
    return const [];
  }
  final globalFrame = cutStartFrame + localFrameIndex;
  final budget = seNameTagWidthBudget(canvas: canvas, cameraFrame: cameraFrame);
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
    final tag = layer.seNameTag;
    final name = frame.seName?.trim() ?? '';
    final dialogue = frame.name?.trim() ?? '';
    final showsLine = (tag?.showLine ?? true) && dialogue.isNotEmpty;
    if (name.isEmpty && !showsLine) {
      continue;
    }
    final anchor =
        tag?.position ??
        defaultSeNameTagPosition(
          canvas: canvas,
          cameraFrame: cameraFrame,
          rowIndex: rowIndex,
          rowOffset: rowOffset,
        );
    tags.add(
      ResolvedSeNameTag(
        layerId: layer.id.value,
        widthBudget: budget,
        content: TextCelContent(
          text: name,
          style: tag?.style ?? SeNameTag.defaultStyle,
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
    Object.hash(tag.layerId, tag.content, tag.line, tag.widthBudget),
]);

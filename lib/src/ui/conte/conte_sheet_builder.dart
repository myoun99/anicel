import 'dart:math' as math;

import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/project.dart';
import '../../models/storyboard_coverage.dart';
import '../../models/timeline_coverage.dart';
import '../../models/track.dart';
import '../storyboard_layer_policy.dart';
import '../storyboard_timeline_layout.dart';

/// Reads a project as a conte sheet.
///
/// Everything here is a READING, never a second copy of the data: the cells
/// are the coverage rule's, the action text is the exposure's memo, the
/// dialogue is the SE blocks', the number is the cut's name, and the times
/// are the storyboard layout's global frames. Nothing on the sheet is
/// authored anywhere but where it already lived.
ConteSheetSource buildConteSheetSource(
  Project project, {
  String title = '',
  String episode = '',
}) {
  final layout = buildStoryboardTimelineLayout(project);
  final cuts = <ConteCutSource>[];
  for (final entry in layout) {
    final track = project.tracks.firstWhere(
      (candidate) => candidate.id == entry.trackId,
    );
    cuts.add(
      _cutSource(
        cut: entry.cut,
        name: entry.cut.name,
        startFrame: entry.startFrame,
        endFrame: entry.endFrame,
        track: track,
        cameraAspect: _aspectOf(entry.cut),
      ),
    );
  }
  return ConteSheetSource(
    cuts: cuts,
    title: title,
    episode: episode,
    framesPerSecond: project.frameRate.countingBase,
  );
}

double _aspectOf(Cut cut) => cut.canvasSize.height <= 0
    ? 16 / 9
    : cut.canvasSize.width / cut.canvasSize.height;

ConteCutSource _cutSource({
  required Cut cut,
  required String name,
  required int startFrame,
  required int endFrame,
  required Track track,
  required double cameraAspect,
}) {
  final storyboard = storyboardLayerForCut(cut);
  final cells = storyboardCoverageCells(
    timeline: storyboard?.timeline,
    cutDuration: cut.duration,
  );
  return ConteCutSource(
    cutId: cut.id,
    name: name,
    durationFrames: cut.duration,
    cumulativeEndFrames: endFrame,
    cells: [
      for (final cell in cells)
        _cellSource(
          cut: cut,
          cell: cell,
          storyboard: storyboard,
          cameraAspect: cameraAspect,
        ),
    ],
    dialogue: _dialogueOf(track, startFrame, endFrame),
  );
}

ConteCellSource _cellSource({
  required Cut cut,
  required StoryboardCoverageCell cell,
  required Layer? storyboard,
  required double cameraAspect,
}) {
  final exposure = storyboard?.timeline[cell.startIndex];
  final move = _cameraMoveIn(cut, cell, cameraAspect);
  return ConteCellSource(
    startFrame: cell.startIndex,
    endFrameExclusive: cell.endIndexExclusive,
    pictureFrame: storyboardCellPictureFrame(
      cell,
      pinnedFrameIndex: cut.metadata.thumbnailFrameIndex,
    ),
    frameId: cell.frameId,
    action: exposure?.memo?.actionMemo ?? '',
    rowSpan: move.rowSpan,
    encroachFraction: move.encroachFraction,
    cameraLabels: move.labels,
  );
}

/// How far the camera travels while this cell is on screen, in SCREENS.
///
/// A vertical move claims an extra row per screen height (design: "세로
/// 이동 = 1칸씩 추가 차지"), and the leftover of a non-integer amount stays
/// margin, which is what a hand-drawn sheet does. A horizontal move
/// encroaches on the ACTION column instead of moving it — the column
/// positions are the sheet's, fixed for every page.
({int rowSpan, double encroachFraction, List<String> labels}) _cameraMoveIn(
  Cut cut,
  StoryboardCoverageCell cell,
  double cameraAspect,
) {
  final keys = [
    for (final key in cut.camera.keyframes.entries)
      if (key.key >= cell.startIndex && key.key < cell.endIndexExclusive) key,
  ];
  if (keys.length < 2) {
    return (rowSpan: 1, encroachFraction: 0.0, labels: const <String>[]);
  }
  var minX = keys.first.value.center.x;
  var maxX = minX;
  var minY = keys.first.value.center.y;
  var maxY = minY;
  for (final key in keys) {
    minX = math.min(minX, key.value.center.x);
    maxX = math.max(maxX, key.value.center.x);
    minY = math.min(minY, key.value.center.y);
    maxY = math.max(maxY, key.value.center.y);
  }
  // One screen = the camera's view of the canvas at zoom 1.
  final screenHeight = cut.canvasSize.height.toDouble();
  final screenWidth = screenHeight * cameraAspect;
  final verticalScreens = screenHeight <= 0
      ? 0.0
      : (maxY - minY) / screenHeight;
  final horizontalScreens = screenWidth <= 0
      ? 0.0
      : (maxX - minX) / screenWidth;
  return (
    rowSpan: 1 + verticalScreens.floor().clamp(0, 4),
    encroachFraction: horizontalScreens.clamp(0.0, 1.0),
    // The keyframe NAMES are the truth for these labels (design); the model
    // carries none yet, so the sheet prints the fallback the design named.
    labels: const <String>['IN', 'OUT'],
  );
}

/// The cut's lines, read off the track's SE rows and clipped to the cut.
///
/// The SE block's frame NAME is the line and its `seName` is the speaker
/// (design G) — the sheet reads them straight, which is why typing dialogue
/// into the conte later writes an SE entry rather than a second field.
List<ConteDialogueLine> _dialogueOf(Track track, int startFrame, int endFrame) {
  final lines = <ConteDialogueLine>[];
  for (final layer in track.seLayers) {
    if (layer.kind != LayerKind.se) {
      continue;
    }
    for (final block in drawingBlocks(layer.timeline)) {
      if (block.endIndexExclusive <= startFrame ||
          block.startIndex >= endFrame) {
        continue;
      }
      final frame = layer.frames
          .where((f) => f.id == block.frameId)
          .firstOrNull;
      final text = frame?.name ?? '';
      if (text.isEmpty) {
        continue;
      }
      lines.add(
        ConteDialogueLine(
          // Clipped: a line that began in an earlier cut still belongs to
          // this cut's first cell, which is where the continuation arrow
          // will sit.
          startFrame: math.max(0, block.startIndex - startFrame),
          text: text,
          speaker: frame?.seName ?? '',
        ),
      );
    }
  }
  lines.sort((a, b) => a.startFrame.compareTo(b.startFrame));
  return lines;
}

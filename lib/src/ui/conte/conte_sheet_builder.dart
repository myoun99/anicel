import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart' show listEquals;

import '../../models/canvas_size.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut.dart';
import '../../models/key_range_move.dart'
    show transformKeyNameUnion, unionMixedKeyName;
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../../models/project.dart';
import '../../models/se_line_type.dart';
import '../../models/storyboard_coverage.dart';
import '../../models/timeline_coverage.dart';
import '../../models/track_frame_range.dart' show frameRangesOverlap;
import '../../models/track.dart';
import '../../services/camera_frame_corners.dart'
    show cameraCornerTrails, cameraFramesBounds, cameraFramesShown;
import '../storyboard_layer_policy.dart';
import '../../models/storyboard_timeline_layout.dart';

/// Reads a project as a conte sheet.
///
/// Everything here is a READING, never a second copy of the data: the cells
/// are the coverage rule's, the action text is the exposure's memo, the
/// dialogue is the SE blocks', the number is the cut's name, and the times
/// are the storyboard layout's global frames. Nothing on the sheet is
/// authored anywhere but where it already lived.
ConteSheetSource buildConteSheetSource(Project project) {
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
        cameraFrameSize: project.cameraSize,
      ),
    );
  }
  // The work's own words, read where every paper form reads them — the
  // envelope's rule: an unnamed work prints the project's name.
  final info = project.timesheetInfo;
  return ConteSheetSource(
    cuts: cuts,
    title: info.title.isEmpty ? project.name : info.title,
    episode: info.episode,
    logoAssetPath: info.logoAssetPath,
    coverImagePath: info.coverImagePath,
    conteStaffName: info.staffNameFor(
      const LayerMark(process: LayerProcess.conte),
    ),
    framesPerSecond: project.frameRate.countingBase,
    cover: info.conteCover,
    blankPage: info.conteBlankPage,
  );
}

ConteCutSource _cutSource({
  required Cut cut,
  required String name,
  required int startFrame,
  required int endFrame,
  required Track track,
  required CanvasSize cameraFrameSize,
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
          cameraFrameSize: cameraFrameSize,
        ),
    ],
    dialogue: _dialogueOf(track, startFrame, endFrame),
  );
}

ConteCellSource _cellSource({
  required Cut cut,
  required StoryboardCoverageCell cell,
  required Layer? storyboard,
  required CanvasSize cameraFrameSize,
}) {
  // The cell counts the conte's frames; the row, the camera and the picture
  // count the cut's, which begin that much earlier in a cut an O.L arrives
  // into (F-227).
  final conteStart = storyboardConteStart(storyboard?.timeline);
  final exposure = storyboard?.timeline[conteStart + cell.startIndex];
  return ConteCellSource(
    startFrame: cell.startIndex,
    endFrameExclusive: cell.endIndexExclusive,
    pictureFrame: storyboardCellPictureFrame(
      cell,
      pinnedFrameIndex: cut.metadata.thumbnailFrameIndex,
      conteStart: conteStart,
    ),
    frameId: cell.frameId,
    inkId: switch (exposure?.memo?.inkId) {
      final inkId? when inkId.isNotEmpty => inkId,
      _ => null,
    },
    action: exposure?.memo?.actionMemo ?? '',
    camera: _cameraWorkIn(cut, cell, cameraFrameSize, conteStart: conteStart),
  );
}

/// What the camera does while [cell] is on screen: its frame at the cell's
/// first and last frames and at each key between, as playback shows them
/// (`cameraFramesShown`, H54), the trail each corner draws through them and
/// the canvas they sweep — null while it holds still (every one of those
/// frames framing one place) or its work is bypassed (the camera row's
/// switch shows the canvas centred).
///
/// A window shows the widest of those frames whole ([_widestFrame]): a
/// frame is what the camera shows, so each frame of a pan takes a window
/// whatever the zoom, and a push-in's closer frame lies inside the wider.
///
/// A key's label is its NAME — the name the camera row's header shows for
/// it (`transformKeyNameUnion`): its lanes agree on it — else IN for the
/// first and OUT for the last, the Storyboard Pro rule; a key whose lanes
/// disagree («...») is unnamed (유저 2026-09-30: 「레인끼리 달라서 헤더가
/// ...으로 표시되는 경우 … 이름 안정해진거랑 같은 규칙으로 IN OUT」).
ConteCameraWork? _cameraWorkIn(
  Cut cut,
  StoryboardCoverageCell cell,
  CanvasSize cameraFrameSize, {
  required int conteStart,
}) {
  if (cut.layers.cameraWorkBypassed) {
    return null;
  }
  final frames = cameraFramesShown(
    cut,
    cameraFrameSize,
    first: conteStart + cell.startIndex,
    last: conteStart + cell.endIndexExclusive - 1,
  );
  final corners = [for (final frame in frames) frame.corners];
  if (corners.every((frame) => listEquals(frame, corners.first))) {
    return null;
  }
  final names = transformKeyNameUnion(cut.camera.track);
  return ConteCameraWork(
    screen: _widestFrame(corners),
    field: _wholePixelsAround(cameraFramesBounds(corners)),
    keys: [
      for (final (index, frame) in frames.indexed)
        _cameraKey(
          frame.corners,
          index == 0
              ? ConteCameraKeyRole.first
              : index == frames.length - 1
              ? ConteCameraKeyRole.last
              : ConteCameraKeyRole.between,
          switch (names[frame.frameIndex]) {
            null || unionMixedKeyName => null,
            final name => name,
          },
        ),
    ],
    trails: cameraCornerTrails(corners),
  );
}

/// The size of the widest of [frames] — by its sides, not its bounds: a
/// frame is no wider for being turned.
Size _widestFrame(List<List<Offset>> frames) {
  var widest = frames.first;
  for (final frame in frames.skip(1)) {
    if ((frame[1] - frame[0]).distance > (widest[1] - widest[0]).distance) {
      widest = frame;
    }
  }
  return Size(
    (widest[1] - widest[0]).distance,
    (widest[3] - widest[0]).distance,
  );
}

/// [region] grown out to whole canvas pixels — the swept canvas is
/// rendered pixel for pixel, and a render has no half pixels to give.
///
/// An edge a hair off a whole pixel is on it: the corners are poses run
/// through a matrix and back, and a hair past 0 must not cost a pixel.
Rect _wholePixelsAround(Rect region) {
  const hair = 1e-6;
  return Rect.fromLTRB(
    (region.left + hair).floorToDouble(),
    (region.top + hair).floorToDouble(),
    (region.right - hair).ceilToDouble(),
    (region.bottom - hair).ceilToDouble(),
  );
}

/// A key [named] or not, as the sheet labels it for its [role].
ConteCameraKey _cameraKey(
  List<Offset> corners,
  ConteCameraKeyRole role,
  String? named,
) => ConteCameraKey(
  corners: corners,
  role: role,
  label:
      named ??
      switch (role) {
        ConteCameraKeyRole.first => 'IN',
        ConteCameraKeyRole.last => 'OUT',
        ConteCameraKeyRole.between => null,
      },
);

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
      if (!frameRangesOverlap(
        block.startIndex,
        block.endIndexExclusive,
        startFrame,
        endFrame,
      )) {
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
          delivery: frame?.seType ?? SeLineType.on,
        ),
      );
    }
  }
  lines.sort((a, b) => a.startFrame.compareTo(b.startFrame));
  return lines;
}

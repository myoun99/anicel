import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart' show StringCharacters;

import '../../models/canvas_size.dart';
import '../../models/camera_moves.dart' show CameraMove, cameraMoves;
import '../../models/camera_work_marks.dart'
    show CameraKeyRole, cameraKeyLabel;
import '../../models/conte/conte_camera_lines.dart';
import '../../models/conte/conte_sheet_source.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/key_range_move.dart' show transformKeyAgreedNames;
import '../../models/layer.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../../models/project.dart';
import '../../models/storyboard_coverage.dart';
import '../../models/timeline_coverage.dart';
import '../../models/track_frame_range.dart' show frameRangesOverlap;
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../services/camera_frame_corners.dart'
    show cameraFramesBounds, cameraFramesShown;
import '../../services/camera_path.dart' show CameraPath;
import '../storyboard_layer_policy.dart';
import '../text/dialogue_fit_layout.dart'
    show dialogueGlyphSlots, dialogueGlyphsShownIn;
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
  final cellsOf = [
    for (final entry in layout)
      storyboardCoverageCells(
        timeline: storyboardLayerForCut(entry.cut)?.timeline,
        cutDuration: entry.cut.duration,
      ),
  ];
  final panels = _panelsOnTheirTracks(layout, cellsOf);
  final cuts = <ConteCutSource>[];
  for (final (index, entry) in layout.indexed) {
    final track = project.tracks.firstWhere(
      (candidate) => candidate.id == entry.trackId,
    );
    cuts.add(
      _cutSource(
        cut: entry.cut,
        name: entry.cut.name,
        cells: cellsOf[index],
        endFrame: entry.endFrame,
        dialogue: _dialogueOf(track, (
          id: entry.cut.id,
          start: entry.startFrame,
          panels: panels[index],
        )),
        project: project,
      ),
    );
  }
  // The work's own words, read where every paper form reads them — the
  // envelope's rule: an unnamed work prints the project's name.
  final info = project.timesheetInfo;
  return ConteSheetSource(
    cuts: cuts,
    title: info.titleOr(project.name),
    episode: info.episode,
    logoAssetPath: info.logoAssetPath,
    coverImagePath: info.coverImagePath,
    conteStaffName: info.staffNameFor(
      const LayerMark(process: LayerProcess.conte),
    ),
    framesPerSecond: project.frameRate.countingBase,
    cover: info.conteCover,
    blankPage: info.conteBlankPage,
    fixedText: info.conteFixedText,
  );
}

ConteCutSource _cutSource({
  required Cut cut,
  required String name,
  required List<StoryboardCoverageCell> cells,
  required int endFrame,
  required List<ConteDialogueLine> dialogue,
  required Project project,
}) {
  final storyboard = storyboardLayerForCut(cut);
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
          project: project,
        ),
    ],
    dialogue: dialogue,
  );
}

ConteCellSource _cellSource({
  required Cut cut,
  required StoryboardCoverageCell cell,
  required Layer? storyboard,
  required Project project,
}) {
  // The cell counts the conte's frames; the row, the camera and the picture
  // count the cut's, which begin that much earlier in a cut an O.L arrives
  // into (F-227).
  final conteStart = storyboardConteStart(storyboard?.timeline);
  final exposure = storyboard?.timeline[conteStart + cell.startIndex];
  return ConteCellSource(
    startFrame: cell.startIndex,
    endFrameExclusive: cell.endIndexExclusive,
    pictureFrame: storyboardCellPictureFrame(cell, conteStart: conteStart),
    frameId: cell.frameId,
    inkId: switch (exposure?.memo?.inkId) {
      final inkId? when inkId.isNotEmpty => inkId,
      _ => null,
    },
    action: exposure?.memo?.actionMemo ?? '',
    camera: _cameraWorkIn(
      cut,
      cell,
      project.cameraSize,
      conteStart: conteStart,
    ),
    // Over the cut's frames the cell shows — the span its camera work is
    // read over.
    cameraLines: _cameraLinesIn(
      cut,
      project,
      from: conteStart + cell.startIndex,
      to: conteStart + cell.endIndexExclusive,
    ),
  );
}

/// What [cut]'s camera does over its frames [from] to [to], a line to each
/// stretch ([conteCameraStretches]) in [project]'s glossary and count.
///
/// ⚠️Mine: a camera whose work is bypassed stands still — the camera row's
/// switch shows the canvas centred — so it is FIX throughout, as a camera
/// with no key is (I-93: 「값이 동일해서 안움직이고 있거나 키가 없는
/// 부분」).
List<String> _cameraLinesIn(
  Cut cut,
  Project project, {
  required int from,
  required int to,
}) {
  final moves = cut.layers.cameraWorkBypassed
      ? const <CameraMove>[]
      : cameraMoves(cut.camera.track);
  return [
    for (final stretch in conteCameraStretches(moves, from: from, to: to))
      conteCameraLine(
        stretch,
        defById: project.cameraInstructions.defById,
        framesPerSecond: project.frameRate.countingBase,
      ),
  ];
}

/// What the camera does while [cell] is on screen: its frame at the cell's
/// first and last frames and at each key between, as playback shows them
/// (`cameraFramesShown`, H54), the trail each corner draws between them as
/// the canvas draws it ([CameraPath.cornerTrailsBetween]) and the canvas
/// they sweep, trails and all — a turn's corners and a bent path run out
/// past the frames they leave and reach. Null while it holds still (every
/// one of those frames framing one place) or its work is bypassed (the
/// camera row's switch shows the canvas centred).
///
/// A window shows the widest of those frames whole ([_widestFrame]): a
/// frame is what the camera shows, so each frame of a pan takes a window
/// whatever the zoom, and a push-in's closer frame lies inside the wider.
///
/// A key's label is its NAME — the name the camera row's header shows for
/// it (`transformKeyAgreedNames`): its lanes agree on it — else the frame
/// it stands on, as every surface labels a key ([cameraKeyLabel], 유저
/// 2026-10-12); a key whose lanes disagree («...») is unnamed (유저
/// 2026-09-30: 「레인끼리 달라서 헤더가 ...으로 표시되는 경우 … 이름
/// 안정해진거랑 같은 규칙으로」).
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
  final trails =
      CameraPath.of(cut, cameraFrameSize)?.cornerTrailsBetween(
        frames.first.frameIndex,
        frames.last.frameIndex,
      ) ??
      const <List<Offset>>[];
  final names = transformKeyAgreedNames(cut.camera.track);
  return ConteCameraWork(
    screen: _widestFrame(corners),
    field: _wholePixelsAround(cameraFramesBounds([...corners, ...trails])),
    keys: [
      for (final (index, frame) in frames.indexed)
        _cameraKey(
          frame.corners,
          CameraKeyRole.at(index, frames.length),
          names[frame.frameIndex],
          frame.frameIndex,
        ),
    ],
    trails: trails,
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

/// A key [named] or not, on [frameIndex], as every surface labels it.
ConteCameraKey _cameraKey(
  List<Offset> corners,
  CameraKeyRole role,
  String? named,
  int frameIndex,
) => ConteCameraKey(
  corners: corners,
  role: role,
  label: cameraKeyLabel(named, frameIndex),
);

/// Frames of a track, `[start, end)`.
typedef _FrameSpan = ({int start, int end});

/// One panel on its track's frames, and the panels either side of it — the
/// one holding the frame before it and the one holding the frame after —
/// or null where the track has none there: its ends, a gap between cuts.
typedef _Panel = ({_FrameSpan span, _FrameSpan? before, _FrameSpan? after});

/// A cut as its dialogue column reads it: its id, the track frame it
/// starts on, and its panels.
typedef _CutPanels = ({CutId id, int start, List<_Panel> panels});

/// The panels of each cut of [layout] on its track's frames, cells
/// [cellsOf] — a cut's first panel stands next to the one before it on the
/// track, in the cut before.
List<List<_Panel>> _panelsOnTheirTracks(
  List<StoryboardTimelineLayoutEntry> layout,
  List<List<StoryboardCoverageCell>> cellsOf,
) {
  // Every panel in the order the layout lays them, track by track.
  final all = [
    for (final (cut, entry) in layout.indexed)
      for (final cell in cellsOf[cut])
        (
          cut: cut,
          track: entry.trackId,
          span: (
            start: entry.startFrame + cell.startIndex,
            end: entry.startFrame + cell.endIndexExclusive,
          ),
        ),
  ];
  _FrameSpan? holding(int at, TrackId track, int frame) {
    if (at < 0 || at >= all.length || all[at].track != track) {
      return null;
    }
    final span = all[at].span;
    return span.start <= frame && frame < span.end ? span : null;
  }

  final panels = [for (final _ in layout) <_Panel>[]];
  for (final (at, panel) in all.indexed) {
    panels[panel.cut].add((
      span: panel.span,
      before: holding(at - 1, panel.track, panel.span.start - 1),
      after: holding(at + 1, panel.track, panel.span.end),
    ));
  }
  return panels;
}

/// The cut's lines, read off the track's SE rows that print on paper
/// ([layerPrintsSheetLines], F-345) — each in its delivery in [cutId]
/// (F-386) — PANEL by panel.
///
/// The SE block's frame NAME is the line and its `seName` is the speaker
/// (design G) — the sheet reads them straight, which is why typing dialogue
/// into the conte later writes an SE entry rather than a second field.
///
/// 🗣️F-501 (유저 2026-10-29): 「콘티용지패널에 들어가는 se는 컷별로 구분하는게
/// 아니라 통일해서 패널별로 … 컷1 패널에 이름「ab / 컷2 패널에 cd」 즉
/// 이어지면 앞의 이름이랑 대사 표시 글자가 안적힘 … 글자가 위치할때만임.
/// 만약 블록 자체가 이어져있는데 해당 패널의 부분에만 띄어쓰기같은거로 인해
/// 글자가 없으면 안적히고, 다음 패널에서 이름「 이게 다시 들어감. 왜냐
/// 이전패널에서 한번 끊겼으니까」. A line is laid out ONCE over its whole
/// block ([dialogueGlyphSlots], F-496 ③) and each panel is a window on it
/// ([dialogueGlyphsShownIn]) — the cut by cut, half by half window the
/// timesheet's SE column paints through (F-358). A panel writes the glyphs
/// whose frame it holds; it opens on the speaker where the panel before
/// wrote none of the line, and closes where the panel after writes none.
/// ↩️Every cut the block reached wrote the whole line, in its first panel.
List<ConteDialogueLine> _dialogueOf(Track track, _CutPanels cut) {
  if (cut.panels.isEmpty) {
    return const [];
  }
  return [
    for (final layer in track.seLayers)
      if (layerPrintsSheetLines(layer))
        for (final block in drawingBlocks(layer.timeline))
          if (frameRangesOverlap(
            block.startIndex,
            block.endIndexExclusive,
            cut.panels.first.span.start,
            cut.panels.last.span.end,
          ))
            ..._partsOf(layer, block, cut),
  ]..sort((a, b) => a.startFrame.compareTo(b.startFrame));
}

/// What [cut]'s panels write of the line [block] of [layer] carries — each
/// the glyphs whose frame it holds, at the frame its first one stands on.
Iterable<ConteDialogueLine> _partsOf(
  Layer layer,
  TimelineDrawingBlock block,
  _CutPanels cut,
) sync* {
  final frame = layer.frameById(block.frameId);
  final glyphs = (frame?.name ?? '').characters.toList(growable: false);
  if (frame == null || glyphs.isEmpty) {
    return;
  }
  final slots = dialogueGlyphSlots(
    glyphCount: glyphs.length,
    frames: block.length,
    mainExtent: block.length.toDouble(),
    spacing: frame.seSpacing,
  );

  /// The glyphs [span] holds, or null where none of them shows.
  ({int first, String text})? partIn(_FrameSpan? span) {
    if (span == null) {
      return null;
    }
    final shown = dialogueGlyphsShownIn(
      slots,
      from: (span.start - block.startIndex).toDouble(),
      to: (span.end - block.startIndex).toDouble(),
    );
    final text = glyphs.sublist(shown.first, shown.end).join();
    return text.trim().isEmpty ? null : (first: shown.first, text: text);
  }

  for (final panel in cut.panels) {
    final part = partIn(panel.span);
    if (part == null) {
      continue;
    }
    final first = slots[part.first];
    yield ConteDialogueLine(
      // The frame its centre stands on: the one the panel holds it by.
      startFrame:
          (block.startIndex + first.cellStart + first.cellExtent / 2).floor() -
          cut.start,
      text: part.text,
      speaker: frame.seName ?? '',
      delivery: frame.seTypes.inCut(cut.id),
      opens: partIn(panel.before) == null,
      closes: partIn(panel.after) == null,
    );
  }
}

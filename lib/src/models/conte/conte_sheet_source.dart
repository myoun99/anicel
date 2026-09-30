/// What the conte sheet reads, with no idea where anything will be drawn.
///
/// The sheet's renderer is shared by the panel, the PNG export and the PDF
/// export (the timesheet's precedent: "the output IS the panel's picture,
/// there is no second layout"), so the layout takes a description like this
/// one and never reaches into the project. That is also what makes the
/// whole thing testable without a canvas.
library;

import 'dart:ui' show Offset, Rect, Size;

import '../cut_id.dart';
import '../frame_id.dart';

/// One panel of a cut, as the sheet reads it.
///
/// A cell is a frame BLOCK of the cut's storyboard row (the coverage rule's
/// cell). A cut with no storyboard row has exactly one, spanning it — the
/// degenerate case the design asked for, so the sheet has no empty rule.
class ConteCellSource {
  const ConteCellSource({
    required this.startFrame,
    required this.endFrameExclusive,
    required this.pictureFrame,
    this.frameId,
    this.inkId,
    this.action = '',
    this.camera,
  });

  /// Cut-LOCAL frames.
  final int startFrame;
  final int endFrameExclusive;

  /// The frame the picture composites at (the panel's own division, unless
  /// the cut's pinned thumbnail frame falls inside it).
  final int pictureFrame;

  /// The drawing in the cell, when it has one.
  final FrameId? frameId;

  /// The block's handwriting on the sheet — its exposure's
  /// `ExposureMemo.inkId`; null until the block is first written on.
  final String? inkId;

  /// The ACTION column's text — the exposure's `actionMemo`.
  final String action;

  /// What the camera does while the cell is on screen — or null while it
  /// holds still, every frame it shows in the cell framing one place. It
  /// decides how much of the sheet the cell's picture takes and what is
  /// drawn over it.
  final ConteCameraWork? camera;

  int get lengthFrames => endFrameExclusive - startFrame;
}

/// A cell's camera work, on the cut's canvas: the camera's frame at the
/// cell's first and last frames and at each key between (H54 — the camera
/// as the cell shows it, not only where it was keyed), the trail each
/// corner draws through them, and the canvas they sweep together — the
/// picture the cell shows (유저 2026-09-29: 「일단 카메라 팬대로 해당
/// 코마에서 보여주고」).
class ConteCameraWork {
  const ConteCameraWork({
    required this.screen,
    required this.field,
    required this.keys,
    required this.trails,
  });

  /// What one window shows, in canvas pixels: the widest of the key
  /// frames — a pushed-in frame lies inside it.
  final Size screen;

  /// The canvas the camera sweeps: every corner of every key.
  final Rect field;

  /// The camera's frames the cell marks, first to last: its first frame,
  /// each key between, its last frame — an end the camera stands at a key
  /// for being that key.
  final List<ConteCameraKey> keys;

  /// The trail each corner of the frame draws from key to key — four
  /// polylines, top-left first (`cameraCornerTrails`).
  final List<List<Offset>> trails;
}

/// Where a camera key stands among the cell's keys — what its frame shows
/// and which colour it wears.
enum ConteCameraKeyRole {
  /// The first key: its frame drawn, IN's green.
  first,

  /// A key between: no frame, only the turn of its trails — and its name,
  /// where it has one (유저 2026-09-30, after Storyboard Pro: 「첫/끝 키
  /// 말고 중간키는 실루엣을 안그려」).
  between,

  /// The last key: its frame drawn, OUT's red.
  last,
}

/// One camera frame the sheet marks: a key, or the camera at the cell's
/// first or last frame where no key stands (H54).
class ConteCameraKey {
  const ConteCameraKey({
    required this.corners,
    required this.role,
    this.label,
  });

  /// The camera's frame at the key, on the canvas: top-left first.
  final List<Offset> corners;

  final ConteCameraKeyRole role;

  /// What the sheet writes at the frame's top-left: the key's name, else
  /// IN for the first and OUT for the last; null for an unnamed key between
  /// (유저 2026-09-30: 「카메라 마크 이름있으면 A,B 이런식으로 이름
  /// 따라가고 없으면 스토리보드프로 규칙 그대로따라서 IN OUT」).
  final String? label;
}

/// A line of dialogue, as the sheet reads it. Dialogue lives on the SE
/// blocks and nowhere else (design G): the block's frame NAME is the line,
/// its `seName` the speaker.
class ConteDialogueLine {
  const ConteDialogueLine({
    required this.startFrame,
    required this.text,
    this.speaker = '',
  });

  /// Cut-LOCAL, clipped to the cut. A line that begins in an earlier cut
  /// arrives here clipped to 0 and marked [continuedFromPrevious].
  final int startFrame;
  final String text;
  final String speaker;

  /// The sheet's own rendering: `speaker「line」`, the shape a Japanese
  /// conte's DIALOGUE column uses. An unnamed speaker prints the line bare.
  String get printed => speaker.isEmpty ? text : '$speaker「$text」';
}

/// One cut's row band on the sheet.
class ConteCutSource {
  const ConteCutSource({
    required this.cutId,
    required this.name,
    required this.durationFrames,
    required this.cumulativeEndFrames,
    required this.cells,
    this.dialogue = const [],
  }) : assert(cells.length > 0, 'Every cut has at least one cell.');

  final CutId cutId;

  /// The cut's NAME is its number — a free string the user owns, not a
  /// position in the track (a reorder must not renumber the sheet).
  final String name;
  final int durationFrames;

  /// Frames from the movie's start to this cut's end — the sheet's running
  /// total, printed in the TIME column.
  final int cumulativeEndFrames;

  final List<ConteCellSource> cells;
  final List<ConteDialogueLine> dialogue;
}

/// The whole sheet's content.
class ConteSheetSource {
  const ConteSheetSource({
    required this.cuts,
    this.title = '',
    this.episode = '',
    this.logoAssetPath,
    this.coverImagePath,
    this.conteStaffName = '',
    this.framesPerSecond = 24,
  });

  final List<ConteCutSource> cuts;

  /// The work and the episode — the cover's words. A body page prints
  /// neither (유저 답 conte-body-header: its top is the page number and the
  /// logo).
  final String title;
  final String episode;

  /// The company logo each body page prints top-right; null prints none.
  final String? logoAssetPath;

  /// The cover's own picture (유저 답 conte-cover-image: 「표지 그림 칸을
  /// 따로」); null leaves its place empty.
  final String? coverImagePath;

  /// The conte artist the cover names (유저 답 conte-cover-staff:
  /// 「コンテ 한 줄」); empty prints no staff line.
  final String conteStaffName;

  final int framesPerSecond;

  /// The cut [cutId] names. Every cut a layout placed is here.
  ConteCutSource cutById(String cutId) =>
      cuts.firstWhere((cut) => cut.cutId.value == cutId);
}

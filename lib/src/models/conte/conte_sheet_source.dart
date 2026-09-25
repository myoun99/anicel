/// What the conte sheet reads, with no idea where anything will be drawn.
///
/// The sheet's renderer is shared by the panel, the PNG export and the PDF
/// export (the timesheet's precedent: "the output IS the panel's picture,
/// there is no second layout"), so the layout takes a description like this
/// one and never reaches into the project. That is also what makes the
/// whole thing testable without a canvas.
library;

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
    this.action = '',
    this.rowSpan = 1,
    this.encroachFraction = 0,
    this.cameraLabels = const [],
  }) : assert(rowSpan >= 1, 'A cell occupies at least one row.');

  /// Cut-LOCAL frames.
  final int startFrame;
  final int endFrameExclusive;

  /// The frame the picture composites at (the panel's own division, unless
  /// the cut's pinned thumbnail frame falls inside it).
  final int pictureFrame;

  /// The drawing in the cell, when it has one.
  final FrameId? frameId;

  /// The ACTION column's text — the exposure's `actionMemo`.
  final String action;

  /// How many sheet ROWS the cell takes.
  ///
  /// Camera work decides it (design): a vertical move claims one extra row
  /// per screen-height travelled, so a long PAN reads as a tall cell the way
  /// it does on paper. A non-integer amount leaves the remainder as margin,
  /// which is what hand-drawn sheets do too.
  final int rowSpan;

  /// How far the picture reaches INTO the text columns, as a fraction of
  /// the action column's width. A horizontal camera move widens the picture
  /// rather than moving the columns: the column positions are fixed for the
  /// whole sheet, and only the cells that need it encroach.
  final double encroachFraction;

  /// The camera frame labels drawn on the picture — the keyframe names when
  /// they have them, `IN`/`OUT` otherwise.
  final List<String> cameraLabels;

  int get lengthFrames => endFrameExclusive - startFrame;
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

  /// How many sheet rows the whole cut claims.
  int get rowSpan => cells.fold(0, (total, cell) => total + cell.rowSpan);
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

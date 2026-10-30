/// What the conte sheet reads, with no idea where anything will be drawn.
///
/// The sheet's renderer is shared by the panel, the PNG export and the PDF
/// export (the timesheet's precedent: "the output IS the panel's picture,
/// there is no second layout"), so the layout takes a description like this
/// one and never reaches into the project. That is also what makes the
/// whole thing testable without a canvas.
library;

import 'dart:ui' show Offset, Rect, Size;

import '../camera_work_marks.dart' show CameraKeyRole;
import '../cut_id.dart';
import '../frame_id.dart';
import '../se_line_type.dart';
import 'conte_camera_room.dart';

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
    this.cameraLines = const [],
    this.transitionLines = const [],
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

  /// What the camera does while the cell is on, as its ACTION column writes
  /// it over the words typed there — a line to each move and each stretch
  /// it stands still, `PAN (0+11)` (`conteCameraStretches`, I-93).
  final List<String> cameraLines;

  /// The transitions the cell's ACTION column writes under [cameraLines] —
  /// `c1 × c2 カットO.L (1+0)` (`conteTransitionLine`, I-93-Q1).
  final List<String> transitionLines;

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

  /// The canvas the camera sweeps: every corner of every key, and every
  /// trail between them.
  final Rect field;

  /// The camera's frames the cell marks, first to last: its first frame,
  /// each key between, its last frame — an end the camera stands at a key
  /// for being that key.
  final List<ConteCameraKey> keys;

  /// The trail each corner of the frame draws over the cell, as the canvas
  /// draws it — four polylines, top-left first
  /// (`CameraPath.cornerTrailsBetween`).
  final List<List<Offset>> trails;
}

/// One camera frame the sheet marks: a key, or the camera at the cell's
/// first or last frame where no key stands (H54).
class ConteCameraKey {
  const ConteCameraKey({
    required this.corners,
    required this.role,
    required this.label,
  });

  /// The camera's frame at the key, on the canvas: top-left first.
  final List<Offset> corners;

  /// Where it stands among the cell's keys: the cell's first frame, a key
  /// between, its last frame.
  final CameraKeyRole role;

  /// What the sheet writes at the frame's top-left corner: the key's name,
  /// else the frame it stands on, as every surface calls a key
  /// (`cameraKeyLabel`, 유저 2026-10-12). ↩️An unnamed first was IN and an
  /// unnamed last OUT (09-30 「없으면 스토리보드프로 규칙 그대로따라서 IN
  /// OUT」), an unnamed key between nothing.
  final String label;
}

/// A line of dialogue as one panel writes it. Dialogue lives on the SE
/// blocks and nowhere else (design G): the block's frame NAME is the line,
/// its `seName` the speaker — and a panel writes the part of the line that
/// stands on its frames (F-501).
class ConteDialogueLine {
  const ConteDialogueLine({
    required this.startFrame,
    required this.text,
    this.speaker = '',
    this.delivery = SeLineType.on,
    this.opens = true,
    this.closes = true,
  });

  /// Cut-LOCAL: the frame the part's first glyph stands on, inside the
  /// panel that writes it.
  final int startFrame;
  final String text;
  final String speaker;

  /// The line's delivery (I-20) — written after the speaker when the sheets
  /// print it ([SeLineType.writtenOut]).
  final SeLineType delivery;

  /// Whether this part begins the line as the sheet writes it — the
  /// speaker and `「` before it — or carries on what the panel before
  /// wrote; and whether it ends it, `」` after it (F-501).
  final bool opens;
  final bool closes;

  /// The sheet's own rendering: `speaker「line」`, the shape a Japanese
  /// conte's DIALOGUE column uses. An unnamed speaker prints the line bare.
  ///
  /// 🗣️I-20-Q2 (유저 2026-09-30): 「콘티 대사 칸에도 찍는다 — 이름 뒤 괄호」 —
  /// `speaker(OFF)「line」`, and only OFF · MONO (「ON일때는 … 콘티용지에는
  /// 표시하지않음」). A delivery with no speaker still says whose voice it is
  /// not: `(OFF)「line」`. 🗣️F-501: 「이어지면 앞의 이름이랑 대사 표시 글자가
  /// 안적힘」 — `speaker「ab` in one panel, `cd」` in the next.
  String get printed {
    final said = delivery.writtenOut ? '(${delivery.label})' : '';
    final who = '$speaker$said';
    if (who.isEmpty) {
      return text;
    }
    return '${opens ? '$who「' : ''}$text${closes ? '」' : ''}';
  }
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
    this.cameraRoom = ConteCameraRoom.grows,
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

  /// How much of the sheet its cells take where its camera moves — the
  /// cut's own, or the format window's where it has none (I-82-Q1).
  final ConteCameraRoom cameraRoom;
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
    this.cover = true,
    this.blankPage = true,
    this.fixedText = true,
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

  /// The pages before the body — the work's choice
  /// (`TimesheetInfo.conteCover` · `TimesheetInfo.conteBlankPage`), read
  /// here so that every book laid from this source (`layoutConteBook`) has
  /// the same front.
  final bool cover;
  final bool blankPage;

  /// Whether a cell writes its camera's lines and its transitions over its
  /// ACTION words ([ConteCellSource.cameraLines] ·
  /// [ConteCellSource.transitionLines]) — the work's choice
  /// (`TimesheetInfo.conteFixedText`), read here for the same reason.
  final bool fixedText;

  /// The cut [cutId] names. Every cut a layout placed is here.
  ConteCutSource cutById(String cutId) =>
      cuts.firstWhere((cut) => cut.cutId.value == cutId);
}

import 'package:flutter/material.dart';

import '../../models/frame.dart' show InbetweenMark;
import '../../models/layer.dart';
import '../text/word_condensation.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_exposure_block_visual.dart';

/// One row's frame cells as a single painter (UI-R9 #12b, the
/// painterization): the dense, mostly-static cell strip — paper blocks,
/// glyphs, ghost dim, band tints — is pure canvas work, so the per-cell
/// widget pipeline (Element + RenderObject + InkWell + Material ink +
/// Semantics per cell) is gone. Sparse interactive chrome (edge grips, run
/// handles, the range gesture layer, the cursor layer) stays widgets ON TOP.
///
/// Every row kind draws through it, and so does the instance-edit dialog's
/// miniature — the widget cell that once rendered the sparse kinds
/// (`TimelineFrameCell`) is gone (2026-09-24).
class TimelineRowCellModel {
  const TimelineRowCellModel({
    required this.frameIndex,
    required this.exposureState,
    required this.segment,
    required this.ghost,
    required this.dimmed,
    required this.glyph,
    required this.mark,
    required this.semanticsLabel,
  });

  final int frameIndex;
  final TimelineCellExposureState exposureState;
  final TimelineExposureBlockVisualSegment segment;
  final bool ghost;
  final bool dimmed;

  /// The text drawn in the cell ('' when none / too narrow).
  final String glyph;

  /// The in-between mark the cell wears, or null — a drawing with no cel
  /// number and the dot inside a block alike ([timelineCellMarker]). A cell
  /// with a mark writes no [glyph].
  final InbetweenMark? mark;
  final String? semanticsLabel;
}

/// What a stretch of a row lays down under its ink.
///
/// [paper]: one piece per run of cells that share a colour and meet without
/// a corner — a block is one fill, not a fill per cell. ⚡Per cell, every
/// cell paid the corner field over its whole box and a margin round it, and
/// neighbouring cells blended their shared edge twice at a fractional zoom.
///
/// [lines]: the frame lines across that paper, where the user shows them.
typedef TimelineRowSubstrate = ({
  List<({Rect rect, Color color, BorderRadius? radius})> paper,
  List<({Rect rect, Color color})> lines,
});

/// The hold ghost's dash glyph — the probe VALUE tests read from
/// [TimelineTileRasterSource.cellModelAt]. paint() renders it as an
/// axis-aligned line (UI-R12 #18), never as text; the tile emitter (T3)
/// keys the same value to bake it as a capsule.
const String timelineHoldDashGlyph = 'ㅡ';

/// WHAT A SUBSTRATE TILE IS RASTERED FROM — the row's geometry, its look
/// identity, and the ink answers the emitter must reproduce exactly.
///
/// ⛔THE PROBE-THE-PAINTER RULE IS THIS TYPE. The classic Dart pass and the
/// baked tile draw the same row two ways, and they cannot be allowed to
/// drift, so the emitter never re-derives a rect, a style or an ink — it
/// asks. Every member below already carried "PUBLIC contract shared by
/// paint() and the tile emitter" in its doc; naming them together is the
/// same rule with a type in front of it.
///
/// 🚨IT IS ALSO THE LOOK IDENTITY. A cached tile compares these values to
/// decide whether it still describes the row (`_TileEntry.matches`), which
/// is why the resolvers, the revision and the generation are here beside
/// the geometry: any fact that changes the picture has to be readable
/// through this one surface, or a stale tile serves the wrong pixels.
///
/// It exists as its own leaf so the store and the painter can each depend
/// on the CONTRACT instead of on each other — the store rasters through it
/// and the painter implements it. It must never import either of them
/// back; a leaf that re-exports its two readers is the loop wearing a hat.
abstract interface class TimelineTileRasterSource {
  /// #29: the (project, cut) world this source's RESOLVERS answer from —
  /// `'<projectId>:<cutId>'`. The store keys and gates on it, because the
  /// resolvers are live tear-offs: a tile request that outlives a cut
  /// switch would otherwise be rastered against another cut's answers.
  String get substrateGeneration;

  /// The row's layer. Layers are immutable, so an edit is a NEW instance
  /// and identity IS the edit test.
  Layer get layer;

  Axis get axis;

  /// What an unworked block's translucent paper is pre-blended onto — the
  /// host's ground (I-44: the grid sheet under the row must not show
  /// through a block). Baked into the tile, so it is part of the look.
  Color? get paperGround;

  /// Whether the frame lines cross a block's paper (Preferences ▸ Display,
  /// 유저 2026-09-24) — baked into the tile, so part of the look.
  bool get blockFrameLines;

  /// The counting fps: a second boundary's line is the strongest, so with
  /// [blockFrameLines] on it is part of the look too.
  int get framesPerSecond;

  /// What this row's COVERAGE follows, when that is not the layer itself
  /// (㉘: a camera row's keys live on `cut.camera`).
  Object? get coverageIdentity;

  double get crossAxisExtent;
  double get frameCellExtent;

  ColorScheme get colorScheme;

  /// The ambient text style the widget cells inherited (DefaultTextStyle).
  TextStyle get baseTextStyle;

  TimelineCellExposureState Function(Layer layer, int frameIndex)
  get exposureStateForLayer;
  String? Function(Layer layer, int frameIndex)? get frameNameForLayer;
  bool Function(Layer layer, int frameIndex)? get celHasContentForLayer;

  /// The unworked-block tint's version. Read LIVE, never captured: the row
  /// does NOT rebuild when a cel gains pixels — it repaints — so a value
  /// frozen at construction would hand the store yesterday's answer.
  int get celContentRevision;

  Rect cellRectFor(int frameIndex);
  TimelineRowCellModel cellModelAt(int frameIndex);

  /// What frames [from, to) lay down UNDER their ink, row-local — the
  /// classic pass paints exactly this and the tile bakes exactly this.
  TimelineRowSubstrate substrateIn(int from, int to);

  /// The glyph's ink. The tile emitter tints glyph blits with exactly this.
  Color foregroundInkFor(TimelineRowCellModel model);

  /// The glyph's resolved text style — the shared glyph cache and the tile
  /// emitter's bake key both read this.
  TextStyle glyphStyleFor(TimelineRowCellModel model);

  /// Where the word of the cell at [frameIndex] is laid, row-local, for a
  /// word of natural size [word], and how far it is narrowed (F-96: a name
  /// that outgrows its cell grows on into its block; B: it narrows only past
  /// the block). The tile emitter bakes its word exactly here, this narrow.
  ({Offset origin, WordFit fit}) cellWordLayoutFor(int frameIndex, Size word);

  /// Where the in-between mark of the cell at [frameIndex] stands, row-local,
  /// and how large it is. The tile emitter bakes the mark exactly here, in
  /// the cell's [foregroundInkFor].
  ({Offset center, double radius}) inbetweenMarkLayoutFor(int frameIndex);

  /// The nearest cell before [frameIndex] that writes a WORD, or null — the
  /// word that may grow into [frameIndex]'s cell from before it (F-96). A
  /// tile lays it at its first cell, as the classic pass does at a window's.
  int? wordCellBefore(int frameIndex);

  /// The cells of [from, to) that write — a word, a mark or a hold dash — in
  /// order. The tile emitter bakes exactly these, as the classic pass inks
  /// exactly these.
  Iterable<int> writingCellsIn(int from, int to);
}

/// #29: THE spelling of [TimelineTileRasterSource.substrateGeneration] — the
/// (project, cut) world a host's rows answer from. Every host that mounts
/// rows on the one tile store names its world here: the store keeps ONE
/// live generation and drops a raster request from any other, so two hosts
/// spelling the same world two ways would starve each other of tiles.
String timelineSubstrateGeneration({
  required String projectId,
  required String? cutId,
}) => '$projectId:${cutId ?? '-'}';

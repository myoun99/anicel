import 'package:flutter/material.dart';

import '../../models/frame.dart' show InbetweenMark;
import '../../models/layer.dart';
import '../text/word_condensation.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_exposure_block_visual.dart';
import 'timeline_frame_window.dart' show TimelineNextPage;

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

/// The hold ghost's glyph — the probe VALUE tests read from
/// [TimelineTileRasterSource.cellModelAt]. It is never written as text: a
/// hold is drawn as its line, which the row lays over its tiles (F-446).
const String timelineHoldGlyph = 'ㅡ';

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

  /// #29: whether this source's resolvers answer from the session's LIVE
  /// cut — a timeline row's read the active cut at drain time — so that a
  /// request of it dies once another world's rows paint
  /// ([substrateGeneration]).
  ///
  /// A row whose resolvers answer from its own layer and from the cuts that
  /// layer names answers the same whatever cut is live: the storyboard's
  /// conte row, laid over the film ([filmSubstrateGeneration]). The store
  /// neither takes its world for the live one nor drops its requests for
  /// another's — ↩️it painted every cell by hand at every opening, the
  /// storyboard's largest paint (frame-panels-build-in-one-frame, 10-24),
  /// because one live world could not hold both panels' rows.
  bool get followsTheLiveCut;

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

  /// The spans `[start, end)` a paint of this row asks the store for, in
  /// the order it asks: those under its window NOW (`shown`), then the one
  /// past each edge it keeps warm (`ahead`,
  /// [TimelineGridTileStore.warmAhead]). The store asks for them again
  /// itself when its queue had no room for this row.
  ({List<(int, int)> shown, List<(int, int)> ahead}) get tileSpans;

  /// Where a playing run's next turn stands this row's frame axis: its
  /// owner's answer, asked once for all the rows it lays
  /// ([TimelineGridTileStore.warmTheNextPage]). Null where no run turns it.
  TimelineNextPage? Function()? get nextPage;

  /// How many steps on the playing run shows this row's frame [frame] — the
  /// run's own order, the one its pictures are made and let go in
  /// (`FrameDemand.stepOf`), asked of its owner — and null for a frame the
  /// run does not show, or wherever nothing plays: what the store lets its
  /// tiles go by ([TimelineGridTileStore]). Null where no run reaches the
  /// row's owner.
  int? Function(int frame)? get stepsUntilShown;

  /// The spans a paint of this row asks for once the axis stands at
  /// [page] — the window there and the span past each of its edges
  /// ([tileSpans]), cut where the axis is built to there: what a run warms
  /// while it plays the page before.
  List<(int, int)> tileSpansOfThePage(TimelineNextPage page);

  /// Runs [reads] as ONE pass: however often they ask for a cell, it is
  /// resolved once — what a paint does, and what a tile bakes of a span.
  /// ⛔Never across an `await`: the answers come from the live session.
  T readInOnePass<T>(T Function() reads);

  /// What frames [from, to) lay down UNDER their ink, row-local — the
  /// classic pass paints exactly this and the tile bakes exactly this.
  TimelineRowSubstrate substrateIn(int from, int to);

  /// The glyph's ink. The tile emitter tints glyph blits with exactly this.
  Color foregroundInkFor(TimelineRowCellModel model);

  /// The glyph's resolved text style — the shared glyph cache and the tile
  /// emitter's bake key both read this.
  TextStyle glyphStyleFor(TimelineRowCellModel model);

  /// The word [text] of the cell at [frameIndex] as it is set there,
  /// row-local (F-96: a name that outgrows its cell grows on into its
  /// block): how far its letter gaps give way (F-234-Q1), where it is laid
  /// and how far it is still narrowed (B: only past the block). The tile
  /// emitter bakes its word exactly here, this tight.
  ({double tightening, Offset origin, WordFit fit}) cellWordSetFor(
    int frameIndex,
    String text,
    TextStyle style,
  );

  /// Where the in-between mark of the cell at [frameIndex] stands, row-local,
  /// and the box it fills. The tile emitter bakes the mark exactly here, in
  /// the cell's [foregroundInkFor].
  ({Offset center, Size size}) inbetweenMarkLayoutFor(int frameIndex);

  /// The cell before [frameIndex] whose WORD grows into [frameIndex]'s cell
  /// and is a tile's to bake ([bakedWritingCellsIn]), or null (F-96). A tile
  /// lays it at its first cell, as the classic pass does at a window's — and
  /// only where it reaches: a word laid where it cannot show would make two
  /// tiles of the same pixels bake apart (F-446).
  int? bakedWordGrowingInto(int frameIndex);

  /// The cells of [from, to) that write — a word or a mark — and that a tile
  /// bakes, in order: every one but a GHOST's ink, which the row lays over
  /// its tiles. The tile emitter bakes exactly these, as the classic pass
  /// inks exactly these. A hold writes in no cell: its line is a ghost's.
  ///
  /// 🗣️F-446 (유저 2026-10-23: 「엔드라인 드래그로 조절하는게 레이어가
  /// 많아질수록 렉이 심함」): a ghost is what the cut's length draws — the
  /// last run's ghost fills to the drawn end — so a tile that baked one
  /// baked again at every step of the end line, on every row a TVPaint cut
  /// has. The length stays out of the tiles, as the out-of-cut wash and the
  /// X (2026-08-02) already keep it out.
  Iterable<int> bakedWritingCellsIn(int from, int to);
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

/// The world of a row laid over the FILM from its own layer — the
/// storyboard's conte row — which follows no live cut
/// ([TimelineTileRasterSource.followsTheLiveCut]). One name for every
/// project: such a row is known by its layer's id, which is its track's.
const String filmSubstrateGeneration = 'film';

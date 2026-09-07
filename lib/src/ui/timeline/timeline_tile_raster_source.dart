import 'package:flutter/material.dart';

import '../../models/layer.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_exposure_block_visual.dart';

/// One DRAWING row's frame cells as a single painter (UI-R9 #12b, the
/// hybrid painterization): the dense, mostly-static cell strip — paper
/// blocks, borders, glyphs, ghost dim, band tints — is pure canvas work,
/// so the per-cell widget pipeline (Element + RenderObject + InkWell +
/// Material ink + Semantics per cell) disappears for the rows that carry
/// hundreds of cells. Sparse interactive chrome (edge grips, run handles,
/// the range gesture layer, the cursor layer) stays widgets ON TOP.
///
/// The visual contract mirrors `TimelineFrameCell` exactly — that widget
/// remains the renderer for the sparse row kinds (SE / instruction /
/// camera).
class TimelineRowCellModel {
  const TimelineRowCellModel({
    required this.frameIndex,
    required this.exposureState,
    required this.segment,
    required this.ghost,
    required this.dimmed,
    required this.glyph,
    required this.semanticsLabel,
  });

  final int frameIndex;
  final TimelineCellExposureState exposureState;
  final TimelineExposureBlockVisualSegment segment;
  final bool ghost;
  final bool dimmed;

  /// The text drawn in the cell ('' when none / too narrow).
  final String glyph;
  final String? semanticsLabel;
}

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

  /// The counting fps, for the seam law's beat strengths (D32/D38).
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

  /// The cell's RESOLVED paint style (dim blends, band tint, block radius).
  ({Color background, Color border, BorderRadius? radius}) resolvedCellStyleFor(
    int frameIndex,
  );

  /// The held-frame seam, or null. ONE line per boundary, drawn identically
  /// by both passes.
  ({Rect rect, Color color})? heldSeamLineFor(int frameIndex);

  /// The row's own ground seam, or null (chromeless rows have none).
  ({Rect rect, Color color})? rowSeamLineFor(int frameIndex);

  /// The glyph's ink. The tile emitter tints glyph blits with exactly this.
  Color foregroundInkFor(TimelineRowCellModel model);

  /// The glyph's resolved text style — the shared glyph cache and the tile
  /// emitter's bake key both read this.
  TextStyle glyphStyleFor(TimelineRowCellModel model);
}

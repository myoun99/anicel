import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer_kind.dart';
import '../models/storyboard_coverage.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnailResolver;
import '../models/timeline_row_address.dart';
import '../models/track_frame_range.dart';
import 'storyboard_layer_policy.dart';
import 'text/word_condensation.dart';
import '../models/storyboard_timeline_layout.dart';
import 'theme/app_theme.dart';
import 'timeline/inbetween_mark_painter.dart';
import 'timeline/timeline_cell_marker.dart'
    show TimelineCellWriting, timelineCellWritesNothing;
import 'timeline/timeline_cell_style.dart';
import 'timeline/timeline_frame_geometry.dart';
import 'timeline/timeline_frame_range_policy.dart'
    show timelineRunLengthLabel;
import 'timeline/timeline_frame_window.dart';
import 'timeline/timeline_glyph_cache.dart';
import 'repaint_props.dart';
import 'timeline/memo_token.dart';

/// The ground EVERY piece of CARRIED writing on a cut block receives — all
/// of it in the bands: the cut's own number and length, and each panel's
/// name and comma count (유저 2026-09-25: 「이름은 윗 띠, 코마는 아랫 띠」).
///
/// 🚨D29-2 (유저 2026-08-22) — **MAKE THE GROUND THE SAME, DON'T MEASURE
/// IT.** It takes no thumbnail argument, and that is the point: carried
/// writing never rides a picture, so there is nothing about the picture to
/// ask.
///
/// > 「컷블록 내 스토리보드레이어의 블록이름/코마수 텍스트가 아직도 컷블록
/// > 이랑 규칙 다름 … 그렇게 할거면 **타임라인도** 그렇게 해야하는거야.
/// > 통일이니까. 그런데 **무거우니까 하기싫고** 그냥 애초에 **받는 바탕을
/// > 똑같게** 하면 되는거 아닌가? **컷 제목이랑 스토리보드블록의
/// > 썸네일없는공간이랑 뭐가 다른거지?**」
///
/// ⛔My answer was to MEASURE the thumbnail's luminance, and the user struck
/// it down twice over: it would owe the timeline the same treatment, and it
/// is expensive. The answer was: nothing is different, once both are
/// carried. Before, the panel labels sat ON the thumbnails and took the
/// picture's ground — BLACK ink, while the cut's title, carried by its band,
/// resolved WHITE. Same block, two inks. D29-2 carried them on plates of this
/// fill over the picture; the plates covered the pictures, so since
/// 2026-09-25 the labels stand in the bands themselves.
Color storyboardCarriedWritingGround(
  StoryboardCutBlockVisual block,
  ColorScheme colorScheme,
) => storyboardCutBlockBackgroundColor(
  colorScheme,
  active: block.isActive,
  hovered: block.isHovered,
  rangeSelected: block.isRangeSelected,
);

/// One cut block as the painter draws it — THE probe surface, in place of
/// the widget keys the blocks used to carry.
class StoryboardCutBlockVisual {
  const StoryboardCutBlockVisual({
    required this.cutId,
    required this.rect,
    required this.isActive,
    required this.isRangeSelected,
    required this.isHovered,
    required this.title,
    required this.layerLabel,
    required this.hasStoryboardLayer,
    required this.total,
    required this.thumbnails,
    required this.cells,
    this.cellHeads = const [],
    this.cellCommaLabels = const [],
    required Rect topBand,
    required Rect strip,
    required Rect bottomBand,
  }) : _topBand = topBand,
       _strip = strip,
       _bottomBand = bottomBand;

  final CutId cutId;

  /// The block's box in ROW-local coordinates.
  final Rect rect;

  /// The three bands, in row-local coordinates. The STRIP is the picture:
  /// the cut's panels live there and nothing is written over them. The two
  /// thin bands carry ALL the writing — the cut's number at the left end of
  /// the top one and its length at the right end of the bottom one (the
  /// conte sheet's CUT and TIME columns laid on their side), and each
  /// panel's name over its head in the top one and its comma count under its
  /// end in the bottom one.
  ///
  /// 🗣️THE BANDS NEVER FOLD (유저 2026-09-25: 「띠는 v행 세로 줄어도 고정으로
  /// 그 자리에 두자」): a shorter row gives up picture, never writing. ↩️Under
  /// 44px they used to fold, and the writing fell back over the picture.
  Rect get topBand => _topBand;
  Rect get strip => _strip;
  Rect get bottomBand => _bottomBand;

  final Rect _topBand;
  final Rect _strip;
  final Rect _bottomBand;

  /// The cut's panels — the divisions the strip draws, under the coverage
  /// rule. Never empty: a cut with no storyboard row still has one cell.
  final List<StoryboardCoverageCell> cells;

  /// What each panel's head writes (#15: the timeline convention — the
  /// frame's cel number, or the in-between mark when it has none,
  /// [drawingHeadOf]), parallel to [cells]; nothing on the no-row
  /// placeholder cell. Written in the TOP band, over the panel's head.
  final List<TimelineCellWriting> cellHeads;

  /// Each panel's printed length (#15: the timeline's comma count), parallel
  /// to [cells]; empty on the no-row placeholder cell. Written in the
  /// BOTTOM band, under the panel's end.
  final List<String> cellCommaLabels;

  final bool isActive;
  final bool isRangeSelected;
  final bool isHovered;

  /// The cut's name, drawn top-left.
  final String title;

  /// The storyboard layer's name, or the empty-state wording when the cut
  /// has no storyboard layer.
  final String layerLabel;
  final bool hasStoryboardLayer;

  /// The cumulative time at the cut's end (the conte sheet's TIME column),
  /// or null when the block is too narrow to print it.
  final String? total;

  /// One picture per [cells] entry, in the same order — null while a
  /// render is pending (that cell shows its placeholder then). Owned by the
  /// thumbnail store.
  final List<ui.Image?> thumbnails;
}

/// THE cut row's picture, built from the material every drawer of it has:
/// the track's layout entries and the room to draw them in.
///
/// D15 (유저 2026-08-21): the folded storyboard has to show the row it
/// folded, and 「썸네일 띄움 · 텍스트같은것도 같은 규칙따라서 위치 맞춤」 is
/// not a list of features to re-implement over there — it is what asking
/// the SAME painter gets you. The two derived maps are the reason this is
/// a function rather than a constructor call at each site: resolving a
/// cut's storyboard-layer name and its coverage cells by hand is exactly
/// the copy that drifts, and the row already had to do both.
///
/// The interactive inputs stay optional, so a display-only host (the
/// collapsed row) omits them and gets the same picture minus the states
/// nothing can enter: no selection tint, no hover.
StoryboardCutBlocksPainter storyboardCutBlocksPainterFor({
  required List<StoryboardTimelineLayoutEntry> entries,
  required TimelineFrameGeometryHandle geometry,
  required double crossAxisExtent,
  required double minBlockWidth,
  required CutId? activeCutId,
  required TimelineRowAddress rowAddress,
  required ColorScheme colorScheme,
  required Brightness brightness,
  required TextStyle baseTextStyle,
  required bool showSeconds,
  required int countingBase,
  ValueListenable<TrackFrameRangeSelection?>? selectedRange,
  ValueListenable<CutId?>? hoveredCutId,
  StoryboardThumbnailResolver? thumbnailFor,
  ValueListenable<int>? windowBucket,
  double viewportMainExtent = 0,
}) => StoryboardCutBlocksPainter(
  entries: entries,
  // Resolved HERE, not in the painter: a cut holding two storyboard
  // layers is a StateError, and a painter that throws takes the frame
  // down with it.
  storyboardLayerNames: {
    for (final entry in entries)
      if (storyboardLayerForCut(entry.cut) case final layer?)
        entry.cutId: layer.name,
  },
  // The STRIP's content: the cut's panels, under the coverage rule — the
  // same reading the row's edge grips hang on and its flip steps through.
  storyboardCellsByCut: storyboardCellsByCut(entries),
  geometry: geometry,
  crossAxisExtent: crossAxisExtent,
  minBlockWidth: minBlockWidth,
  activeCutId: activeCutId,
  selectedRange: selectedRange,
  rowAddress: rowAddress,
  hoveredCutId: hoveredCutId ?? _noHover,
  colorScheme: colorScheme,
  brightness: brightness,
  baseTextStyle: baseTextStyle,
  showSeconds: showSeconds,
  countingBase: countingBase,
  thumbnailFor: thumbnailFor,
  showThumbnails: thumbnailFor != null,
  windowBucket: windowBucket,
  viewportMainExtent: viewportMainExtent,
);

/// The hover channel for hosts that have no pointer to hover with — a
/// single shared constant rather than one notifier per build, which would
/// re-subscribe the painter's `repaint` merge every pass.
final ValueNotifier<CutId?> _noHover = ValueNotifier<CutId?>(null);

/// The cut row's blocks, PAINTED (the storyboard's half of the timeline's
/// row painterization).
///
/// The row used to be three widgets a cut — the block, plus a grip at each
/// edge — laid into one `Stack` for the whole track, so a zoom step relaid
/// out every cut on the film and every build asked the thumbnail store for
/// every cut's picture. The timeline solved this years of rounds ago: cells
/// are canvas work and only the sparse interactive chrome stays widgets.
/// This is the same treatment for cuts, which lets the row take the shared
/// frame WINDOW as well — off-screen cuts cost nothing, thumbnails included.
///
/// Only the drawing lives here. Selecting, sliding and reordering are the
/// shared range gesture's, mounted above.
class StoryboardCutBlocksPainter extends CustomPainter with RepaintOnProps {
  StoryboardCutBlocksPainter({
    required this.entries,
    required this.storyboardLayerNames,
    required this.storyboardCellsByCut,
    required this.geometry,
    required this.crossAxisExtent,
    required this.minBlockWidth,
    required this.activeCutId,
    required this.selectedRange,
    required this.rowAddress,
    required this.hoveredCutId,
    required this.colorScheme,
    required this.brightness,
    required this.baseTextStyle,
    required this.showSeconds,
    required this.countingBase,
    this.thumbnailFor,
    this.showThumbnails = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
  }) : super(
         repaint: Listenable.merge([
           geometry,
           ?selectedRange,
           hoveredCutId,
           ?windowBucket,
         ]),
       );

  final List<StoryboardTimelineLayoutEntry> entries;

  /// Each cut's storyboard layer NAME, or absent when the cut has none.
  ///
  /// Resolved by the row at build time as shared inputs (the grips read
  /// the same cells). [storyboardLayerForCut] stopped throwing on
  /// duplicate rows (#760) — "the first one is the row" — so the painter
  /// may also call it directly where it needs more than these carry (the
  /// per-panel frame names).
  final Map<CutId, String> storyboardLayerNames;

  /// Each cut's panels (the coverage rule's cells), resolved by the row —
  /// the strip's content AND its grip material, one resolution for both.
  /// A cut always has at least one.
  final Map<CutId, List<StoryboardCoverageCell>> storyboardCellsByCut;

  /// The LIVE frame-axis geometry: a zoom step repaints instead of
  /// rebuilding the row that built this.
  final TimelineFrameGeometryHandle geometry;

  final double crossAxisExtent;

  /// Blocks never draw narrower than this, however short the cut — the
  /// `TimelineScale` rule the widget blocks were sized by.
  final double minBlockWidth;

  final CutId? activeCutId;

  /// The live frame RANGE on this track's global axis. A block is selected
  /// when the range COVERS it — the cut row is a frame-axis row and a cut
  /// is a long block on it, so there is no list of selected cuts to carry.
  final ValueListenable<TrackFrameRangeSelection?>? selectedRange;

  /// This row's address, so a selection anchored on another row (an S row,
  /// once those select too) does not tint these blocks.
  final TimelineRowAddress rowAddress;
  final ValueListenable<CutId?> hoveredCutId;

  final ColorScheme colorScheme;
  final Brightness brightness;
  final TextStyle baseTextStyle;
  final bool showSeconds;
  final int countingBase;

  /// Painted, never disposed here: the thumbnail store owns the image.
  /// Asked ONLY for blocks inside the window, which is the point.
  final StoryboardThumbnailResolver? thumbnailFor;
  final bool showThumbnails;

  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  static const double _padding = 4;
  /// The CUT PLATE's corner — the V row's block, the one the standing
  /// outline wraps when you stand on a cut. Not the frame-block law: the
  /// plate is a container with bands, and it is the ONE rounded thing in it —
  /// what sits inside is square and clipped by this corner (유저 2026-09-26:
  /// 「블록이 모서리 둥근건 블록 자체」). ↩️The panels inside it wore the
  /// frame-block law until then.
  static const double plateCornerRadius = 8;

  /// The narrowest block that still prints its total (the widget rule).
  static const double totalLabelMinWidth = 48;

  double get _cellExtent => geometry.value.frameCellExtent;

  /// A frame's leading edge in the ROW's coordinates — measured from the
  /// geometry's first frame, which is the contract every row painter keeps
  /// ([TimelineFrameGeometry.leadingFrameSpacerWidth]: 「[frameStartIndex]'s
  /// leading edge in the ROW's own coordinates」).
  ///
  /// ⚠️This was `frame * cell`, which is the same number only while the
  /// geometry starts at frame 0 with no spacer — and the panel's always
  /// does, so nothing ever showed it. The folded track row's geometry starts
  /// at the first VISIBLE frame (F-143), and there `frame * cell` put every
  /// block that many cells too far right.
  double _left(int frame) =>
      geometry.value.leadingFrameSpacerWidth +
      (frame - geometry.value.frameStartIndex) * _cellExtent;

  double _widthFor(int duration) {
    final width = duration * _cellExtent;
    return width < minBlockWidth ? minBlockWidth : width;
  }

  /// The frame span worth drawing — the full track under the classic
  /// contract, the bucket-derived window (shared policy) when the row is
  /// self-windowing.
  ({int startIndex, int endIndexExclusive}) visibleFrameWindow() {
    final bucket = windowBucket;
    if (bucket == null || viewportMainExtent <= 0 || _cellExtent <= 0) {
      return (startIndex: 0, endIndexExclusive: 1 << 30);
    }
    return timelineFrameWindowFor(
      bucket: bucket.value,
      cellExtent: _cellExtent,
      viewportExtent: viewportMainExtent,
    );
  }

  /// The thin bands' height — at every row height: they never fold
  /// ([StoryboardCutBlockVisual.topBand]).
  static const double bandHeight = 13;

  /// The STRIP's vertical slot in a row this tall, row-local — what the
  /// bands leave. The panels are drawn there, so the panel gestures are
  /// mounted there too: one definition, or the picture and the pointer
  /// disagree.
  static ({double top, double height}) stripBandOf(double rowHeight) => (
    top: bandHeight,
    height: math.max(0.0, rowHeight - bandHeight * 2),
  );

  /// A block's three bands: the two thin ones at its top and bottom, and
  /// the strip between them ([stripBandOf]).
  ({Rect top, Rect strip, Rect bottom}) _bandsOf(Rect rect) {
    final band = stripBandOf(rect.height);
    return (
      top: Rect.fromLTWH(rect.left, rect.top, rect.width, bandHeight),
      strip: Rect.fromLTWH(
        rect.left,
        rect.top + band.top,
        rect.width,
        band.height,
      ),
      bottom: Rect.fromLTWH(
        rect.left,
        rect.bottom - bandHeight,
        rect.width,
        bandHeight,
      ),
    );
  }

  /// One cut's block, or null when it lies outside the visible window:
  /// its rect and bands, the cells with their names and comma labels, the
  /// selection and hover state, the title
  /// and layer label, the total when the block is wide enough, and the
  /// thumbnails when they are shown.
  StoryboardCutBlockVisual? _visualFor(
    StoryboardTimelineLayoutEntry entry, {
    required ({int startIndex, int endIndexExclusive}) window,
    required TrackFrameRangeSelection? selection,
    required CutId? hovered,
  }) {
    final left = _left(entry.startFrame);
    final width = _widthFor(entry.duration);
    // A block reaches at least [minBlockWidth], so its visible end is
    // measured in pixels, not in the cut's own frames.
    final endFrame = _cellExtent <= 0
        ? entry.endFrame
        : entry.startFrame + (width / _cellExtent).ceil();
    if (endFrame <= window.startIndex ||
        entry.startFrame >= window.endIndexExclusive) {
      return null;
    }
    final layerName = storyboardLayerNames[entry.cutId];
    final rect = Rect.fromLTWH(left, 0, width, crossAxisExtent);
    final bands = _bandsOf(rect);
    final cells = storyboardCellsByCut[entry.cutId] ?? const [];
    final writing = _cellWriting(entry, cells);
    return StoryboardCutBlockVisual(
      cutId: entry.cutId,
      rect: rect,
      topBand: bands.top,
      strip: bands.strip,
      bottomBand: bands.bottom,
      cells: cells,
      cellHeads: writing.heads,
      cellCommaLabels: writing.commaLabels,
      isActive: entry.cutId == activeCutId,
      isRangeSelected:
          selection?.overlaps(entry.startFrame, entry.endFrame) ?? false,
      isHovered: entry.cutId == hovered,
      title: entry.cut.name,
      // D27: no explanatory copy — an empty layer slot reads as ''.
      layerLabel: layerName ?? '',
      hasStoryboardLayer: layerName != null,
      // ↩️F-89 (유저 2026-09-12): 「컷블록의 컷 길이 텍스트가 실제 컷길이랑
      // 다름 … 프레임블록이랑 똑같은거니까 거기서 사용하는 로직 그대로
      // 재사용」 — the cut's own length, by the frame blocks' run label. It
      // printed the running END frame, the conte sheet's TIME column (D23),
      // which the conte sheet itself keeps.
      total: width >= totalLabelMinWidth
          ? timelineRunLengthLabel(
              entry.endFrame - entry.startFrame,
              showSeconds: showSeconds,
              countingBase: countingBase,
            )
          : null,
      thumbnails: _thumbnailsFor(entry, cells),
    );
  }

  /// The panels' writing (#15): frame name + comma count per cell, the
  /// timeline row's conventions (an unnamed head wears the in-between
  /// mark). Safe to resolve here — the row lookup no
  /// longer throws on duplicates (#760).
  ///
  /// ↩️#15 kept the unnamed head HOLLOW (`○`) precisely so it would NOT
  /// read as the in-between dot (`●`). 유저 reversed that on 2026-09-16
  /// (F-149): 「일단 이름 없는 기본상태를 속이 찬 동그라미로 통일적용 …
  /// 당장은 제거」 — an unnamed drawing IS an in-between mark, so reading as
  /// one is the point now, and the storyboard follows by asking the same
  /// [drawingHeadOf] as the timeline — the mark as data since
  /// 2026-09-24 (유저: 「중간나누기 마크1로서 작동했으면」).
  /// ↩️And back to no mark on 2026-09-26 (유저: 「콘티레이어는 이름 없으면
  /// 진짜 이름 없도록 … 애니메이션 이외 레이어는 이름없으면 진짜
  /// 이름없도록」) — still by asking [drawingHeadOf], which answers per kind
  /// ([LayerKind.unnamedDrawingIsInbetween]): the band keeps its place and
  /// writes nothing.
  ({List<TimelineCellWriting> heads, List<String> commaLabels}) _cellWriting(
    StoryboardTimelineLayoutEntry entry,
    List<StoryboardCoverageCell> cells,
  ) {
    final frameNames = <FrameId, String?>{
      for (final frame
          in storyboardLayerForCut(entry.cut)?.frames ?? const <Frame>[])
        frame.id: frame.name,
    };
    return (
      heads: [
        for (final cell in cells)
          if (cell.frameId == null)
            timelineCellWritesNothing
          else
            drawingHeadOf(
              frameNames[cell.frameId],
              kind: LayerKind.storyboard,
            ),
      ],
      commaLabels: [
        for (final cell in cells)
          // D23: a 1-comma panel prints nothing — the shared
          // predicate, through the existing empty-string convention
          // the paint path already skips. (The block's bottom-right
          // `total` is a running END frame, not a comma length — it
          // stays un-gated on purpose.)
          // ↩️F-89 (유저 2026-09-12): the total is the cut's own length now,
          // by this same label.
          if (cell.frameId == null)
            ''
          else
            timelineRunLengthLabel(
                  cell.endIndexExclusive - cell.startIndex,
                  showSeconds: showSeconds,
                  countingBase: countingBase,
                ) ??
                '',
      ],
    );
  }

  /// One picture per PANEL, each at the frame that panel is about — asked
  /// ONLY for blocks the window keeps: the row used to request every
  /// cut's picture on every build.
  List<ui.Image?> _thumbnailsFor(
    StoryboardTimelineLayoutEntry entry,
    List<StoryboardCoverageCell> cells,
  ) => [
    if (showThumbnails && thumbnailFor != null)
      for (final cell in cells)
        thumbnailFor!(
          entry.cut,
          storyboardCellPictureFrame(
            cell,
            pinnedFrameIndex: entry.cut.metadata.thumbnailFrameIndex,
          ),
        ),
  ];

  /// Every block this row would draw, in track order — THE probe surface.
  ///
  /// Off-window cuts are absent by construction, which is also what keeps
  /// [thumbnailFor] from being asked for pictures nobody can see.
  List<StoryboardCutBlockVisual> blocks() {
    final window = visibleFrameWindow();
    final selectionValue = selectedRange?.value;
    final selection =
        selectionValue != null && selectionValue.coversRow(rowAddress)
        ? selectionValue
        : null;
    final hovered = hoveredCutId.value;
    final visuals = <StoryboardCutBlockVisual>[];
    for (final entry in entries) {
      final visual = _visualFor(
        entry,
        window: window,
        selection: selection,
        hovered: hovered,
      );
      if (visual != null) {
        visuals.add(visual);
      }
    }
    return visuals;
  }

  /// D30: the CREATE affordance a block actually wears, or null — ONE
  /// eligibility AND geometry for the painter and the press layer (this
  /// row's rule: where it is drawn is where it is hit, and only what is
  /// drawn is pressable). EVERY layerless block wears it. A small
  /// square centred in the strip.
  ///
  /// 🚨H13 (유저 2026-08-22) — **NO ACTIVE-CUT RULE.**
  ///
  /// > 「컷블록에 스토리보드레이어 없을때 뜨는 스토리보드레이어 추가버튼,
  /// > **액티브컷에만 띄우는게아니라 그런 규칙 두지말고** 그냥 다른
  /// > 컷블록도 없으면 띄우도록」
  ///
  /// ⚠️`|| !block.isActive` used to stand here, and the reason it stood
  /// was real: a press ACTIVATES the cut it lands on, so if the affordance
  /// were read after that activation, one press would both select and
  /// create. D30 answered that with two guards — this one, and the press
  /// layer judging the PRE-press snapshot.
  ///
  /// ★The second guard is the one that carries the weight, and it still
  /// stands. What this one added was a DISAGREEMENT between the two: on a
  /// non-active cut the '+' was not drawn, so the tap that landed on it
  /// had to mean something else. Drawing the '+' everywhere removes the
  /// disagreement rather than relaxing it — pre-press and post-press now
  /// answer the same, so pressing a '+' the user can SEE creates, which is
  /// this row's rule read straight.
  static Rect? createAffordanceRectOf(StoryboardCutBlockVisual block) {
    if (block.hasStoryboardLayer) {
      return null;
    }
    // A strip too narrow or too flat to hold the whole square holds NO
    // affordance: a clamped-width block's extra pixels map to frames
    // past the cut (the press could light a '+' it can never honour),
    // and an unclamped 22px box would paint over the neighbour. The
    // add-layer verb stays reachable through the layer rail's own +.
    if (block.strip.width < 22 || block.strip.height <= 8) {
      return null;
    }
    return Rect.fromCenter(
      center: block.strip.center,
      width: 22,
      height: math.min(22, block.strip.height),
    );
  }

  /// The block covering row-local [position], or null between blocks.
  StoryboardCutBlockVisual? blockAt(Offset position) {
    for (final block in blocks()) {
      if (block.rect.contains(position)) {
        return block;
      }
    }
    return null;
  }

  StoryboardCutBlockVisual? blockForCut(CutId cutId) {
    for (final block in blocks()) {
      if (block.cutId == cutId) {
        return block;
      }
    }
    return null;
  }

  TextStyle get _labelStyle =>
      baseTextStyle.merge(const TextStyle(fontSize: 11));

  // The CELLS' writing convention on every cut-block label too (user
  // 2026-07-29, "cut blocks and storyboard blocks read as one"): panel ink
  // carried by the shared GROUND LAW (2026-08-17, the difference blend's
  // successor) — one solid, black or white by the luminance of the fill
  // each label sits on, in place of scrims, halos and per-surface colours.
  // The styles' colors are layout/cache identity; the paint resolves the
  // real ink through [paintTimelineGlyphOnGround].
  TextStyle get _titleStyle => _labelStyle.copyWith(
    color: timelineDrawingInkColor,
    fontWeight: FontWeight.bold,
  );

  /// The bands' LENGTH words — the cut's length and each panel's comma
  /// count. D29: the cut-block text grade, the same 11 the title wears, not
  /// a cell-fitted 9 that shrank to ~6px at storyboard zooms.
  TextStyle get _totalStyle => _labelStyle.copyWith(
    color: timelineDrawingInkColor.withValues(alpha: 0.72),
    // R27 #3: bold — the readout was too easy to miss.
    fontWeight: FontWeight.w700,
  );

  /// The BANDS' composited fill — the ground ALL of the block's writing
  /// sits on. The bands wear the range tint whenever the block is
  /// range-selected, so this is one expression of the same fills
  /// [_paintBlock] lays down.
  Color _bandGround(StoryboardCutBlockVisual block) =>
      storyboardCarriedWritingGround(block, colorScheme);

  /// The block's own fill at rest in its state — the plate under the
  /// strip, and the ground of the one mark the strip carries without
  /// pictures. The strip never takes the range tint: a selection colours
  /// what is NOT the picture.
  Color _stripGround(StoryboardCutBlockVisual block) =>
      storyboardCutBlockBackgroundColor(
        colorScheme,
        active: block.isActive,
        hovered: block.isHovered,
        rangeSelected: false,
      );

  /// The ground the create `+` sits on in the strip (D29 — B1's twin, for
  /// text): with thumbnails on, it rides the paper-white composite pictures,
  /// and reading the dark plate there resolved WHITE ink on white
  /// thumbnails. Without thumbnails the plate is honest.
  ///
  /// ⚠️It is for the one mark with NOWHERE else to go. Writing that can
  /// stand in a band does ([storyboardCarriedWritingGround]), which makes
  /// its ground true rather than a guess at the picture under it.
  Color _stripWritingGround(StoryboardCutBlockVisual block) =>
      showThumbnails ? storyboardPanelPictureGroundColor : _stripGround(block);

  @override
  void paint(Canvas canvas, Size size) {
    for (final block in blocks()) {
      _paintBlock(canvas, block);
    }
  }

  void _paintBlock(Canvas canvas, StoryboardCutBlockVisual block) {
    final rrect = RRect.fromRectAndRadius(
      block.rect,
      const Radius.circular(plateCornerRadius),
    );
    // The BACKGROUND carries the cut's own states. A range selection tints
    // only what is NOT the picture (design: "a cut selection colours the
    // area that is not a storyboard block") — the bands.
    canvas.drawRRect(rrect, Paint()..color = _stripGround(block));
    if (block.isRangeSelected) {
      final tint = Paint()..color = _bandGround(block);
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(block.topBand, tint);
      canvas.drawRect(block.bottomBand, tint);
      canvas.restore();
    }

    final inner = block.strip;
    if (showThumbnails && inner.width > 0 && inner.height > 0) {
      canvas.save();
      canvas.clipRRect(rrect);
      _paintPanelPictures(canvas, block, inner);
      canvas.restore();
    }
    // The panels separate through their own SILHOUETTE borders (#15,
    // painted per slot above) — the divider question #760 left open is
    // closed by those, not by a rule of their own.

    // D30: the ACTIVE cut with NO storyboard layer swaps the reserved
    // strip slot's content to the CREATE affordance — an icon, not copy.
    // Eligibility and rect are [createAffordanceRectOf]'s, shared with
    // the press layer.
    if (createAffordanceRectOf(block) case final affordance?) {
      canvas.drawRect(
        // The slot a panel would fill, so it is as square as a panel's
        // picture (유저 2026-09-26 — the rounding is the plate's).
        affordance,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = storyboardCutBlockEdgeColor(
            colorScheme,
            brightness,
            active: false,
            hovered: block.isHovered,
          ),
      );
      final plusStyle = _labelStyle.copyWith(
        fontWeight: FontWeight.w700,
        color: timelineDrawingInkColor,
      );
      final glyph = timelineGlyphPainter('+', plusStyle);
      paintTimelineGlyphOnGround(
        canvas,
        Offset(
          affordance.center.dx - glyph.width / 2,
          affordance.center.dy - glyph.height / 2,
        ),
        '+',
        plusStyle,
        // The WRITING ground (D29): a no-layer cut still paints its
        // coverage cell's paper-white composite across the strip, so
        // reading the dark plate here would resolve white-on-white.
        ground: _stripWritingGround(block),
      );
    }

    // ONE border for every cut block. The active cut used to wear a 2px
    // accent one here — this rail's own way of saying "the block you are
    // standing on", invented because the storyboard was never unified with
    // the timeline. The standing outline says it now, in the timeline's
    // words and on every row kind, so a second sentence in the same place
    // is just two borders on one rectangle. Which cut is ACTIVE still
    // reads from the BACKGROUND: a different statement, a different
    // channel, and the one that survives standing somewhere else.
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = storyboardCutBlockEdgeColor(
          colorScheme,
          brightness,
          active: false,
          hovered: block.isHovered,
        ),
    );

    // THE BANDS carry the writing, so nothing is drawn over the picture and
    // no scrim is needed. Number at the top band's left end, length at the
    // bottom band's right end: the conte sheet's CUT and TIME columns sit
    // outside the picture cell exactly this way, one above and one below,
    // and this is that sheet turned on its side — with each panel's name
    // and length beside them.
    final bandGround = _bandGround(block);
    canvas.save();
    canvas.clipRect(block.topBand);
    final title = _paintBandText(
      canvas,
      text: block.title,
      style: _titleStyle,
      band: block.topBand,
      alignRight: false,
      ground: bandGround,
    );
    _paintPanelHeads(canvas, block, after: title?.right, ground: bandGround);
    canvas.restore();

    canvas.save();
    canvas.clipRect(block.bottomBand);
    // D27: a cut with no storyboard layer prints NOTHING in the left end
    // of its bottom band — the explanatory copy is gone (blocks WITH a
    // layer never printed anything there either; the band and its total
    // stay, the reserved slot the create affordance swaps into).
    final total = block.total;
    final length = total == null
        ? null
        : _paintBandText(
            canvas,
            text: total,
            style: _totalStyle,
            band: block.bottomBand,
            alignRight: true,
            ground: bandGround,
          );
    _paintPanelCommas(canvas, block, before: length?.left, ground: bandGround);
    canvas.restore();
  }

  /// Each panel's head in the TOP band, over the panel — its cel number, or
  /// the in-between mark ([drawingHeadOf]) — at the panel's left, and never
  /// before [after], where the cut's title ends.
  ///
  /// 🗣️유저 2026-09-25, to 「패널의 이름·코마 글씨가 썸네일을 가린다」: 「띠로
  /// 옮긴다 — 이름은 윗 띠, 코마는 아랫 띠」. ↩️D29-2 (유저 2026-08-22: 「받는
  /// 바탕을 똑같게」) had carried the panel writing over the picture on
  /// plates of the band's own fill — the ground was right, but the plates
  /// covered the pictures. In the band the ground IS the band's. The panel's
  /// LEFT stays its anchor: the cut title's own (유저 2026-07-29).
  void _paintPanelHeads(
    Canvas canvas,
    StoryboardCutBlockVisual block, {
    required double? after,
    required Color ground,
  }) {
    final band = block.topBand;
    final heads = block.cellHeads;
    for (var index = 0; index < heads.length; index += 1) {
      final span = _panelSpan(block, block.cells[index]);
      final room = Rect.fromLTRB(
        after == null ? span.left : math.max(span.left, after),
        band.top,
        span.right,
        band.bottom,
      );
      final head = heads[index];
      final mark = head.mark;
      if (mark != null) {
        _paintBandMark(canvas, mark, room, ground);
      } else {
        _paintBandText(
          canvas,
          text: head.word,
          style: _titleStyle,
          band: room,
          alignRight: false,
          ground: ground,
        );
      }
    }
  }

  /// An in-between mark where a band's word would stand at the left of
  /// [room] — in a square as high as that word — fitted into the room the
  /// way the timeline's marks are ([timelineInbetweenMarkRadius]). A room
  /// too narrow for the square keeps the mark at its middle, smaller, as a
  /// word there would narrow rather than go.
  void _paintBandMark(
    Canvas canvas,
    InbetweenMark mark,
    Rect room,
    Color ground,
  ) {
    if (room.width <= 0) {
      return;
    }
    final style = _titleStyle;
    final side = timelineGlyphPainter('', style).height;
    paintInbetweenMark(canvas, mark, (
      center: Offset(
        math.min(room.left + _padding + side / 2, room.center.dx),
        room.center.dy,
      ),
      radius: timelineInbetweenMarkRadius(
        style.fontSize ?? 11,
        cellExtent: room.width,
        crossExtent: room.height,
      ),
    ), timelineTextOnColor(ground));
  }

  /// Each panel's comma count in the BOTTOM band, under the panel's end —
  /// and never past [before], where the cut's length begins (the answer
  /// quoted at [_paintPanelHeads]).
  ///
  /// ↩️F-96: centred on the panel's last cell while it fits; a count wider
  /// than the cell ends at the cell and grows back into the panel, and (B)
  /// narrows only once it would leave the panel — the run label's law
  /// ([timelineBlockWordLayout]). Where the cut's length stands over that
  /// cell, the cell ends where the length begins. D23: a 1-comma panel's
  /// count is empty and prints nothing.
  void _paintPanelCommas(
    Canvas canvas,
    StoryboardCutBlockVisual block, {
    required double? before,
    required Color ground,
  }) {
    final band = block.bottomBand;
    final commas = block.cellCommaLabels;
    for (var index = 0; index < commas.length; index += 1) {
      final comma = commas[index];
      final span = _panelSpan(block, block.cells[index]);
      final end = before == null
          ? span.right
          : math.min(span.right, before - _padding);
      if (comma.isEmpty || end <= span.left || _cellExtent <= 0) {
        continue;
      }
      final glyph = timelineGlyphPainter(comma, _totalStyle);
      final layout = timelineBlockWordLayout(glyph.size, (
        axis: Axis.horizontal,
        room: Rect.fromLTRB(span.left, band.top, end, band.bottom),
        cellStart: end - _cellExtent,
        cellExtent: _cellExtent,
        growth: TimelineBlockWordGrowth.towardBlockStart,
        acrossAlignment: 0,
      ));
      paintTimelineGlyphOnGround(
        canvas,
        layout.origin,
        comma,
        _totalStyle,
        ground: ground,
        fit: layout.fit,
      );
    }
  }

  /// Panel [cell]'s stretch along [block], in row-local x: measured in
  /// FRAMES like every other x on this row, and held inside the block (a
  /// block drawn at [minBlockWidth] is wider than its frames).
  ({double left, double right}) _panelSpan(
    StoryboardCutBlockVisual block,
    StoryboardCoverageCell cell,
  ) {
    final rect = block.rect;
    if (_cellExtent <= 0) {
      return (left: rect.left, right: rect.right);
    }
    return (
      left: math.max(rect.left, rect.left + cell.startIndex * _cellExtent),
      right: math.min(
        rect.right,
        rect.left + cell.endIndexExclusive * _cellExtent,
      ),
    );
  }

  /// A band's writing, held to one end of [band] — the whole band, or the
  /// stretch of it a panel's word may use — and the box it was drawn in, or
  /// null when there was nothing to draw or no stretch at all to draw it in.
  ///
  /// 🚨It keeps its type and narrows into the band (B, 유저 2026-09-24:
  /// 「컷블록의 텍스트든 se텍스트든 뭐든」) — to a sliver if that is all the
  /// room there is, never to nothing ([wordCondensation]: 「절대 안
  /// 사라지도록」). ↩️A title too long for its band was cut to an ellipsis —
  /// the `Text` + `TextOverflow.ellipsis` it was painted in for — so a cut's
  /// name lost its end at zoom-out.
  Rect? _paintBandText(
    Canvas canvas, {
    required String text,
    required TextStyle style,
    required Rect band,
    required bool alignRight,
    required Color ground,
  }) {
    if (text.isEmpty || band.width <= 0) {
      return null;
    }
    // The inset gives way to a stretch narrower than two of it, so a word
    // narrowed there stays in its own stretch — a panel's, not the next.
    final inset = math.min(_padding, band.width / 2);
    final glyph = timelineGlyphPainter(text, style);
    final fit = wordFit(
      glyph.size,
      Size(band.width - inset * 2, band.height),
    );
    final width = glyph.width * fit.x;
    final height = glyph.height * fit.y;
    final dx = alignRight ? band.right - inset - width : band.left + inset;
    final origin = Offset(dx, band.top + (band.height - height) / 2);
    paintTimelineGlyphOnGround(
      canvas,
      origin,
      text,
      style,
      ground: ground,
      fit: fit,
    );
    return origin & Size(width, height);
  }

  /// One picture per PANEL, each in its own slice of the strip.
  ///
  /// The slice is measured in FRAMES, like every other x on this row: a
  /// panel's picture starts where its division does, so it lines up with
  /// the ruler, the playhead and the SE rows. A block drawn at
  /// [minBlockWidth] is wider than its frames, and its panels simply clip.
  void _paintPanelPictures(
    Canvas canvas,
    StoryboardCutBlockVisual block,
    Rect inner,
  ) {
    if (block.cells.isEmpty || block.thumbnails.length != block.cells.length) {
      // No coverage reading (or a mid-rebuild mismatch): the block is one
      // slot, and the placeholder covers it. It is a plate on the rows body,
      // so it wears the shade rather than a chrome fill.
      canvas.drawRect(block.rect, Paint()..color = AppColors.washUp);
      return;
    }
    for (var index = 0; index < block.cells.length; index += 1) {
      final span = _panelSpan(block, block.cells[index]);
      final slot = Rect.fromLTRB(span.left, inner.top, span.right, inner.bottom);
      if (slot.width <= 0) {
        continue;
      }
      canvas.save();
      // 🚨THE ROUNDING IS THE PLATE'S (유저 2026-09-26): 「블록이 모서리
      // 둥근건 블록 자체잖아 … 지금 컷블록이나 콘티블록은 둥근 모서리의
      // 안쪽에 있는것이잖아. 띠가 있으니까. 그래서 모서리가 둥글 이유가
      // 없을거같거든? 관련 로직 삭제. 만약 나중에 띠부분까지 전면 썸네일로
      // 표시한다면 자연스럽게 모서리 잘리도록 낡지않는구조로」 — a picture is
      // clipped to its own panel and nothing rounder. Every picture is drawn
      // inside the plate's clip ([_paintBlock]), so the one round corner a
      // picture can meet is the plate's: a picture that some day fills the
      // bands too is cut by it with no change here.
      // ↩️D30 / I-43 gave each picture the timeline's block corner (「a panel
      // is a frame block in thumbnail mode」), which rounded it INSIDE the
      // plate, between the bands.
      canvas.clipRect(slot);
      _paintPanelPicture(canvas, block.thumbnails[index], slot);
      canvas.restore();
      if (block.hasStoryboardLayer) {
        // The panel's SILHOUETTE (#15): each block outlines itself, which
        // is what separates two touching panels — the seam the removed
        // division rules used to draw, without a rule of its own.
        canvas.drawRect(
          slot.deflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = storyboardCutBlockEdgeColor(
              colorScheme,
              brightness,
              active: false,
              hovered: false,
            ),
        );
      }
    }
  }

  void _paintPanelPicture(Canvas canvas, ui.Image? image, Rect slot) {
    if (image == null) {
      // The pending placeholder the empty thumbnail slot used to be.
      canvas.drawRect(slot, Paint()..color = AppColors.washUp);
      return;
    }
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    // The picture is sized by the ROW's height alone and LEFT-aligned: a
    // shorter comma shows LESS of it, never a smaller copy of it (user,
    // 2026-07-28). Fitting the width instead made the picture shrink as
    // the block narrowed, so a row of short holds read as a row of tiny
    // thumbnails rather than as short holds. The caller clips to the slot,
    // which is what turns "less width" into "less picture".
    final scale = slot.height / source.height;
    final drawn = Size(source.width * scale, source.height * scale);
    canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(slot.left, slot.top, drawn.width, drawn.height),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  // Geometry, selection and hover are absent on purpose — they arrive
  // through `repaint`.
  Object get props => (
    ByIdentity(entries),
    ByMap(storyboardLayerNames),
    crossAxisExtent,
    minBlockWidth,
    activeCutId,
    rowAddress,
    colorScheme,
    brightness,
    baseTextStyle,
    showSeconds,
    countingBase,
    showThumbnails,
    viewportMainExtent,
  );

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        // One node per block: the `Text` widgets these replaced carried their
        // own, and dropping them would take the row away from screen readers.
        for (final block in blocks())
          CustomPainterSemantics(
            rect: block.rect,
            properties: SemanticsProperties(
              // Joined from the parts that EXIST: D27 made layerLabel
              // empty on a no-layer cut, and the old unconditional
              // joiner left its space behind.
              label: [
                block.title,
                if (block.layerLabel.isNotEmpty) block.layerLabel,
                ?block.total,
              ].join(' '),
              textDirection: TextDirection.ltr,
            ),
          ),
      ];
}

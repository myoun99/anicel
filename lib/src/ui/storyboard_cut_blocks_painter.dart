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
import 'storyboard_cut_thumbnail_store.dart'
    show StoryboardThumbnailTier, StoryboardThumbnails;
import '../models/timeline_row_address.dart';
import '../models/track_frame_range.dart';
import 'storyboard_layer_policy.dart';
import 'text/word_condensation.dart';
import '../models/storyboard_timeline_layout.dart';
import 'theme/app_theme.dart';
import 'timeline/layer_label_controls.dart' show layerMarkColor;
import 'timeline/timeline_cell_marker.dart'
    show TimelineCellWriting, timelineCellWritesNothing;
import 'timeline/timeline_cell_style.dart';
import 'timeline/timeline_frame_geometry.dart';
import 'timeline/timeline_frame_range_policy.dart'
    show timelineRunLengthLabel;
import 'timeline/timeline_frame_window.dart';
import 'timeline/timeline_glyph_cache.dart';
import 'timeline/timeline_row_edit_chrome.dart'
    show TimelineChromeGround, TimelineChromeGrounds;
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
///
/// 🗣️유저 2026-09-26: the bands wear LABELS — the cut's pair the cut's 색
/// 라벨, the conte blocks' pair the storyboard layer's (「안쪽띠, 콘티블록
/// 라벨 반영」), the plate where the cut has no storyboard layer — so the
/// ground is the band's own, still carried and still never measured.
Color storyboardCarriedWritingGround(
  StoryboardCutBlockVisual block,
  ColorScheme colorScheme, {
  required StoryboardBand band,
}) => storyboardCutBandColor(
  switch (band) {
    StoryboardBand.cut => block.cutLabel,
    StoryboardBand.conte =>
      block.conteLabel ??
          storyboardCutBlockBackgroundColor(
            colorScheme,
            active: block.isActive,
            hovered: block.isHovered,
          ),
  },
  rangeSelected: block.isRangeSelected,
);

/// Which of a cut block's two pairs of bands a piece of writing stands in.
enum StoryboardBand {
  /// The CUT's, outside — its number and its length.
  cut,

  /// The CONTE BLOCKS', inside — each panel's name and comma count.
  conte,
}

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
    required Rect innerTopBand,
    required Rect strip,
    required Rect innerBottomBand,
    required Rect bottomBand,
    required this.cutLabel,
    required this.conteLabel,
  }) : _topBand = topBand,
       _innerTopBand = innerTopBand,
       _strip = strip,
       _innerBottomBand = innerBottomBand,
       _bottomBand = bottomBand;

  final CutId cutId;

  /// The block's box in ROW-local coordinates.
  final Rect rect;

  /// The bands, in row-local coordinates, top to bottom: the CUT's two
  /// ([topBand], [bottomBand]) outside, the CONTE BLOCKS' two
  /// ([innerTopBand], [innerBottomBand]) inside them, and the STRIP between
  /// — the picture, where the cut's panels live and nothing is written. The
  /// cut's number stands at the left end of its top band and its length at
  /// the right end of its bottom one (the conte sheet's CUT and TIME columns
  /// laid on their side); each panel's name stands over its head in the
  /// inner top band and its comma count under its end in the inner bottom
  /// one.
  ///
  /// 🗣️유저 2026-09-26: 「처음부터 콘티블록 생각해서 띠 위치 잡아두는게
  /// 콘티블록 있는거랑 없는거랑 ui차이 안날거같은데」 — the conte blocks' bands
  /// are there on EVERY cut, a cut with no storyboard layer included (its
  /// inner top band is then the button that makes one,
  /// [createAffordanceRectOf]). ↩️One band each side, shared by the cut's
  /// writing and its panels', since 2026-09-25.
  ///
  /// 🗣️THE BANDS NEVER FOLD (유저 2026-09-25: 「띠는 v행 세로 줄어도 고정으로
  /// 그 자리에 두자」): a shorter row gives up picture, never writing. ↩️Under
  /// 44px they used to fold, and the writing fell back over the picture.
  Rect get topBand => _topBand;
  Rect get innerTopBand => _innerTopBand;
  Rect get strip => _strip;
  Rect get innerBottomBand => _innerBottomBand;
  Rect get bottomBand => _bottomBand;

  final Rect _topBand;
  final Rect _innerTopBand;
  final Rect _strip;
  final Rect _innerBottomBand;
  final Rect _bottomBand;

  /// The cut's 색 라벨, as the colour its two bands wear — the frame blocks'
  /// paper law on the cut's own label (유저 2026-09-26: 「블록도 색라벨에맞춰서
  /// 프레임블록 칠하는거마냥」). An unlabelled cut wears the paper, as an
  /// unlabelled row's blocks do.
  final Color cutLabel;

  /// The storyboard layer's 색 라벨, as the colour the conte blocks' bands
  /// wear (유저 2026-09-26: 「안쪽띠, 콘티블록 라벨 반영」); null when the cut
  /// has no storyboard layer — its inner bands are the plate then.
  final Color? conteLabel;

  /// The cut's panels — the divisions the strip draws, under the coverage
  /// rule. Never empty: a cut with no storyboard row still has one cell.
  final List<StoryboardCoverageCell> cells;

  /// What each panel's head writes (#15: the timeline convention — the
  /// frame's cel number, and nothing when it has none, [drawingHeadOf]),
  /// parallel to [cells]; nothing on the no-row placeholder cell. Written in
  /// the INNER top band, over the panel's head.
  final List<TimelineCellWriting> cellHeads;

  /// Each panel's printed length (#15: the timeline's comma count), parallel
  /// to [cells]; empty on the no-row placeholder cell. Written in the INNER
  /// bottom band, under the panel's end.
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
  required TextStyle baseTextStyle,
  required bool showSeconds,
  required int countingBase,
  ValueListenable<TrackFrameRangeSelection?>? selectedRange,
  ValueListenable<CutId?>? hoveredCutId,
  StoryboardThumbnails? thumbnails,
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
  baseTextStyle: baseTextStyle,
  showSeconds: showSeconds,
  countingBase: countingBase,
  thumbnails: thumbnails,
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
    required this.baseTextStyle,
    required this.showSeconds,
    required this.countingBase,
    this.thumbnails,
    this.windowBucket,
    this.viewportMainExtent = 0,
  }) : super(
         repaint: Listenable.merge([
           geometry,
           ?selectedRange,
           hoveredCutId,
           ?windowBucket,
           ?thumbnails?.landed,
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
  final TextStyle baseTextStyle;
  final bool showSeconds;
  final int countingBase;

  /// Painted, never disposed here: the thumbnail store owns the image.
  /// Asked ONLY for blocks inside the window, which is the point — and a
  /// landed one repaints this painter alone, never the row that built it.
  final StoryboardThumbnails? thumbnails;

  bool get showThumbnails => thumbnails != null;

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

  /// A cut's block width: its frames, and at least [minBlockWidth] so a
  /// short cut can be seen — but never past where the next cut starts
  /// ([roomFrames] from this cut's start; null for the last cut).
  ///
  /// 🗣️유저 2026-09-26 (zoom-floor-fixed-marks-Q1, 「다음 컷 앞에서 멈춘다 …
  /// 안겹치고 … 프리미어처럼」): at I-22's ten-minute floor the 8px floor was
  /// 64 frames, and every shorter cut lay over the next one — drawn under it
  /// and pressed as itself. A row of short cuts reads frame for frame now,
  /// as Premiere's does.
  double _widthFor(int duration, {required int? roomFrames}) {
    final width = duration * _cellExtent;
    final floor = roomFrames == null
        ? minBlockWidth
        : math.min(minBlockWidth, roomFrames * _cellExtent);
    return width < floor ? floor : width;
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
  /// four bands leave, where the pictures are drawn.
  static ({double top, double height}) stripBandOf(double rowHeight) => (
    top: bandHeight * 2,
    height: math.max(0.0, rowHeight - bandHeight * 4),
  );

  /// The CONTE BLOCKS' slot in a row this tall, row-local: their two bands
  /// and the strip between ([StoryboardCutBlockVisual.innerTopBand]) —
  /// where a panel is a block, so where the panel gestures, the panel
  /// selection and the panel edges are mounted: one definition, or the
  /// block and the pointer disagree.
  static ({double top, double height}) conteBlockBandOf(double rowHeight) => (
    top: bandHeight,
    height: math.max(0.0, rowHeight - bandHeight * 2),
  );

  /// A block's five bands, top to bottom: the cut's, the conte blocks', the
  /// strip, the conte blocks', the cut's ([stripBandOf]).
  ({Rect top, Rect innerTop, Rect strip, Rect innerBottom, Rect bottom})
  _bandsOf(Rect rect) {
    final band = stripBandOf(rect.height);
    Rect row(double top) =>
        Rect.fromLTWH(rect.left, top, rect.width, bandHeight);
    return (
      top: row(rect.top),
      innerTop: row(rect.top + bandHeight),
      strip: Rect.fromLTWH(
        rect.left,
        rect.top + band.top,
        rect.width,
        band.height,
      ),
      innerBottom: row(rect.bottom - bandHeight * 2),
      bottom: row(rect.bottom - bandHeight),
    );
  }

  /// One cut's block, or null when it lies outside the visible window:
  /// its rect and bands, the cells with their names and comma labels, the
  /// selection and hover state, the title
  /// and layer label, the total when the block is wide enough, and the
  /// thumbnails when they are shown.
  StoryboardCutBlockVisual? _visualFor(
    StoryboardTimelineLayoutEntry entry, {
    required int? nextStartFrame,
    required ({int startIndex, int endIndexExclusive}) window,
    required TrackFrameRangeSelection? selection,
    required CutId? hovered,
  }) {
    final left = _left(entry.startFrame);
    final width = _widthFor(
      entry.duration,
      roomFrames: nextStartFrame == null
          ? null
          : nextStartFrame - entry.startFrame,
    );
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
    final conteLayer = storyboardLayerForCut(entry.cut);
    return StoryboardCutBlockVisual(
      cutId: entry.cutId,
      rect: rect,
      topBand: bands.top,
      innerTopBand: bands.innerTop,
      strip: bands.strip,
      innerBottomBand: bands.innerBottom,
      bottomBand: bands.bottom,
      // The palette's own reading of each label — the rail chip's plate and
      // the frame blocks' paper ask the same function.
      cutLabel: layerMarkColor(entry.cut.metadata.mark),
      conteLabel: conteLayer == null ? null : layerMarkColor(conteLayer.mark),
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
  ) {
    final thumbnails = this.thumbnails;
    if (thumbnails == null) {
      return const [];
    }
    final tier = thumbnailTierFor(
      stripBandOf(crossAxisExtent).height,
      canvasAspect:
          entry.cut.canvasSize.height / entry.cut.canvasSize.width,
    );
    return [
      for (final cell in cells)
        thumbnails.resolve(
          entry.cut,
          storyboardCellPictureFrame(
            cell,
            pinnedFrameIndex: entry.cut.metadata.thumbnailFrameIndex,
          ),
          tier: tier,
        ),
    ];
  }

  /// The thumbnail a strip [stripHeight] tall draws SHARP: the strip-sized
  /// one while its own height — its width over the canvas's [canvasAspect]
  /// (height ÷ width) — covers the strip, the sheet-sized one past that.
  ///
  /// 🗣️유저 2026-09-26: 「최대값은 최대한 키울수있으면 좋아」 — a V row may grow
  /// to [StoryboardPanel.maxTrackLaneHeight], and a picture stretched past
  /// the pixels it was rendered with is a picture bought with resolution
  /// (⛔해상도로 속도를 사지 않는다). ↩️The strip always asked for the strip
  /// size, which a 160px row already stretched to twice its height.
  static StoryboardThumbnailTier thumbnailTierFor(
    double stripHeight, {
    required double canvasAspect,
  }) => StoryboardThumbnailTier.strip.width * canvasAspect >= stripHeight
      ? StoryboardThumbnailTier.strip
      : StoryboardThumbnailTier.sheet;

  /// Every block this row would draw, in track order — THE probe surface.
  ///
  /// Off-window cuts are absent by construction, which is also what keeps
  /// [thumbnails] from being asked for pictures nobody can see.
  List<StoryboardCutBlockVisual> blocks() {
    final window = visibleFrameWindow();
    final selectionValue = selectedRange?.value;
    final selection =
        selectionValue != null && selectionValue.coversRow(rowAddress)
        ? selectionValue
        : null;
    final hovered = hoveredCutId.value;
    final visuals = <StoryboardCutBlockVisual>[];
    for (var index = 0; index < entries.length; index += 1) {
      final entry = entries[index];
      final visual = _visualFor(
        entry,
        // In track order, so the next entry is the next cut on the row.
        nextStartFrame: index + 1 < entries.length
            ? entries[index + 1].startFrame
            : null,
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
  /// drawn is pressable). EVERY layerless block wears it: its WHOLE inner
  /// top band, with the `+` where a conte block's name would stand.
  ///
  /// 🗣️유저 2026-09-26: 「지금 콘티블록 생성버튼이 중앙에있는데 그게아니라
  /// 띠에? 콘티블록의 블록이름이 위치할 띠 쪽에 그냥 콘티블록 상단띠 전면을
  /// 생성버튼으로 하는게 좋을지도?」 — the band is there on every cut
  /// ([StoryboardCutBlockVisual.innerTopBand]), so the button takes a place
  /// that was always reserved. ↩️A 22px square centred in the strip until
  /// then, gone on any strip too narrow or too flat to hold it.
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
    if (block.hasStoryboardLayer || block.innerTopBand.isEmpty) {
      return null;
    }
    return block.innerTopBand;
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

  /// A pair of BANDS' composited fill — the ground the writing in them sits
  /// on. The bands wear the range tint whenever the block is range-selected,
  /// so this is one expression of the same fills [_paintBlock] lays down.
  Color _bandGround(StoryboardCutBlockVisual block, StoryboardBand band) =>
      storyboardCarriedWritingGround(block, colorScheme, band: band);

  /// The PLATE in the block's state — around the strip's pictures. The
  /// strip never takes the range tint: a selection colours what is NOT the
  /// picture.
  Color _stripGround(StoryboardCutBlockVisual block) =>
      storyboardCutBlockBackgroundColor(
        colorScheme,
        active: block.isActive,
        hovered: block.isHovered,
      );

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
    // 🗣️유저 2026-09-26: 「패딩/실루엣선 이런거 싹 없도록 심플하게만」 — the
    // block is its plate, its bands and its pictures, painted, and nothing
    // else: no outline, no silhouette, no gap. The plate's one rounded
    // outline clips everything inside it. ↩️A light outline wrapped the
    // plate (R26 #8) and each panel (#15, the seam between two touching
    // pictures) until then; the edges' white triangles drowned in it
    // (「애초 블럭이 실루엣이 흰색이라」). Which cut is ACTIVE still reads from
    // the plate: a different statement, a different channel, and the one
    // that survives standing somewhere else.
    canvas.drawRRect(rrect, Paint()..color = _stripGround(block));
    canvas.save();
    canvas.clipRRect(rrect);
    _paintBands(canvas, block);
    _paintPanelPictures(canvas, block);
    canvas.restore();
    _paintWriting(canvas, block);
  }

  /// The four bands' fills: the cut's pair in its label, the conte blocks'
  /// pair in theirs — the plate where the cut has no storyboard layer. A
  /// range selection tints all four ([storyboardCutBandColor]).
  void _paintBands(Canvas canvas, StoryboardCutBlockVisual block) {
    final cut = Paint()..color = _bandGround(block, StoryboardBand.cut);
    canvas.drawRect(block.topBand, cut);
    canvas.drawRect(block.bottomBand, cut);
    final conte = Paint()..color = _bandGround(block, StoryboardBand.conte);
    canvas.drawRect(block.innerTopBand, conte);
    canvas.drawRect(block.innerBottomBand, conte);
  }

  /// THE BANDS carry the writing, so nothing is drawn over the picture and
  /// no scrim is needed. The cut's number at its top band's left end and its
  /// length at its bottom band's right end — the conte sheet's CUT and TIME
  /// columns sit outside the picture cell exactly this way, one above and one
  /// below, and this is that sheet turned on its side — and each panel's
  /// name and length in the conte blocks' bands between.
  void _paintWriting(Canvas canvas, StoryboardCutBlockVisual block) {
    final cutGround = _bandGround(block, StoryboardBand.cut);
    final conteGround = _bandGround(block, StoryboardBand.conte);
    canvas.save();
    canvas.clipRect(block.topBand);
    _paintBandText(
      canvas,
      text: block.title,
      style: _titleStyle,
      band: block.topBand,
      alignRight: false,
      ground: cutGround,
    );
    canvas.restore();

    canvas.save();
    canvas.clipRect(block.innerTopBand);
    if (createAffordanceRectOf(block) case final button?) {
      // D30: the create affordance — an icon, not copy — where a conte
      // block's name would stand; the band around it is the button.
      _paintBandText(
        canvas,
        text: '+',
        style: _titleStyle,
        band: button,
        alignRight: false,
        ground: conteGround,
      );
    } else {
      _paintPanelHeads(canvas, block, ground: conteGround);
    }
    canvas.restore();

    canvas.save();
    canvas.clipRect(block.innerBottomBand);
    _paintPanelCommas(canvas, block, ground: conteGround);
    canvas.restore();

    canvas.save();
    canvas.clipRect(block.bottomBand);
    // D27: a cut with no storyboard layer prints NOTHING beside its length —
    // the explanatory copy is gone.
    if (block.total case final total?) {
      _paintBandText(
        canvas,
        text: total,
        style: _totalStyle,
        band: block.bottomBand,
        alignRight: true,
        ground: cutGround,
      );
    }
    canvas.restore();
  }

  /// Each panel's head in the conte blocks' TOP band, over the panel — its
  /// cel number, and nothing without one ([drawingHeadOf]) — at the panel's
  /// left.
  ///
  /// 🗣️유저 2026-09-25, to 「패널의 이름·코마 글씨가 썸네일을 가린다」: 「띠로
  /// 옮긴다 — 이름은 윗 띠, 코마는 아랫 띠」. ↩️D29-2 (유저 2026-08-22: 「받는
  /// 바탕을 똑같게」) had carried the panel writing over the picture on
  /// plates of the band's own fill — the ground was right, but the plates
  /// covered the pictures. In the band the ground IS the band's. The panel's
  /// LEFT stays its anchor: the cut title's own (유저 2026-07-29).
  /// ↩️The heads shared the cut's band and stood after its title until the
  /// conte blocks got bands of their own (유저 2026-09-26); and an unnamed
  /// head wore the in-between mark, drawn in the band, until the same day
  /// (「콘티레이어는 이름 없으면 진짜 이름 없도록」).
  void _paintPanelHeads(
    Canvas canvas,
    StoryboardCutBlockVisual block, {
    required Color ground,
  }) {
    final band = block.innerTopBand;
    final heads = block.cellHeads;
    for (var index = 0; index < heads.length; index += 1) {
      final span = _panelSpan(block, block.cells[index]);
      _paintBandText(
        canvas,
        text: heads[index].word,
        style: _titleStyle,
        band: Rect.fromLTRB(span.left, band.top, span.right, band.bottom),
        alignRight: false,
        ground: ground,
      );
    }
  }

  /// Each panel's comma count in the conte blocks' BOTTOM band, under the
  /// panel's end (the answer quoted at [_paintPanelHeads]).
  ///
  /// ↩️F-96: centred on the panel's last cell while it fits; a count wider
  /// than the cell ends at the cell and grows back into the panel, and (B)
  /// narrows only once it would leave the panel — the run label's law
  /// ([timelineBlockWordLayout]). D23: a 1-comma panel's count is empty and
  /// prints nothing. ↩️It shared the cut's band, and ended where the cut's
  /// length began, until the conte blocks got bands of their own.
  void _paintPanelCommas(
    Canvas canvas,
    StoryboardCutBlockVisual block, {
    required Color ground,
  }) {
    final band = block.innerBottomBand;
    final commas = block.cellCommaLabels;
    for (var index = 0; index < commas.length; index += 1) {
      final comma = commas[index];
      final span = _panelSpan(block, block.cells[index]);
      if (comma.isEmpty || span.right <= span.left || _cellExtent <= 0) {
        continue;
      }
      final glyph = timelineGlyphPainter(comma, _totalStyle);
      final layout = timelineBlockWordLayout(glyph.size, (
        axis: Axis.horizontal,
        room: Rect.fromLTRB(span.left, band.top, span.right, band.bottom),
        cellStart: span.right - _cellExtent,
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
  /// stretch of it a panel's word may use. Nothing is drawn with nothing to
  /// draw, or no stretch at all to draw it in.
  ///
  /// 🚨It keeps its type and narrows into the band (B, 유저 2026-09-24:
  /// 「컷블록의 텍스트든 se텍스트든 뭐든」) — to a sliver if that is all the
  /// room there is, never to nothing ([wordCondensation]: 「절대 안
  /// 사라지도록」). ↩️A title too long for its band was cut to an ellipsis —
  /// the `Text` + `TextOverflow.ellipsis` it was painted in for — so a cut's
  /// name lost its end at zoom-out.
  void _paintBandText(
    Canvas canvas, {
    required String text,
    required TextStyle style,
    required Rect band,
    required bool alignRight,
    required Color ground,
  }) {
    if (text.isEmpty || band.width <= 0) {
      return;
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
  }

  /// One picture per PANEL, each in its own slice of the strip — where the
  /// painter draws them AND where the edges read their ground
  /// ([groundsOf]): one definition, or an edge's ink disagrees with what it
  /// stands on.
  ///
  /// The slice is measured in FRAMES, like every other x on this row: a
  /// panel's picture starts where its division does, so it lines up with
  /// the ruler, the playhead and the SE rows. A block drawn at
  /// [minBlockWidth] is wider than its frames, and its panels simply clip.
  ///
  /// No coverage reading (or a mid-rebuild mismatch) places nothing, and
  /// the plate under the strip shows. ↩️It laid a shade over the whole
  /// block, which would cover the bands now that they are painted first.
  Iterable<({Rect slot, ui.Image? image})> _picturesOf(
    StoryboardCutBlockVisual block,
  ) sync* {
    final inner = block.strip;
    if (!showThumbnails ||
        inner.width <= 0 ||
        inner.height <= 0 ||
        block.cells.isEmpty ||
        block.thumbnails.length != block.cells.length) {
      return;
    }
    for (var index = 0; index < block.cells.length; index += 1) {
      final span = _panelSpan(block, block.cells[index]);
      final slot = Rect.fromLTRB(
        span.left,
        inner.top,
        span.right,
        inner.bottom,
      );
      if (slot.width > 0) {
        yield (slot: slot, image: block.thumbnails[index]);
      }
    }
  }

  /// Where [image] lands in [slot] — before the slot clips it.
  ///
  /// The picture is sized by the ROW's height alone and LEFT-aligned: a
  /// shorter comma shows LESS of it, never a smaller copy of it (user,
  /// 2026-07-28). Fitting the width instead made the picture shrink as the
  /// block narrowed, so a row of short holds read as a row of tiny
  /// thumbnails rather than as short holds. The slot's clip is what turns
  /// "less width" into "less picture".
  static Rect _pictureIn(Rect slot, ui.Image image) => Rect.fromLTWH(
    slot.left,
    slot.top,
    image.width * slot.height / image.height,
    slot.height,
  );

  /// What a mark over [block] stands on besides its plate, row-local: its
  /// four bands in their fills and each panel's picture on its paper — a
  /// pending one on its placeholder's shade. The same fills [_paintBlock]
  /// lays down, read rather than measured.
  List<TimelineChromeGround> groundsOf(StoryboardCutBlockVisual block) {
    final cut = _bandGround(block, StoryboardBand.cut);
    final conte = _bandGround(block, StoryboardBand.conte);
    return [
      (rect: block.topBand, color: cut),
      (rect: block.innerTopBand, color: conte),
      (rect: block.innerBottomBand, color: conte),
      (rect: block.bottomBand, color: cut),
      for (final (:slot, :image) in _picturesOf(block))
        if (image == null)
          (rect: slot, color: AppColors.washUp)
        else
          (
            rect: _pictureIn(slot, image).intersect(slot),
            color: storyboardPanelPictureGroundColor,
          ),
    ];
  }

  void _paintPanelPictures(Canvas canvas, StoryboardCutBlockVisual block) {
    for (final (:slot, :image) in _picturesOf(block)) {
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
      _paintPanelPicture(canvas, image, slot);
      canvas.restore();
      // ⛔No silhouette (유저 2026-09-26: 「패딩/실루엣선 이런거 싹 없도록」):
      // two touching panels part where the second picture starts, as two
      // touching frame blocks part at their seam. ↩️#15 outlined each panel,
      // the seam the removed division rules used to draw.
    }
  }

  void _paintPanelPicture(Canvas canvas, ui.Image? image, Rect slot) {
    if (image == null) {
      // The pending placeholder the empty thumbnail slot used to be.
      canvas.drawRect(slot, Paint()..color = AppColors.washUp);
      return;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      _pictureIn(slot, image),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  // Geometry, selection, hover and a landed picture are absent on purpose —
  // they arrive through `repaint`.
  Object get props => (
    ByIdentity(entries),
    ByMap(storyboardLayerNames),
    crossAxisExtent,
    minBlockWidth,
    activeCutId,
    rowAddress,
    colorScheme,
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

/// What the V row's edges stand on, for a chrome layer mounted
/// [crossOffset] down the row ([TimelineChromeGrounds]): the bands and the
/// pictures of the block under an edge ([StoryboardCutBlocksPainter
/// .groundsOf]). The plate is the rest — the chrome's own `gripGround`.
///
/// Made once a paint: the blocks are read against the live geometry then,
/// and each edge finds its block by halving rather than by a walk.
class StoryboardPlateGrounds implements TimelineChromeGrounds {
  StoryboardPlateGrounds(this._painter, {required double crossOffset})
    : _offset = Offset(0, crossOffset),
      _blocks = _painter.blocks();

  final StoryboardCutBlocksPainter _painter;
  final Offset _offset;

  /// In track order — so in x order.
  final List<StoryboardCutBlockVisual> _blocks;

  @override
  List<TimelineChromeGround> under(Rect box) {
    final rowBox = box.shift(_offset);
    final block = _blockAt(rowBox.center.dx);
    if (block == null) {
      return const [];
    }
    return [
      for (final ground in _painter.groundsOf(block))
        if (ground.rect.overlaps(rowBox))
          (rect: ground.rect.shift(-_offset), color: ground.color),
    ];
  }

  /// The first block not wholly left of [x]. In a gap that is the next
  /// block, which is harmless: [under] keeps only the grounds its box
  /// touches.
  StoryboardCutBlockVisual? _blockAt(double x) {
    var low = 0;
    var high = _blocks.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_blocks[middle].rect.right <= x) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low == _blocks.length ? null : _blocks[low];
  }
}

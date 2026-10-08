import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsProperties;

import '../models/cut_id.dart';
import '../models/storyboard_coverage.dart';
import 'storyboard_cut_thumbnail_store.dart' show StoryboardThumbnails;
import '../models/timeline_row_address.dart';
import '../models/track_frame_range.dart';
import 'storyboard_layer_policy.dart';
import 'text/word_condensation.dart';
import '../models/storyboard_timeline_layout.dart';
import 'theme/app_theme.dart';
import 'timeline/layer_label_controls.dart' show layerMarkColor;
import 'timeline/timeline_cell_style.dart';
import 'timeline/timeline_frame_coordinate_policy.dart'
    show timelineFrameAt, timelineFrameEdge;
import 'timeline/timeline_frame_geometry.dart';
import 'timeline/timeline_frame_range_policy.dart'
    show timelineRunLengthLabel;
import 'timeline/timeline_frame_window.dart';
import 'timeline/timeline_glyph_cache.dart';
import 'timeline/timeline_row_edit_chrome.dart'
    show TimelineChromeGround, TimelineChromeGrounds;
import 'repaint_props.dart';
import 'text/word_bake.dart' show RepaintOnWordBakes;
import 'timeline/memo_token.dart';

/// The ground EVERY piece of CARRIED writing on a cut block receives — all
/// of it in the bands: the cut's own number and length.
///
/// ↩️Each panel's name and comma count stood in bands of their own between
/// them (유저 2026-09-25: 「이름은 윗 띠, 코마는 아랫 띠」) until I-73 moved
/// those two bands out to the conte row under the V row (유저 2026-10-08:
/// 「띠 둘만 이사로 가자」), where they are frame blocks' own print.
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
/// 🗣️유저 2026-09-26: the bands wear the cut's 색 라벨 — so the ground is the
/// band's own, still carried and still never measured. ↩️The conte blocks'
/// pair wore the storyboard layer's (「안쪽띠, 콘티블록 라벨 반영」), which
/// the conte row's blocks wear as their paper now.
Color storyboardCarriedWritingGround(StoryboardCutBlockVisual block) =>
    storyboardCutBandColor(
      block.cutLabel,
      rangeSelected: block.isRangeSelected,
      standing: block.isStanding,
    );

/// One cut block as the painter draws it — THE probe surface, in place of
/// the widget keys the blocks used to carry.
class StoryboardCutBlockVisual {
  const StoryboardCutBlockVisual({
    required this.cutId,
    required this.rect,
    required this.isRangeSelected,
    required this.isHovered,
    required this.isStanding,
    required this.title,
    required this.total,
    required this.thumbnails,
    required this.cells,
    required Rect topBand,
    required Rect strip,
    required Rect bottomBand,
    required this.cutLabel,
    this.isLinkedCut = false,
  }) : _topBand = topBand,
       _strip = strip,
       _bottomBand = bottomBand;

  final CutId cutId;

  /// The block's box in ROW-local coordinates.
  final Rect rect;

  /// The bands, in row-local coordinates, top to bottom: the CUT's two
  /// ([topBand], [bottomBand]) and the STRIP between — the picture, where
  /// the cut's panels lie side by side and nothing is written. The cut's
  /// number stands at the left end of its top band and its length at the
  /// right end of its bottom one (the conte sheet's CUT and TIME columns
  /// laid on their side).
  ///
  /// ↩️THE CONTE BLOCKS' TWO BANDS LEFT (I-73, 유저 2026-10-08: 「우선
  /// v행은 지금처럼 보여주는건 그대로 보여줘 … 컷 선택만 되도록」 · 「띠
  /// 둘만 이사로 가자」): each panel's name stood over its head in an inner
  /// top band and its comma count under its end in an inner bottom one, on
  /// EVERY cut — 유저 2026-09-26: 「처음부터
  /// 콘티블록 생각해서 띠 위치 잡아두는게 콘티블록 있는거랑 없는거랑 ui차이
  /// 안날거같은데」 — and a cut with no storyboard layer wore the button that
  /// makes one there. They are the conte row's frame blocks now, under the
  /// V row, and the button is that row's. ↩️One band each side, shared by
  /// the cut's writing and its panels', since 2026-09-25.
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

  /// The cut's 색 라벨, as the colour its two bands wear — the frame blocks'
  /// paper law on the cut's own label (유저 2026-09-26: 「블록도 색라벨에맞춰서
  /// 프레임블록 칠하는거마냥」). An unlabelled cut wears the paper, as an
  /// unlabelled row's blocks do.
  final Color cutLabel;

  /// Whether the cut is a LINKED cut (I-25) — its name wears the link
  /// icon, which opens the link window.
  final bool isLinkedCut;

  /// The cut's panels — the divisions the strip draws its pictures by,
  /// under the coverage rule. Never empty: a cut with no storyboard row
  /// still has one cell.
  final List<StoryboardCoverageCell> cells;

  final bool isRangeSelected;
  final bool isHovered;

  /// The cut you stand on (F-248) — its bands wear the standing wash.
  final bool isStanding;

  /// The cut's name, drawn top-left.
  final String title;

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
/// the SAME painter gets you. The derived map is the reason this is a
/// function rather than a constructor call at each site: resolving a cut's
/// coverage cells by hand is exactly the copy that drifts.
///
/// The interactive inputs stay optional, so a display-only host (the
/// collapsed row) omits them and gets the same picture minus the states
/// nothing can enter: no selection tint, no hover.
StoryboardCutBlocksPainter storyboardCutBlocksPainterFor({
  required List<StoryboardTimelineLayoutEntry> entries,
  required TimelineFrameGeometryHandle geometry,
  required double crossAxisExtent,
  required double minBlockWidth,
  required TimelineRowAddress rowAddress,
  required ColorScheme colorScheme,
  required TextStyle baseTextStyle,
  required bool showSeconds,
  required int countingBase,
  ValueListenable<TrackFrameRangeSelection?>? selectedRange,
  ValueListenable<CutId?>? hoveredCutId,
  ValueListenable<CutId?>? standingCutId,
  StoryboardThumbnails? thumbnails,
  required double devicePixelRatio,
  ValueListenable<int>? windowBucket,
  Set<CutId> linkedCutIds = const {},
  double viewportMainExtent = 0,
}) => StoryboardCutBlocksPainter(
  entries: entries,
  // The STRIP's content: the cut's panels, under the coverage rule — the
  // same reading the conte row under this one draws its blocks from.
  storyboardCellsByCut: storyboardCellsByCut(entries),
  linkedCutIds: linkedCutIds,
  geometry: geometry,
  crossAxisExtent: crossAxisExtent,
  minBlockWidth: minBlockWidth,
  selectedRange: selectedRange,
  rowAddress: rowAddress,
  hoveredCutId: hoveredCutId ?? _noHover,
  standingCutId: standingCutId,
  colorScheme: colorScheme,
  baseTextStyle: baseTextStyle,
  showSeconds: showSeconds,
  countingBase: countingBase,
  thumbnails: thumbnails,
  devicePixelRatio: devicePixelRatio,
  windowBucket: windowBucket,
  viewportMainExtent: viewportMainExtent,
);

/// The hover channel for hosts that have no pointer to hover with — a
/// single shared constant rather than one notifier per build, which would
/// re-subscribe the painter's `repaint` merge every pass.
final ValueNotifier<CutId?> _noHover = ValueNotifier<CutId?>(null);

/// The cut a V row's bands mark as stood on (F-248): the cut under the
/// playhead [cut] while that row is the one you stand on ([standsOnRow]).
///
/// 🗣️유저 2026-10-01: 「s행에서면 s행블록만 칠해지도록」 — one standing place,
/// as the timeline's lane takes the wash off its layer's row. Heard through
/// [changes], which carry both answers; it holds nothing of its own, so a
/// host builds one per build.
class StandingCut implements ValueListenable<CutId?> {
  const StandingCut({
    required this.changes,
    required this.standsOnRow,
    required this.cut,
  });

  final Listenable changes;
  final bool Function() standsOnRow;
  final ValueListenable<CutId?> cut;

  @override
  CutId? get value => standsOnRow() ? cut.value : null;

  @override
  void addListener(VoidCallback listener) => changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      changes.removeListener(listener);
}

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
class StoryboardCutBlocksPainter extends CustomPainter
    with RepaintOnProps, RepaintOnWordBakes {
  StoryboardCutBlocksPainter({
    required this.entries,
    required this.storyboardCellsByCut,
    this.linkedCutIds = const {},
    required this.geometry,
    required this.crossAxisExtent,
    required this.minBlockWidth,
    required this.selectedRange,
    required this.rowAddress,
    required this.hoveredCutId,
    this.standingCutId,
    required this.colorScheme,
    required this.baseTextStyle,
    required this.showSeconds,
    required this.countingBase,
    this.thumbnails,
    required this.devicePixelRatio,
    this.windowBucket,
    this.viewportMainExtent = 0,
  }) : super(
         repaint: Listenable.merge([
           geometry,
           ?selectedRange,
           hoveredCutId,
           ?standingCutId,
           ?windowBucket,
           ?thumbnails?.landed,
         ]),
       );

  final List<StoryboardTimelineLayoutEntry> entries;

  /// Each cut's panels (the coverage rule's cells), resolved by the row —
  /// the strip's content: a picture a panel. A cut always has at least one.
  final Map<CutId, List<StoryboardCoverageCell>> storyboardCellsByCut;

  /// The LINKED cuts among [entries] (I-25), resolved by the host that
  /// knows the project's links — the painter only reads them.
  final Set<CutId> linkedCutIds;

  /// The LIVE frame-axis geometry: a zoom step repaints instead of
  /// rebuilding the row that built this.
  final TimelineFrameGeometryHandle geometry;

  final double crossAxisExtent;

  /// Blocks never draw narrower than this, however short the cut — the
  /// `TimelineScale` rule the widget blocks were sized by.
  final double minBlockWidth;

  /// The live frame RANGE on this track's global axis. A block is selected
  /// when the range COVERS it — the cut row is a frame-axis row and a cut
  /// is a long block on it, so there is no list of selected cuts to carry.
  final ValueListenable<TrackFrameRangeSelection?>? selectedRange;

  /// This row's address, so a selection anchored on another row (an S row,
  /// once those select too) does not tint these blocks.
  final TimelineRowAddress rowAddress;
  final ValueListenable<CutId?> hoveredCutId;

  /// The cut you stand on (F-248), whose bands wear the standing wash — a
  /// [StandingCut]: the cut under the playhead while this row is the one
  /// you stand on. It moves on crossings and stands, so this row repaints
  /// once a cut, never a tick. Null where nobody stands.
  final ValueListenable<CutId?>? standingCutId;

  final ColorScheme colorScheme;

  /// The ambient text style the row sits in — the app's face. Every word
  /// on a block is printed from it the one way ([timelineBlockWordStyle]).
  final TextStyle baseTextStyle;
  final bool showSeconds;
  final int countingBase;

  /// Painted, never disposed here: the thumbnail store owns the image.
  /// Asked ONLY for blocks inside the window, which is the point — and a
  /// landed one repaints this painter alone, never the row that built it.
  final StoryboardThumbnails? thumbnails;

  bool get showThumbnails => thumbnails != null;

  /// The screen's pixels per logical one: the pictures are asked at the
  /// device pixels they are drawn with, not the layout's.
  final double devicePixelRatio;

  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  static const double _padding = 4;

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
  ///
  /// It is the geometry's own [TimelineFrameGeometry.edgeAt] — the frame
  /// axis' one law (F-220) — rather than a copy of it.
  double _left(int frame) => geometry.value.edgeAt(frame);

  /// A cut's block width: its frames, and at least [minBlockWidth] so a
  /// short cut can be seen — but never past where the next cut starts.
  ///
  /// 🗣️유저 2026-09-26 (zoom-floor-fixed-marks-Q1, 「다음 컷 앞에서 멈춘다 …
  /// 안겹치고 … 프리미어처럼」): at I-22's ten-minute floor the 8px floor was
  /// 64 frames, and every shorter cut lay over the next one — drawn under it
  /// and pressed as itself. A row of short cuts reads frame for frame now,
  /// as Premiere's does.
  ///
  /// 🗣️유저 2026-09-27 (「최대한 원래 공간만 차지하도록」): the floor is one
  /// pixel ([StoryboardPanel.cutBlockMinWidth]) — it keeps a sub-pixel cut
  /// from vanishing and grows nothing that covers a pixel of its own.
  double _widthFor(StoryboardTimelineLayoutEntry entry) {
    final start = _left(entry.startFrame);
    final width = _left(entry.endFrame) - start;
    final next = _nextStartByCut[entry.cutId];
    final floor = next == null
        ? minBlockWidth
        : math.min(minBlockWidth, _left(next) - start);
    return width < floor ? floor : width;
  }

  /// The frame after the one [entry]'s block, [width] wide, reaches into.
  /// A block reaches at least [minBlockWidth], so its visible end is
  /// measured in pixels, not in the cut's own frames.
  int _reachedEndFrame(StoryboardTimelineLayoutEntry entry, double width) {
    if (_cellExtent <= 0) {
      return entry.endFrame;
    }
    final farEdge = timelineFrameEdge(entry.startFrame, _cellExtent) + width;
    return timelineFrameAt(farEdge - 1e-6, _cellExtent) + 1;
  }

  /// Where the cut after each one starts — [entries] are in track order,
  /// and the last cut has no one to stop for.
  late final Map<CutId, int> _nextStartByCut = {
    for (var index = 0; index + 1 < entries.length; index += 1)
      entries[index].cutId: entries[index + 1].startFrame,
  };

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
  /// cut's two bands leave, where the pictures are drawn.
  static ({double top, double height}) stripBandOf(double rowHeight) => (
    top: bandHeight,
    height: math.max(0.0, rowHeight - bandHeight * 2),
  );

  /// A block's three bands, top to bottom: the cut's, the strip, the cut's
  /// ([stripBandOf]).
  ({Rect top, Rect strip, Rect bottom}) _bandsOf(Rect rect) {
    final band = stripBandOf(rect.height);
    Rect row(double top) =>
        Rect.fromLTWH(rect.left, top, rect.width, bandHeight);
    return (
      top: row(rect.top),
      strip: Rect.fromLTWH(
        rect.left,
        rect.top + band.top,
        rect.width,
        band.height,
      ),
      bottom: row(rect.bottom - bandHeight),
    );
  }

  /// One cut's block, or null when it lies outside the visible window:
  /// its rect and bands, its panels, the selection and hover state, the
  /// title, the total when the block is wide enough, and the thumbnails
  /// when they are shown.
  StoryboardCutBlockVisual? _visualFor(
    StoryboardTimelineLayoutEntry entry, {
    required ({int startIndex, int endIndexExclusive}) window,
    required TrackFrameRangeSelection? selection,
    required CutId? hovered,
  }) {
    final left = _left(entry.startFrame);
    final width = _widthFor(entry);
    final endFrame = _reachedEndFrame(entry, width);
    if (endFrame <= window.startIndex ||
        entry.startFrame >= window.endIndexExclusive) {
      return null;
    }
    final rect = Rect.fromLTWH(left, 0, width, crossAxisExtent);
    final bands = _bandsOf(rect);
    final cells = storyboardCellsByCut[entry.cutId] ?? const [];
    return StoryboardCutBlockVisual(
      cutId: entry.cutId,
      rect: rect,
      topBand: bands.top,
      strip: bands.strip,
      bottomBand: bands.bottom,
      // The palette's own reading of the label — the rail chip's plate and
      // the frame blocks' paper ask the same function.
      cutLabel: layerMarkColor(entry.cut.metadata.mark),
      isLinkedCut: linkedCutIds.contains(entry.cutId),
      cells: cells,
      isRangeSelected:
          selection?.overlaps(entry.startFrame, entry.endFrame) ?? false,
      isHovered: entry.cutId == hovered,
      isStanding: entry.cutId == standingCutId?.value,
      title: entry.cut.name,
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
      thumbnails: _thumbnailsFor(entry, cells, strip: bands.strip),
    );
  }

  /// One picture per PANEL, each at the frame that panel is about — asked
  /// ONLY for blocks the window keeps: the row used to request every
  /// cut's picture on every build.
  ///
  /// ⛔And not at all for a [strip] that shows none ([_stripShowsPictures]):
  /// a V row at its floor keeps its bands and no picture, and it still
  /// asked for every panel's — a render each, and a render thaws its cut's
  /// cels at the canvas's full size whatever width it is for (measured
  /// 09-28 on the user's film: 26 pictures nobody could see, +570MB).
  List<ui.Image?> _thumbnailsFor(
    StoryboardTimelineLayoutEntry entry,
    List<StoryboardCoverageCell> cells, {
    required Rect strip,
  }) {
    final thumbnails = this.thumbnails;
    if (thumbnails == null || !_stripShowsPictures(strip)) {
      return const [];
    }
    // The picture is drawn the strip's height tall ([_pictureIn]), so that
    // many device pixels is what it asks for — the conte cell's law.
    //
    // 🗣️유저 2026-09-26: 「최대값은 최대한 키울수있으면 좋아」 — a V row may
    // grow to [StoryboardPanel.maxTrackLaneHeightFor], and a picture stretched
    // past the pixels it was rendered with is a picture bought with
    // resolution (⛔해상도로 속도를 사지 않는다). ↩️It chose between a 128px
    // and a 640px picture, and read neither the screen's density nor the
    // camera's shape.
    final shownHeight = strip.height * devicePixelRatio;
    final conteStart = storyboardConteStart(
      storyboardLayerForCut(entry.cut)?.timeline,
    );
    return [
      for (final cell in cells)
        thumbnails.resolve(
          entry.cut,
          storyboardCellPictureFrame(
            cell,
            pinnedFrameIndex: entry.cut.metadata.thumbnailFrameIndex,
            conteStart: conteStart,
          ),
          shownHeight: shownHeight,
        ),
    ];
  }

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

  /// 🗣️I-25 (유저 2026-09-14): 「링크컷이 발생해있는 경우, 모든 컷에 적용.
  /// 내용은 컷블록에서 컷 이름 오른쪽에 링크아이콘(레이어에서 사용하는거랑
  /// 똑같은 것) 사용. 그리고 해당 버튼 클릭시 공용창 띄움」 — the icon's
  /// square right after a linked cut's name, in its top band: the ONE rect the
  /// paint draws and the press reads (the D30 create affordance's shape).
  /// Null on a cut that is not linked, or a band too narrow for the square.
  Rect? linkAffordanceRectOf(StoryboardCutBlockVisual block) {
    if (!block.isLinkedCut) {
      return null;
    }
    final band = block.topBand;
    final side = band.height;
    final inset = math.min(_padding, band.width / 2);
    final titleRoom = band.width - inset * 2 - side;
    if (side <= 0 || titleRoom < 0) {
      return null;
    }
    final titleWidth = _bandTextWidth(
      block.title,
      _titleStyle,
      Size(titleRoom, band.height),
    );
    return Rect.fromLTWH(band.left + inset + titleWidth, band.top, side, side);
  }

  /// The width [text] is painted at in a [room] ([_paintBandText]'s fit).
  double _bandTextWidth(String text, TextStyle style, Size room) {
    if (text.isEmpty || room.width <= 0) {
      return 0;
    }
    final set = timelineWordSetOnto(text, style, room.width);
    return set.glyph.width * wordFit(set.glyph.size, room).x;
  }

  /// The layer badge's glyph ([Icons.link]) in the accent, centred in [rect].
  void _paintLinkIcon(Canvas canvas, Rect rect) {
    const icon = Icons.link;
    final glyph = timelineGlyphPainter(
      String.fromCharCode(icon.codePoint),
      TextStyle(
        fontSize: rect.height,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: colorScheme.primary,
        height: 1.0,
      ),
    );
    glyph.paint(
      canvas,
      rect.center - Offset(glyph.width / 2, glyph.height / 2),
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

  /// D29: the cut-block text grade — the title and the length alike, not a
  /// cell-fitted 9 that shrank to ~6px at storyboard zooms.
  static const double _wordSize = 11;

  // The CELLS' writing convention on every cut-block label too (user
  // 2026-07-29, "cut blocks and storyboard blocks read as one"): panel ink
  // carried by the shared GROUND LAW (2026-08-17, the difference blend's
  // successor) — one solid, black or white by the luminance of the fill
  // each label sits on, in place of scrims, halos and per-surface colours.
  // The styles' colors are layout/cache identity; the paint resolves the
  // real ink through [paintTimelineGlyphOnGround].
  //
  // 🗣️F-234 (유저 2026-09-29): 「코마텍스트가 위아래 정렬이 중앙이아니라
  // 살짝위라던가 … 특히 컷블록의 코마텍스트. 관련 텍스트 통일」 — the words
  // are printed the block word's one way ([timelineBlockWordStyle]).
  // ↩️They were `labelSmall` at 11, whose 1.45 line made a 16px box: taller
  // than the 13px band, so every word was narrowed to 81% of its height to
  // fit a band its ink never overflowed.
  TextStyle get _titleStyle => bandWordStyleOn(baseTextStyle);

  /// A band's word in [base]'s face — the cut's name, and the `+` the conte
  /// row under this one wears where a cut has no conte layer
  /// ([paintBandWord]).
  static TextStyle bandWordStyleOn(TextStyle base) => timelineBlockWordStyle(
    base,
    ink: timelineDrawingInkColor,
    fontSize: _wordSize,
    bold: true,
  );

  /// The bands' LENGTH word — the cut's length, at the frame blocks' 0.72
  /// (R27 #3: bold — the readout was too easy to miss).
  TextStyle get _totalStyle => timelineBlockWordStyle(
    baseTextStyle,
    ink: timelineDrawingInkColor.withValues(alpha: 0.72),
    fontSize: _wordSize,
    bold: true,
  );

  /// The BANDS' composited fill — the ground the writing in them sits on.
  /// The bands wear the range tint whenever the block is range-selected, so
  /// this is one expression of the same fills [_paintBlock] lays down.
  Color _bandGround(StoryboardCutBlockVisual block) =>
      storyboardCarriedWritingGround(block);

  /// The PLATE in the block's state — around the strip's pictures. The
  /// strip never takes the range tint: a selection colours what is NOT the
  /// picture.
  Color _stripGround(StoryboardCutBlockVisual block) =>
      storyboardCutBlockBackgroundColor(
        colorScheme,
        hovered: block.isHovered,
      );

  @override
  void paint(Canvas canvas, Size size) {
    for (final block in blocks()) {
      _paintBlock(canvas, block);
    }
  }

  /// The CUT PLATE's corner — the V row's block, rounded by the frame-block
  /// law like every other block: 6px, no larger than half a frame's cell or
  /// half the plate. The plate is a container with bands, and it is the ONE
  /// rounded thing in it — what sits inside is square and clipped by this
  /// corner (유저 2026-09-26: 「블록이 모서리 둥근건 블록 자체」).
  ///
  /// 🗣️F-219 (유저 2026-09-28): 「컷블록의 꼭짓점은 10%대에서도 작은 줌에서도
  /// 둥근데, se블록이나 타임라인의 프레임블록은 네모남 … 컷블록을 작은 줌에서
  /// 네모나게 되는 법으로 통일」. ↩️A constant 8px, round at every zoom.
  Radius get plateCorner => timelineBlockCornerRadiusAt(
    cellExtent: _cellExtent,
    crossExtent: crossAxisExtent,
  );

  void _paintBlock(Canvas canvas, StoryboardCutBlockVisual block) {
    final rrect = RRect.fromRectAndRadius(block.rect, plateCorner);
    // 🗣️유저 2026-09-26: 「패딩/실루엣선 이런거 싹 없도록 심플하게만」 — the
    // block is its plate, its bands and its pictures, painted, and nothing
    // else: no outline, no silhouette, no gap. The plate's one rounded
    // outline clips everything inside it. ↩️A light outline wrapped the
    // plate (R26 #8) and each panel (#15, the seam between two touching
    // pictures) until then; the edges' white triangles drowned in it
    // (「애초 블럭이 실루엣이 흰색이라」). The cut you stand in is the
    // playhead's to say (F-212); ↩️its plate said it too, in the accent.
    canvas.drawRRect(rrect, Paint()..color = _stripGround(block));
    canvas.save();
    canvas.clipRRect(rrect);
    _paintBands(canvas, block);
    _paintPanelPictures(canvas, block);
    canvas.restore();
    _paintWriting(canvas, block);
  }

  /// The two bands' fills, in the cut's label. A range selection tints both
  /// ([storyboardCutBandColor]).
  void _paintBands(Canvas canvas, StoryboardCutBlockVisual block) {
    final cut = Paint()..color = _bandGround(block);
    canvas.drawRect(block.topBand, cut);
    canvas.drawRect(block.bottomBand, cut);
  }

  /// THE BANDS carry the writing, so nothing is drawn over the picture and
  /// no scrim is needed. The cut's number at its top band's left end and its
  /// length at its bottom band's right end — the conte sheet's CUT and TIME
  /// columns sit outside the picture cell exactly this way, one above and one
  /// below, and this is that sheet turned on its side.
  void _paintWriting(Canvas canvas, StoryboardCutBlockVisual block) {
    final cutGround = _bandGround(block);
    canvas.save();
    canvas.clipRect(block.topBand);
    final link = linkAffordanceRectOf(block);
    final top = block.topBand;
    paintBandWord(
      canvas,
      text: block.title,
      style: _titleStyle,
      // A linked cut's name gives up the icon's square at its end, so the
      // icon stands right of it however the name narrows.
      band: link == null
          ? top
          : Rect.fromLTRB(top.left, top.top, top.right - link.width, top.bottom),
      alignRight: false,
      ground: cutGround,
    );
    if (link != null) {
      _paintLinkIcon(canvas, link);
    }
    canvas.restore();

    canvas.save();
    canvas.clipRect(block.bottomBand);
    // D27: a cut with no storyboard layer prints NOTHING beside its length —
    // the explanatory copy is gone.
    if (block.total case final total?) {
      paintBandWord(
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
    // The cut's first frame: a block starts on its cut's first boundary.
    final g = geometry.value;
    final start = timelineFrameAt(
      rect.left -
          g.leadingFrameSpacerWidth +
          timelineFrameEdge(g.frameStartIndex, _cellExtent),
      _cellExtent,
    );
    return (
      left: math.max(rect.left, _left(start + cell.startIndex)),
      right: math.min(rect.right, _left(start + cell.endIndexExclusive)),
    );
  }

  /// A band's word, held to one end of [band]. Nothing is drawn with
  /// nothing to draw, or no stretch at all to draw it in. The cut's name
  /// and length are printed so — and the `+` of a cut with no conte layer,
  /// on the conte row under this one, so the two rows' words are one print.
  ///
  /// 🚨It keeps its type and narrows into the band (B, 유저 2026-09-24:
  /// 「컷블록의 텍스트든 se텍스트든 뭐든」) — to a sliver if that is all the
  /// room there is, never to nothing ([wordCondensation]: 「절대 안
  /// 사라지도록」). ↩️A title too long for its band was cut to an ellipsis —
  /// the `Text` + `TextOverflow.ellipsis` it was painted in for — so a cut's
  /// name lost its end at zoom-out.
  static void paintBandWord(
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
    // narrowed there stays in its own stretch.
    final inset = math.min(_padding, band.width / 2);
    final room = Size(band.width - inset * 2, band.height);
    // Its letter gaps give way first, then it narrows (F-234-Q1).
    final set = timelineWordSetOnto(text, style, room.width);
    final fit = wordFit(set.glyph.size, room);
    final width = set.glyph.width * fit.x;
    final height = set.glyph.height * fit.y;
    final dx = alignRight ? band.right - inset - width : band.left + inset;
    final origin = Offset(dx, band.top + (band.height - height) / 2);
    paintTimelineGlyphOnGround(
      canvas,
      origin,
      text,
      style,
      ground: ground,
      fit: fit,
      tightening: set.tightening,
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
        !_stripShowsPictures(inner) ||
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

  /// Whether a block's [strip] has room for its panels' pictures — the one
  /// answer for what is drawn there ([_picturesOf]) and what is asked for
  /// it ([_thumbnailsFor]).
  static bool _stripShowsPictures(Rect strip) =>
      strip.width > 0 && strip.height > 0;

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
  /// two bands in their fill and each panel's picture on its paper — a
  /// pending one on its placeholder's shade. The same fills [_paintBlock]
  /// lays down, read rather than measured.
  List<TimelineChromeGround> groundsOf(StoryboardCutBlockVisual block) {
    final cut = _bandGround(block);
    return [
      (rect: block.topBand, color: cut),
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
    BySet(linkedCutIds),
    crossAxisExtent,
    minBlockWidth,
    rowAddress,
    colorScheme,
    baseTextStyle,
    showSeconds,
    countingBase,
    showThumbnails,
    devicePixelRatio,
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
              // Joined from the parts that EXIST: a block too narrow for
              // its length prints none, and an unconditional joiner would
              // leave its space behind. ↩️The storyboard layer's name stood
              // between the two while the conte blocks were this block's
              // (I-73: they are the conte row's cells, which say their own).
              label: [block.title, ?block.total].join(' '),
              textDirection: TextDirection.ltr,
            ),
          ),
      ];
}

/// What the V row's edges stand on ([TimelineChromeGrounds]): the bands and
/// the pictures of the block under an edge ([StoryboardCutBlocksPainter
/// .groundsOf]). The plate is the rest — the chrome's own `gripGround`.
///
/// Made once a paint: the blocks are read against the live geometry then,
/// and each edge finds its block by halving rather than by a walk.
///
/// ↩️It took the offset of a chrome layer mounted part-way down the row —
/// the conte blocks', a band in — while the row had two papers; the cut's
/// own chrome covers the whole row (I-73).
class StoryboardPlateGrounds implements TimelineChromeGrounds {
  StoryboardPlateGrounds(this._painter) : _blocks = _painter.blocks();

  final StoryboardCutBlocksPainter _painter;

  /// In track order — so in x order.
  final List<StoryboardCutBlockVisual> _blocks;

  @override
  List<TimelineChromeGround> under(Rect box) {
    final block = _blockAt(box.center.dx);
    if (block == null) {
      return const [];
    }
    return [
      for (final ground in _painter.groundsOf(block))
        if (ground.rect.overlaps(box)) ground,
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

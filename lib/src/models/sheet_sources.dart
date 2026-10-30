import 'cut.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'timesheet_sheet_kind.dart';
import 'track_se_window.dart';
import 'transition_geometry.dart';

/// The rows one cut hands a SHEET, and how long the sheet runs.
///
/// The printed timesheet and the XDTS export are two renderings of ONE
/// projection, and both already carried comments promising as much. They
/// derived it separately until this class existed, which is how the
/// instruction row's sheet toggle came to be honoured on paper and ignored
/// in the export.
class SheetSources {
  SheetSources._({
    required this.playbackFrameCount,
    required this.handles,
    required this.drawnFrameCount,
    required this.clipToSheet,
    required this.celLayers,
    required this.actionBooks,
    required this.seLayers,
    required this.instructionLayers,
  });

  /// [transitionSpans] are the track's, on the GLOBAL axis; only the ones
  /// that cross one of the cut's boundaries matter, and what they buy the
  /// sheet is のりしろ ([handles]).
  factory SheetSources.of({
    required Cut cut,
    List<Layer> trackSeLayers = const [],
    int cutStartFrame = 0,
    List<TransitionSpan> transitionSpans = const [],
  }) {
    final playbackFrameCount = cut.duration < 1 ? 1 : cut.duration;
    // のりしろ. The conte 尺 (and so the cut block, and so the total) never
    // moves — the sheet just has more rows to fill than the cut is long,
    // which is exactly what 「シートは必ずここまで記入する」 asks for.
    //
    // Both sides show it at the TAIL (user's rule): the blue line answers
    // "how much do I draw", not "where does the extra sit", and the mark on
    // the transition row answers where.
    final handles = cutTransitionHandles(
      cutStart: cutStartFrame,
      cutEnd: cutStartFrame + playbackFrameCount,
      spans: transitionSpans,
    );
    final drawnFrameCount = handles.drawnFrames(playbackFrameCount);
    // The display window is open-ended on the right now (SE globalization
    // — the timeline's runway shows the neighbours' sounds), but a printed
    // page is no runway: entries starting at or past the line the cut is
    // DRAWN to stay off the sheet, crossing blocks keep their true length
    // and the sheet marks them with the timeline's `~`. One clip for every
    // cut-scoped export ([clipLayerStartsBefore] — the XDTS sheet reads the
    // same projection), and for the live clone a drag publishes.
    //
    // 🗣️F-358 (유저 2026-10-17): 「컷 엔드라인(OL여백이든 뭐든 총합적인
    // 엔드라인) 넘어가는건 안보이게하고」. ↩️It clipped at the conte end, and
    // a sound starting in the tail のりしろ the sheet draws stayed off it.
    Layer clipToSheet(Layer displayClone) =>
        clipLayerStartsBefore(displayClone, drawnFrameCount);
    return SheetSources._(
      playbackFrameCount: playbackFrameCount,
      handles: handles,
      drawnFrameCount: drawnFrameCount,
      clipToSheet: clipToSheet,
      // Cel columns: ONE gate shared with the envelope and the XDTS export
      // ([layerTakesSheetCelColumn], D24) — image rows answer false, a
      // nameless held picture prints nothing.
      celLayers: [
        for (final layer in cut.layers)
          if (layerTakesSheetCelColumn(layer)) layer,
      ],
      actionBooks: sheetBooksOf(_actionBlockRows(cut.layers)),
      seLayers: _seRowsOf(
        cut,
        trackSeLayers,
        window: TrackSeWindow(
          cutStartFrame: cutStartFrame - handles.head,
          cutDurationFrames: handles.head + cut.duration,
        ),
        clipToSheet: clipToSheet,
      ),
      instructionLayers: [
        for (final layer in cut.layers)
          if (layer.kind == LayerKind.instruction && layer.onTimesheet) layer,
      ],
    );
  }

  /// The SE rows the sheet prints. SE rows are track-owned: their global
  /// timelines are windowed to this cut (spill-in synthesizes a display
  /// block) and clipped as the sheet is ([clipToSheet]). Cut-owned SE
  /// layers remain for legacy fixtures.
  ///
  /// 🗣️I-73-ol-sheet-columns: the [window] opens where the cut's OWN frame
  /// 0 stands — its conte start less the のりしろ an O.L arriving into it
  /// asks — as the cut view's does (`TrackSeDisplay.trackSeWindow`). The
  /// sheet's rows are the cut's own frames, its cel columns' and its
  /// sounds' alike. ↩️It opened at the cut's place, so in a cut an O.L
  /// arrives into a sound printed the のりしろ above the picture it is
  /// heard with (🧪10-09: the picture's head on row 12, the sound's on 6).
  static List<({Layer layer, int? spillInLeadFrames})> _seRowsOf(
    Cut cut,
    List<Layer> trackSeLayers, {
    required TrackSeWindow window,
    required Layer Function(Layer displayClone) clipToSheet,
  }) => [
    for (final layer in cut.layers)
      if (layerPrintsSheetLines(layer))
        (layer: layer, spillInLeadFrames: null),
    for (final layer in trackSeLayers)
      if (layerPrintsSheetLines(layer))
        (
          layer: clipToSheet(window.displayLayer(layer)),
          spillInLeadFrames: window.spillInLeadFrames(layer),
        ),
  ];

  /// The rows the ACTION block's books lie among: every row that takes no
  /// cel column, and the ACTION block's own cel rows. The CELL block's rows
  /// are not there for a book to lie between (F-406-Q1).
  static List<Layer> _actionBlockRows(List<Layer> layers) => [
    for (final layer in layers)
      if (!layerTakesSheetCelColumn(layer) || !layerTakesTheCelBlock(layer))
        layer,
  ];

  /// The cut's length in rows the sheet must show, never less than 1.
  final int playbackFrameCount;

  /// The のりしろ the cut draws outside its conte 尺, one side at a time.
  final CutTransitionHandles handles;

  /// How many rows the sheet DRAWS: the conte 尺 and the [handles] — the
  /// line the cut ends at on paper.
  final int drawnFrameCount;

  /// An SE row windowed onto the cut's own frames, as the sheet prints it:
  /// nothing starting at or past [drawnFrameCount]. The rows in [seLayers]
  /// already wear it; the live clone a drag publishes arrives outside this
  /// class and still owes it.
  final Layer Function(Layer displayClone) clipToSheet;

  /// The rows that take a cel column — on the printed timesheet, the
  /// ACTION block's ([actionLayers]) and the CELL block's ([cellLayers]).
  final List<Layer> celLayers;

  /// The cel rows the timesheet prints in its ACTION block: all but the
  /// CELL block's (F-406 · F-431).
  List<Layer> get actionLayers => [
    for (final layer in celLayers)
      if (!layerTakesTheCelBlock(layer)) layer,
  ];

  /// The cel rows the timesheet prints in its CELL block: the 動画 and
  /// 仕上げ ones ([layerTakesTheCelBlock]), by the ACTION block's law (F-406: 「기본적인 규칙 왠만한건 액션란 등
  /// 규칙 똑같음. 법 통일」).
  ///
  /// 🗣️F-406-Q1 (유저 2026-10-20): 「CELL 은 동화 행만」 — each block lays
  /// its own rows in turn, and the ACTION block's names are not mirrored
  /// over the CELL block any more: 「동화 하는 사람이 액션이랑 셀 칸
  /// 위치맞추기 알아서 하도록 … 동화 레이어 끼리만 위치관계 가지는느낌?
  /// 액션란도 그렇잖아」. ↩️The CELL block was blank paper headed by the
  /// ACTION rows' names (UI-R10 #10).
  List<Layer> get cellLayers => [
    for (final layer in celLayers)
      if (layerTakesTheCelBlock(layer)) layer,
  ];

  /// The cel columns a timesheet's paper must hold: its wider block's.
  int get celColumnsAcross {
    final cells = cellLayers.length;
    final actions = celLayers.length - cells;
    return actions > cells ? actions : cells;
  }

  /// The books the ACTION block marks between its columns ([sheetBooksOf]).
  ///
  /// ↩️F-430 (유저 2026-10-21): the CELL block marks none — 「셀 란은 이런
  /// 북 표시 하지않음. 기본적으로는 액션란이랑 셀 구성이 똑같기 때문에 셀
  /// 란에는 BOOK표시 안하는 것」. It marked its own since F-406-Q1.
  final List<SheetBook> actionBooks;

  /// The SE rows, already windowed onto the cut's own frames and clipped
  /// ([clipToSheet]), each with how far into a sound spilled in from an
  /// earlier cut its first frame is
  /// ([TrackSeWindow.spillInLeadFrames]) — where the printed sheet lays
  /// that sound's words from, and marks its start-side `~`. Whether one
  /// runs past the end is the sheet's to ask, at the line it draws the cut
  /// to ([seSoundRunsPast], F-358).
  final List<({Layer layer, int? spillInLeadFrames})> seLayers;

  /// The instruction rows the sheet prints.
  final List<Layer> instructionLayers;
}

/// A BOOK the sheet marks (D24): [boundary] cel columns up from the
/// bottom — between column `boundary - 1` and `boundary` — and its tag,
/// every book at that boundary bottom first, joined by `,` (유저
/// 2026-09-25: 「같은 축에 여러 북 있으면 … 레이어이름,레이어이름 이런식으로
/// 사이에 , 넣어서」).
typedef SheetBook = ({int boundary, String label});

/// The books [layers] (bottom to top, the cut's order) mark on a sheet,
/// left to right: every image row [layerMarksSheetBook] answers for, at
/// the boundary of the cel columns below it.
///
/// ⛔None under the first cel column — 유저 2026-09-25
/// (timesheet-edge-books-Q1): 「업계에서 보통 A셀 밑, 셀 맨 밑은
/// 표시안해」. The one over the last column is marked.
List<SheetBook> sheetBooksOf(List<Layer> layers) {
  var cels = 0;
  final labels = <int, List<String>>{};
  for (final layer in layers) {
    if (layerTakesSheetCelColumn(layer)) {
      cels += 1;
    } else if (cels > 0 && layerMarksSheetBook(layer)) {
      (labels[cels] ??= []).add(sheetBookLabel(layer));
    }
  }
  return [
    for (final MapEntry(key: boundary, value: names) in labels.entries)
      (boundary: boundary, label: names.join(',')),
  ];
}

/// A book's tag: its row's name and the name of the picture the row
/// holds, run together — 「BOOK」 and 「1」 print 「BOOK1」 — or the row's
/// name alone when the picture has none (유저 2026-09-25: 「레이어이름이
/// BOOK인데 프레임이름 없으면 BOOK으로 넣고, BOOK인데 프레임이름1이면
/// BOOK1이렇게」). An image row holds one picture a cut
/// ([LayerKind.holdsSingleCel]) — the one its lane shows
/// ([authoredBlockOf]); its bank may hold other cuts' as well.
String sheetBookLabel(Layer layer) {
  final shown = authoredBlockOf(layer)?.frameId;
  final picture = shown == null ? null : layer.frameById(shown);
  return '${layer.name}${picture?.celNumber ?? ''}';
}

/// The paper [cut] prints its timesheet on: the kind it chose, while a
/// strip holds the cel columns its [sources] lay ([sheetKindFor]).
TimesheetSheetKind printedSheetKindOf(Cut cut, SheetSources sources) =>
    sheetKindFor(cut.metadata.sheetKind, celColumns: sources.celColumnsAcross);

/// How many frames a page of [cut]'s timesheet holds at [fps] — its paper's
/// ([printedSheetKindOf]), the page the timeline's page view counts by:
/// 🗣️I-81-Q1 (유저 2026-10-30 「그 컷의 X시트 장을 따른다」).
int sheetPageFramesOf(Cut cut, int fps) =>
    printedSheetKindOf(cut, SheetSources.of(cut: cut)).pageSeconds * fps;

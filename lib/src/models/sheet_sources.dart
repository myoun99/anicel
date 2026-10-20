import 'cut.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'track_se_window.dart';

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
    required this.celLayers,
    required this.actionBooks,
    required this.cellBooks,
    required this.seLayers,
    required this.instructionLayers,
  });

  factory SheetSources.of({
    required Cut cut,
    List<Layer> trackSeLayers = const [],
    int cutStartFrame = 0,
  }) {
    final playbackFrameCount = cut.duration < 1 ? 1 : cut.duration;
    // SE rows are track-owned: window their global timelines to this cut
    // (spill-in synthesizes a display block). Cut-owned SE layers remain
    // for legacy fixtures.
    final seWindow = TrackSeWindow(
      cutStartFrame: cutStartFrame,
      cutDurationFrames: cut.duration,
    );
    return SheetSources._(
      playbackFrameCount: playbackFrameCount,
      // Cel columns: ONE gate shared with the envelope and the XDTS export
      // ([layerTakesSheetCelColumn], D24) — image rows answer false, a
      // nameless held picture prints nothing.
      celLayers: [
        for (final layer in cut.layers)
          if (layerTakesSheetCelColumn(layer)) layer,
      ],
      actionBooks: sheetBooksOf(_blockRows(cut.layers, inbetween: false)),
      cellBooks: sheetBooksOf(_blockRows(cut.layers, inbetween: true)),
      seLayers: [
        for (final layer in cut.layers)
          if (layerPrintsSheetLines(layer))
            (layer: layer, crosses: crossesCutEnd(layer, playbackFrameCount),
             spills: false),
        for (final layer in trackSeLayers)
          if (layerPrintsSheetLines(layer))
            () {
              // The display window is open-ended on the right now (SE
              // globalization — the timeline's runway shows the
              // neighbours' sounds), but a printed page is no runway:
              // entries starting at or past the cut end stay off the
              // sheet, crossing blocks keep their true length and the
              // sheet marks them with the timeline's `~`. One clip for
              // every cut-scoped export ([clipLayerStartsBefore] — the
              // XDTS sheet reads the same projection).
              final clone = clipLayerStartsBefore(
                seWindow.displayLayer(layer),
                playbackFrameCount,
              );
              return (
                layer: clone,
                crosses: crossesCutEnd(clone, playbackFrameCount),
                spills: seWindow.spillInBlock(layer) != null,
              );
            }(),
      ],
      instructionLayers: [
        for (final layer in cut.layers)
          if (layer.kind == LayerKind.instruction && layer.onTimesheet) layer,
      ],
    );
  }

  /// The rows a block's books lie among: every row that takes no cel
  /// column, and that block's own cel rows — the 動画 ones for the CELL
  /// block, the others for the ACTION block. The other block's rows are not
  /// there for a book to lie between (F-406-Q1).
  static List<Layer> _blockRows(
    List<Layer> layers, {
    required bool inbetween,
  }) => [
    for (final layer in layers)
      if (!layerTakesSheetCelColumn(layer) ||
          layerMarkedInbetween(layer) == inbetween)
        layer,
  ];

  /// The cut's length in rows the sheet must show, never less than 1.
  final int playbackFrameCount;

  /// The rows that take a cel column — on the printed timesheet, the
  /// ACTION block's ([actionLayers]) and the CELL block's ([cellLayers]).
  final List<Layer> celLayers;

  /// The cel rows the timesheet prints in its ACTION block: all but the
  /// 動画 ones (F-406).
  List<Layer> get actionLayers => [
    for (final layer in celLayers)
      if (!layerMarkedInbetween(layer)) layer,
  ];

  /// The cel rows the timesheet prints in its CELL block: the 動画 ones,
  /// by the ACTION block's law (F-406: 「기본적인 규칙 왠만한건 액션란 등
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
      if (layerMarkedInbetween(layer)) layer,
  ];

  /// The cel columns a timesheet's paper must hold: its wider block's.
  int get celColumnsAcross {
    final cells = cellLayers.length;
    final actions = celLayers.length - cells;
    return actions > cells ? actions : cells;
  }

  /// The books the ACTION block marks between its columns, and those the
  /// CELL block marks between its own ([sheetBooksOf]).
  final List<SheetBook> actionBooks;
  final List<SheetBook> cellBooks;

  /// The SE rows, already windowed and clipped to this cut, each with the
  /// two facts the printed sheet marks: whether the row's block runs past
  /// the cut end, and whether it spilled in from an earlier cut.
  final List<({Layer layer, bool crosses, bool spills})> seLayers;

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

/// Whether any authored block of [clone] starts inside the cut and runs
/// past [playbackFrameCount] — the `~` the sheet marks a crossing with.
bool crossesCutEnd(Layer clone, int playbackFrameCount) {
  for (final entry in clone.timeline.entries) {
    if (entry.value.isDrawing &&
        !entry.value.ghost &&
        entry.key < playbackFrameCount &&
        entry.key + (entry.value.length ?? 1) > playbackFrameCount) {
      return true;
    }
  }
  return false;
}

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/conte/conte_ink_keys.dart';
import '../../models/conte/conte_ink_windows.dart';
import '../../models/conte/conte_sheet_layout.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../services/brush_frame_store.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/history_manager.dart';
import '../brush/brush_tool_state.dart';
import '../sheet/sheet_ink_layer.dart';
import '../sheet/sheet_ink_controller.dart';
import 'conte_picture_ink.dart';

/// Owns the conte's sheet ink (#16 — the conte panel is the timesheet's
/// canvas shell with conte content): brush strokes on the conte's cells,
/// kept in a coordinator/store SEPARATE from the session's cel
/// [BrushFrameStore] so sheet ink can never leak into cel rendering or
/// export, committed through the app [HistoryManager] with the same
/// [BrushStrokeHistoryCommand] the drawing canvas uses.
///
/// ONE plane, the envelope's shape: ink over a cell's whole ROW BAND (cut
/// column through the TIME column), one surface per storyboard BLOCK —
/// keyed by the block's own handwriting id, which rides on its memo beside
/// its ACTION (`ExposureMemo.inkId`) — so the ink rides its block through
/// moves and repagination, saves with the project, and dies with the
/// block. ↩️There was a paper plane too, for the header, the margins and
/// the rows no cut stood in; ink kept there stayed where it was drawn
/// while the cuts moved under it, and the user wanted ink in the cells
/// alone (H44, 09-26 「칸에만 … 구조적으로 강제」). The store may be handed
/// in by the session so the project archive can persist it
/// ([BrushFrameStore] cels, the second namespace).
class ConteInkController extends SheetInkController<Null> {
  ConteInkController({BrushFrameStore? rowStore})
    : this._(
        InkPlaneSlot(
          store: rowStore ?? BrushFrameStore(),
          initialFrameKey: const BrushFrameKey(
            projectId: conteInkProjectId,
            trackId: conteInkTrackId,
            cutId: CutId('conte-ink-init'),
            layerId: conteInkRowLayerId,
            frameId: FrameId('conte-ink-init'),
          ),
        ),
      );

  ConteInkController._(this._row) : super({null: _row});

  final InkPlaneSlot _row;

  /// One cell surface, at [conteInkScale]: the page BODY's size for every
  /// cell (the coordinator shares one geometry per plane). A cell's window
  /// exposes only its own band's slice — the tile-sparse store makes the
  /// unused remainder free, and a cell that GROWS (rowSpan) simply reveals
  /// more of the same surface with its ink intact.
  CanvasSize? get rowSurfaceSize => _row.size;

  /// Adopts the sheet geometry (every page shares one metrics). Never
  /// notifies: callers run this during build.
  void syncGeometry(ConteSheetMetrics metrics) {
    _row.syncTo(
      CanvasSize(
        width: (metrics.bodyWidth * conteInkScale).ceil(),
        height: (metrics.bodyHeight * conteInkScale).ceil(),
      ),
    );
  }
}

/// The ink windows for one page: a window per cell's band, so a stroke
/// over several cells leaves each its own piece ([sheetInkRegions]) and a
/// stroke outside every cell leaves nothing — ink is the cells' alone (유저
/// 09-26, H44 「칸에만」). A block not yet written on writes under the name
/// [unwrittenInkIdOf] gives it ahead.
///
/// A cell with no block draws its band as its picture draws (유저 답
/// conte-drawing-target-Q3 「그림 칸과 같이 (토글을 따른다)」): into the
/// handwriting of the block its first stroke makes — or, while the
/// canvas's 「프레임 자동 생성」 is off, into nothing, refusing the pen with
/// [rowRefusal] as the picture does.
///
/// ⛔Made from the walk the page's printers read ([conteInkMarks]) — the
/// brush writes through exactly the windows the paper shows.
List<SheetInkWindow> conteInkWindows(
  ContePageLayout page, {
  String Function(ContePlacedCell cell)? unwrittenInkIdOf,
  String? rowRefusal,
}) {
  final blockless = {
    if (unwrittenInkIdOf != null)
      for (final cell in page.cells)
        if (cell.source.frameId == null)
          conteInkRowKey(CutId(cell.cutId), unwrittenInkIdOf(cell)),
  };
  return [
    for (final ink in conteInkMarks(
      page,
      page.metrics,
      unwrittenInkIdOf: unwrittenInkIdOf,
    ))
      SheetInkWindow.of(
        ink,
        id: 'row-${ink.key.cutId.value}-${ink.key.frameId.value}',
        refusal: blockless.contains(ink.key) ? rowRefusal : null,
      ),
  ];
}

/// The conte's ink input/display stack: every window hosts the SAME
/// interactive brush view the drawing canvas uses, windowed onto its
/// surface by a derived viewport ([SheetInkLayer]) — the sheet's own ink
/// and, above it, the pictures drawing into their cels.
class ConteInkLayer extends StatelessWidget {
  const ConteInkLayer({
    super.key,
    required this.controller,
    required this.page,
    required this.brushToolState,
    required this.historyManager,
    required this.viewport,
    required this.strokeActive,
    this.cacheInvalidationSink,
    this.pictures,
    this.pictureWindows = const [],
    this.pictureInvalidationSink,
    this.unwrittenInkIdOf,
    this.rowRefusal,
    this.beforeLanding,
  });

  final ConteInkController controller;

  /// The page ON SCREEN — its windows are mounted; the other pages'
  /// surfaces keep their ink, they just have no window.
  final ContePageLayout page;

  /// Forwarded to [SheetInkLayer.brushToolState] — heard, not handed over.
  final ValueListenable<BrushToolState> brushToolState;
  final HistoryManager historyManager;

  /// The live panel viewport (the same transform the page painter applies).
  final CanvasViewport viewport;

  /// Forwarded to [SheetInkLayer.strokeActive].
  final ValueNotifier<bool> strokeActive;

  final CacheInvalidationSink? cacheInvalidationSink;

  /// The cels the pictures draw into, and the windows they draw through
  /// ([contePictures]).
  final ContePictureInkController? pictures;
  final List<SheetPictureWindow> pictureWindows;

  /// Where a picture's stroke tells the caches which cel changed — the
  /// canvas's own sink: the cel is the canvas's, and the pictures and the
  /// playback that show it have to hear.
  final CacheInvalidationSink? pictureInvalidationSink;

  /// The name a block not yet written on writes under ([conteInkWindows]).
  final String Function(ContePlacedCell cell)? unwrittenInkIdOf;

  /// Why the band of a cell with no block takes no ink — the pictures'
  /// refusal, word for word ([conteInkWindows]).
  final String? rowRefusal;

  /// Told each piece of a stroke is landing, before it is kept — where what
  /// it was drawn into is made or named: the block a cell with none draws
  /// into (its picture or its band), the id a block's first handwriting
  /// puts on it.
  /// So the stroke lands in something its cut has, in the stroke's own undo
  /// step.
  final ValueChanged<SheetWindow>? beforeLanding;

  @override
  Widget build(BuildContext context) {
    return SheetInkLayer(
      windows: [
        ...conteInkWindows(
          page,
          unwrittenInkIdOf: unwrittenInkIdOf,
          rowRefusal: rowRefusal,
        ),
        ...pictureWindows,
      ],
      keyPrefix: 'conte',
      viewport: viewport,
      brushToolState: brushToolState,
      strokeActive: strokeActive,
      history: historyManager.gestures,
      // The plane axis stays HERE, with the controller that has one: a
      // picture's plane is its cel's canvas size; the ink has one plane.
      sessionStateFor: (window) => switch (window.plane) {
        final CanvasSize size => pictures!.sessionStateFor(size, window.key),
        _ => controller.sessionStateFor(null, window.key),
      },
      onStrokeCommitted: (window, strokeData) {
        beforeLanding?.call(window);
        if (window case SheetPictureWindow(plane: final CanvasSize size)) {
          pictures!.commitStroke(
            plane: size,
            key: window.key,
            strokeData: strokeData,
            historyManager: historyManager,
            cacheInvalidationSink: pictureInvalidationSink,
          );
          return;
        }
        controller.commitStroke(
          plane: null,
          key: window.key,
          strokeData: strokeData,
          historyManager: historyManager,
          cacheInvalidationSink: cacheInvalidationSink,
        );
      },
    );
  }
}

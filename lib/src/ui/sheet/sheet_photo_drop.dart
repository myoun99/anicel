import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/media_asset.dart';
import '../../models/media_reference.dart';
import '../../models/sheet_marks.dart' show SheetInkPlacement;
import '../../services/cache_invalidation_executor.dart';
import '../../services/commands/cel_photo_edit_command.dart';
import '../../services/import/raster_cel_import.dart' show fitPose;
import '../../services/media/media_pixel_size.dart';
import '../editor_session_manager.dart';
import '../media/media_asset_drag_data.dart';
import '../media/media_asset_drop_target.dart';
import '../theme/app_theme.dart' show AppColors;
import 'sheet_ink_controller.dart';
import 'sheet_ink_layer.dart';

/// Where a pool picture of [picture]'s own pixels, dropped at paper point
/// [paper] in the cell [placement] lays, stands on that cell's ink (I-97
/// Q2 c, 유저 2026-10-15 「원본 크기, 칸보다 크면 칸에 맞게」): a pixel of the
/// picture a pixel of the ink — shrunk to fit the cell where it is larger,
/// never grown ([fitPose]'s contain, else its 1:1) — its centre where it
/// was dropped. The cell clips it as it clips the ink.
///
/// ⛔Not the pool's own fit ([MediaAsset.fitMode]) — that one places the
/// picture on a canvas; a sheet's cell is answered by Q2 c.
MediaReference droppedSheetPhoto({
  required String path,
  required CanvasSize picture,
  required SheetInkPlacement placement,
  required Offset paper,
}) {
  final cell = Rect.fromPoints(
    placement.pixelOf(placement.window.topLeft),
    placement.pixelOf(placement.window.bottomRight),
  );
  final larger = picture.width > cell.width || picture.height > cell.height;
  final at = placement.pixelOf(paper);
  return MediaReference(
    assetPath: path,
    pose: fitPose(
      picture: picture,
      canvas: CanvasSize(
        width: cell.width.floor(),
        height: cell.height.floor(),
      ),
      fit: larger ? MediaFitMode.contain : MediaFitMode.none,
    ).copyWith(center: CanvasPoint(x: at.dx, y: at.dy)),
    pictureSize: picture,
  );
}

/// A pool picture dropped on a cell of a sheet lands on that cell's ink as
/// a photo (I-97) — a conte's band, a timesheet's page, an envelope's box
/// — brush or no brush: a drop is no stray mark for the switch to guard.
/// The cell is the one a stroke started there writes in
/// ([sheetInkOwnerAt]); one that takes no ink takes no photo, and the
/// drag's chip says so ([MediaAssetDropTarget.accepts]).
///
/// While a picture is dragged over a cell, that cell is outlined — where
/// the drop will land, before it lands.
class SheetPhotoDrop extends StatefulWidget {
  const SheetPhotoDrop({
    super.key,
    required this.session,
    required this.ink,
    required this.windows,
    required this.viewport,
    this.beforeLanding,
    this.cacheInvalidationSink,
  });

  final EditorSessionManager session;

  /// The sheet's ink the photo lands on.
  final SheetInkController<Null> ink;

  /// Every window of the sheet, bottom of the stack first — mounted or
  /// not: a drop lands in the cells, not in whatever views are on screen.
  /// Asked once a picture is over the sheet and not before: a sheet builds
  /// at every frame of a pan, and next to none of them meets a drop.
  final List<SheetWindow> Function() windows;
  final CanvasViewport viewport;

  /// Told a photo is landing, before it is kept — where what the cell
  /// lacks is made, in the photo's own undo step: the hook a stroke's
  /// landing calls ([SheetInkLayer]), the same one (the conte's block).
  final ValueChanged<SheetWindow>? beforeLanding;
  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  State<SheetPhotoDrop> createState() => _SheetPhotoDropState();
}

class _SheetPhotoDropState extends State<SheetPhotoDrop> {
  /// The cell a picture is dragged over, on the paper.
  Rect? _over;

  /// [SheetPhotoDrop.windows] as this widget was asked — a drag's every
  /// move asks for the cell under it — until it is built again.
  List<SheetWindow>? _asked;

  List<SheetWindow> get _windows => _asked ??= widget.windows();

  @override
  void didUpdateWidget(SheetPhotoDrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _asked = null;
  }

  /// Where [global] is on the paper — when what is dragged is one of the
  /// pool's pictures.
  Offset? _paperAt(MediaAssetDragData data, Offset global) {
    final asset = widget.session.repository.requireProject().mediaAssetByPath(
      data.path,
    );
    final render = context.findRenderObject();
    if (asset?.kind != MediaAssetKind.image ||
        render is! RenderBox ||
        !render.hasSize) {
      return null;
    }
    final viewport = widget.viewport;
    return (render.globalToLocal(global) -
            Offset(viewport.panX, viewport.panY)) /
        viewport.zoom;
  }

  /// The cell under paper point [paper] that takes a photo: the one a
  /// stroke started there writes in ([sheetInkOwnerAt]).
  SheetInkWindow? _cellUnder(Offset paper) =>
      switch (sheetInkOwnerAt(_windows, paper)) {
        final SheetInkWindow window when window.refusal == null => window,
        _ => null,
      };

  SheetInkWindow? _cellAt(MediaAssetDragData data, Offset global) =>
      switch (_paperAt(data, global)) {
        final paper? => _cellUnder(paper),
        null => null,
      };

  void _hover(Rect? cell) {
    if (cell != _over) {
      setState(() => _over = cell);
    }
  }

  void _drop(MediaAssetDragData data, Offset global) {
    if (_paperAt(data, global) case final paper?) {
      unawaited(_land(paper, data.path));
    }
  }

  /// [path]'s picture read for its size — its own pixels, what a photo
  /// dropped on a sheet stands at (I-97 Q2 c) — then landed in the cell
  /// under [paper] as the sheet is THEN — one laid again while the picture
  /// was read (a form switched, a page added) is asked again, as a stroke
  /// started there would ask it.
  Future<void> _land(Offset paper, String path) async {
    final picture = await readMediaPixelSize(
      MediaAssetKind.image,
      path,
      widget.session.projectFile.holdMediaBytes,
    );
    if (picture == null || !mounted) {
      return;
    }
    final window = _cellUnder(paper);
    if (window == null) {
      return;
    }
    final history = widget.session.historyManager;
    final start = history.gestures.mark;
    widget.beforeLanding?.call(window);
    widget.ink.putPhoto(
      plane: null,
      key: window.key,
      reference: droppedSheetPhoto(
        path: path,
        picture: picture,
        placement: window.placement,
        paper: paper,
      ),
      historyManager: history,
      cacheInvalidationSink: widget.cacheInvalidationSink,
    );
    history.gestures.foldSince(start, CelPhotoEditCommand.label);
  }

  @override
  Widget build(BuildContext context) {
    final viewport = widget.viewport;
    final over = _over;
    return Stack(
      children: [
        Positioned.fill(
          child: MediaAssetDropTarget(
            framed: false,
            accepts: (data, global) => _cellAt(data, global) != null,
            onHover: (data, global) =>
                _hover(_cellAt(data, global)?.documentRect),
            onLeave: () => _hover(null),
            onDrop: _drop,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: const ValueKey<String>('sheet-photo-drop-outline'),
              painter: SheetDropOutline(
                over == null
                    ? null
                    : Rect.fromLTWH(
                        viewport.panX + viewport.zoom * over.left,
                        viewport.panY + viewport.zoom * over.top,
                        viewport.zoom * over.width,
                        viewport.zoom * over.height,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The cell a dragged picture will land in, outlined on the screen;
/// nothing without one.
class SheetDropOutline extends CustomPainter {
  const SheetDropOutline(this.cell);

  final Rect? cell;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = this.cell;
    if (cell == null) {
      return;
    }
    canvas.drawRect(
      cell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(SheetDropOutline oldDelegate) => oldDelegate.cell != cell;
}

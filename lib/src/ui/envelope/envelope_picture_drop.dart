import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/contain_rect.dart';
import '../../models/brush_stamp_image.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_piece.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/media_asset.dart';
import '../../services/brush_stroke_commit_data.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/canvas_selection_paint_clip.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/cut_piece_stamp.dart';
import '../../services/media/held_viewer_document.dart';
import '../../services/media/image_viewer_document.dart';
import '../editor_session_manager.dart';
import '../media/media_asset_drag_data.dart';
import '../media/media_asset_drop_target.dart';
import '../sheet/sheet_ink_layer.dart';
import '../theme/app_theme.dart' show AppColors;
import 'cut_envelope_ink.dart';

/// A picture from the media pool, dropped on a box of the cut's 봉투: stamped
/// into the envelope's handwriting — the layer the brush's checks go into —
/// contained in the box, its shape kept (유저 답 envelope-stamp-Q1 「풀
/// 그림을 칸에 끌어다 놓으면 그 컷의 손글씨로 찍힌다」). One undo takes it
/// back; after that it is ink like any other, for the eraser and the brush.
///
/// While a picture is dragged over a box, that box is outlined — where the
/// drop will land, before it lands.
class EnvelopePictureDrop extends StatefulWidget {
  const EnvelopePictureDrop({
    super.key,
    required this.session,
    required this.layout,
    required this.windows,
    required this.ink,
    required this.viewport,
    this.cacheInvalidationSink,
  });

  final EditorSessionManager session;
  final CutEnvelopeLayout layout;

  /// Every inking box's window on the owning cut ([envelopeInkWindows]),
  /// bottom of the stack first — mounted or not: a drop lands in the
  /// boxes, not in whatever views are on screen right now.
  final List<SheetInkWindow> windows;
  final CutEnvelopeInkController ink;
  final CanvasViewport viewport;
  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  State<EnvelopePictureDrop> createState() => _EnvelopePictureDropState();
}

class _EnvelopePictureDropState extends State<EnvelopePictureDrop> {
  /// The box a picture is dragged over, on the paper.
  Rect? _over;

  /// The inking box under [global] — the topmost, as a stroke finds it —
  /// when what is dragged is one of the pool's pictures.
  SheetInkWindow? _windowAt(MediaAssetDragData data, Offset global) {
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
    final paper =
        (render.globalToLocal(global) - Offset(viewport.panX, viewport.panY)) /
        viewport.zoom;
    final box = widget.layout.inkBoxAt(paper.dx, paper.dy);
    for (final window in widget.windows) {
      if (window.id == box?.id) {
        return window;
      }
    }
    return null;
  }

  void _hover(Rect? box) {
    if (box != _over) {
      setState(() => _over = box);
    }
  }

  void _drop(MediaAssetDragData data, Offset global) {
    final target = _windowAt(data, global);
    if (target == null) {
      return;
    }
    unawaited(
      stampEnvelopePicture(
        (
          session: widget.session,
          ink: widget.ink,
          windows: widget.windows,
          cacheInvalidationSink: widget.cacheInvalidationSink,
        ),
        target: target,
        path: data.path,
      ),
    );
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
            accepts: (data, global) => _windowAt(data, global) != null,
            onHover: (data, global) =>
                _hover(_windowAt(data, global)?.documentRect),
            onLeave: () => _hover(null),
            onDrop: _drop,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: const ValueKey<String>('envelope-drop-outline'),
              painter: EnvelopeDropOutline(
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

/// The box a dragged picture will land in, outlined on the screen; nothing
/// without one.
class EnvelopeDropOutline extends CustomPainter {
  const EnvelopeDropOutline(this.box);

  final Rect? box;

  @override
  void paint(Canvas canvas, Size size) {
    final box = this.box;
    if (box == null) {
      return;
    }
    canvas.drawRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(EnvelopeDropOutline oldDelegate) =>
      oldDelegate.box != box;
}

/// One cut's envelope handwriting, as a stamp lands in it: the session (its
/// history, and the media's bytes), the envelope's ink, the owning cut's
/// inking boxes ([envelopeInkWindows], bottom of the stack first) and the
/// sink a stroke's commit tells.
typedef EnvelopeHandwriting = ({
  EditorSessionManager session,
  CutEnvelopeInkController ink,
  List<SheetInkWindow> windows,
  CacheInvalidationSink? cacheInvalidationSink,
});

/// Stamps the pool picture at [path] into [target]'s box: contained in it,
/// its shape kept (「늘어난 도장은 도장이 아니다」 — [containRect]), at the
/// ink's own pixels, and landed on [envelope]'s boxes as one paper in one
/// undo step. False when there is nothing to stamp — no picture, or a form
/// switched while the picture decoded, which moved every box.
///
/// Nothing new underneath: the viewer's decode at the size asked for
/// ([openHeldViewerDocument] — the project's carried copy first), a cut
/// piece's paste ([buildCutPasteDab] — an RGBA box stamped 1:1), and the
/// sheet's own landing: each window keeps the piece it SHOWS
/// ([sheetInkRegions]), and the pieces fold into one step as a stroke's
/// do (「진짜 하나의 용지처럼」).
Future<bool> stampEnvelopePicture(
  EnvelopeHandwriting envelope, {
  required SheetInkWindow target,
  required String path,
}) async {
  final ink = envelope.ink;
  final geometry = ink.surfaceSize;
  final document = await openHeldViewerDocument(
    envelope.session.projectFile.holdMediaBytes,
    path,
    ImageViewerDocument.open,
  );
  if (document == null) {
    return false;
  }
  try {
    final shown = containRect(document.pageSize(0), target.documentRect);
    final width = (shown.width * target.surfaceScale).floor();
    final height = (shown.height * target.surfaceScale).floor();
    if (width <= 0 || height <= 0) {
      return false;
    }
    final picture = await document.renderPage(0, width: width, height: height);
    try {
      final rgba = await picture.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (rgba == null || ink.surfaceSize != geometry) {
        return false;
      }
      _land(
        envelope,
        target: target,
        paper: shown,
        image: BrushStampImage(
          id: 'envelope-${DateTime.now().microsecondsSinceEpoch}',
          width: picture.width,
          height: picture.height,
          rgba: rgba.buffer.asUint8List(),
        ),
      );
      return true;
    } finally {
      picture.dispose();
    }
  } finally {
    await document.dispose();
  }
}

/// [image] laid on the paper at [paper]'s corner — inside [target]'s box —
/// as ONE undo step: the box it was dropped on, and every box stacked over
/// it, keeps the piece it shows.
///
/// ⚠️Only the boxes it truly lies on. A box's edges are fractions of the
/// form, so neighbours meet a hair apart or a hair over each other, and a
/// neighbour a hair over the picture took a sliver of it at the shared
/// edge. A box below the target shows nothing of it (the target is over
/// it there); a box over it takes a piece only where the two meet by a
/// whole ink pixel each way.
void _land(
  EnvelopeHandwriting envelope, {
  required SheetInkWindow target,
  required Rect paper,
  required BrushStampImage image,
}) {
  final (:session, :ink, :windows, :cacheInvalidationSink) = envelope;
  final from = windows.indexOf(target);
  if (from < 0) {
    return;
  }
  final history = session.historyManager;
  final start = history.gestures.mark;
  final regions = sheetInkRegions(windows);
  for (var index = from; index < windows.length; index += 1) {
    final window = windows[index];
    final region = regions[index];
    final meets = window.documentRect.intersect(paper);
    final pixel = 1 / window.surfaceScale;
    if (region == null ||
        meets.width < pixel ||
        meets.height < pixel) {
      continue;
    }
    final corner = window.placement.pixelOf(paper.topLeft);
    final landed = clipStrokeCommitToSelection(
      BrushStrokeCommitData(
        sourceDabs: [
          buildCutPasteDab(
            CutPiece(
              image: image,
              originLeft: corner.dx.round(),
              originTop: corner.dy.round(),
            ),
          ),
        ],
      ),
      region: region,
      surface: ink.sessionStateFor(null, window.key).canvasState.currentSurface,
    );
    if (landed != null) {
      ink.commitStroke(
        plane: null,
        key: window.key,
        strokeData: landed,
        historyManager: history,
        cacheInvalidationSink: cacheInvalidationSink,
      );
    }
  }
  history.gestures.foldSince(start, BrushStrokeHistoryCommand.label);
}

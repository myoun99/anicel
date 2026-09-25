import 'dart:ui' show Rect, Size;

import '../../models/brush_frame_key.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart';
import '../../models/envelope/cut_envelope_layout.dart';
import '../../models/frame_id.dart';
import '../../models/sheet_marks.dart';
import '../../services/brush_frame_store.dart';
import '../../services/history_manager.dart';
import '../sheet/sheet_ink_layer.dart';
import '../sheet/sheet_ink_controller.dart';

/// Owns the envelope's ink: brush strokes on a cut envelope, kept in a
/// store fully SEPARATE from the session's cel [BrushFrameStore] so sheet
/// ink can never leak into cel rendering or export. Strokes commit through
/// the app [HistoryManager] with the same command the drawing canvas uses,
/// so undo behaves identically.
///
/// ONE plane, unlike the timesheet's and conte's pair: an envelope has no
/// page plane because it has no margin — its boxes meet, and every stroke
/// belongs to the box it started in. A box that stops existing takes its
/// ink with it, which is exactly the contract that removes stray
/// annotations from a form the user re-shapes.
class CutEnvelopeInkController extends SheetInkController<Null> {
  CutEnvelopeInkController({BrushFrameStore? store})
    : this._(
        InkPlaneSlot(
          store: store ?? BrushFrameStore(),
          initialFrameKey: const BrushFrameKey(
            projectId: envelopeInkProjectId,
            trackId: envelopeInkTrackId,
            cutId: CutId('envelope-ink-init'),
            layerId: envelopeInkLayerId,
            frameId: FrameId('envelope-ink-init'),
          ),
        ),
      );

  CutEnvelopeInkController._(this._plane) : super({null: _plane});

  final InkPlaneSlot _plane;

  /// One box surface's size, in FORM space at [envelopeInkSurfaceWidth].
  /// Every box in the plane shares one geometry (the coordinator's rule)
  /// and each box's window exposes its own slice; the tile-sparse store
  /// makes the remainder free.
  CanvasSize? get surfaceSize => _plane.size;

  /// Adopts the FORM's geometry — deliberately not the paper's.
  ///
  /// The panel prints on the cut's canvas, the export may print on a real
  /// 봉투, and the next cut's canvas is a different size again; keying the
  /// surface to any of those would shift yesterday's handwriting every time
  /// one changed. The form's aspect ratio is the one thing all of them
  /// share, so that is what the ink is measured in.
  ///
  /// A geometry change (the user picks another preset) rebuilds the ink
  /// session from its durable commands with stroke coordinates preserved
  /// — top-left anchored, like a canvas resize.
  ///
  /// Never notifies: callers run this during build.
  void syncGeometry({required double aspectRatio}) {
    final ratio = aspectRatio <= 0 ? 1.0 : aspectRatio;
    _plane.syncTo(
      CanvasSize(
        width: envelopeInkSurfaceWidth.ceil(),
        height: (envelopeInkSurfaceWidth / ratio).ceil().clamp(1, 1 << 16),
      ),
    );
  }
}

/// The smallest on-screen extent worth an ink window.
const double _minMountedScreenExtent = 24;

/// The windows worth MOUNTING right now.
///
/// The analog preset has 86 inking boxes — eight times a conte page — and
/// every mounted window costs a brush session even though only one can
/// take a stroke at a time. So a window is mounted only when it is both on
/// screen and big enough to draw in, the same gate the timeline uses to
/// hide sparse elements below a zoom tier.
///
/// Zoomed out, that leaves nothing mounted, which is correct: a cell a few
/// pixels across is not one anybody is writing in. Zoomed in, it leaves
/// the handful actually in view.
List<SheetInkWindow> mountedEnvelopeInkWindows(
  List<SheetInkWindow> windows,
  CanvasViewport viewport,
  Size screenSize,
) {
  final screen = Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
  return [
    for (final window in windows)
      if (_mountable(window, viewport, screen, _minMountedScreenExtent))
        window,
  ];
}

bool _mountable(
  SheetInkWindow window,
  CanvasViewport viewport,
  Rect screen,
  double minScreenExtent,
) {
  final rect = window.screenRect(viewport);
  if (rect.width < minScreenExtent || rect.height < minScreenExtent) {
    return false;
  }
  return rect.overlaps(screen);
}

/// The envelope's ink windows, bottom-of-stack first.
///
/// One per box that takes ink, in FORM order — so a box drawn later (an
/// inner cell over the one it sits on) is hit first, matching
/// [CutEnvelopeLayout.inkBoxAt]. There is no page window: the form has no
/// margin, its cells meet, and a stroke that starts outside every inking
/// box simply has nowhere to go.
List<SheetInkWindow> envelopeInkWindows(
  CutEnvelopeLayout layout,
  CutId ownerCutId,
) {
  final surfaceScale = layout.inkSurfaceScale;
  return [
    for (final placed in layout.placedBoxes)
      if (placed.box.takesInk)
        SheetInkWindow(
          id: placed.box.id,
          key: envelopeInkBoxKey(ownerCutId, placed.box.id),
          placement: SheetInkPlacement(
            window: Rect.fromLTWH(
              placed.x,
              placed.y,
              placed.width,
              placed.height,
            ),
            scale: surfaceScale,
          ),
        ),
  ];
}

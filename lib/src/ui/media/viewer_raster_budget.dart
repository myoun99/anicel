import 'dart:ui' as ui;

import '../../models/bitmap_tile.dart' show BitmapTile;
import '../../models/rgba_image_bytes.dart';
import '../../services/brush_frame_store.dart' show deviceScaledHotCelBudget;
import '../../services/memory_pressure_budget.dart';
import 'viewer_render_tier.dart';

/// Bytes one page costs at the tier's ceiling: [viewerMaxRenderPixels] at
/// 4 bytes each — 64MB. Nothing the viewer holds is ever bigger.
const int viewerPageBytesAtCap =
    viewerMaxRenderPixels * BitmapTile.bytesPerPixel;

/// 🚨★★★**THE VIEWER'S CACHE IS BOUNDED IN BYTES, ON THE SAME DEVICE
/// LAW AS THE CANVAS, AND IT HEARS THE MEMORY WARNING.**
///
/// It used to be bounded by a COUNT — four pages — and a count is not a
/// bound: four pages at [viewerMaxRenderPixels] is a quarter of a
/// gigabyte, and four thumbnails is under a megabyte. The same number
/// meant both. So on a 3GB tablet the canvas correctly scaled itself down
/// to 768MB while the viewer beside it went on holding up to 256MB more,
/// deaf to the warning that reached every other cache in the app.
///
/// 유저 2026-08-29: 「캔버스 베이스패널이니까 캔버스패널에서 활용가능한거
/// 그대로 재사용가능한거아닌가? 그렇다고 사본만드는건 절대금지니까
/// 공용화할거 해서 통일한다거나」 — so this reuses the two laws that
/// already exist rather than restating them: [deviceScaledHotCelBudget]
/// decides what this DEVICE affords, and [MemoryPressureBudget] owns the
/// lowers-only rule.
///
/// ⚠️**ONE PER VIEWER, and the app mounts two** (the floor's viewer and
/// the sub viewer beside the drawing), so the viewers together can hold
/// twice the number below. That is deliberate: it is exactly what the old
/// count of four allowed per viewer, and two references open side by side
/// is the workflow this panel exists for. What bounds the pair is the
/// warning — both halve when it arrives, because both are listening.
class ViewerRasterBudget {
  /// Test seam, the same shape as `PdfRenderService.debugOpenerOverride`:
  /// what to pretend ONE page costs. Both the budget and its floor are
  /// expressed in pages, so overriding this scales the whole world down
  /// without disturbing the relationship between them.
  ///
  /// 🚨A test cannot have a device. The smallest budget this app can
  /// legitimately produce is one page at the render cap — 64MB — so a
  /// widget test proving eviction happens AT ALL would have to rasterise
  /// tens of megabytes, in every shard, forever. This buys the same proof
  /// for a few small rects.
  static int? debugPageBytesOverride;

  ViewerRasterBudget({required int? physicalMemoryBytes})
    : _budget = MemoryPressureBudget.halving(
        normal: debugPageBytesOverride == null
            ? viewerRasterBytesFor(physicalMemoryBytes: physicalMemoryBytes)
            : debugPageBytesOverride! * 4,
        // One page, so whatever else pressure takes, the page being
        // LOOKED AT survives. Cutting past the visible page does not save
        // memory, it just re-renders it — the same reason the undo stack
        // always keeps its newest entry.
        //
        // ⚠️On a device already at the floor the budget IS one page, so
        // pressure correctly does nothing: there is nothing left to give.
        floor: debugPageBytesOverride ?? viewerPageBytesAtCap,
      );

  final MemoryPressureBudget _budget;

  int get byteBudget => _budget.bytes;

  bool respondToMemoryPressure() => _budget.respondToMemoryPressure();

  /// What [image] costs resident: 4 bytes a pixel, the same estimate the
  /// cel store's hot tier bills a surface at.
  static int costOf(ui.Image image) =>
      estimatedImageBytes(image.width, image.height);
}

/// The viewer's share of what this device affords, derived from the
/// canvas's own number rather than picked.
///
/// 🚨**THE DIVISOR IS NOT A GUESS — it is fixed by both endpoints.**
/// [deviceScaledHotCelBudget] clamps to [384MB, 1536MB], a span of 4×.
/// Dividing by 6 maps that span onto [1 page, 4 pages] at the render cap:
///
/// • a desktop (1536MB canvas) → 256MB = **4 pages**, which is EXACTLY the
///   worst case the old count bound of four already permitted, so no
///   machine that works today starts evicting;
/// • the device floor (384MB canvas) → 64MB = **1 page**, the least that
///   can be held without re-rendering the page on screen.
///
/// Any other divisor breaks one end or the other.
int viewerRasterBytesFor({required int? physicalMemoryBytes}) =>
    deviceScaledHotCelBudget(physicalMemoryBytes: physicalMemoryBytes) ~/ 6;

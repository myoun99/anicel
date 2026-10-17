import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_asset_drop_target.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_controller.dart';
import 'package:anicel/src/ui/sheet/sheet_photo_drop.dart';
import 'package:anicel/src/ui/sheet/sheet_photos.dart';

/// Drives a sheet's photo entrance ([SheetPhotoDrop]) as the pool's drag
/// reaches it — one helper for the three sheets that have one.

SheetPhotoDrop sheetPhotoEntrance(WidgetTester tester, {Finder? within}) =>
    tester.widget<SheetPhotoDrop>(_entrance(within));

/// The entrance — the one inside [within], where two sheets are up.
Finder _entrance(Finder? within) => within == null
    ? find.byType(SheetPhotoDrop)
    : find.descendant(of: within, matching: find.byType(SheetPhotoDrop));

/// The entrance's drop target — what the dragged file's chip asks.
MediaAssetDropTarget sheetPhotoTarget(WidgetTester tester) =>
    tester.widget<MediaAssetDropTarget>(
      find.descendant(
        of: find.byType(SheetPhotoDrop),
        matching: find.byType(MediaAssetDropTarget),
      ),
    );

/// Where the paper point [paper] of the sheet [within] is on the screen.
Offset sheetPaperOnScreen(
  WidgetTester tester,
  Offset paper, {
  Finder? within,
}) {
  final viewport = sheetPhotoEntrance(tester, within: within).viewport;
  return tester.getTopLeft(_entrance(within)) +
      Offset(
        viewport.panX + viewport.zoom * paper.dx,
        viewport.panY + viewport.zoom * paper.dy,
      );
}

/// A drag in flight never reaches a target as pointer events, so the
/// landing is handed over the way the framework hands it: through the
/// target's accept.
void dropOnSheet(WidgetTester tester, String path, Offset at) =>
    tester
        .widget<DragTarget<MediaAssetDragData>>(
          find
              .descendant(
                of: find.byType(SheetPhotoDrop),
                matching: find.byType(DragTarget<MediaAssetDragData>),
              )
              .first,
        )
        .onAcceptWithDetails!(
      DragTargetDetails<MediaAssetDragData>(
        data: MediaAssetDragData(path: path, name: path),
        offset: at,
      ),
    );

/// The photos [key]'s picture carries on [ink], as the sheet prints it.
List<CelPhoto> sheetPhotosOn(
  SheetInkController<Null> ink,
  BrushFrameKey key,
) => ink.surfaceFor(null, key)?.photos ?? const [];

/// The photos the sheet's live ink windows show now.
List<CelPhoto> sheetPhotosShown(WidgetTester tester) => [
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (paint.painter case final SheetPhotosPainter painter) ...painter.photos,
];

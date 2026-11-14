@Tags(['gc'])
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';

import '../../helpers/a_folder_of_two_inked_rows.dart';
import '../../helpers/collect_garbage.dart';

/// 🚨A HOLE A MEMORY WARNING TOOK IS LET GO OF ONCE THE CANVAS BUILDS AGAIN
/// (card a-lifted-row-painter-holds-a-reclaimed-hole, 2026-11-12).
///
/// A box over a folder shows each row it lifted as that row's cel with its
/// hole (`CanvasPanelLift.liftedRows`), and a memory warning gives the hole
/// back (`BrushFrameStore.holdReclaimableView`): the lift drops it and makes
/// it again the next time it is asked. The canvas keeps a painter for each
/// lifted row (`LiftedRowPainters`), made again only when the row's surface
/// is another — so a painter kept for the same cel whatever its surface
/// would draw the same pixels and hold the hole the warning took, for as
/// long as the box stays open: the warning would free nothing.
///
/// ⛔THE PICTURE CANNOT SAY SO — both draw the same pixels. Only the
/// collector can, so this reads the hole it took through a [WeakReference].
void main() {
  testWidgets('🚨a hole a memory warning took is let go of once the canvas '
      'under the box over a folder builds again', (tester) async {
    final session = await pumpAFolderOfTwoInkedRows(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final commands = tester
        .widget<CanvasSelectionLayer>(find.byType(CanvasSelectionLayer).first)
        .selectionCommands!;
    commands.beginTransform();
    await tester.pumpAndSettle();
    final key = session.brushFrameKeyForCut(
      session.requireActiveCut,
      liftedRowA,
      FrameId('${liftedRowA.value}-0'),
    );
    final taken = _weakly(_liftedSurfaceOf(tester, key));
    expect(
      taken.target,
      isNotNull,
      reason: '⛔premise: the box shows the row lifted, holed',
    );

    tester.binding.handleMemoryPressure();
    // ⚠️A WARNING BUILDS NOTHING: the hole on screen is the canvas panel's
    // until the panel builds again (🧪a box moved or a wheel's zoom builds
    // it not; a window resized does). It is what was on screen.
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    await tester.pumpAndSettle();
    expect(
      (
        _liftedSurfaceOf(tester, key) != null,
        identical(_liftedSurfaceOf(tester, key), taken.target),
      ),
      (true, false),
      reason: '⛔premise: the warning took the hole, and the canvas built '
          'again draws the row from one made again',
    );

    await tester.runAsync(collectGarbage);
    expect(
      taken.target,
      isNull,
      reason: 'nothing holds the hole the warning took',
    );
  });
}

/// [surface] held by nothing but this.
WeakReference<BitmapSurface> _weakly(BitmapSurface? surface) =>
    WeakReference(surface!);

/// [key]'s surface as the canvas's picture shows it lifted, if it does.
BitmapSurface? _liftedSurfaceOf(WidgetTester tester, BrushFrameKey key) =>
    tester
        .widget<FramePictureView>(find.byType(FramePictureView).first)
        .live
        ?.liftedRows[key]
        ?.surface;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/sheet_marks.dart' show SheetInkPlacement;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/sheet/sheet_photo_drop.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/sheet_photo_drops.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// I-97: a pool picture dropped on a sheet lands in the cell under the
/// drop — the cell a stroke started there writes in — as the sheet is when
/// it LANDS. The picture is read for its size first, and a sheet can be
/// laid again meanwhile; the cells are asked again then, as a stroke
/// starting there would ask them, and never kept from an earlier build.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sheet_photo_landing_');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  const cut = CutId('39');

  SheetInkWindow box(String id, Rect rect) => SheetInkWindow(
    id: id,
    key: envelopeInkBoxKey(cut, id),
    placement: SheetInkPlacement(window: rect, scale: 1),
  );

  final outer = box('outer', const Rect.fromLTWH(20, 20, 400, 300));
  final inner = box('inner', const Rect.fromLTWH(200, 150, 80, 60));
  final dropped = inner.documentRect.center;

  /// A 40×10 picture in the pool.
  Future<String> poolPicture(WidgetTester tester) async => normalizedMediaPath(
    (await tester.runAsync(
      () => writeSolidPng(
        tempDir,
        'photo.png',
        width: 40,
        height: 10,
        rgba: 0xFF0000FF,
      ),
    ))!,
  );

  /// A session whose pool holds [png], and an envelope's ink.
  (EditorSessionManager, CutEnvelopeInkController) inkWith(String png) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('landing'),
        name: 'Landing',
        createdAt: DateTime.utc(2026, 10, 15),
        mediaAssets: [
          MediaAsset(path: png, name: 'photo', kind: MediaAssetKind.image),
        ],
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              Cut(
                id: cut,
                name: '39',
                duration: 24,
                canvasSize: const CanvasSize(width: 640, height: 480),
                layers: const [],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    final ink = CutEnvelopeInkController()..syncGeometry(aspectRatio: 4 / 3);
    addTearDown(ink.dispose);
    return (session, ink);
  }

  /// The drop over a sheet whose cells are [windows] — built again with
  /// each call, as a sheet is.
  Future<void> pumpSheet(
    WidgetTester tester, {
    required EditorSessionManager session,
    required CutEnvelopeInkController ink,
    required List<SheetWindow> windows,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 640,
          height: 480,
          child: SheetPhotoDrop(
            session: session,
            ink: ink,
            windows: () => windows,
            viewport: CanvasViewport(),
          ),
        ),
      ),
    ),
  );

  testWidgets('🚨the cells are asked again once the sheet is built again — a '
      'box laid since takes the drop it lies under', (tester) async {
    final png = await poolPicture(tester);
    final (session, ink) = inkWith(png);
    await pumpSheet(tester, session: session, ink: ink, windows: [outer]);
    expect(
      sheetPhotoTarget(tester).accepts!(
        MediaAssetDragData(path: png, name: 'photo'),
        sheetPaperOnScreen(tester, dropped),
      ),
      isTrue,
      reason: 'the CONTROL — asked while only the outer box was there',
    );

    await pumpSheet(
      tester,
      session: session,
      ink: ink,
      windows: [outer, inner],
    );
    dropOnSheet(tester, png, sheetPaperOnScreen(tester, dropped));
    await settleAsync(tester, () => sheetPhotosOn(ink, inner.key).isNotEmpty);

    expect(sheetPhotosOn(ink, inner.key), hasLength(1));
    expect(sheetPhotosOn(ink, outer.key), isEmpty);
  });

  testWidgets('a sheet laid again while the picture is read: the photo lands '
      'in the box under the drop as the sheet is then, standing where it '
      'was dropped on that box', (tester) async {
    final png = await poolPicture(tester);
    final (session, ink) = inkWith(png);
    await pumpSheet(
      tester,
      session: session,
      ink: ink,
      windows: [outer, inner],
    );

    dropOnSheet(tester, png, sheetPaperOnScreen(tester, dropped));
    // The read has not run yet (a widget test's clock does no I/O), and the
    // inner box moves off the point before it does.
    final moved = box('inner', inner.documentRect.shift(const Offset(0, 90)));
    await pumpSheet(
      tester,
      session: session,
      ink: ink,
      windows: [outer, moved],
    );
    await settleAsync(tester, () => sheetPhotosOn(ink, outer.key).isNotEmpty);

    expect(sheetPhotosOn(ink, inner.key), isEmpty);
    final [photo] = sheetPhotosOn(ink, outer.key);
    final at = outer.placement.pixelOf(dropped);
    expect(photo.reference.pose.center.x, closeTo(at.dx, 1e-3));
    expect(photo.reference.pose.center.y, closeTo(at.dy, 1e-3));
  });

  testWidgets('a sheet closed while its picture is read lands nothing', (
    tester,
  ) async {
    final png = await poolPicture(tester);
    final (session, ink) = inkWith(png);
    await pumpSheet(
      tester,
      session: session,
      ink: ink,
      windows: [outer, inner],
    );

    expect(session.historyManager.canUndo, isFalse, reason: '⛔fixture');
    dropOnSheet(tester, png, sheetPaperOnScreen(tester, dropped));
    await tester.pumpWidget(const SizedBox());
    await lendBothClocks(tester, rounds: 10);

    expect(sheetPhotosOn(ink, inner.key), isEmpty);
    expect(session.historyManager.canUndo, isFalse);
  });

  testWidgets('a pool picture whose file cannot be read lands nothing, and '
      'says nothing', (tester) async {
    final gone = normalizedMediaPath('${tempDir.path}/gone.png');
    final (session, ink) = inkWith(gone);
    await pumpSheet(
      tester,
      session: session,
      ink: ink,
      windows: [outer, inner],
    );
    expect(
      sheetPhotoTarget(tester).accepts!(
        MediaAssetDragData(path: gone, name: 'photo'),
        sheetPaperOnScreen(tester, dropped),
      ),
      isTrue,
      reason: 'the CONTROL — the pool says it is a picture',
    );

    expect(session.historyManager.canUndo, isFalse, reason: '⛔fixture');
    dropOnSheet(tester, gone, sheetPaperOnScreen(tester, dropped));
    await lendBothClocks(tester, rounds: 10);

    expect(sheetPhotosOn(ink, inner.key), isEmpty);
    expect(session.historyManager.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });
}

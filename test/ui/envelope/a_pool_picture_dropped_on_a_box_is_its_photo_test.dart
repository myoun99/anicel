import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_form.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import 'package:anicel/src/ui/sheet/sheet_photo_drop.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/sheet_photo_drops.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️유저 I-97 (2026-10-15): a pool picture dropped on a box of the cut's
/// 봉투 is a PHOTO kept in that box's handwriting — 「사진으로 남게(셀의
/// 텍스트처럼)」, at 「원본 크기, 칸보다 크면 칸에 맞게」 — and one undo takes
/// it back.
///
/// ↩️envelope-stamp-Q1 (2026-09-27): 「풀 그림을 칸에 끌어다 놓으면 그 컷의
/// 손글씨로 찍힌다」 — the picture was stamped, contained in the box, into
/// the pixels of its handwriting. I-97 keeps the box it lands in and the
/// one undo; the picture stays itself, as it does on every sheet.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('envelope_photo_');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  Project project(List<MediaAsset> pool) => Project(
    id: const ProjectId('envelope'),
    name: 'Envelope',
    createdAt: DateTime.utc(2026, 9, 27),
    mediaAssets: pool,
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('39'),
            name: '39',
            duration: 24,
            canvasSize: const CanvasSize(width: 640, height: 480),
            layers: [
              Layer(
                id: const LayerId('a'),
                name: 'A',
                kind: LayerKind.animation,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );

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

  /// The panel on [pool], its brush OFF — a drop is no pen mark.
  Future<(EditorSessionManager, CutEnvelopeInkController)> pumpEnvelope(
    WidgetTester tester,
    List<MediaAsset> pool,
  ) async {
    final session = EditorSessionManager(initialProject: project(pool));
    addTearDown(session.dispose);
    final ink = CutEnvelopeInkController();
    addTearDown(ink.dispose);
    final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    addTearDown(tool.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CutEnvelopeTabHost(
            session: session,
            inkController: ink,
            brushToolState: tool,
            onBrushAllowedChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (session, ink);
  }

  List<SheetInkWindow> boxes(WidgetTester tester) => [
    ...sheetPhotoEntrance(tester).windows().whereType<SheetInkWindow>(),
  ];

  /// The largest box no other inking box lies over: the whole drop is its.
  SheetInkWindow openBox(List<SheetInkWindow> windows) {
    SheetInkWindow? best;
    for (var index = 0; index < windows.length; index += 1) {
      final window = windows[index];
      final covered = windows
          .skip(index + 1)
          .any((above) => above.documentRect.overlaps(window.documentRect));
      final area = window.documentRect.width * window.documentRect.height;
      final bestArea = best == null
          ? 0.0
          : best.documentRect.width * best.documentRect.height;
      if (!covered && area > bestArea) {
        best = window;
      }
    }
    return best!;
  }

  testWidgets('a pool picture dropped on a box, the brush off, is that '
      'box\'s photo — at its own pixels, its centre where it was dropped, '
      'no pixel of the handwriting — and one undo takes it back', (
    tester,
  ) async {
    final png = await poolPicture(tester);
    final (session, ink) = await pumpEnvelope(tester, [
      MediaAsset(path: png, name: 'photo', kind: MediaAssetKind.image),
    ]);
    final windows = boxes(tester);
    final box = openBox(windows);
    // Off the box's centre, so the centre the photo takes is the drop's.
    final dropped =
        box.documentRect.topLeft +
        Offset(box.documentRect.width * 0.3, box.documentRect.height * 0.6);
    expect(sheetPhotosOn(ink, box.key), isEmpty);

    dropOnSheet(tester, png, sheetPaperOnScreen(tester, dropped));
    await settleAsync(tester, () => sheetPhotosOn(ink, box.key).isNotEmpty);

    final [photo] = sheetPhotosOn(ink, box.key);
    final reference = photo.reference;
    expect(reference.assetPath, png);
    expect(reference.pictureSize, const CanvasSize(width: 40, height: 10));
    expect((reference.pose.scaleX, reference.pose.scaleY), (1.0, 1.0));
    final at = box.placement.pixelOf(dropped);
    expect(reference.pose.center.x, closeTo(at.dx, 1e-3));
    expect(reference.pose.center.y, closeTo(at.dy, 1e-3));
    expect(
      surfacePixelRgba(
            ink.surfaceFor(null, box.key)!,
            at.dx.floor(),
            at.dy.floor(),
          ) ??
          0,
      0,
      reason: 'a photo, not pixels of the handwriting (I-97 Q1)',
    );
    expect(
      [
        for (final window in windows)
          if (window != box && sheetPhotosOn(ink, window.key).isNotEmpty)
            window.id,
      ],
      isEmpty,
      reason: 'the box it was dropped on, and no other',
    );

    session.historyManager.undo();
    expect(sheetPhotosOn(ink, box.key), isEmpty, reason: 'one undo');
  });

  // The bundled forms' inking boxes only meet; a form with a box inside a
  // box is what a drop over two boxes needs, so it is laid here.
  testWidgets('dropped where a box lies inside another, the photo is the '
      'inner box\'s — the box a stroke started there writes in (H49) — and '
      'beside it, the outer\'s', (tester) async {
    const form = CutEnvelopeForm(
      id: 'nested',
      name: 'nested',
      aspectRatio: 4 / 3,
      boxes: [
        EnvelopeBox(
          id: 'outer',
          rect: EnvelopeRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
        ),
        EnvelopeBox(
          id: 'inner',
          rect: EnvelopeRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
        ),
      ],
    );
    final png = await poolPicture(tester);
    final session = EditorSessionManager(
      initialProject: project([
        MediaAsset(path: png, name: 'photo', kind: MediaAssetKind.image),
      ]),
    );
    addTearDown(session.dispose);
    final ink = CutEnvelopeInkController();
    addTearDown(ink.dispose);
    ink.syncGeometry(aspectRatio: form.aspectRatio);
    final windows = envelopeInkWindows(
      CutEnvelopeLayout.fit(form: form, paperWidth: 640, paperHeight: 480),
      const CutId('39'),
    );
    final [outer, inner] = windows;
    await tester.pumpWidget(
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

    dropOnSheet(
      tester,
      png,
      sheetPaperOnScreen(tester, inner.documentRect.center),
    );
    await settleAsync(tester, () => sheetPhotosOn(ink, inner.key).isNotEmpty);
    expect(sheetPhotosOn(ink, inner.key), hasLength(1));
    expect(sheetPhotosOn(ink, outer.key), isEmpty);

    dropOnSheet(
      tester,
      png,
      sheetPaperOnScreen(
        tester,
        outer.documentRect.topLeft + const Offset(4, 4),
      ),
    );
    await settleAsync(tester, () => sheetPhotosOn(ink, outer.key).isNotEmpty);
    expect(sheetPhotosOn(ink, outer.key), hasLength(1));
    expect(sheetPhotosOn(ink, inner.key), hasLength(1));
  });

  testWidgets('a sound on a box, or a picture where no box takes ink, lands '
      'nothing — and the chip says so; the box a picture would land in is '
      'outlined while it is over it', (tester) async {
    final (_, ink) = await pumpEnvelope(tester, [
      MediaAsset(path: 'C:/sound.wav', name: 'sound'),
      MediaAsset(
        path: 'C:/photo.png',
        name: 'photo',
        kind: MediaAssetKind.image,
      ),
    ]);
    final windows = boxes(tester);
    expect(windows, isNotEmpty, reason: 'fixture: the form has boxes');
    final box = openBox(windows);
    final overBox = sheetPaperOnScreen(tester, box.documentRect.center);
    final offPaper = sheetPaperOnScreen(tester, const Offset(-50, -50));

    // What the dragged file's chip says, before any drop.
    final target = sheetPhotoTarget(tester);
    const sound = MediaAssetDragData(path: 'C:/sound.wav', name: 'sound');
    const picture = MediaAssetDragData(path: 'C:/photo.png', name: 'photo');
    expect(target.accepts!(sound, overBox), isFalse, reason: 'no picture');
    expect(target.accepts!(picture, offPaper), isFalse, reason: 'no box');
    expect(target.accepts!(picture, overBox), isTrue);

    const outlined = ValueKey<String>('sheet-photo-drop-outline');
    SheetDropOutline outline() =>
        tester.widget<CustomPaint>(find.byKey(outlined)).painter!
            as SheetDropOutline;
    expect(outline().cell, isNull);
    target.onHover!(picture, overBox);
    await tester.pump();
    final viewport = sheetPhotoEntrance(tester).viewport;
    expect(
      outline().cell,
      Rect.fromLTWH(
        viewport.panX + viewport.zoom * box.documentRect.left,
        viewport.panY + viewport.zoom * box.documentRect.top,
        viewport.zoom * box.documentRect.width,
        viewport.zoom * box.documentRect.height,
      ),
    );
    target.onLeave!();
    await tester.pump();
    expect(outline().cell, isNull);

    dropOnSheet(tester, 'C:/sound.wav', overBox);
    dropOnSheet(tester, 'C:/photo.png', offPaper);
    await lendBothClocks(tester, rounds: 5);

    expect(
      [
        for (final window in windows)
          if (sheetPhotosOn(ink, window.key).isNotEmpty) window.id,
      ],
      isEmpty,
    );
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/contain_rect.dart';
import 'package:anicel/src/models/canvas_size.dart';
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
import 'package:anicel/src/ui/envelope/envelope_picture_drop.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_asset_drop_target.dart';
import 'package:anicel/src/ui/sheet/sheet_ink_layer.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️유저 답 envelope-stamp-Q1 (2026-09-27): 「풀 그림을 칸에 끌어다 놓으면
/// 그 컷의 손글씨로 찍힌다」 — a 도장 is a picture from the media pool,
/// dropped on a box of the cut's 봉투, stamped into that box's handwriting:
/// contained in the box, its shape kept, one undo to take it back.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('envelope_stamp_');
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

  EnvelopePictureDrop entrance(WidgetTester tester) =>
      tester.widget<EnvelopePictureDrop>(find.byType(EnvelopePictureDrop));

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

  /// Where the paper point [paper] is on the screen.
  Offset onScreen(WidgetTester tester, Offset paper) {
    final viewport = entrance(tester).viewport;
    return tester.getTopLeft(find.byType(EnvelopePictureDrop)) +
        Offset(
          viewport.panX + viewport.zoom * paper.dx,
          viewport.panY + viewport.zoom * paper.dy,
        );
  }

  /// A drag in flight never reaches a target as pointer events, so the
  /// landing is handed over the way the framework hands it: through the
  /// target's accept.
  void drop(WidgetTester tester, String path, Offset at) {
    tester
        .widget<DragTarget<MediaAssetDragData>>(
          find
              .descendant(
                of: find.byType(EnvelopePictureDrop),
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
  }

  /// Lets the picture's decode run until [landed] says so.
  Future<void> settle(WidgetTester tester, bool Function() landed) async {
    for (var tries = 0; tries < 100 && !landed(); tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('a pool picture dropped on a box, the brush off, lands in that '
      'box\'s handwriting — contained, its shape kept — and one undo takes it '
      'back', (tester) async {
    final png = normalizedMediaPath(
      (await tester.runAsync(
        () => writeSolidPng(
          tempDir,
          'stamp.png',
          width: 40,
          height: 10,
          rgba: 0xFF0000FF,
        ),
      ))!,
    );
    final (session, ink) = await pumpEnvelope(tester, [
      MediaAsset(path: png, name: 'stamp', kind: MediaAssetKind.image),
    ]);
    final windows = entrance(tester).windows;
    final box = openBox(windows);
    final aspect = box.documentRect.width / box.documentRect.height;
    expect(
      (aspect / 4 - 1).abs(),
      greaterThan(0.2),
      reason: 'fixture: a box of another shape than the 4:1 picture',
    );
    expect(ink.hasInkFor(null, box.key), isFalse);

    drop(tester, png, onScreen(tester, box.documentRect.center));
    await settle(tester, () => ink.hasInkFor(null, box.key));

    expect(ink.hasInkFor(null, box.key), isTrue);
    expect(
      [
        for (final window in windows)
          if (window != box && ink.hasInkFor(null, window.key)) window.id,
      ],
      isEmpty,
      reason: 'the box it was dropped on, and no other',
    );

    // Where the picture lies in the box, in the box's own surface pixels.
    final shown = containRect(const Size(40, 10), box.documentRect);
    final corner = box.placement.pixelOf(shown.topLeft);
    final far = box.placement.pixelOf(shown.bottomRight);
    final surface = ink.sessionStateFor(null, box.key).canvasState;
    int? at(double x, double y) =>
        surfacePixelRgba(surface.currentSurface, x.floor(), y.floor());
    expect(
      at((corner.dx + far.dx) / 2, (corner.dy + far.dy) / 2),
      0xFF0000FF,
      reason: 'the picture, in the middle of where it is contained',
    );
    final slice = box.surfaceRect;
    final bare = (far.dy - corner.dy) < slice.height - 4
        ? Offset(slice.center.dx, slice.top + 1)
        : Offset(slice.left + 1, slice.center.dy);
    expect(
      at(bare.dx, bare.dy),
      0,
      reason: 'its shape kept: the box is bare beside a picture of '
          'another shape',
    );

    session.historyManager.undo();
    expect(ink.hasInkFor(null, box.key), isFalse, reason: 'one undo');
  });

  // The bundled forms' inking boxes only meet; a form with a box inside a
  // box is what a stamp over two boxes needs, so it is laid here.
  testWidgets('stamped on a box with another box inside it, the picture is '
      'one paper: each box keeps the piece it shows, and one undo takes '
      'both', (tester) async {
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
    final session = EditorSessionManager(initialProject: project(const []));
    addTearDown(session.dispose);
    final ink = CutEnvelopeInkController();
    addTearDown(ink.dispose);
    ink.syncGeometry(aspectRatio: form.aspectRatio);
    final windows = envelopeInkWindows(
      CutEnvelopeLayout.fit(form: form, paperWidth: 640, paperHeight: 480),
      const CutId('39'),
    );
    final [outer, inner] = windows;
    // The outer box's own shape, so the picture fills it.
    final rect = outer.documentRect;
    final png = (await tester.runAsync(
      () => writeSolidPng(
        tempDir,
        'stamp.png',
        width: 200,
        height: (200 * rect.height / rect.width).round(),
        rgba: 0x00FF00FF,
      ),
    ))!;

    final stamped = await tester.runAsync(
      () => stampEnvelopePicture(
        (
          session: session,
          ink: ink,
          windows: windows,
          cacheInvalidationSink: null,
        ),
        target: outer,
        path: png,
      ),
    );

    expect(stamped, isTrue);
    expect(ink.hasInkFor(null, outer.key), isTrue);
    expect(
      ink.hasInkFor(null, inner.key),
      isTrue,
      reason: 'the piece over the inner box is the inner box\'s, as a '
          'stroke\'s is',
    );
    session.historyManager.undo();
    expect(ink.hasInkFor(null, outer.key), isFalse);
    expect(ink.hasInkFor(null, inner.key), isFalse, reason: 'ONE undo');
  });

  testWidgets('a sound on a box, or a picture where no box takes ink, '
      'stamps nothing', (tester) async {
    final (_, ink) = await pumpEnvelope(tester, [
      MediaAsset(path: 'C:/sound.wav', name: 'sound'),
      MediaAsset(
        path: 'C:/stamp.png',
        name: 'stamp',
        kind: MediaAssetKind.image,
      ),
    ]);
    final windows = entrance(tester).windows;
    expect(windows, isNotEmpty, reason: 'fixture: the form has boxes');
    final box = openBox(windows);
    final overBox = onScreen(tester, box.documentRect.center);
    final offPaper = onScreen(tester, const Offset(-50, -50));

    // What the dragged file's chip says, before any drop.
    final target = tester.widget<MediaAssetDropTarget>(
      find.descendant(
        of: find.byType(EnvelopePictureDrop),
        matching: find.byType(MediaAssetDropTarget),
      ),
    );
    const sound = MediaAssetDragData(path: 'C:/sound.wav', name: 'sound');
    const picture = MediaAssetDragData(path: 'C:/stamp.png', name: 'stamp');
    expect(target.accepts!(sound, overBox), isFalse, reason: 'no picture');
    expect(target.accepts!(picture, offPaper), isFalse, reason: 'no box');
    expect(target.accepts!(picture, overBox), isTrue);

    // The box it would land in, outlined while it is over it.
    EnvelopeDropOutline outline() =>
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey<String>('envelope-drop-outline')),
                )
                .painter!
            as EnvelopeDropOutline;
    expect(outline().box, isNull);
    target.onHover!(picture, overBox);
    await tester.pump();
    final viewport = entrance(tester).viewport;
    expect(
      outline().box,
      Rect.fromLTWH(
        viewport.panX + viewport.zoom * box.documentRect.left,
        viewport.panY + viewport.zoom * box.documentRect.top,
        viewport.zoom * box.documentRect.width,
        viewport.zoom * box.documentRect.height,
      ),
    );
    target.onLeave!();
    await tester.pump();
    expect(outline().box, isNull);

    drop(tester, 'C:/sound.wav', overBox);
    drop(tester, 'C:/stamp.png', offPaper);
    for (var tries = 0; tries < 5; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(
      [
        for (final window in windows)
          if (ink.hasInkFor(null, window.key)) window.id,
      ],
      isEmpty,
    );
  });
}

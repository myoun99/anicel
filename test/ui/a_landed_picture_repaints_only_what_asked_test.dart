import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/sheet_paint_layer.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_book_page.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/media/viewer_raster_budget.dart';
import 'package:anicel/src/ui/media/viewer_render_tier.dart';
import 'package:anicel/src/ui/sheet/sheet_image_cache.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

import '../helpers/draw_on_current_frame.dart';
import '../helpers/solid_png_fixture.dart';
import '../helpers/project_scratch_folder.dart';
import '../helpers/poll_until.dart';
import '../helpers/settle_async.dart';
import '../helpers/until_the_brushes_land.dart';

/// A picture that LANDS repaints the painters that asked for it and
/// rebuilds nothing — in the workspace as it is wired, with its own store.
///
/// ↩️The store sat in the storyboard tab's and the conte tab's listenable
/// merge, so every landing rebuilt the whole panel: at I-22's ten-minute
/// zoom every cut on the film lands a picture, and the storyboard's ruler,
/// rows and chrome were rebuilt once for each.
void main() {
  Future<void> open(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey<String>(tab)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    Project? project,
    String? tab,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(initialProject: project ?? createDefaultProject()),
      ),
    );
    await tester.pumpAndSettle();
    if (tab != null) {
      await open(tester, tab);
    }
  }

  /// Every picture the surfaces on screen asked for, landed and painted —
  /// and the brushes, whose landing rebuilds the home page — so what a
  /// landing repaints next is the landing's alone.
  Future<void> settlePictures(
    WidgetTester tester,
    StoryboardThumbnails thumbnails,
  ) async {
    await untilTheBrushesLand(tester);
    expect(
      await settleAsync(tester, () => !thumbnails.pending()),
      isTrue,
      reason: 'the premise: every picture on screen landed',
    );
    await tester.pumpAndSettle();
  }

  /// [cut]'s picture lands as a render lands it — asked at a width no
  /// surface on screen asks for, inside the real clock, and with no frame
  /// drawn after it: what it repaints still needs its paint.
  Future<void> land(
    WidgetTester tester,
    StoryboardThumbnails thumbnails,
    Cut cut,
  ) async {
    final camera = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session
        .camera
        .cameraFrameSize;
    final original = Size(
      camera.width.toDouble(),
      camera.height.toDouble(),
    );
    final width = pictureRenderWidthFor(original.height, original);
    bool landed() =>
        thumbnails.resolve(cut, 0, shownHeight: original.height)?.width ==
        width;
    expect(landed(), isFalse, reason: 'the premise: not held at that width');
    expect(
      await tester.runAsync(() => pollUntil(landed)),
      isTrue,
      reason: 'the premise: the picture landed',
    );
  }

  testWidgets('🚨the storyboard: a landing repaints the blocks of its own '
      'track, never another track\'s, and the panel is not rebuilt '
      '(conte-one-eye-repaints-every-track)', (tester) async {
    final project = _film(tracks: 3, cutsEach: 1);
    await pumpHome(
      tester,
      project: project,
      tab: 'timeline-mode-storyboard-button',
    );
    List<({StoryboardCutBlocksPainter painter, RenderCustomPaint render})>
    blocksOnScreen() => [
      for (final element in find
          .byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter is StoryboardCutBlocksPainter,
          )
          .evaluate())
        if (element.widget case CustomPaint(
          painter: final StoryboardCutBlocksPainter painter,
        ))
          (
            painter: painter,
            render: element.renderObject! as RenderCustomPaint,
          ),
    ];
    final thumbnails = blocksOnScreen().first.painter.thumbnails;
    if (thumbnails == null) {
      fail('the premise: pictures');
    }
    await settlePictures(tester, thumbnails);
    final blocks = blocksOnScreen();
    final host = tester.widget<StoryboardTabHost>(
      find.byType(StoryboardTabHost),
    );
    expect(
      {
        for (final (:painter, render: _) in blocks)
          for (final entry in painter.entries) entry.cut.id,
      },
      containsAll([
        for (final track in project.tracks.take(2)) track.cuts.single.id,
      ]),
      reason: 'the premise: the blocks of two tracks on screen',
    );
    for (final (painter: _, :render) in blocks) {
      expect(render.debugNeedsPaint, isFalse, reason: 'the premise: settled');
    }

    final cut = project.tracks.first.cuts.single;
    await land(tester, thumbnails, cut);
    for (final (:painter, :render) in blocks) {
      final shows = painter.entries.any((entry) => entry.cut.id == cut.id);
      expect(
        render.debugNeedsPaint,
        shows,
        reason: shows
            ? 'the blocks that show it heard it'
            : 'another track\'s blocks heard nothing',
      );
    }
    await tester.pump();

    expect(
      identical(tester.widget(find.byType(StoryboardTabHost)), host),
      isTrue,
      reason: 'nothing rebuilt the panel for a picture',
    );
  });

  testWidgets('the three sheets draw their media from ONE cache, and each '
      'hears what lands in it — the timesheet its photos (I-97)', (
    tester,
  ) async {
    await pumpHome(tester);
    // The sheet ships open in the right dock (R26 #31).
    final timesheet = tester.widget<TimesheetTabHost>(
      find.byType(TimesheetTabHost),
    );
    await open(tester, 'timeline-mode-conte-button');
    final conte = tester.widget<ConteTabHost>(find.byType(ConteTabHost));
    await open(tester, 'timeline-mode-envelope-button');
    final envelope = tester.widget<CutEnvelopeTabHost>(
      find.byType(CutEnvelopeTabHost),
    );
    final cache = conte.imageRepaint;
    if (cache is! SheetImageCache) {
      fail('the premise: the conte hears the workspace\'s image cache');
    }
    expect(conte.imageFor, cache.imageFor);

    for (final (name, imageFor, landed) in [
      ('envelope', envelope.imageFor, envelope.imageRepaint),
      ('timesheet', timesheet.imageFor, timesheet.imageRepaint),
    ]) {
      expect(identical(landed, cache), isTrue, reason: name);
      expect(imageFor, cache.imageFor, reason: name);
    }
  });

  testWidgets('the sheets\' images are the project\'s: read through it, '
      'counted in its census row and halved by its memory warning (I-97)', (
    tester,
  ) async {
    // A 4×4 picture is a page: the share is a few of them — as many as the
    // memory allowance makes of four.
    ViewerRasterBudget.debugPageBytesOverride = 4 * 4 * 4;
    addTearDown(() => ViewerRasterBudget.debugPageBytesOverride = null);
    final dir = Directory.systemTemp.createTempSync('sheet-images');
    deleteAfterSessionEnds(dir);
    await pumpHome(tester, tab: 'timeline-mode-conte-button');
    final conte = tester.widget<ConteTabHost>(find.byType(ConteTabHost));
    final cache = conte.imageRepaint! as SheetImageCache;
    final session = conte.session;

    // Pictures until the cache lets one go: its share is full.
    final full = await tester.runAsync(() async {
      for (var read = 1; read <= 40; read += 1) {
        final path = await writeSolidPng(
          dir,
          'p$read.png',
          width: 4,
          height: 4,
        );
        await pollUntil(() => cache.imageFor(path) != null);
        if (cache.decodedBytes < read * 64) {
          return cache.decodedBytes;
        }
      }
      return null;
    });
    expect(full, isNotNull, reason: 'the premise: the share filled up');
    expect(session.renderCaches.sheetImageBytes, full);

    session.memoryPressureTicks.value += 1;

    expect(cache.decodedBytes, lessThan(full!));
    expect(session.renderCaches.sheetImageBytes, cache.decodedBytes);

    await tester.pumpWidget(const SizedBox());
    expect(
      session.renderCaches.sheetImageBytes,
      0,
      reason: 'the images go with the project off the screen',
    );
  });

  testWidgets('🚨the conte: a landing repaints the pictures of the pages '
      'that print its cut, never another page\'s, and the panel is not '
      'rebuilt (conte-one-eye-repaints-every-track)', (tester) async {
    final project = _film(tracks: 1, cutsEach: 12);
    await pumpHome(tester, project: project, tab: 'timeline-mode-conte-button');
    final thumbnails = tester
        .widget<ConteTabHost>(find.byType(ConteTabHost))
        .thumbnails;
    if (thumbnails == null) {
      fail('the premise: pictures');
    }
    await settlePictures(tester, thumbnails);
    final host = tester.widget<ConteTabHost>(find.byType(ConteTabHost));
    final pages = [
      for (final element in find.byType(ConteBookPage).evaluate())
        (
          cuts: {
            for (final cell in (element.widget as ConteBookPage).page.cells)
              cell.cutId,
          },
          pictures: _pictureStratumUnder(element),
        ),
    ];
    for (final page in pages) {
      expect(
        page.pictures.debugNeedsPaint,
        isFalse,
        reason: 'the premise: settled',
      );
    }
    bool printed(Cut cut) =>
        pages.any((page) => page.cuts.contains(cut.id.value));
    final cuts = project.tracks.single.cuts;
    final onScreen = cuts.firstWhere(printed);
    final offScreen = cuts.lastWhere(
      (cut) => !printed(cut),
      orElse: () => fail('the premise: a cut no page on screen prints'),
    );

    for (final cut in [offScreen, onScreen]) {
      await land(tester, thumbnails, cut);
      for (final page in pages) {
        final prints = page.cuts.contains(cut.id.value);
        expect(
          page.pictures.debugNeedsPaint,
          prints,
          reason: prints
              ? 'the page that prints ${cut.name} heard it'
              : 'a page that does not print ${cut.name} heard nothing',
        );
      }
    }
    await tester.pump();

    expect(
      identical(tester.widget(find.byType(ConteTabHost)), host),
      isTrue,
      reason: 'nothing rebuilt the sheet for a picture',
    );
  });

  testWidgets('🚨a panel\'s picture lands while the hand rests: none under a '
      'pen that is down, and it comes once the pen is up (F-533)', (
    tester,
  ) async {
    await pumpHome(tester, tab: 'timeline-mode-storyboard-button');
    final painter =
        tester
                .widget<CustomPaint>(
                  find
                      .byWidgetPredicate(
                        (widget) =>
                            widget is CustomPaint &&
                            widget.painter is StoryboardCutBlocksPainter,
                      )
                      .first,
                )
                .painter!
            as StoryboardCutBlocksPainter;
    final thumbnails = painter.thumbnails!;
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final camera = session.camera.cameraFrameSize;
    final original = Size(
      camera.width.toDouble(),
      camera.height.toDouble(),
    );
    // A width no block on screen asked for: its picture is rendered anew.
    final shownHeight = original.height;
    final width = pictureRenderWidthFor(shownHeight, original);
    bool landed(Cut cut) =>
        thumbnails.resolve(cut, 0, shownHeight: shownHeight)?.width == width;

    await tester.runAsync(() async {
      // A row with ink: a picture with no row composes nothing to wait for.
      drawOnCurrentFrame(session);
      final cut = session.requireActiveCut;
      session.setBrushInputActive(true);
      // Asked inside the real clock: a render asked on the test's own
      // clock waits behind a timer nothing turns.
      expect(
        landed(cut),
        isFalse,
        reason: 'the premise: not held at that width',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(
        landed(cut),
        isFalse,
        reason: 'a stroke in hand shares the GPU with no panel\'s picture',
      );
      expect(thumbnails.pending(), isTrue, reason: 'it waits, still asked');

      session.setBrushInputActive(false);
      expect(
        await pollUntil(() => landed(cut)),
        isTrue,
        reason: 'the pen up and the edits quiet, the picture is made',
      );
    });
  });
}

/// A film of [tracks] tracks of [cutsEach] cuts, each cut a conte row and a
/// drawing row with a cel exposed over its length.
Project _film({required int tracks, required int cutsEach}) {
  Layer drawn(String id, LayerKind kind) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 24)},
  );
  return Project(
    id: const ProjectId('a-landing-repaints-its-own'),
    name: 'A landing repaints its own',
    createdAt: DateTime.utc(2026, 11, 8),
    tracks: [
      for (var t = 0; t < tracks; t += 1)
        Track(
          id: TrackId('t$t'),
          name: 'T$t',
          cuts: [
            for (var c = 0; c < cutsEach; c += 1)
              Cut(
                id: CutId('t$t-c$c'),
                name: '${t * cutsEach + c + 1}',
                duration: 24,
                canvasSize: const CanvasSize(width: 1280, height: 720),
                camera: CutCamera.empty(),
                layers: [
                  drawn('t$t-c$c-conte', LayerKind.storyboard),
                  drawn('t$t-c$c-a', LayerKind.animation),
                ],
              ),
          ],
        ),
    ],
  );
}

/// The picture stratum of the conte page [page] — what a landed picture
/// repaints.
RenderCustomPaint _pictureStratumUnder(Element page) {
  RenderCustomPaint? found;
  void visit(Element element) {
    if (element.widget case CustomPaint(
      painter: final ContePagePainter painter,
    ) when identical(painter.layers, SheetStratum.picture.layers)) {
      found = element.renderObject! as RenderCustomPaint;
    }
    element.visitChildElements(visit);
  }

  page.visitChildElements(visit);
  return found ?? fail('the premise: the page has a picture stratum');
}

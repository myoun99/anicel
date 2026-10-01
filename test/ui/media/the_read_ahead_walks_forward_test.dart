import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/app_memory_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_raster_budget.dart';

import '../../helpers/fake_pdf_document.dart';

/// 🚨★★★**THE READ-AHEAD WALKS FORWARD, ONE ASK AT A TIME, AND NEVER EATS
/// ITS OWN CUSHION.**
///
/// Two laws of a playing document's pages that nothing pinned until the
/// run and the page cache were lifted out of the viewer for a second
/// surface (import-preview-plays-silent, 2026-09-29) and a mutation pass
/// showed both lines could be deleted in silence:
///
///  - the decoders behind a document are serial, so the read-ahead asks
///    for nothing while anything is still out with them; and
///  - playback only moves forward, so a frame already passed is the first
///    thing the budget lets go — measured the way paging by hand is
///    (`abs()`), a frame five behind tied a frame five ahead, and the
///    buffer evicted its own cushion and asked for it again.
void main() {
  late EditorSessionManager session;
  late MediaViewerSlot slot;

  /// Distinguishes one open from the next — the request is const, and the
  /// budget is read once when the State is built (see the byte-bounded
  /// cache's test for both).
  var opens = 0;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    // Budgets count in frames at factor 1: every budget is its law.
    AppMemory.settings.value = AppMemorySettings(
      allowanceBytes: session.deviceCacheBudgets.total,
    );
    slot = MediaViewerSlot();
    opens = 0;
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    ViewerRasterBudget.debugPageBytesOverride = null;
    AppMemory.settings.value = const AppMemorySettings();
    slot.dispose();
    session.dispose();
  });

  /// Mounts a FRESH viewer on a movie of [frames] frames at 24fps, with
  /// the renders of [held] frames waiting for [FakePdfDocument.releaseRender].
  Future<FakePdfDocument> openMovie(
    WidgetTester tester, {
    required int frames,
    Set<int> held = const {},
  }) async {
    opens += 1;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    slot.request.value = null;
    slot.position.value = 0;

    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(frames, const ui.Size(595, 842)),
      framesPerSecond: 24,
    );
    for (final frame in held) {
      fake.holdRender(frame);
    }
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: slot.position,
            builder: (context, position, _) => MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: slot.position,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    slot.request.value = MediaViewerRequest(
      path: 'C:/work/clip-$opens.pdf',
      kind: MediaAssetKind.pdf,
      name: 'clip',
    );
    // Fixed pumps, not a settle: a held first frame is a future that never
    // lands by itself.
    for (var frame = 0; frame < 4; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      fake.renderRequests,
      isNotEmpty,
      reason: 'fixture: the movie opened and asked for its first frame',
    );
    return fake;
  }

  Future<void> play(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
    );
    await tester.pump();
  }

  /// One tick of a 24fps run, and the frame the tick schedules.
  Future<void> tick(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 42));

  List<int> framesAsked(FakePdfDocument fake) => [
    for (final request in fake.renderRequests) request.$1,
  ];

  testWidgets('🚨one ask with the decoder at a time: the read-ahead waits '
      'behind the frame on screen', (tester) async {
    final fake = await openMovie(tester, frames: 12, held: {0});
    await play(tester);
    for (var ticks = 0; ticks < 5; ticks += 1) {
      await tick(tester);
    }
    expect(
      framesAsked(fake),
      [0],
      reason:
          '🚨frame 0 is still out with the decoder, and the decoder is '
          'serial: a second ask would only queue behind it, holding a '
          'future, and push whatever the view asks next further back',
    );

    fake.releaseRender(0);
    for (var ticks = 0; ticks < 5; ticks += 1) {
      await tick(tester);
    }
    expect(
      framesAsked(fake),
      containsAll(<int>[1, 2]),
      reason: 'and the walk starts the moment it lands — waiting, not dead',
    );
  });

  testWidgets('🚨a straight play-through asks for every frame ONCE — what '
      'the playhead has passed goes first, never what it is about to '
      'need', (tester) async {
    // What one frame costs in this harness, read off the panel's own
    // render rather than written by hand.
    final probe = await openMovie(tester, frames: 2);
    final first = probe.renderRequests.first;
    // Four frames of budget: the frame on screen and a cushion of three.
    // ⚠️At three or fewer the two measures pick the same frame to drop and
    // this cannot tell them apart.
    ViewerRasterBudget.debugPageBytesOverride = first.$2 * first.$3 * 4;

    final fake = await openMovie(tester, frames: 16);
    await play(tester);
    for (var ticks = 0; ticks < 80 && slot.position.value < 15; ticks += 1) {
      await tick(tester);
    }
    expect(
      slot.position.value,
      15,
      reason: 'fixture: the run reached the last frame',
    );

    final seen = <int>{};
    expect(
      [
        for (final frame in framesAsked(fake))
          if (!seen.add(frame)) frame,
      ],
      isEmpty,
      reason:
          '🚨a frame asked for twice is a frame the budget dropped from '
          'AHEAD of the playhead — measured like paging by hand, the frame '
          'just passed tied the cushion and the cushion lost',
    );
  });
}

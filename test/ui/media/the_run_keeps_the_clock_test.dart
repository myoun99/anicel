import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/fake_pdf_document.dart';

/// 🚨★★★**A RUN TURNS ITS PAGES BY THE CLOCK, NOT BY ITS LOOKS**
/// (viewer-plays-by-the-one-playback-law, ④ — 유저 2026-10-08: 「쓸수있는
/// 로직 뷰어패널에서도 법 통일된거 재사용하게」).
///
/// The viewer's run looks at every vsync, as the canvas's does, and a page
/// turns on the first look its time has come on — a clock that got ahead
/// is followed the canvas's way (`playheadWay`). ↩️A `Timer.periodic` of a
/// frame's length turned a page each time it fired, and Dart's timers count
/// whole milliseconds: a 24fps run asked for 41,667µs, got 41ms and played
/// 24.374 frames a second — a ten-second movie over in 9.846s, with its
/// sound running at its own speed beside it (🔬10-11, this machine).
///
/// These are SILENT runs — a document that turns its own pages and carries
/// no sound, so the clock is the run's own span. A movie's pictures follow
/// its sound: `the_whole_transport_waits_test`.
void main() {
  late EditorSessionManager session;
  late MediaViewerSlot slot;
  var opens = 0;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    opens = 0;
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    slot.dispose();
    session.dispose();
  });

  /// A look at 60Hz — what a screen's vsync hands the clock.
  const look = Duration(microseconds: 16667);

  /// A document of [pages] frames at 24fps, small enough that the
  /// read-ahead holds all of it.
  Future<FakePdfDocument> open(WidgetTester tester, {int pages = 30}) async {
    opens += 1;
    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(pages, const ui.Size(64, 36)),
      framesPerSecond: 24,
    );
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
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> press(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-transport-play')),
    );
    await tester.pump();
  }

  Future<void> looks(
    WidgetTester tester,
    int count, {
    Duration each = look,
  }) async {
    for (var i = 0; i < count; i += 1) {
      await tester.pump(each);
    }
  }

  /// Looks that take no time: the clock stands, and the read-ahead comes
  /// in under it — so what is measured after is the clock, not a wait for
  /// a page.
  Future<void> readAhead(WidgetTester tester) =>
      looks(tester, 40, each: Duration.zero);

  testWidgets('🚨24 frames a second is 24 pages a second, looked at 60 times '
      'a second — a page turns when its time comes, not when the clock '
      'looks', (tester) async {
    await open(tester);
    await press(tester);
    await readAhead(tester);
    expect(slot.position.value, 0, reason: 'fixture: no time has passed');

    await looks(tester, 60);

    expect(
      slot.position.value,
      24,
      reason: 'one second in, at 24 — a run that turned a page a look would '
          'be at its end',
    );
  });

  testWidgets('🚨a clock that got ahead is followed to its page — the pages '
      'on the way drop, as the canvas\'s do: time never stretches', (
    tester,
  ) async {
    await open(tester);
    await press(tester);
    await readAhead(tester);

    // A busy frame: the first look is half a second late.
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      slot.position.value,
      12,
      reason: 'half a second in, at 24 — ↩️the run turned a page a look and '
          'showed page 1 here, its picture a page a look behind its clock',
    );
  });

  testWidgets('🚨a clock that got ahead past a page that is not there stands '
      'BEFORE that page — never on a page it has not got', (tester) async {
    final fake = await open(tester);
    fake.holdRender(5);
    await press(tester);
    await readAhead(tester);

    await tester.pump(const Duration(milliseconds: 500));

    expect(
      slot.position.value,
      4,
      reason: 'the way stops at the first page that is not there, on the way '
          'to the twelfth the clock says — the pages before it drop as any '
          'do',
    );
    await looks(tester, 10);
    expect(slot.position.value, 4, reason: 'and it stays parked there');
  });

  testWidgets('🚨a run pressed again plays at once — its clock starts with '
      'it', (tester) async {
    await open(tester);
    await press(tester);
    await readAhead(tester);
    await looks(tester, 20);
    await press(tester);
    final stoppedAt = slot.position.value;
    expect(stoppedAt, 8, reason: 'fixture: a third of a second in');

    await press(tester);
    await looks(tester, 3);

    expect(
      slot.position.value,
      stoppedAt + 1,
      reason: 'a frame\'s time after the press is a page on — a clock that '
          'counted on from the last run would stand the third of a second '
          'that run had played',
    );
  });

  testWidgets('🚨a run that stood for a page goes on at its rate — it does '
      'not race to make up the time it stood', (tester) async {
    final fake = await open(tester);
    fake.holdRender(5);
    await press(tester);
    await looks(tester, 60);
    expect(
      slot.position.value,
      4,
      reason: 'fixture: parked before the page it has not got',
    );

    fake.releaseRender(5);
    for (var i = 0; i < 100 && slot.position.value == 4; i += 1) {
      await tester.pump(look);
    }
    expect(slot.position.value, 5, reason: 'fixture: it went on');

    await looks(tester, 4);

    expect(
      slot.position.value,
      6,
      reason: 'a frame and a half after going on is a page on — a clock that '
          'kept the second it stood would jump to where that second ends',
    );
  });
}

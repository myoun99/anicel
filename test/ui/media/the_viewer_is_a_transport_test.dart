import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/playback/playback_actuation_gate.dart';

import '../../helpers/fake_pdf_document.dart';

/// 🚨★★★**THE MEDIA VIEWER IS ONE OF THE THINGS THE APP CAN BE PLAYING.**
///
/// 유저 2026-09-07 answered `viewer-plays-sound-Q1` with `exclusive`:
/// 「나중에 누른 쪽이 이기고 진 쪽은 정지」 — and the option they chose spelled
/// out both directions, 「뷰어가 소리를 내는 중에 타임라인 재생을 누르면
/// 뷰어가 멈춥니다」.
///
/// Only one of those directions used to exist. The viewer's play button
/// sits under [PlaybackActuationGate], so a canvas run already stopped a
/// viewer press before it landed; the reverse could not happen at all,
/// because the gate held a `CanvasPlaybackController` by its concrete type
/// and the viewer runs its own `Timer`. Registering the viewer as a
/// `PlaybackTransport` is the whole fix — the law and its home are the
/// ones that were already written.
void main() {
  late EditorSessionManager session;
  late MediaViewerSlot slot;
  late int taps;
  var opens = 0;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    taps = 0;
    opens = 0;
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    slot.dispose();
    session.dispose();
  });

  /// The viewer mounted UNDER the real gate, beside a surface that does its
  /// own job — the arrangement the editor itself has.
  Future<FakePdfDocument> openUnderTheGate(
    WidgetTester tester, {
    required int pages,
    required double framesPerSecond,
  }) async {
    opens += 1;
    slot.request.value = null;
    slot.position.value = 0;

    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(pages, const ui.Size(595, 842)),
      framesPerSecond: framesPerSecond,
    );
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackActuationGate(
            transports: session.playbackRig.transports,
            child: Column(
              children: [
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: slot.position,
                    builder: (context, position, _) => MediaViewerTabHost(
                      viewerId: 'media-viewer',
                      session: session,
                      request: slot.request,
                      position: position,
                      onPositionChanged: (next) => slot.position.value = next,
                    ),
                  ),
                ),
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: GestureDetector(
                    key: const ValueKey<String>('elsewhere'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps += 1,
                    child: const ColoredBox(color: Color(0xFF222222)),
                  ),
                ),
              ],
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

  Future<void> pressPlay(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
    );
    await tester.pump();
  }

  testWidgets('a playing viewer IS the app playing — the one question the '
      'gate asks answers yes', (tester) async {
    await openUnderTheGate(tester, pages: 12, framesPerSecond: 24);
    expect(session.playbackRig.transports.value, isFalse);

    await pressPlay(tester);

    expect(
      session.playbackRig.transports.value,
      isTrue,
      reason: '⛔not「the canvas is playing」 — the law is 「재생 중이면」',
    );
  });

  testWidgets('🚨an actuation ELSEWHERE stops the viewer and is consumed — '
      'the direction that did not exist', (tester) async {
    await openUnderTheGate(tester, pages: 12, framesPerSecond: 24);
    await pressPlay(tester);
    final startedAt = slot.position.value;

    await tester.tap(find.byKey(const ValueKey<String>('elsewhere')));
    await tester.pump();

    expect(
      session.playbackRig.transports.value,
      isFalse,
      reason: '「뭘 하든 정지만」 — 진 쪽은 정지',
    );
    expect(taps, 0, reason: '「입력 일 안함」 — the actuation was eaten');

    // And it stays stopped: the clock runs, the playhead does not.
    for (var frame = 0; frame < 6; frame += 1) {
      await tester.pump(const Duration(milliseconds: 42));
    }
    expect(slot.position.value, startedAt);
  });

  testWidgets('the SECOND actuation does its job — 유저 09-08: 「그대로 둠. '
      '그게 직관적임」', (tester) async {
    await openUnderTheGate(tester, pages: 12, framesPerSecond: 24);
    await pressPlay(tester);

    await tester.tap(find.byKey(const ValueKey<String>('elsewhere')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('elsewhere')));
    await tester.pump();

    expect(taps, 1, reason: 'the first was consumed, the second was not');
  });

  testWidgets('a closed viewer leaves the list — a tab that is gone must '
      'not be walked when the rig goes down', (tester) async {
    await openUnderTheGate(tester, pages: 12, framesPerSecond: 24);
    expect(session.playbackRig.transports.registered, hasLength(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(
      session.playbackRig.transports.registered,
      hasLength(1),
      reason: 'the canvas stays; the viewer deregistered on dispose',
    );
  });
}

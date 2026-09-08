import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';

import '../../helpers/fake_pdf_document.dart';

/// 🚨★★★**THE WHOLE TRANSPORT WAITS — SOUND INCLUDED.**
///
/// 유저 2026-08-31 gave this viewer its law: 「유지하지말고 **로드할때까지
/// 멈춰있어야지**」, because a held picture cannot be told apart from a hold
/// the animator DREW. Once a movie plays its soundtrack beside that
/// picture, the law has to reach the sound — the alternative proves it:
/// letting the sound run on while the picture parks means the picture must
/// later CATCH UP by dropping frames, and dropping frames is what the user
/// rejected for this surface in the first place.
///
/// ⚠️This file exists because the bench is BLIND to sound. A widget test
/// never gets an audio device (`audioOutputUnlessTesting`), so every call
/// the panel makes into [ViewerSound] is a no-op and deleting any of them
/// leaves the rest of the suite green. The panel takes an injectable
/// [ViewerSound] for exactly this — the same seam its file picker has.
///
/// 🚨★★★**WHAT IS STILL NOT MEASURED HERE, AND WHY.** The hold-and-resume
/// itself — a movie whose buffer runs dry parking its soundtrack with the
/// picture — needs a document that turns pages AND carries sound. A
/// `FakePdfDocument` turns pages but `mediaKindCanCarrySound` says a PDF
/// has none; a real movie carries sound but `VideoViewerDocument.open`
/// goes through `QaVideoDecoder.instance?.isSupported` and
/// `videoDecodeBackend`, neither of which a test can hand a fake to. So
/// the WHOLE video arm of this viewer is unmeasured, not only its sound.
/// ⛔Do not read the green here as covering it — the missing seam is on
/// the board as its own card.
void main() {
  late EditorSessionManager session;
  late MediaViewerSlot slot;
  late _RecordingSound sound;
  var opens = 0;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    sound = _RecordingSound(session.audioConformStore);
    opens = 0;
  });

  tearDown(() {
    PdfRenderService.debugResetForTests();
    slot.dispose();
    session.dispose();
  });

  /// A movie of [pages] frames at 24fps, held from frame 1 on.
  Future<FakePdfDocument> openMovie(
    WidgetTester tester, {
    int pages = 12,
  }) async {
    opens += 1;
    slot.request.value = null;
    slot.position.value = 0;
    final fake = FakePdfDocument(
      pageSizes: List<ui.Size>.filled(pages, const ui.Size(640, 360)),
      framesPerSecond: 24,
    );
    PdfRenderService.debugOpenerOverride = (path) async => fake;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: slot.position,
            builder: (context, position, _) => MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: position,
              onPositionChanged: (next) => slot.position.value = next,
              sound: sound,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    slot.request.value = MediaViewerRequest(
      // A movie, so `mediaKindCanCarrySound` says it can hold a soundtrack.
      path: 'C:/work/clip-$opens.mp4',
      kind: MediaAssetKind.video,
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

  testWidgets('pressing play starts the soundtrack', (tester) async {
    await openMovie(tester);
    await pressPlay(tester);

    expect(
      sound.played,
      ['C:/work/clip-1.mp4'],
      reason: '🪦the viewer was completely silent until 2026-09-08 — a movie '
          'turned its pages and its soundtrack was never asked for',
    );
  });

  testWidgets('stopping the run stops the sound', (tester) async {
    await openMovie(tester);
    await pressPlay(tester);
    final before = sound.stops;

    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
    );
    await tester.pump();

    expect(
      sound.stops,
      greaterThan(before),
      reason: '🧪this is the line the previous round could only write a note '
          'beside: on the bench a sound left playing is invisible, and this '
          'seam is what makes it visible',
    );
  });
}

/// A [ViewerSound] that records what it was asked to do, and reports that
/// it is carrying — so the panel takes the paths a real device would.
class _RecordingSound extends ViewerSound {
  _RecordingSound(AudioConformStore store) : super(conformStore: store);

  final List<String> played = [];
  int holds = 0;
  int resumes = 0;
  int stops = 0;

  @override
  bool get isCarrying => played.isNotEmpty;

  @override
  bool play(String sourcePath, {double fromSeconds = 0}) {
    played.add(sourcePath);
    return true;
  }

  @override
  void hold() => holds += 1;

  @override
  void resume(double fromSeconds) => resumes += 1;

  @override
  void stop() {
    stops += 1;
    played.clear();
  }

  /// A clock that stands still: the tests here drive the PICTURE, and a
  /// position that ran on its own would decide when the run ends.
  @override
  double? get positionSeconds => 0;

  @override
  bool get ended => false;
}

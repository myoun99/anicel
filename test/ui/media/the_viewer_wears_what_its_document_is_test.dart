import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/recording_viewer_sound.dart';

/// 🗣️F-289 (유저 2026-10-06): 「이 캔버스 베이스패널은 형식에 따라
/// 나누기로하자. 뷰어패널이라도 pdf면 타임시트나 콘티용지패널이랑 같은
/// 알약쓰고, 한장짜리면 그 알약조차 없애고, 동영상같은거면 아래에 재생ui
/// 넣고」 — the viewer wears what its DOCUMENT is:
///
///  * one that runs in time (its pages advance by themselves, or it
///    sounds) stands on the transport;
///  * a book turns its pages on the left;
///  * a single picture has neither.
///
/// And whatever it is, the file's name is written in one place.
void main() {
  late MediaViewerSlot slot;
  EditorSessionManager? session;
  RecordingViewerSound? sound;

  setUp(() => slot = MediaViewerSlot());

  tearDown(() {
    PdfRenderService.debugResetForTests();
    debugVideoDecodeBackend = null;
    slot.dispose();
    session?.dispose();
    session = null;
    sound = null;
  });

  Finder key(String suffix) => find.byKey(ValueKey<String>(suffix));

  const transport = 'canvas-transport';
  const strip = 'canvas-page-strip';

  Future<void> pumpViewer(
    WidgetTester tester, {
    CanvasFloorInsets Function(Widget child)? onFloor,
  }) async {
    final viewer = ValueListenableBuilder<int>(
      valueListenable: slot.position,
      builder: (context, position, _) => MediaViewerTabHost(
        viewerId: 'media-viewer',
        session: session!,
        request: slot.request,
        position: slot.position,
        loudness: slot.loudness,
        sound: sound,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: onFloor == null ? viewer : onFloor(viewer)),
      ),
    );
    await tester.pump();
  }

  /// A document of [pages] pages that turns them itself at
  /// [framesPerSecond], or a book when that is null — the PDF arm with a
  /// fake behind it, which is how the bench reaches either.
  Future<void> openPages(
    WidgetTester tester, {
    required int pages,
    double? framesPerSecond,
    CanvasFloorInsets Function(Widget child)? onFloor,
  }) async {
    session = EditorSessionManager(initialProject: createDefaultProject());
    PdfRenderService.debugOpenerOverride = (_) async => FakePdfDocument(
      pageSizes: List<ui.Size>.filled(pages, const ui.Size(595, 842)),
      framesPerSecond: framesPerSecond,
    );
    await pumpViewer(tester, onFloor: onFloor);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/pages.pdf',
      kind: MediaAssetKind.pdf,
      name: 'pages',
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMovie(WidgetTester tester, {int frames = 12}) async {
    session = EditorSessionManager(initialProject: createDefaultProject());
    sound = RecordingViewerSound(session!.audioConformStore);
    debugVideoDecodeBackend = FakeVideoBackend(frameCount: frames);
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/clip.mp4',
      kind: MediaAssetKind.video,
      name: 'clip',
    );
    await tester.pumpAndSettle();
  }

  const soundSeconds = 4.0;

  Future<void> openSound(WidgetTester tester) async {
    session = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: AudioConformStore(
        resolveConformPath: (_) => null,
        runner: (request) async => ConformResult(
          outcome: ConformOutcome.built,
          peaks: AudioPeaks(
            bucketsPerSecond: 80,
            peaks: Float32List((80 * soundSeconds).round()),
          ),
          samples: Float32List((soundSeconds * 48000).round()),
          channels: 1,
          sampleRate: 48000,
          frames: (soundSeconds * 48000).round(),
        ),
        log: (_) {},
      ),
    );
    sound = RecordingViewerSound(session!.audioConformStore);
    await pumpViewer(tester);
    slot.request.value = const MediaViewerRequest(
      path: 'C:/work/line.wav',
      kind: MediaAssetKind.audio,
      name: 'line',
    );
    await tester.pumpAndSettle();
  }

  TransportBar bar(WidgetTester tester) =>
      tester.widget<TransportBar>(find.byType(TransportBar));

  Future<void> press(WidgetTester tester, String suffix) async {
    await tester.tap(key('media-viewer-transport-$suffix'));
    await tester.pump();
  }

  group('what it wears', () {
    testWidgets('a document that turns its own pages stands on the '
        'transport, and has no page strip', (tester) async {
      await openPages(tester, pages: 12, framesPerSecond: 24);

      expect(key(transport), findsOneWidget);
      expect(key(strip), findsNothing, reason: '↩️it wore the left strip');
      expect(key('media-viewer-previous-page-button'), findsNothing);
      expect(bar(tester).frameCount, 12);
      expect(bar(tester).range, isNull, reason: 'a viewer trims nothing');
    });

    testWidgets('a book turns its pages on the left, and has no transport', (
      tester,
    ) async {
      await openPages(tester, pages: 3);

      expect(key(strip), findsOneWidget);
      expect(key('media-viewer-next-page-button'), findsOneWidget);
      expect(key(transport), findsNothing);
      expect(find.byType(TransportBar), findsNothing);
    });

    testWidgets('a single picture has neither', (tester) async {
      await openPages(tester, pages: 1);

      expect(key(strip), findsNothing);
      expect(key(transport), findsNothing);
    });

    testWidgets('a sound stands on the transport — one page, and it runs', (
      tester,
    ) async {
      await openSound(tester);

      expect(key(transport), findsOneWidget);
      expect(key(strip), findsNothing);
    });

    testWidgets('an empty viewer has neither, and writes no name', (
      tester,
    ) async {
      session = EditorSessionManager(initialProject: createDefaultProject());
      await pumpViewer(tester);

      expect(key(strip), findsNothing);
      expect(key(transport), findsNothing);
      expect(key('canvas-document-name'), findsNothing);
    });
  });

  group('the transport of a document that turns its pages', () {
    testWidgets('reads the page it is on, and steps and seeks turn to one', (
      tester,
    ) async {
      await openPages(tester, pages: 12, framesPerSecond: 24);
      slot.position.value = 4;
      await tester.pump();
      expect(bar(tester).currentFrame, 4);
      expect(find.text('05 / 12'), findsOneWidget);

      await press(tester, 'step-forward');
      expect(slot.position.value, 5);
      await press(tester, 'step-back');
      await press(tester, 'step-back');
      expect(slot.position.value, 3);
      await press(tester, 'last');
      expect(slot.position.value, 11);
      await press(tester, 'first');
      expect(slot.position.value, 0);

      bar(tester).onSeek(7);
      await tester.pump();
      expect(slot.position.value, 7);
    });

    testWidgets('play runs it and a second press stops it', (tester) async {
      await openPages(tester, pages: 12, framesPerSecond: 24);

      await press(tester, 'play');
      expect(bar(tester).playing, isTrue);
      await tester.pump(const Duration(milliseconds: 42));
      await tester.pump(const Duration(milliseconds: 42));
      expect(slot.position.value, greaterThan(0), reason: 'the pages turn');

      await press(tester, 'play');
      expect(bar(tester).playing, isFalse);
    });

    testWidgets('with no sound beside its pages the sound cell stands off', (
      tester,
    ) async {
      await openPages(tester, pages: 12, framesPerSecond: 24);
      expect(bar(tester).sound, isNull);
    });
  });

  group('the transport of a sound', () {
    testWidgets('counts its length in the project\'s frames, and a seek '
        'moves where a press picks it up', (tester) async {
      await openSound(tester);
      final rate = session!.projectSettings.projectFrameRate;
      final frames = bar(tester).frameCount;
      expect(
        frames,
        AudioPeaks(
          bucketsPerSecond: 80,
          peaks: Float32List((80 * soundSeconds).round()),
        ).durationFrames(rate),
        reason: 'the frames the import window counts the same sound in',
      );
      expect(frames, greaterThan(1));

      final half = frames ~/ 2;
      bar(tester).onSeek(half);
      await tester.pump();
      expect(bar(tester).currentFrame, half, reason: 'the pair round-trips');

      await press(tester, 'play');
      expect(sound!.from, hasLength(1));
      expect(
        sound!.from.single,
        moreOrLessEquals(soundSeconds / 2, epsilon: 0.05),
        reason: 'the sound starts where the playhead was put',
      );
      await press(tester, 'play');
    });

    testWidgets('a seek while it runs picks the sound up from there', (
      tester,
    ) async {
      await openSound(tester);
      await press(tester, 'play');
      expect(sound!.from, [0]);

      final frames = bar(tester).frameCount;
      bar(tester).onSeek(frames ~/ 4);
      await tester.pump();

      expect(sound!.from, hasLength(2));
      expect(
        sound!.from.last,
        moreOrLessEquals(soundSeconds / 4, epsilon: 0.05),
      );
      expect(bar(tester).playing, isTrue);
      await press(tester, 'play');
    });
  });

  group('how loud', () {
    FieldSlider volume(WidgetTester tester) => tester.widget<FieldSlider>(
      key('media-viewer-transport-volume'),
    );

    testWidgets('a press plays at the level the bar stands at', (
      tester,
    ) async {
      await openSound(tester);
      expect(volume(tester).value, 1);

      bar(tester).sound!.onLevelSettled(0.4);
      await tester.pump();
      expect(volume(tester).value, 0.4);
      expect(sound!.played, isEmpty, reason: 'nothing going, nothing to arm');

      await press(tester, 'play');
      expect(sound!.gains, [0.4]);
      await press(tester, 'play');
    });

    testWidgets('a sound already going is armed again where it stands — '
        'when the hand lets go, not on every step under it', (tester) async {
      await openSound(tester);
      await press(tester, 'play');
      sound!.at = 1.5;
      await tester.pump(const Duration(milliseconds: 16));
      expect(sound!.gains, [1]);

      bar(tester).sound!.onLevelChanged(0.8);
      await tester.pump();
      bar(tester).sound!.onLevelChanged(0.6);
      await tester.pump();
      expect(sound!.gains, [1], reason: 'the bar is still under the hand');
      expect(volume(tester).value, 0.6, reason: 'and reads where it is');

      bar(tester).sound!.onLevelSettled(0.6);
      await tester.pump();
      expect(sound!.gains, [1, 0.6]);
      expect(sound!.from.last, 1.5, reason: 'from where it stood');
      expect(bar(tester).playing, isTrue);
      await press(tester, 'play');
    });

    testWidgets('the speaker silences it and keeps the level; moving the '
        'bar is asking to hear it', (tester) async {
      await openSound(tester);
      bar(tester).sound!.onLevelSettled(0.5);
      await tester.pump();

      await press(tester, 'mute');
      expect(bar(tester).sound!.muted, isTrue);
      expect(volume(tester).value, 0.5, reason: 'the level stays');
      await press(tester, 'play');
      expect(sound!.gains.last, 0);
      await press(tester, 'play');

      bar(tester).sound!.onLevelSettled(0.7);
      await tester.pump();
      expect(bar(tester).sound!.muted, isFalse);
      await press(tester, 'play');
      expect(sound!.gains.last, 0.7);
      await press(tester, 'play');
    });

    testWidgets('the level is the viewer\'s: it outlives the panel, and a '
        'new file does not reset it', (tester) async {
      await openSound(tester);
      bar(tester).sound!.onLevelSettled(0.3);
      await tester.pump();
      expect(slot.loudness.value, const ViewerLoudness(level: 0.3));

      // The rail group folded away and back: the panel is a new State.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await pumpViewer(tester);
      await tester.pumpAndSettle();
      expect(volume(tester).value, 0.3);

      slot.open(
        const MediaViewerRequest(
          path: 'C:/work/other.wav',
          kind: MediaAssetKind.audio,
          name: 'other',
        ),
      );
      await tester.pumpAndSettle();
      expect(volume(tester).value, 0.3);
    });

    testWidgets('a movie\'s sound hears it too', (tester) async {
      await openMovie(tester);
      bar(tester).sound!.onLevelSettled(0.25);
      await tester.pump();

      await press(tester, 'play');
      expect(sound!.gains, [0.25]);
      await press(tester, 'play');
    });
  });

  group('the file\'s name', () {
    testWidgets('is written whatever the document is — the asset\'s, or the '
        'file\'s own', (tester) async {
      await openPages(tester, pages: 12, framesPerSecond: 24);
      expect(
        find.descendant(
          of: key('canvas-document-name'),
          matching: find.text('pages'),
        ),
        findsOneWidget,
      );

      slot.open(
        const MediaViewerRequest(
          path: 'C:/work/board_03.pdf',
          kind: MediaAssetKind.pdf,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: key('canvas-document-name'),
          matching: find.text('board_03.pdf'),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('the floor\'s viewer keeps its transport clear of the panels '
      'lying on it', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    const cover = EdgeInsets.only(left: 200, right: 150, bottom: 240);
    await openPages(
      tester,
      pages: 12,
      framesPerSecond: 24,
      onFloor: (child) => CanvasFloorInsets(insets: cover, child: child),
    );

    final panel = tester.getRect(key('canvas-editor-panel-shell'));
    final capsule = tester.getRect(key(transport));
    expect(capsule.left, greaterThanOrEqualTo(panel.left + cover.left));
    expect(capsule.right, lessThanOrEqualTo(panel.right - cover.right));
    expect(capsule.bottom, lessThanOrEqualTo(panel.bottom - cover.bottom));
  });
}

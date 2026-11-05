import 'dart:typed_data';
import 'dart:ui' as ui show Paragraph;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/sound_face.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/number_pad_keyboard.dart';

/// 🗣️F-71 (유저 09-11 카드): 「오디오를 뷰어에서 재생시 파형이 진짜 뒤 흰
/// 용지 위에 래스터화시킨거처럼 보이는데, 그게아니라 진짜 미디어
/// 플레이어처럼 해줬으면함」. F-71-Q7 (11-05): 「위 전체 · 아래 확대
/// (다빈치식)」 — 아래 줄 배율은 알약으로, 스크롤바 없음.
void main() {
  /// [seconds] of sound at the conform's 80 buckets a second, two channels.
  AudioPeaks peaksOfSeconds(double seconds) {
    Float32List lane() => Float32List.fromList([
      for (var bucket = 0; bucket < (80 * seconds).round(); bucket += 1)
        if (bucket.isEven) 0.9 else 0.2,
    ]);
    return AudioPeaks.ofChannels(
      bucketsPerSecond: 80,
      lanes: [lane(), lane()],
    );
  }

  group('the face', () {
    // 402 × 202: inside its rim, 400 wide and 200 tall — the upper row the
    // top 84, the lower from 86 (`_wholeShare` of 200, and a rule).
    const faceSize = Size(402, 202);
    const lastFrame = 48;
    const upperPerFrame = 400 / lastFrame;

    Future<List<int>> pumpFace(
      WidgetTester tester, {
      int currentFrame = 24,
      double zoom = 1,
      ({int first, int last})? kept,
      FrameRulerView view = FrameRulerView.frames,
      List<int>? seekingInto,
    }) async {
      final seeks = seekingInto ?? <int>[];
      final rulerView = ValueNotifier(view);
      addTearDown(rulerView.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: faceSize,
              child: SoundFace(
                keyValue: 'face',
                peaks: peaksOfSeconds(2.05),
                frameRate: ProjectFrameRate.fps24,
                frameCount: lastFrame + 1,
                framesPerSecond: 24,
                rulerView: rulerView,
                currentFrame: currentFrame,
                zoom: zoom,
                onSeek: seeks.add,
                kept: kept,
              ),
            ),
          ),
        ),
      );
      return seeks;
    }

    Finder painted() => find.descendant(
      of: find.byKey(const ValueKey<String>('face')),
      matching: find.byType(CustomPaint),
    );

    /// What the face draws, on a canvas that answers its clip as the band
    /// asks it (`WaveformPainter`) — the test's recording canvas cannot.
    _Drawn drawn(WidgetTester tester) {
      final canvas = _Drawn();
      tester
          .widget<CustomPaint>(painted())
          .painter!
          .paint(canvas, tester.getSize(painted()));
      return canvas;
    }

    testWidgets('the upper row spans the frames end to end, as the seek track '
        'does, and stands the playhead\'s line at its frame', (tester) async {
      await pumpFace(tester, currentFrame: 24);

      expect(
        drawn(tester).rects,
        contains(
          _laid(
            Rect.fromLTWH((1 + 24 * upperPerFrame).floorToDouble(), 1, 1, 84),
            AppColors.text,
          ),
        ),
      );
    });

    testWidgets('the lower row stands the playhead at its middle', (
      tester,
    ) async {
      await pumpFace(tester, currentFrame: 30);

      expect(
        drawn(tester).rects,
        contains(
          _laid(const Rect.fromLTWH(201, 86, 1, 115), AppColors.text),
        ),
      );
    });

    testWidgets('its ruler rules the timeline\'s marks: a second, a beat and '
        'a frame, each as tall as its kind', (tester) async {
      await pumpFace(tester, currentFrame: 40);

      double x(int frame) => (1 + frame * upperPerFrame).floorToDouble();
      // The upper row's foot stands 22 under its top. The file's first
      // frame is a second's head too: the 0 is written beside it.
      expect(
        drawn(tester).rects,
        containsAll([
          _laid(Rect.fromLTWH(x(0), 16, 1, 7), AppColors.hairlineStrong),
          _laid(Rect.fromLTWH(x(1), 20, 1, 3), AppColors.hairlineStrong),
          _laid(Rect.fromLTWH(x(6), 18, 1, 5), AppColors.hairlineStrong),
          _laid(Rect.fromLTWH(x(24), 16, 1, 7), AppColors.hairlineStrong),
        ]),
      );
    });

    testWidgets('🎯the playhead writes its place over the ruler, and the '
        'marks its writing touches stand down whole (I-16)', (tester) async {
      // On a second's boundary the playhead's place covers that second's
      // mark — in the upper row and in the lower, which centres on it.
      await pumpFace(tester, currentFrame: 24);
      expect(drawn(tester).paragraphs, 6);

      // Off it, every mark stands: 0 1 2 and the place, in either row.
      await pumpFace(tester, currentFrame: 36);
      expect(drawn(tester).paragraphs, 8);
    });

    testWidgets('the place it writes is the transport\'s, as the timeline\'s '
        'rulers count (F-71-Q1)', (tester) async {
      String place() =>
          (tester.widget<CustomPaint>(painted()).painter as dynamic).place
              as String;

      await pumpFace(tester, currentFrame: 24);
      expect(place(), '25');

      await pumpFace(
        tester,
        currentFrame: 24,
        view: FrameRulerView.secondsPlusFrames,
      );
      expect(place(), '1+1');
    });

    testWidgets('the span IN/OUT keep is washed, edged where they stand', (
      tester,
    ) async {
      await pumpFace(tester, kept: (first: 12, last: 23));

      const from = 1 + 12 * upperPerFrame;
      const to = 1 + 24 * upperPerFrame;
      expect(
        drawn(tester).rects,
        containsAll([
          _laid(const Rect.fromLTRB(from, 24, to, 85), TransportBar.rangeWash),
          _laid(
            Rect.fromLTWH(from.floorToDouble(), 24, 1, 61),
            AppColors.accent,
          ),
          _laid(Rect.fromLTWH(to.floorToDouble(), 24, 1, 61), AppColors.accent),
        ]),
      );
    });

    testWidgets('a press in the upper row goes where the track would take it',
        (tester) async {
      final seeks = await pumpFace(tester, currentFrame: 0);

      await tester.tapAt(const Offset(1 + 300, 40));
      await tester.pump();

      expect(seeks, [(300 / upperPerFrame).round()]);
    });

    testWidgets('🎯a drag in the lower row is measured against the row as it '
        'stood at the press — the row follows the playhead, the hand does not '
        'chase it', (tester) async {
      // At 1 a second is 100 pixels: at 24 frames a second, 25/6 a frame.
      const perFrame = 100 / 24;
      final seeks = await pumpFace(tester, currentFrame: 24);

      final hand = await tester.startGesture(const Offset(201, 150));
      await tester.pump();
      await hand.moveBy(const Offset(5 * perFrame, 0));
      await tester.pump();
      // The face follows its playhead as the host would stand it there.
      await pumpFace(tester, currentFrame: seeks.last, seekingInto: seeks);
      await hand.moveBy(const Offset(5 * perFrame, 0));
      await tester.pump();
      await hand.up();

      expect(
        seeks,
        [24, 29, 34],
        reason: 'ten frames from where it was pressed, each frame asked once',
      );
    });

    testWidgets('the lower row\'s zoom is the one it is handed: twice the '
        'zoom, half the frames under the same reach', (tester) async {
      const perFrame = 100 / 24;
      final seeks = await pumpFace(tester, currentFrame: 24, zoom: 2);

      await tester.tapAt(const Offset(201 + 8 * perFrame, 150));
      await tester.pump();

      expect(seeks, [28]);
    });
  });

  group('the viewer', () {
    late MediaViewerSlot slot;
    late EditorSessionManager session;

    setUp(() => slot = MediaViewerSlot());
    tearDown(() {
      slot.dispose();
      session.dispose();
    });

    Future<void> pumpViewer(
      WidgetTester tester, {
      ValueListenable<BrushToolState>? brushTool,
    }) async {
      session = EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: AudioConformStore(
          resolveConformPath: (_) => null,
          runner: (request) async => ConformResult(
            outcome: ConformOutcome.built,
            peaks: peaksOfSeconds(2),
            samples: Float32List(2 * 48000),
            channels: 1,
            sampleRate: 48000,
            frames: 2 * 48000,
          ),
          log: (_) {},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: slot.position,
              brushTool: brushTool,
            ),
          ),
        ),
      );
      slot.request.value = const MediaViewerRequest(
        path: 'C:/work/line.wav',
        kind: MediaAssetKind.audio,
      );
      await tester.pumpAndSettle();
    }

    const faceKey = ValueKey<String>('media-viewer-face');
    const trackKey = ValueKey<String>('media-viewer-transport-track');

    TransportBar bar(WidgetTester tester) =>
        tester.widget<TransportBar>(find.byType(TransportBar));

    SoundFace face(WidgetTester tester) =>
        tester.widget<SoundFace>(find.byType(SoundFace));

    testWidgets('its upper row\'s ends stand where the seek track\'s do', (
      tester,
    ) async {
      await pumpViewer(tester);

      final shown = tester.getRect(find.byKey(faceKey));
      final track = tester.getRect(find.byKey(trackKey));
      expect(shown.left + 1, closeTo(track.left, 0.01));
      expect(shown.right - 1, closeTo(track.right, 0.01));
    });

    testWidgets('it counts what the transport counts, and a press on it '
        'moves the transport\'s playhead', (tester) async {
      await pumpViewer(tester);
      expect(
        (face(tester).frameCount, face(tester).framesPerSecond),
        (bar(tester).frameCount, bar(tester).framesPerSecond),
      );

      // A quarter of the way along the upper row, inside its rim.
      final shown = tester.getRect(find.byKey(faceKey));
      await tester.tapAt(
        Offset(shown.left + 1 + (shown.width - 2) / 4, shown.top + 30),
      );
      await tester.pumpAndSettle();

      expect(
        bar(tester).currentFrame,
        ((bar(tester).frameCount - 1) / 4).round(),
      );
      expect(face(tester).currentFrame, bar(tester).currentFrame);
    });

    testWidgets('⛔a press on it is its own under a tool that acts on the '
        'page — a control\'s', (tester) async {
      final cut = ValueNotifier(
        BrushToolState.defaults.copyWith(tool: CanvasTool.cut),
      );
      addTearDown(cut.dispose);
      await pumpViewer(tester, brushTool: cut);
      expect(armedCutShape(cut.value), isNotNull, reason: 'the premise');

      final shown = tester.getRect(find.byKey(faceKey));
      await tester.tapAt(Offset(shown.center.dx, shown.top + 30));
      await tester.pumpAndSettle();

      expect(bar(tester).currentFrame, greaterThan(0));
    });

    testWidgets('🎯its lower row is the pill\'s zoom: 1:1 is a second to a '
        'hundred pixels, and the zoom typed is the row\'s', (tester) async {
      await pumpViewer(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('canvas-viewport-reset')),
      );
      await tester.pumpAndSettle();
      expect(face(tester).zoom, closeTo(1, 1e-9));

      // A docked panel's pill has no zoom steps — they are the floor's.
      await tester.tap(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-label-edit')),
      );
      await tester.pumpAndSettle();
      await openThePadsKeyboard(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-input')),
        '250',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(face(tester).zoom, closeTo(2.5, 1e-9));
    });

    testWidgets('⛔no panbars: the face follows its playhead and pans with '
        'nothing', (tester) async {
      await pumpViewer(tester);

      expect(
        find.byKey(const ValueKey<String>('canvas-panbar-vertical')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-panbar-horizontal')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-transport')),
        findsOneWidget,
        reason: 'the transport stands as it did',
      );
    });

    testWidgets('it stands clear of the name plate at the stage\'s foot', (
      tester,
    ) async {
      await pumpViewer(tester);

      final shown = tester.getRect(find.byKey(faceKey));
      final name = tester.getRect(
        find.byKey(const ValueKey<String>('canvas-document-name')),
      );
      expect(shown.bottom, lessThanOrEqualTo(name.top));
    });
  });
}

/// [rect] laid in [color], as [_Drawn] keeps it: a paint holds its colour at
/// single precision, so colours are told apart by their 32 bits.
({Rect rect, int argb}) _laid(Rect rect, Color color) =>
    (rect: rect, argb: color.toARGB32());

/// Every rect laid, with the colour it was laid in, and how many paragraphs
/// were written — on a canvas that answers its clip, which the band reads.
class _Drawn implements Canvas {
  final rects = <({Rect rect, int argb})>[];
  int paragraphs = 0;

  @override
  Rect getLocalClipBounds() => Rect.largest;

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(_laid(rect, paint.color));

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      paragraphs += 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

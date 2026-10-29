import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/audio/sound_cannot_play.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerMarkColor;
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineUnreadableCelPaperColor;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart'
    show SePaperSpan;
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

/// 유저 2026-10-17 (playback-waits-for-its-sound-Q1: 「a + …」, 「이유(형식 ·
/// 파일 없음 · 출력)는 툴팁으로」): the block of a sound that cannot be played
/// says why on its warning line — the line a clipped take already wears —
/// on the timeline's SE row and the storyboard's; and the storyboard paints
/// its block red, as the timeline's cells do (`LayerStack`'s answer,
/// `a_sound_it_cannot_play_is_red_test`).
void main() {
  const seId = LayerId('se');

  /// An SE row whose one block, over frames 0–5, carries `gone.wav` — a
  /// take that clipped, with [clipped].
  Layer row({bool clipped = false}) => Layer(
    id: seId,
    name: 'S1',
    kind: LayerKind.se,
    frames: [Frame(id: const FrameId('f'), duration: 6, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f'), length: 6)},
    audioClips: [
      AudioClip(
        filePath: 'gone.wav',
        frameId: const FrameId('f'),
        clipped: clipped,
      ),
    ],
  );

  SoundCannotPlay? gone(String path) =>
      path == 'gone.wav' ? SoundCannotPlay.missing : null;
  SoundCannotPlay? plays(String path) => null;

  /// What the block's warning line under [key] says — null without one.
  String? says(WidgetTester tester, String key) {
    final line = find.byKey(ValueKey<String>(key));
    if (line.evaluate().isEmpty) {
      return null;
    }
    return tester
        .widget<AppTooltip>(
          find.descendant(of: line, matching: _aTooltip),
        )
        .message;
  }

  /// What a mouse resting on the middle of [block] is told.
  Future<Finder> hoveredWith(
    WidgetTester tester,
    String block,
    String words,
  ) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(ValueKey<String>(block))));
    await tester.pump(const Duration(seconds: 2));
    return find.text(words);
  }

  group('the timeline\'s SE row', () {
    Future<void> pump(
      WidgetTester tester,
      SoundCannotPlay? Function(String) cannotPlay, {
      bool clipped = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelinePanel(
              layers: [row(clipped: clipped)],
              activeLayerId: null,
              frameCursor: ValueNotifier<int>(0),
              playbackFrameCount: 24,
              exposureStateForLayer: (_, _) =>
                  TimelineCellExposureState.uncovered,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onAddLayer: () {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              projectFrameRate: ProjectFrameRate.fps24,
              pixelsPerFrame: 24,
              seClipMarkerTooltip: 'clipped take',
              soundCannotPlay: cannotPlay,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const line = 'timeline-block-warning-se-b0';

    testWidgets('says why the sound cannot be played', (tester) async {
      await pump(tester, gone);
      expect(
        says(tester, line),
        AppText.strings.soundCannotPlay(SoundCannotPlay.missing),
      );
    });

    testWidgets('⛔CONTROL: a sound that plays wears no line', (tester) async {
      await pump(tester, plays);
      expect(says(tester, line), isNull);
    });

    // 🗣️F-495 (유저 2026-10-28): 「블록에 호버하면 툴팁 띄우도록」.
    testWidgets('says it under a hover on the block', (tester) async {
      await pump(tester, gone);
      expect(
        await hoveredWith(
          tester,
          'timeline-se-label-se-0',
          AppText.strings.soundCannotPlay(SoundCannotPlay.missing),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a take that clipped and cannot be played says both, on the '
        'one line', (tester) async {
      await pump(tester, gone, clipped: true);
      expect(
        says(tester, line),
        '${AppText.strings.soundCannotPlay(SoundCannotPlay.missing)}\n'
        'clipped take',
      );
    });
  });

  group('the storyboard\'s SE row', () {
    Future<void> pump(
      WidgetTester tester,
      SoundCannotPlay? Function(String) cannotPlay,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoryboardPanel(
              project: Project(
                id: const ProjectId('p'),
                name: 'P',
                createdAt: DateTime.utc(2026, 10, 23),
                tracks: [
                  Track(
                    id: const TrackId('t'),
                    name: 'Video',
                    seLayers: [row()],
                    cuts: [
                      Cut(
                        id: const CutId('c'),
                        name: 'C',
                        duration: 12,
                        canvasSize: const CanvasSize(width: 64, height: 36),
                        layers: const [],
                      ),
                    ],
                  ),
                ],
              ),
              activeCutId: const CutId('c'),
              pixelsPerFrame: 8,
              projectFrameRate: ProjectFrameRate.fps24,
              soundCannotPlay: cannotPlay,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Color paper(WidgetTester tester) => tester
        .widget<SePaperSpan>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('storyboard-se-paper-se-0')),
            matching: find.byType(SePaperSpan),
          ),
        )
        .paper;

    const line = 'storyboard-se-block-warning-se-b0';

    testWidgets('paints the block red and says why', (tester) async {
      await pump(tester, gone);
      expect(paper(tester), timelineUnreadableCelPaperColor);
      expect(
        says(tester, line),
        AppText.strings.soundCannotPlay(SoundCannotPlay.missing),
      );
    });

    testWidgets('⛔CONTROL: a sound that plays wears its row\'s colour and no '
        'line', (tester) async {
      await pump(tester, plays);
      expect(paper(tester), layerMarkColor(row().mark));
      expect(says(tester, line), isNull);
    });

    testWidgets('says it under a hover on the block', (tester) async {
      await pump(tester, gone);
      expect(
        await hoveredWith(
          tester,
          'storyboard-se-paper-se-0',
          AppText.strings.soundCannotPlay(SoundCannotPlay.missing),
        ),
        findsOneWidget,
      );
    });
  });
}

final _aTooltip = find.byType(AppTooltip);

import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/ui/audio/audio_slide.dart';
import 'package:anicel/src/ui/audio/waveform_painter.dart';
import 'package:anicel/src/ui/dialogs/se_instance_dialog.dart';
import 'package:anicel/src/ui/dialogs/se_offset_strip.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/instance_editor_commands.dart';
import 'package:anicel/src/ui/timeline/timeline_se_row_visual.dart'
    show SePaperSpan;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// A placed sound's start offset is the BLOCK's — edited in the block's
/// own edit window, where the waveform slides as it is dragged.
///
/// 🗣️유저 2026-09-27: 「오디오 배치된거 시작 오프셋 움직이는거 드래그중
/// 라이브로 파형움직이게 가볍게하고, 이거 블록별로 오프셋이 맞지않나?
/// 그래서 블록 편집창에서 하는게 맞을듯」.
void main() {
  const rate = ProjectFrameRate.fps24;
  // Two seconds of waveform: 48 frames at 24 fps.
  final peaks = AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(160));

  group('the slide law', () {
    test('dragging toward the block\'s start plays a LATER part of the '
        'file; the offset stays inside the file', () {
      int slid(int base, double pixels) => slidAudioOffset(
        base: base,
        dragPixels: pixels,
        pixelsPerFrame: 10,
        fileFrames: 48,
      );
      expect(slid(5, -30), 8);
      expect(slid(5, 30), 2);
      expect(slid(5, 200), 0, reason: 'never before the file starts');
      expect(slid(5, -1000), 47, reason: 'never past its last frame');
    });
  });

  group('the strip', () {
    Future<List<int>> pumpStrip(
      WidgetTester tester, {
      int offsetFrames = 2,
      AudioPeaks? withPeaks,
    }) async {
      final heard = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: SeOffsetStrip(
                  offsetFrames: offsetFrames,
                  blockFrames: 12,
                  frameRate: rate,
                  peaks: withPeaks,
                  onChanged: heard.add,
                ),
              ),
            ),
          ),
        ),
      );
      return heard;
    }

    WaveformPainter plays(WidgetTester tester) =>
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey<String>('se-offset-plays')),
                )
                .painter!
            as WaveformPainter;

    testWidgets('🎯the waveform slides WHILE the finger moves, and the window '
        'hears the offset only when it lets go — nothing else is written '
        'on the way', (tester) async {
      final heard = await pumpStrip(tester, withPeaks: peaks);
      // Twelve frames in four fifths of 400px, capped at the timeline's
      // 24px cell: 24px a frame.
      const pixelsPerFrame = 24.0;
      expect(plays(tester).leadingFrames, 2, reason: 'CONTROL');

      final finger = await tester.startGesture(
        tester.getCenter(find.byType(SeOffsetStrip)),
      );
      await finger.moveBy(const Offset(-3 * pixelsPerFrame, 0));
      await tester.pump();

      expect(plays(tester).leadingFrames, 5, reason: 'live, mid-drag');
      expect(find.text('5f'), findsOneWidget);
      expect(heard, isEmpty, reason: 'nothing leaves the strip mid-drag');

      await finger.up();
      await tester.pump();
      expect(heard, [5]);
    });

    testWidgets('a sound whose waveform is not known yet shows its offset '
        'and cannot be dragged', (tester) async {
      final heard = await pumpStrip(tester, offsetFrames: 4);

      await tester.drag(find.byType(SeOffsetStrip), const Offset(-100, 0));
      await tester.pump();

      expect(find.text('4f'), findsOneWidget);
      expect(heard, isEmpty);
    });
  });

  group('the window', () {
    SeInstanceAudioLink link(int token, {int offsetFrames = 0}) => (
      label: 'take-$token.wav',
      token: token,
      offsetFrames: offsetFrames,
      blockFrames: 12,
      frameRate: rate,
      peaks: peaks,
    );

    Future<ValueNotifier<SeInstanceDialogResult?>> open(
      WidgetTester tester,
      List<SeInstanceAudioLink> links,
    ) async {
      final result = ValueNotifier<SeInstanceDialogResult?>(null);
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result.value =
                    await showDialog<SeInstanceDialogResult>(
                      context: context,
                      builder: (_) => SeInstanceDialog(linkedAudio: links),
                    ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return result;
    }

    Future<void> slide(WidgetTester tester, int token, int frames) async {
      final strip = find.byKey(ValueKey<String>('se-offset-strip-$token'));
      final width = tester.getSize(strip).width;
      final pixelsPerFrame = (width * 0.8 / 12).clamp(0, 24).toDouble();
      await tester.drag(strip, Offset(-frames * pixelsPerFrame, 0));
      await tester.pumpAndSettle();
    }

    testWidgets('🎯every linked sound has its offset strip, and OK hands '
        'back the offsets moved — of the sounds that stay', (tester) async {
      final result = await open(tester, [link(0), link(1, offsetFrames: 2)]);

      await slide(tester, 1, 4);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('se-offset-strip-1')),
          matching: find.text('6f'),
        ),
        findsOneWidget,
        reason: 'the strip keeps what it was moved to until OK',
      );
      await slide(tester, 0, 3);
      await tester.tap(find.byKey(const ValueKey<String>('se-unlink-audio-0')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
      );
      await tester.pumpAndSettle();

      expect(result.value?.audioOffsets, {1: 6});
      expect(result.value?.unlinkedAudioTokens, {0});
    });

    testWidgets('Cancel keeps every offset as it was', (tester) async {
      final result = await open(tester, [link(0)]);

      await slide(tester, 0, 3);
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-cancel-button')),
      );
      await tester.pumpAndSettle();

      expect(result.value, isNull);
    });
  });

  group('the host — both doors', () {
    late Directory folder;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('anicel-se-offset');
    });
    tearDown(() => deleteTempQuietly(folder));

    /// A two-second mono take on disk.
    String take(String name) {
      final path = '${folder.path.replaceAll(r'\', '/')}/$name';
      File(path).writeAsBytesSync(
        wav16Bytes(Int16List(96000), sampleRate: 48000, channels: 1),
      );
      return path;
    }

    /// A session standing on a 12-frame S block at frame 0 that carries
    /// [sounds], each conformed so its strip can be dragged.
    Future<EditorSessionManager> standingOnSounds(
      WidgetTester tester,
      List<({String path, int offsetFrames})> sounds, {
      int fps = 24,
    }) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      s.projectSettings.setProjectFps(fps);
      final row = s.activeTrack.seLayers.first.id;
      s.selectLayer(row);
      s.selectFrameIndex(0);
      s.seEntries.createSeEntryAtCurrentFrame(name: '', lengthFrames: 12);
      final entry = s.selectedFrame!;
      s.cutCommandCoordinator.updateLayerAudioClips(
        cutId: s.activeCutId,
        layerId: row,
        audioClips: [
          for (final sound in sounds)
            AudioClip(
              filePath: sound.path,
              frameId: entry.id,
              offsetFrames: sound.offsetFrames,
            ),
        ],
      );
      await tester.runAsync(() async {
        for (final sound in sounds) {
          await s.audioConformStore.ensureFor(sound.path);
        }
      });
      expect(
        s.voiceRecording.audioPeaksForDisplay(sounds.last.path),
        isNotNull,
        reason: 'CONTROL: the strip can be dragged',
      );
      return s;
    }

    Future<BuildContext> contextFrom(WidgetTester tester) async {
      late BuildContext context;
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return context;
    }

    /// Drags the strip of [token] by [frames] toward the block's start, and
    /// answers the block's window as the strip drew it, in frames.
    Future<double> slide(WidgetTester tester, int token, int frames) async {
      final strip = find.byKey(ValueKey<String>('se-offset-strip-$token'));
      final width = tester.getSize(strip).width;
      final pixelsPerFrame = (width * 0.8 / 12).clamp(0, 24).toDouble();
      final window = tester
          .getSize(find.descendant(of: strip, matching: find.byType(SePaperSpan)))
          .width;
      await tester.drag(strip, Offset(-frames * pixelsPerFrame, 0));
      await tester.pumpAndSettle();
      return window / pixelsPerFrame;
    }

    Future<void> pressOk(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('instance-edit-ok-button')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('🚨the STORYBOARD door: the strip starts at the sound\'s own '
        'offset, in its block\'s window — and OK moves the sound it names '
        'even when a sound before it is taken off in the same sitting (the '
        'offsets land before the unlink shifts the indexes)', (tester) async {
      final first = take('first.wav');
      final second = take('second.wav');
      final s = await standingOnSounds(tester, [
        (path: first, offsetFrames: 0),
        (path: second, offsetFrames: 3),
      ]);
      final context = await contextFrom(tester);

      final editing = editSeEntryInstance(
        context,
        s,
        layerId: s.activeTrack.seLayers.first.id,
        globalFrame: 0,
      );
      await tester.pumpAndSettle();
      final window = await slide(tester, 1, 4);
      await tester.tap(find.byKey(const ValueKey<String>('se-unlink-audio-0')));
      await tester.pumpAndSettle();
      await pressOk(tester);
      await editing;

      expect(window, 12, reason: 'the block\'s own twelve frames');
      final clips = s.activeTrack.seLayers.first.audioClips;
      expect(clips.map((clip) => clip.filePath), [second]);
      expect(clips.single.offsetFrames, 7, reason: 'from its own 3, by 4');
    });

    testWidgets('🎯the TIMELINE door: the same strip in the block the '
        'playhead stands in — and the offset stops at the file\'s last frame '
        'at the PROJECT\'s rate', (tester) async {
      final only = take('only.wav');
      final s = await standingOnSounds(tester, [
        (path: only, offsetFrames: 0),
      ], fps: 30);
      final context = await contextFrom(tester);

      final editing = activateCellEditor(
        context,
        s,
        layerId: s.activeTrack.seLayers.first.id,
        frameIndex: 0,
      );
      await tester.pumpAndSettle();
      final window = await slide(tester, 0, 200);
      await pressOk(tester);
      await editing;

      expect(window, 12);
      expect(
        s.activeTrack.seLayers.first.audioClips.single.offsetFrames,
        59,
        reason: 'two seconds at 30 fps, less one',
      );
    });
  });
}

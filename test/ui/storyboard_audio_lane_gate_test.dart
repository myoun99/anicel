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
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/se_audio_lane.dart' show seAudioLanesFor;

/// 🚨C5 (2026-08-17): the storyboard's S-row twirl shows a WAVEFORM (Audio)
/// lane exactly when the TIMELINE's own lane law emits one —
/// [seAudioLanesFor], which answers nothing for an SE row with no sounds
/// imported. The storyboard used to mount the lane off the twirl alone, so
/// an empty S row showed a waveform strip its timeline twin never draws.
const _trackId = TrackId('agate-track');
const _withSoundId = LayerId('agate-se-sound');
const _emptyId = LayerId('agate-se-empty');

Project _project() => Project(
  id: const ProjectId('agate-project'),
  name: 'Audio Lane Gate',
  createdAt: DateTime.utc(2026, 8, 17),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('agate-cut'),
          name: 'Cut',
          duration: 10,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: const LayerId('agate-cel'),
              name: 'A',
              frames: const [],
              timeline: const {},
            ),
          ],
        ),
      ],
      seLayers: [
        // Slot 0 (S1): a sound block WITH an imported clip.
        Layer(
          id: _withSoundId,
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('agate-cel-sound'),
              duration: 4,
              strokes: const [],
            ),
          ],
          timeline: {
            1: const TimelineExposure.drawing(
              FrameId('agate-cel-sound'),
              length: 4,
            ),
          },
          audioClips: const [
            AudioClip(filePath: 'a.wav', frameId: FrameId('agate-cel-sound')),
          ],
        ),
        // Slot 1 (S2): nothing imported.
        Layer(
          id: _emptyId,
          name: 'S2',
          kind: LayerKind.se,
          frames: const [],
          timeline: const {},
        ),
      ],
    ),
  ],
);

Future<void> _openStoryboard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
  );
  await tester.pumpAndSettle();
}

Future<void> _twirl(WidgetTester tester, int slot) async {
  final toggle = find.byKey(
    ValueKey<String>('storyboard-se-lane-toggle-${_trackId.value}-${slot + 1}'),
  );
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

void main() {
  test('THE predicate is the timeline\'s own lane law: no clips, no Audio '
      'lane — with clips, one', () {
    final layers = _project().tracks.single.seLayers;
    expect(seAudioLanesFor(layers[0]), hasLength(1));
    expect(seAudioLanesFor(layers[1]), isEmpty);
  });

  testWidgets('twirling an S row with NO imported audio shows NO waveform '
      'lane — no strip row, no rail label; the Transform group still '
      'twirls open', (tester) async {
    await _openStoryboard(tester);
    // S2 renders top-most (slot 1 sits above slot 0).
    await _twirl(tester, 1);

    expect(
      find.byKey(const ValueKey<String>('storyboard-audio-lane-row-0-2')),
      findsNothing,
      reason: 'no clips, no waveform strip — the timeline\'s own answer',
    );
    expect(
      find.byKey(
        ValueKey<String>('storyboard-lane-label-${_trackId.value}-s2-audio'),
      ),
      findsNothing,
      reason: 'and no Audio label on the rail',
    );
    expect(
      find.byKey(
        ValueKey<String>('storyboard-se-lane-row-0-2-transform-group'),
      ),
      findsOneWidget,
      reason: 'the twirl itself still opens the Transform group',
    );
  });

  testWidgets('twirling the S row WITH audio shows the waveform lane, as '
      'before', (tester) async {
    await _openStoryboard(tester);
    await _twirl(tester, 0);

    expect(
      find.byKey(const ValueKey<String>('storyboard-audio-lane-row-0-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey<String>('storyboard-lane-label-${_trackId.value}-s1-audio'),
      ),
      findsOneWidget,
    );
  });
}

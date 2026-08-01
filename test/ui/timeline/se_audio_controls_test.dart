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
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';

/// ⑨b SE audio UX: the row's mute speaker + the audio lane's AE-style
/// offset value field.

const _seLayerId = LayerId('sea-voice');

Project _project() {
  return Project(
    id: const ProjectId('sea-project'),
    name: 'SEA Project',
    createdAt: DateTime.utc(2026, 7, 10),
    tracks: [
      Track(
        id: const TrackId('sea-track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('sea-cut'),
            name: 'SEA Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: const LayerId('sea-cel'),
                name: 'A',
                frames: const [],
                timeline: const {},
              ),
              Layer(
                id: _seLayerId,
                name: 'S1',
                kind: LayerKind.se,
                frames: [
                  Frame(
                    id: const FrameId('sea-f1'),
                    duration: 3,
                    name: 'Steps',
                    strokes: const [],
                  ),
                ],
                timeline: const {
                  1: TimelineExposure.drawing(FrameId('sea-f1'), length: 3),
                },
                audioClips: const [
                  AudioClip(filePath: 'steps.wav', frameId: FrameId('sea-f1')),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Layer _seLayer(ProjectRepository repository) {
  return repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .firstWhere((layer) => layer.id == _seLayerId);
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required void Function(ProjectRepository repository) onRepositoryCreated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(
        initialProject: _project(),
        onRepositoryCreated: onRepositoryCreated,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _ensureVisibleAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('Layer json round-trips muted (absent = false)', () {
    final layer = Layer(
      id: const LayerId('m'),
      name: 'S1',
      kind: LayerKind.se,
      frames: const [],
      muted: true,
    );
    expect(Layer.fromJson(layer.toJson()).muted, isTrue);

    final json = layer.copyWith(muted: false).toJson();
    expect(json.containsKey('muted'), isFalse);
    expect(Layer.fromJson(json).muted, isFalse);
  });

  test('the offset drag session previews repo-direct and commits ONE undo '
      'on release (R4 live slide)', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);

    Layer seLayer() => _seLayer(session.repository);
    expect(
      session.beginAudioClipOffsetDrag(layerId: _seLayerId, clipIndex: 0),
      isTrue,
    );

    // Live preview: the MODEL carries the dragged offset (waveforms
    // everywhere repaint from it), history untouched.
    session.updateAudioClipOffsetDrag(5);
    expect(seLayer().audioClips.single.offsetFrames, 5);
    expect(session.canUndo, isFalse);

    session.updateAudioClipOffsetDrag(9);
    expect(seLayer().audioClips.single.offsetFrames, 9);

    // Release: ONE undo step back to the untouched clip.
    session.endAudioClipOffsetDrag();
    expect(seLayer().audioClips.single.offsetFrames, 9);
    expect(session.canUndo, isTrue);
    session.undo();
    expect(seLayer().audioClips.single.offsetFrames, 0);

    // Cancel reverts silently.
    session.beginAudioClipOffsetDrag(layerId: _seLayerId, clipIndex: 0);
    session.updateAudioClipOffsetDrag(7);
    expect(seLayer().audioClips.single.offsetFrames, 7);
    session.cancelAudioClipOffsetDrag();
    expect(seLayer().audioClips.single.offsetFrames, 0);
  });

  testWidgets('the SE speaker opens the MIXER in both orientations, and '
      'mute lives inside it (view state, not undoable)', (tester) async {
    // R10 R6: the x-sheet's stood-up header sheds controls when the panel
    // is too short to stack them, and the speaker is on that ladder. This
    // test is about the DOOR being the same in both orientations, so give
    // the dock the height a user working in the sheet would.
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await _ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey<String>('timeline-layer-mute-sea-voice')),
    );
    expect(
      find.byKey(const ValueKey<String>('se-layer-mixer')),
      findsOneWidget,
      reason: 'the speaker is a door now — R10 R3',
    );

    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-mute')));
    await tester.pumpAndSettle();
    expect(_seLayer(repository).muted, isTrue);

    // The cel row carries no speaker — SE rows only.
    expect(
      find.byKey(const ValueKey<String>('timeline-layer-mute-sea-cel')),
      findsNothing,
    );

    // Dismiss: a pointer down anywhere outside closes it (the shared
    // anchored-window rule).
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('se-layer-mixer')), findsNothing);

    // The X-sheet header carries the same door.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    await _ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey<String>('xsheet-layer-mute-sea-voice')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-mute')));
    await tester.pumpAndSettle();
    expect(_seLayer(repository).muted, isFalse);
  });

  testWidgets('the mixer carries solo and the fader beside mute — the four '
      'controls the speaker\'s context menu used to scatter. Solo tints the '
      'RAIL speaker, which the rail memo could not see before', (
    tester,
  ) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);

    final speaker = find.byKey(
      const ValueKey<String>('timeline-layer-mute-sea-voice'),
    );
    Icon speakerIcon() => tester.widget<Icon>(
      find.descendant(of: speaker, matching: find.byType(Icon)),
    );
    expect(speakerIcon().color, isNull, reason: 'not soloed yet');

    await _ensureVisibleAndTap(tester, speaker);
    await tester.tap(find.byKey(const ValueKey<String>('se-mixer-solo')));
    await tester.pumpAndSettle();
    expect(
      speakerIcon().color,
      isNotNull,
      reason: 'solo is SESSION state — the rail row memo must compare it or '
          'the tint never arrives',
    );

    // The fader writes on RELEASE (commit-on-release, like the opacity
    // bars) — a drag left of centre pulls the gain down from unity.
    final gain = find.byKey(const ValueKey<String>('se-mixer-gain'));
    await tester.drag(gain, const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(_seLayer(repository).audioGain, lessThan(1.0));

    // Pan is a BALANCE: it starts centred and moves either way.
    final pan = find.byKey(const ValueKey<String>('se-mixer-pan'));
    await tester.drag(pan, const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(_seLayer(repository).audioPan, lessThan(0.0));
  });

  testWidgets('the audio lane value field types an offset trim and scrubs '
      'AE-style (one undo)', (tester) async {
    late ProjectRepository repository;
    await _pumpHome(tester, onRepositoryCreated: (repo) => repository = repo);

    // Twirl the SE row down; the audio lane label carries the value cell.
    await _ensureVisibleAndTap(
      tester,
      find.byKey(const ValueKey<String>('timeline-lane-toggle-sea-voice')),
    );
    final valueCell = find.byKey(
      const ValueKey<String>('timeline-lane-value-sea-voice-se-audio'),
    );
    await tester.ensureVisible(valueCell);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.descendant(of: valueCell, matching: find.byType(Text)),
          )
          .data,
      '0f',
    );

    // Tap to type: Enter commits through session.setAudioClipOffset.
    await tester.tap(valueCell);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('timeline-lane-value-field-sea-voice-se-audio'),
      ),
      '7f',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_seLayer(repository).audioClips.single.offsetFrames, 7);

    // ONE undo restores the untouched trim.
    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pumpAndSettle();
    expect(_seLayer(repository).audioClips.single.offsetFrames, 0);

    // A drag on the value scrubs it: 4px per frame, rightward = deeper.
    await tester.ensureVisible(valueCell);
    await tester.pumpAndSettle();
    await tester.drag(valueCell, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(_seLayer(repository).audioClips.single.offsetFrames, 10);
  });
}

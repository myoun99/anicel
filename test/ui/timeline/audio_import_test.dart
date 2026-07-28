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
import 'package:anicel/src/models/timeline_coverage.dart'
    show drawingBlocks;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

import '../flyout_test_helpers.dart';

const _importKey = ValueKey<String>('import-audio-button');
const _seLayerId = LayerId('audio-se');
const _celLayerId = LayerId('audio-cel');

EditorSessionManager _session() {
  return EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('audio-project'),
      name: 'Audio Project',
      createdAt: DateTime.utc(2026, 7, 8),
      tracks: [
        Track(
          id: const TrackId('audio-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('audio-cut'),
              name: 'Audio Cut',
              duration: 12,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(
                  id: _celLayerId,
                  name: 'A',
                  frames: const [],
                  timeline: const {},
                ),
                Layer(
                  id: _seLayerId,
                  name: 'S1',
                  kind: LayerKind.se,
                  frames: const [],
                  timeline: const {},
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

Future<void> _pumpHost(
  WidgetTester tester,
  EditorSessionManager session, {
  Future<String?> Function()? audioFilePicker,
}) async {
  // The test owns the session (HomePage normally does) — dispose it so
  // playback/prerender machinery cancels its timers before teardown.
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: session,
          builder: (context, _) => TimelineTabHost(
            session: session,
            orientation: TimelineOrientation.horizontal,
            onOrientationChanged: (_) {},
            pixelsPerFrame: 48,
            onPixelsPerFrameChanged: (_) {},
            showSeconds: false,
            onShowSecondsChanged: (_) {},
            audioFilePicker: audioFilePicker,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Menu-aware (R-toolbar round): import audio lives in the Layer ▾ flyout.
Future<bool> _importEnabled(WidgetTester tester) =>
    readCommandEnabled(tester, _importKey);

Future<void> _tapImport(WidgetTester tester) =>
    tapCommandButton(tester, _importKey);

void main() {
  testWidgets('import audio is SE-only and places the clip at the playhead '
      'with one undo', (tester) async {
    final session = _session();
    var picks = 0;
    await _pumpHost(
      tester,
      session,
      audioFilePicker: () async {
        picks += 1;
        return r'C:\sound\voice.wav';
      },
    );

    // Animation layer active: disabled.
    session.selectLayer(_celLayerId);
    await tester.pumpAndSettle();
    expect(await _importEnabled(tester), isFalse);

    // SE layer at frame 4: imports at the playhead.
    session.selectLayer(_seLayerId);
    session.selectFrameIndex(4);
    await tester.pumpAndSettle();
    expect(await _importEnabled(tester), isTrue);

    await _tapImport(tester);

    expect(picks, 1);
    Layer seLayer() =>
        session.layers.firstWhere((layer) => layer.id == _seLayerId);
    expect(seLayer().audioClips.single.filePath, r'C:\sound\voice.wav');
    // The pool learned the imported file (browse/reuse surface).
    expect(session.mediaAssets.single.path, r'C:\sound\voice.wav');
    expect(session.mediaAssets.single.name, 'voice.wav');
    // Frame-linked: importing onto the empty cell created an SE instance
    // at the playhead and linked the sound to ITS frame — the block is the
    // sound's window.
    final carrierBlock = drawingBlocks(seLayer().timeline).single;
    expect(carrierBlock.startIndex, 4);
    expect(seLayer().audioClips.single.frameId, carrierBlock.frameId);

    session.undo();
    await tester.pumpAndSettle();
    expect(seLayer().audioClips, isEmpty);

    // Removal API round-trip.
    session.redo();
    session.removeAudioClipAt(_seLayerId, 0);
    expect(seLayer().audioClips, isEmpty);
    // Flush the prerender scheduler's zero-delay yields before teardown.
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    final session = _session();
    await _pumpHost(tester, session, audioFilePicker: () async => null);

    session.selectLayer(_seLayerId);
    await tester.pumpAndSettle();
    await _tapImport(tester);

    expect(
      session.layers.firstWhere((layer) => layer.id == _seLayerId).audioClips,
      isEmpty,
    );
  });

  testWidgets('media pool flows: import-to-browse, link-to-block reuse, '
      'rename, relink, remove guard', (tester) async {
    const foot = r'C:\snd\foot.wav';
    const moved = r'C:\snd\moved\foot.wav';
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('pool-project'),
        name: 'Pool Project',
        createdAt: DateTime.utc(2026, 7, 9),
        tracks: [
          Track(
            id: const TrackId('pool-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('pool-cut'),
                name: 'Pool Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: _seLayerId,
                    name: 'S1',
                    kind: LayerKind.se,
                    frames: [
                      Frame(
                        id: const FrameId('se-f1'),
                        duration: 1,
                        strokes: const [],
                      ),
                      Frame(
                        id: const FrameId('se-f2'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: {
                      0: const TimelineExposure.drawing(
                        FrameId('se-f1'),
                        length: 4,
                      ),
                      6: const TimelineExposure.drawing(
                        FrameId('se-f2'),
                        length: 3,
                      ),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    await _pumpHost(tester, session);

    Layer seLayer() =>
        session.layers.firstWhere((layer) => layer.id == _seLayerId);

    // Import to browse: the pool holds the file, nothing is linked yet;
    // re-adding a known path is a no-op.
    session.addMediaAssets([foot]);
    session.addMediaAssets([foot]);
    expect(session.mediaAssets.single.name, 'foot.wav');
    expect(seLayer().audioClips, isEmpty);
    expect(session.isMediaAssetReferenced(foot), isFalse);

    // Drag-to-block linking: the same sound lands on both blocks
    // (footsteps reuse); re-dropping on a carrying block is a no-op.
    session.linkMediaAssetToSeBlock(
      layerId: _seLayerId,
      blockStartFrame: 0,
      path: foot,
    );
    session.linkMediaAssetToSeBlock(
      layerId: _seLayerId,
      blockStartFrame: 0,
      path: foot,
    );
    session.linkMediaAssetToSeBlock(
      layerId: _seLayerId,
      blockStartFrame: 6,
      path: foot,
    );
    expect(seLayer().audioClips, hasLength(2));
    expect(seLayer().audioClips[0].frameId, const FrameId('se-f1'));
    expect(seLayer().audioClips[1].frameId, const FrameId('se-f2'));
    expect(session.isMediaAssetReferenced(foot), isTrue);

    // Dropping on empty runway does nothing (no block, no carrier).
    session.linkMediaAssetToSeBlock(
      layerId: _seLayerId,
      blockStartFrame: 4,
      path: foot,
    );
    expect(seLayer().audioClips, hasLength(2));

    // Rename survives a relink; the relink rewrites every clip.
    session.renameMediaAsset(foot, '발소리');
    session.relinkMediaAsset(foot, moved);
    expect(session.mediaAssets.single.path, moved);
    expect(session.mediaAssets.single.name, '발소리');
    expect(
      seLayer().audioClips.map((clip) => clip.filePath),
      everyElement(moved),
    );

    // Remove refuses while referenced, succeeds once the clips are gone,
    // and undoes back into the pool.
    expect(session.removeMediaAsset(moved), isFalse);
    session.removeAudioClipAt(_seLayerId, 1);
    session.removeAudioClipAt(_seLayerId, 0);
    expect(session.removeMediaAsset(moved), isTrue);
    expect(session.mediaAssets, isEmpty);
    session.undo();
    expect(session.mediaAssets.single.name, '발소리');
    await tester.pumpAndSettle();
  });

  testWidgets('dragging a media asset onto an SE block links the sound to '
      'that block', (tester) async {
    const foot = r'C:\snd\foot.wav';
    const dragSourceKey = ValueKey<String>('test-media-drag-source');
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('drop-project'),
        name: 'Drop Project',
        createdAt: DateTime.utc(2026, 7, 9),
        tracks: [
          Track(
            id: const TrackId('drop-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('drop-cut'),
                name: 'Drop Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: _seLayerId,
                    name: 'S1',
                    kind: LayerKind.se,
                    frames: [
                      Frame(
                        id: const FrameId('drop-f1'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: {
                      2: const TimelineExposure.drawing(
                        FrameId('drop-f1'),
                        length: 4,
                      ),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // Stand-in for the media browser's draggable row (the browser
              // panel lives in the workspace; the payload contract is what
              // this test pins).
              SizedBox(
                height: 40,
                child: Draggable<MediaAssetDragData>(
                  data: const MediaAssetDragData(path: foot, name: 'foot.wav'),
                  feedback: const SizedBox(width: 8, height: 8),
                  child: Container(
                    key: dragSourceKey,
                    width: 40,
                    height: 40,
                    color: const Color(0xFF888888),
                  ),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: session,
                  builder: (context, _) => TimelineTabHost(
                    session: session,
                    orientation: TimelineOrientation.horizontal,
                    onOrientationChanged: (_) {},
                    pixelsPerFrame: 48,
                    onPixelsPerFrameChanged: (_) {},
                    showSeconds: false,
                    onShowSecondsChanged: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropTarget = find.byKey(
      const ValueKey<String>('timeline-se-asset-drop-audio-se-2'),
    );
    expect(dropTarget, findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(dragSourceKey)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(dropTarget));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    Layer seLayer() =>
        session.layers.firstWhere((layer) => layer.id == _seLayerId);
    expect(seLayer().audioClips.single.filePath, foot);
    expect(seLayer().audioClips.single.frameId, const FrameId('drop-f1'));
    // The drop registered the sound in the pool too.
    expect(session.mediaAssets.single.path, foot);

    // The audio lane's slide edit: one undo step, clamped non-negative.
    session.setAudioClipOffset(_seLayerId, 0, 6);
    expect(seLayer().audioClips.single.offsetFrames, 6);
    session.setAudioClipOffset(_seLayerId, 0, -4); // clamps back to 0
    expect(seLayer().audioClips.single.offsetFrames, 0);
    session.undo();
    expect(seLayer().audioClips.single.offsetFrames, 6);
    await tester.pumpAndSettle();
  });

  testWidgets('REC1-A: deleting the carrier block prunes the audio link '
      'and frees the media asset', (tester) async {
    const foot = r'C:\snd\foot.wav';
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('prune-project'),
        name: 'Prune Project',
        createdAt: DateTime.utc(2026, 7, 22),
        tracks: [
          Track(
            id: const TrackId('prune-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('prune-cut'),
                name: 'Prune Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: _seLayerId,
                    name: 'S1',
                    kind: LayerKind.se,
                    frames: [
                      Frame(
                        id: const FrameId('prune-f1'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: {
                      0: const TimelineExposure.drawing(
                        FrameId('prune-f1'),
                        length: 3,
                      ),
                    },
                    audioClips: const [
                      AudioClip(
                        filePath: foot,
                        frameId: FrameId('prune-f1'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    await _pumpHost(tester, session);
    session.addMediaAssets([foot]);
    expect(session.isMediaAssetReferenced(foot), isTrue);
    expect(session.removeMediaAsset(foot), isFalse);

    Layer seLayer() =>
        session.layers.firstWhere((layer) => layer.id == _seLayerId);
    session.selectLayer(_seLayerId);
    session.selectFrameIndex(0);
    session.deleteCellAtCurrentFrame();
    await tester.pumpAndSettle();

    // The frame is gone AND the link went with it — the sound has no
    // carrier anywhere, so the pool releases the asset.
    expect(seLayer().audioClips, isEmpty);
    expect(session.isMediaAssetReferenced(foot), isFalse);
    expect(session.removeMediaAsset(foot), isTrue);
    expect(session.mediaAssets, isEmpty);

    // Undo is symmetric: the pool returns, then the block AND its link.
    session.undo();
    expect(session.mediaAssets.single.path, foot);
    session.undo();
    expect(seLayer().audioClips.single.frameId, const FrameId('prune-f1'));
    expect(session.isMediaAssetReferenced(foot), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('REC1-A: a dangling audio link (frame already gone) does not '
      'hold the media pool hostage', (tester) async {
    const foot = r'C:\snd\foot.wav';
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('dangle-project'),
        name: 'Dangle Project',
        createdAt: DateTime.utc(2026, 7, 22),
        tracks: [
          Track(
            id: const TrackId('dangle-track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('dangle-cut'),
                name: 'Dangle Cut',
                duration: 12,
                canvasSize: const CanvasSize(width: 640, height: 360),
                layers: [
                  Layer(
                    id: _seLayerId,
                    name: 'S1',
                    kind: LayerKind.se,
                    frames: const [],
                    timeline: const {},
                    audioClips: const [
                      AudioClip(filePath: foot, frameId: FrameId('gone')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    await _pumpHost(tester, session);
    session.addMediaAssets([foot]);
    // The dangling link is inaudible everywhere — it must not count as a
    // reference, and removal must succeed.
    expect(session.isMediaAssetReferenced(foot), isFalse);
    expect(session.removeMediaAsset(foot), isTrue);
    expect(session.mediaAssets, isEmpty);
    await tester.pumpAndSettle();
  });
}

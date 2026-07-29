import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show PropertyLaneEditCallbacks;
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_policy.dart'
    show TimelineCommaDragCallbacks;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/storyboard_cut_fade_policy.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

/// One second at half amplitude → 24 frames at 24 fps.
final _peaks = AudioPeaks(
  bucketsPerSecond: 80,
  peaks: Float32List.fromList(List.filled(80, 0.5)),
);

Layer _seLayer() => Layer(
  id: const LayerId('lane-se'),
  name: 'S1',
  kind: LayerKind.se,
  frames: [Frame(id: const FrameId('lane-f'), duration: 8, strokes: const [])],
  timeline: {0: const TimelineExposure.drawing(FrameId('lane-f'), length: 8)},
  audioClips: const [
    AudioClip(filePath: 'voice.wav', frameId: FrameId('lane-f')),
  ],
);

Project _project({
  Cut Function(Cut cut)? mapCut,
  List<Layer>? seLayers,
  TransformTrack? transformTrack,
}) {
  var cut = Cut(
    id: const CutId('lane-cut'),
    name: 'Lane Cut',
    duration: 10,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: const [],
  );
  if (mapCut != null) {
    cut = mapCut(cut);
  }
  return Project(
    id: const ProjectId('lane-project'),
    name: 'Lanes',
    createdAt: DateTime.utc(2026, 7, 10),
    tracks: [
      Track(
        id: const TrackId('lane-track'),
        name: 'Video',
        cuts: [cut],
        // SE rows are TRACK-owned (global frame axis).
        seLayers: seLayers ?? [_seLayer()],
        // The V effects too (R4): lanes keyed on the track's global axis.
        transformTrack: transformTrack,
      ),
    ],
  );
}

/// Pumps the panel with host-style toggle wiring (view-state sets live in
/// the harness, like StoryboardTabHost).
Future<void> _pumpPanel(
  WidgetTester tester, {
  required Project project,
  CutId? activeCutId = const CutId('lane-cut'),
  void Function(CutId cutId, int fadeInFrames, int fadeOutFrames)? onSetCutFade,
  ValueChanged<LayerId>? onToggleLayerVisibility,
  ValueChanged<LayerId>? onToggleLayerMuted,
  void Function(LayerId layerId, double opacity)? onLayerOpacityChanged,
  StoryboardRowFramePress? onRowFramePress,
  TimelineCommaDragCallbacks? seCommaDrag,
  void Function(LayerId layerId, int clipIndex, int offsetFrames)?
  onSetAudioClipOffset,
  PropertyLaneEditCallbacks? Function(Track track)? trackLaneEditFor,
  PropertyLaneEditCallbacks? layerLaneEdit,
  bool Function(CutId cutId)? cutFxEnabledOf,
  ValueChanged<CutId>? onToggleCutFx,
  bool Function(CutId cutId)? cutPictureVisibleOf,
  ValueChanged<CutId>? onToggleCutPictureVisibility,
}) async {
  final expandedAudio = <String>{};
  final expandedTransform = <String>{};
  final expandedGroups = <String>{};
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => StoryboardPanel(
            project: project,
            activeCutId: activeCutId,
            onRowFramePress: onRowFramePress,
            pixelsPerFrame: 12,
            projectFrameRate: const ProjectFrameRate.integer(24),
            audioPeaksFor: (path) => path == 'voice.wav' ? _peaks : null,
            expandedSeAudioRows: expandedAudio,
            onToggleSeRowLane: (track, slot) => setState(() {
              final key = StoryboardPanel.seRowKey(track, slot);
              if (!expandedAudio.add(key)) {
                expandedAudio.remove(key);
              }
            }),
            expandedTransformTracks: expandedTransform,
            onToggleTrackLane: (track) => setState(() {
              if (!expandedTransform.add(track.id.value)) {
                expandedTransform.remove(track.id.value);
              }
            }),
            expandedTransformGroups: expandedGroups,
            onToggleTransformGroup: (groupKey) => setState(() {
              if (!expandedGroups.add(groupKey)) {
                expandedGroups.remove(groupKey);
              }
            }),
            trackLaneEditFor: trackLaneEditFor,
            layerLaneEdit: layerLaneEdit,
            poseDisplaySize: const CanvasSize(width: 640, height: 360),
            onSetCutFade: onSetCutFade,
            onToggleLayerVisibility: onToggleLayerVisibility,
            onToggleLayerMuted: onToggleLayerMuted,
            onLayerOpacityChanged: onLayerOpacityChanged,
            seCommaDrag: seCommaDrag,
            onSetAudioClipOffset: onSetAudioClipOffset,
            cutFxEnabledOf: cutFxEnabledOf,
            onToggleCutFx: onToggleCutFx,
            cutPictureVisibleOf: cutPictureVisibleOf,
            onToggleCutPictureVisibility: onToggleCutPictureVisibility,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Twirls down the V track and its Transform group (AE double step: the
/// chevron reveals the group header, the header opens the lanes).
Future<void> _expandVTransform(WidgetTester tester) async {
  await tester.tap(
    find.byKey(
      const ValueKey<String>('storyboard-track-lane-toggle-lane-track'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      const ValueKey<String>(
        'storyboard-lane-group-toggle-v-track:lane-track-transform-group',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a GAP (no active cut) keeps the SE rail controls up '
      '(UI-R10 #12): track-owned rows never depend on a cut', (
    tester,
  ) async {
    await _pumpPanel(
      tester,
      project: _project(),
      activeCutId: null,
      onToggleLayerVisibility: (_) {},
    );

    expect(
      find.byKey(
        const ValueKey<String>('storyboard-layer-visibility-lane-se'),
      ),
      findsOneWidget,
      reason: 'the SE eye survives the no-cut state',
    );
  });

  testWidgets('the V-track chevron twirls down the Transform GROUP header '
      '(collapsed, AE-style) and the header opens the lanes with the '
      'fade-envelope Opacity strip last', (tester) async {
    await _pumpPanel(tester, project: _project());

    // Collapsed: no lane rows at all.
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-row-0-transform-group'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-opacity-lane-row-0')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-toggle-lane-track'),
      ),
    );
    await tester.pumpAndSettle();

    // The group header shows, its members stay collapsed (default).
    expect(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-label-v-track:lane-track-transform-group',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-opacity-lane-row-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-track-lane-row-0-position')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-group-toggle-v-track:lane-track-transform-group',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // AE order: Anchor Point / Position / Scale / Rotation / Opacity —
    // the Opacity strip IS the cut-fade envelope row.
    for (final laneId in ['anchor-point', 'position', 'scale', 'rotation']) {
      expect(
        find.byKey(
          ValueKey<String>('storyboard-lane-label-v-track:lane-track-$laneId'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('storyboard-track-lane-row-0-$laneId')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-lane-label-v-track:lane-track-opacity'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-opacity-lane-row-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-cut-fade-span-lane-cut')),
      findsOneWidget,
    );

    // The chevron twirls the whole group back up.
    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-toggle-lane-track'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('storyboard-opacity-lane-row-0')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-row-0-transform-group'),
      ),
      findsNothing,
    );
  });

  testWidgets('the S-row chevron twirls down the audio lane plus its OWN '
      'Transform group on the active cut\'s slot layer', (tester) async {
    await _pumpPanel(tester, project: _project());

    expect(
      find.byKey(const ValueKey<String>('storyboard-audio-lane-row-0-1')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-se-lane-toggle-lane-track-1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('storyboard-audio-lane-row-0-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-lane-label-lane-track-s1-audio'),
      ),
      findsOneWidget,
    );
    // The lane carries the clip's enlarged waveform span — the REUSED
    // timeline Audio lane substrate ('완벽통일': its span keys ride the
    // storyboard-<layerId> prefix now that the lane mounts once across
    // the track).
    expect(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-se-audio-lane-span-lane-se-0-b0',
        ),
      ),
      findsOneWidget,
    );

    // Audio leads; the Transform group header sits BELOW it, collapsed.
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-lane-label-lane-se-transform-group'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('storyboard-se-lane-row-0-1-position')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-group-toggle-lane-se-transform-group',
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final laneId in [
      'anchor-point',
      'position',
      'scale',
      'rotation',
      'opacity',
    ]) {
      expect(
        find.byKey(ValueKey<String>('storyboard-lane-label-lane-se-$laneId')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('storyboard-se-lane-row-0-1-$laneId')),
        findsOneWidget,
      );
    }
  });

  testWidgets('the V Transform lanes edit the TRACK on its global axis '
      '(R4b): key toggles route the track lane edit hooks and keyed '
      'frames show as markers on the continuous row', (tester) async {
    final toggles = <(String, String, int)>[];
    await _pumpPanel(
      tester,
      project: _project(
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            2,
            CanvasPoint(x: 10, y: 20),
          ),
        ),
      ),
      trackLaneEditFor: (track) => PropertyLaneEditCallbacks(
        onToggleKeyAt: (_, lane, frame) =>
            toggles.add((track.id.value, lane.laneId, frame)),
        onMoveKey: (_, _, _, _) {},
        onRemoveKey: (_, _, _) {},
        onToggleHold: (_, _, _) {},
      ),
    );
    await _expandVTransform(tester);

    // The keyed frame sits at its GLOBAL position on the continuous row.
    expect(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-key-v-track:lane-track-position-2',
        ),
      ),
      findsOneWidget,
    );
    // The value column resolves the track pose over the display space —
    // unkeyed lanes read the identity (display center).
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>(
            'storyboard-lane-value-v-track:lane-track-scale',
          ),
        ),
        matching: find.text('100%'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-key-toggle-v-track:lane-track-position',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(toggles, [('lane-track', 'position', 0)]);
  });

  testWidgets('the S-row Transform lanes edit the slot LAYER\'s track '
      'through the shared layer lane hooks', (tester) async {
    final toggles = <(String, String, int)>[];
    await _pumpPanel(
      tester,
      project: _project(),
      layerLaneEdit: PropertyLaneEditCallbacks(
        onToggleKeyAt: (layer, lane, frame) =>
            toggles.add((layer.id.value, lane.laneId, frame)),
        onMoveKey: (_, _, _, _) {},
        onRemoveKey: (_, _, _) {},
        onToggleHold: (_, _, _) {},
      ),
    );

    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-se-lane-toggle-lane-track-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-group-toggle-lane-se-transform-group',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-lane-key-toggle-lane-se-position'),
      ),
    );
    await tester.pumpAndSettle();
    expect(toggles, [('lane-se', 'position', 0)]);
  });

  testWidgets('track groups run in TIMELINE order (R6 B3): the S rows sit '
      'ABOVE the V track, and the section divider caps the group', (
    tester,
  ) async {
    await _pumpPanel(tester, project: _project());

    final seLabelTop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('storyboard-se-label-lane-track-1'),
          ),
        )
        .dy;
    final vLabelTop = tester
        .getTopLeft(
          find.byKey(
            const ValueKey<String>('storyboard-track-label-row-lane-track'),
          ),
        )
        .dy;
    expect(
      seLabelTop,
      lessThan(vLabelTop),
      reason: 'rail order: S rows above the V track',
    );

    final seRowTop = tester
        .getTopLeft(find.byKey(const ValueKey<String>('storyboard-se-row-0-1')))
        .dy;
    final vRowTop = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('storyboard-track-row-lane-track')),
        )
        .dy;
    expect(
      seRowTop,
      lessThan(vRowTop),
      reason: 'strip order mirrors the rail: S rows above the V track',
    );

    // UI-R5: the extra 2px section divider is retired (single shared row
    // lines); UI-R7 #2: the group reads from the section ZONES spanning
    // each group's rows (the old gutter bracket, inside the rows).
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-section-divider-rail-lane-track'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-section-zone-lane-track-se'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-section-zone-lane-track-v'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the S-row waveform-hide eye is retired (UI-R7 #8) — the '
      'waveform always shows, the toggle key is gone', (tester) async {
    await _pumpPanel(tester, project: _project());

    expect(
      find.byKey(const ValueKey<String>('storyboard-audio-clip-lane-se-0-b0')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('storyboard-se-waveform-toggle-lane-track-1'),
      ),
      findsNothing,
    );
  });

  testWidgets('dragging the cut-fade handles commits the fade lengths '
      '(one commit per drag)', (tester) async {
    final commits = <(CutId, int, int)>[];
    await _pumpPanel(
      tester,
      project: _project(),
      onSetCutFade: (cutId, fadeIn, fadeOut) =>
          commits.add((cutId, fadeIn, fadeOut)),
    );

    await _expandVTransform(tester);

    // 12 px/frame: 3 frames = 36 px rightward on the fade-in handle.
    await tester.drag(
      find.byKey(
        const ValueKey<String>('storyboard-cut-fade-in-handle-lane-cut'),
      ),
      const Offset(36, 0),
    );
    await tester.pumpAndSettle();
    expect(commits, [(const CutId('lane-cut'), 3, 0)]);

    // 2 frames leftward on the fade-out handle.
    await tester.drag(
      find.byKey(
        const ValueKey<String>('storyboard-cut-fade-out-handle-lane-cut'),
      ),
      const Offset(-24, 0),
    );
    await tester.pumpAndSettle();
    expect(commits, [
      (const CutId('lane-cut'), 3, 0),
      (const CutId('lane-cut'), 0, 2),
    ]);
  });

  testWidgets('existing fade keys read back into the handles: dragging '
      'extends from the current lengths', (tester) async {
    final commits = <(CutId, int, int)>[];
    await _pumpPanel(
      tester,
      project: _project(
        transformTrack: trackTransformWithCutFade(
          TransformTrack.empty(),
          startFrame: 0,
          duration: 10,
          fadeInFrames: 2,
          fadeOutFrames: 0,
        ),
      ),
      onSetCutFade: (cutId, fadeIn, fadeOut) =>
          commits.add((cutId, fadeIn, fadeOut)),
    );

    await _expandVTransform(tester);

    await tester.drag(
      find.byKey(
        const ValueKey<String>('storyboard-cut-fade-in-handle-lane-cut'),
      ),
      const Offset(24, 0),
    );
    await tester.pumpAndSettle();
    expect(commits, [(const CutId('lane-cut'), 4, 0)]);
  });

  testWidgets('the fade span carries NO target menu any more (R3b): the '
      'fade is transparency toward the backdrop, so a long-press does '
      'nothing here', (tester) async {
    await _pumpPanel(tester, project: _project(), onSetCutFade: (_, _, _) {});

    await _expandVTransform(tester);

    await tester.longPress(
      find.byKey(const ValueKey<String>('storyboard-cut-fade-span-lane-cut')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('cut-fade-target-white')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('cut-fade-target-black')),
        findsNothing);
  });

  group('timeline-parity S rows (R4-⑨ 완벽통일)', () {
    testWidgets('the rail carries the ACTIVE cut layer\'s eye/mute/opacity '
        'controls with the shared session hooks', (tester) async {
      final visibilityToggles = <LayerId>[];
      final muteToggles = <LayerId>[];
      final opacityChanges = <(LayerId, double)>[];
      await _pumpPanel(
        tester,
        project: _project(),
        onToggleLayerVisibility: visibilityToggles.add,
        onToggleLayerMuted: muteToggles.add,
        onLayerOpacityChanged: (layerId, opacity) =>
            opacityChanges.add((layerId, opacity)),
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('storyboard-layer-visibility-lane-se'),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('storyboard-layer-mute-lane-se')),
      );
      await tester.drag(
        find.byKey(const ValueKey<String>('storyboard-layer-opacity-lane-se')),
        const Offset(-20, 0),
      );
      await tester.pumpAndSettle();

      expect(visibilityToggles, [const LayerId('lane-se')]);
      expect(muteToggles, [const LayerId('lane-se')]);
      expect(opacityChanges, isNotEmpty);
      expect(opacityChanges.last.$1, const LayerId('lane-se'));
      expect(opacityChanges.last.$2, lessThan(1));
    });

    testWidgets('pressing an S row selects the row and the frame under the '
        'pointer — an EMPTY cell included (timeline cell parity)', (
      tester,
    ) async {
      const pixelsPerFrame = 12.0;
      final presses = <(TimelineRowAddress, int)>[];
      await _pumpPanel(
        tester,
        project: _project(),
        onRowFramePress: (row, globalFrame) => presses.add((row, globalFrame)),
      );

      final rowLeft = tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('storyboard-se-row-0-1')),
          )
          .dx;
      final rowCentreY = tester
          .getCenter(find.byKey(const ValueKey<String>('storyboard-se-row-0-1')))
          .dy;

      // Frame 2: inside the row's written block.
      await tester.tapAt(
        Offset(rowLeft + 2.5 * pixelsPerFrame, rowCentreY),
      );
      await tester.pumpAndSettle();
      // Frame 6: past the writing, where the old per-BLOCK tap zones had
      // nothing to answer with.
      await tester.tapAt(
        Offset(rowLeft + 6.5 * pixelsPerFrame, rowCentreY),
      );
      await tester.pumpAndSettle();

      expect(presses, [
        (const LayerRowAddress(LayerId('lane-se')), 2),
        (const LayerRowAddress(LayerId('lane-se')), 6),
      ]);
    });

    testWidgets('the ACTIVE cut\'s SE blocks carry the timeline comma '
        'grips: an end-edge drag rides the session drag hooks', (tester) async {
      final log = <String>[];
      await _pumpPanel(
        tester,
        project: _project(),
        seCommaDrag: TimelineCommaDragCallbacks(
          onBegin: (layerId, blockStartIndex, edge) {
            log.add('begin $layerId $blockStartIndex ${edge.name}');
            return true;
          },
          onUpdate: (delta) => log.add('update $delta'),
          onEnd: () => log.add('end'),
          onCancel: () => log.add('cancel'),
        ),
      );

      // 12px per frame; the recognizer's slop eats ~20px, so 48px lands a
      // whole-frame delta (same allowance as the XSheet grip tests).
      await tester.drag(
        find.byKey(const ValueKey<String>('storyboard-se-grip-lane-se-0-end')),
        const Offset(48, 0),
      );
      await tester.pumpAndSettle();

      expect(log.first, 'begin lane-se 0 end');
      expect(
        log.where((entry) => entry.startsWith('update')),
        isNotEmpty,
        reason: 'the drag must report whole-frame deltas',
      );
      expect(log.last, 'end');
    });

    testWidgets('the twirled-down audio lane IS the timeline lane substrate '
        'and slide-edits the ACTIVE cut\'s clip', (tester) async {
      final offsets = <(LayerId, int, int)>[];
      await _pumpPanel(
        tester,
        project: _project(),
        onSetAudioClipOffset: (layerId, clipIndex, offsetFrames) =>
            offsets.add((layerId, clipIndex, offsetFrames)),
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('storyboard-se-lane-toggle-lane-track-1'),
        ),
      );
      await tester.pumpAndSettle();

      final span = find.byKey(
        const ValueKey<String>(
          'storyboard-lane-se-audio-lane-span-lane-se-0-b0',
        ),
      );
      expect(span, findsOneWidget, reason: 'the reused timeline lane span');

      // Slide LEFT (a later part of the file plays at the block start —
      // offset grows; rightward from offset 0 clamps to no-op), exactly
      // like the timeline's Audio lane.
      await tester.drag(span, const Offset(-60, 0));
      await tester.pumpAndSettle();

      expect(offsets, isNotEmpty);
      expect(offsets.last.$1, const LayerId('lane-se'));
      expect(offsets.last.$3, greaterThan(0));
    });
  });

  group('V-row display toggles (R9)', () {
    testWidgets('the fx switch and the eye act on the ACTIVE cut and '
        'reflect the session state', (tester) async {
      final fxToggles = <CutId>[];
      final eyeToggles = <CutId>[];
      var fxEnabled = true;
      await _pumpPanel(
        tester,
        project: _project(),
        cutFxEnabledOf: (_) => fxEnabled,
        onToggleCutFx: (cutId) {
          fxToggles.add(cutId);
          fxEnabled = !fxEnabled;
        },
        cutPictureVisibleOf: (_) => true,
        onToggleCutPictureVisibility: eyeToggles.add,
      );

      final fxFinder = find.byKey(
        const ValueKey<String>('storyboard-cut-fx-lane-cut'),
      );
      final eyeFinder = find.byKey(
        const ValueKey<String>('storyboard-cut-visibility-lane-cut'),
      );
      expect(fxFinder, findsOneWidget);
      expect(eyeFinder, findsOneWidget);

      await tester.tap(fxFinder);
      await tester.pumpAndSettle();
      expect(fxToggles, [const CutId('lane-cut')]);

      await tester.tap(eyeFinder);
      await tester.pumpAndSettle();
      expect(eyeToggles, [const CutId('lane-cut')]);
    });

    testWidgets('the toggles hide without wiring (display-only rail)', (
      tester,
    ) async {
      await _pumpPanel(tester, project: _project());
      expect(
        find.byKey(const ValueKey<String>('storyboard-cut-fx-lane-cut')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('storyboard-cut-visibility-lane-cut'),
        ),
        findsNothing,
      );
    });

    testWidgets('the GAP keeps the fx/eye buttons NORMAL — never grayed, '
        'never gone; a press is simply a no-op because no cut exists at '
        'the index (UI-R13 #2)', (tester) async {
      await _pumpPanel(
        tester,
        project: _project(),
        activeCutId: null, // gap: no cut selected anywhere
        cutFxEnabledOf: (_) => true,
        onToggleCutFx: (_) => fail('no subject cut — presses must no-op'),
        cutPictureVisibleOf: (_) => true,
        onToggleCutPictureVisibility: (_) =>
            fail('no subject cut — presses must no-op'),
      );

      final fx = find.byKey(
        const ValueKey<String>('storyboard-cut-fx-none-lane-track'),
      );
      final eye = find.byKey(
        const ValueKey<String>('storyboard-cut-visibility-none-lane-track'),
      );
      expect(fx, findsOneWidget);
      expect(eye, findsOneWidget);
      expect(
        tester.widget<IconButton>(fx).onPressed,
        isNotNull,
        reason: 'the button stays fully NORMAL (no disabled look)',
      );
      expect(tester.widget<IconButton>(eye).onPressed, isNotNull);
      // Pressing is a no-op (the fail() wiring proves nothing fires).
      await tester.tap(fx);
      await tester.tap(eye);
      await tester.pumpAndSettle();
    });
  });

  group('rail layout (R7-④⑤)', () {
    final twoSeRows = [
      _seLayer(),
      Layer(
        id: const LayerId('lane-se-2'),
        name: 'S2',
        kind: LayerKind.se,
        frames: const [],
        timeline: const {},
      ),
    ];

    testWidgets('SE slots count UP from the bottom like the timeline '
        '(top-down S2, S1, V) and the rows stack FLUSH — no inter-row '
        'padding', (tester) async {
      await _pumpPanel(tester, project: _project(seLayers: twoSeRows));

      final s1 = tester.getRect(
        find.byKey(const ValueKey<String>('storyboard-se-label-lane-track-1')),
      );
      final s2 = tester.getRect(
        find.byKey(const ValueKey<String>('storyboard-se-label-lane-track-2')),
      );
      final vRow = tester.getRect(
        find.byKey(
          const ValueKey<String>('storyboard-track-label-row-lane-track'),
        ),
      );
      expect(s2.top, lessThan(s1.top), reason: 'S2 above S1 (bottom-up)');
      expect(s1.top, s2.bottom, reason: 'rows flush: no padding S2 → S1');
      expect(vRow.top, s1.bottom, reason: 'rows flush: no padding S1 → V');

      // The strips column mirrors the rail row for row.
      final s1Strip = tester.getRect(
        find.byKey(const ValueKey<String>('storyboard-se-row-0-1')),
      );
      final s2Strip = tester.getRect(
        find.byKey(const ValueKey<String>('storyboard-se-row-0-2')),
      );
      expect(s2Strip.top, lessThan(s1Strip.top));
      expect(s1Strip.top, s2Strip.bottom);
    });

    testWidgets('sections live INSIDE the rows as run-spanning ZONES '
        '(UI-R7 #2): the SE zone covers S2+S1 as one vertical sub-zone, '
        'the V zone the track row', (tester) async {
      await _pumpPanel(tester, project: _project(seLayers: twoSeRows));

      // The SE zone spans BOTH S rows (S1·S2 read as one section).
      final seZone = tester.getRect(
        find.byKey(
          const ValueKey<String>('storyboard-section-zone-lane-track-se'),
        ),
      );
      final s2 = tester.getRect(
        find.byKey(const ValueKey<String>('storyboard-se-label-lane-track-2')),
      );
      final s1 = tester.getRect(
        find.byKey(const ValueKey<String>('storyboard-se-label-lane-track-1')),
      );
      expect(seZone.top, lessThanOrEqualTo(s2.top + 1));
      expect(seZone.bottom, greaterThanOrEqualTo(s1.bottom - 1));

      final vZone = tester.getRect(
        find.byKey(
          const ValueKey<String>('storyboard-section-zone-lane-track-v'),
        ),
      );
      final vRow = tester.getRect(
        find.byKey(
          const ValueKey<String>('storyboard-track-label-row-lane-track'),
        ),
      );
      expect(vZone.top, lessThanOrEqualTo(vRow.top + 1));
      expect(vZone.bottom, greaterThanOrEqualTo(vRow.bottom - 1));
    });
  });
}

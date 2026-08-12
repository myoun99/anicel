import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kSecondaryButton;
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
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/text/vertical_writing_text.dart'
    show VerticalWritingText;
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
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show
        LayerRowDragState,
        LayerRowDragSubject,
        LayerRowSubject,
        TimelineRowDragHooks;
import 'package:anicel/src/ui/timeline/timeline_current_row.dart';

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
  void Function(BuildContext anchorContext, LayerId layerId)? onOpenLayerMixer,
  void Function(LayerId layerId, double opacity)? onLayerOpacityChanged,
  StoryboardRowFramePress? onRowFramePress,
  TimelineCommaDragCallbacks? seCommaDrag,
  void Function(LayerId layerId, int clipIndex, int offsetFrames)?
  onSetAudioClipOffset,
  PropertyLaneEditCallbacks? Function(Track track)? trackLaneEditFor,
  PropertyLaneEditCallbacks? layerLaneEdit,
  bool Function(CutId cutId)? cutPictureVisibleOf,
  ValueChanged<CutId>? onToggleCutPictureVisibility,
  LayerFxState Function(Track track)? trackFxStateOf,
  ValueChanged<Track>? onToggleTrackFx,
  double Function(Track track)? trackOpacityOf,
  void Function(Track track, double opacity)? onTrackOpacityChangeEnd,
  TimelineCurrentRowHooks? currentRowHooks,
  TimelineRowDragHooks? rowDragHooks,
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
            currentRowHooks: currentRowHooks,
            rowDragHooks: rowDragHooks,
            poseDisplaySize: const CanvasSize(width: 640, height: 360),
            onSetCutFade: onSetCutFade,
            onToggleLayerVisibility: onToggleLayerVisibility,
            onOpenLayerMixer: onOpenLayerMixer,
            onLayerOpacityChanged: onLayerOpacityChanged,
            seCommaDrag: seCommaDrag,
            onSetAudioClipOffset: onSetAudioClipOffset,
            cutPictureVisibleOf: cutPictureVisibleOf,
            onToggleCutPictureVisibility: onToggleCutPictureVisibility,
            trackFxStateOf: trackFxStateOf,
            onToggleTrackFx: onToggleTrackFx,
            trackOpacityOf: trackOpacityOf,
            onTrackOpacityChanged: onTrackOpacityChangeEnd == null
                ? null
                : (_, _) {},
            onTrackOpacityChangeEnd: onTrackOpacityChangeEnd,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// `_expandVTransform` went with the V row's Transform group: the chevron opens
// the row's fx chain now, and an effect group opens by its own header.

void main() {
  // ㉒ (user, 2026-08-12): 「스토리보드 레전드에 fx 펼치기 버튼이 없다 ⇒
  // 타임라인과 통일」. The rows always twirled; the LEGEND's bulk verb over
  // them was missing, because the shared header only draws that button when
  // a host hands it both verbs — and this host handed it neither.
  testWidgets('the legend twirls every row open and shut, like the '
      'timeline\'s', (tester) async {
    await _pumpPanel(tester, project: _project());

    const laneToggle = ValueKey<String>('legend-lanes-toggle');
    const seLane = ValueKey<String>('storyboard-audio-lane-row-0-1');

    // The V row's own state is read off its chevron: its lanes are its fx
    // chain, and a track with no effects opens onto nothing to find.
    bool vRowOpen() =>
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(
                  const ValueKey<String>(
                    'storyboard-track-lane-toggle-lane-track',
                  ),
                ),
                matching: find.byType(Icon),
              ),
            )
            .icon ==
        Icons.arrow_drop_down;

    expect(find.byKey(laneToggle), findsOneWidget);
    expect(find.byKey(seLane), findsNothing);
    expect(vRowOpen(), isFalse);

    // ONE tap opens BOTH kinds of row — an S row and the V row. A verb that
    // reached only one of them would look right on whichever row the tester
    // happened to check.
    await tester.tap(find.byKey(laneToggle));
    await tester.pumpAndSettle();
    expect(find.byKey(seLane), findsOneWidget);
    expect(vRowOpen(), isTrue);

    // The same button is the CLOSING verb once anything is open (the icon
    // flips with `anyLanesExpanded`), so a second tap shuts what the first
    // opened rather than toggling each row back to where it started.
    await tester.tap(find.byKey(laneToggle));
    await tester.pumpAndSettle();
    expect(find.byKey(seLane), findsNothing);
    expect(vRowOpen(), isFalse);
  });

  testWidgets('one open row makes the legend button the CLOSING verb, and '
      'it shuts the rest with it', (tester) async {
    // The mixed state: with a single S row twirled open by hand, the button
    // must not re-toggle row by row — that would open the V row and close
    // the S row in the same tap, which is what a blind sweep does.
    await _pumpPanel(tester, project: _project());

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

    await tester.tap(find.byKey(const ValueKey<String>('legend-lanes-toggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('storyboard-audio-lane-row-0-1')),
      findsNothing,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(
                const ValueKey<String>(
                  'storyboard-track-lane-toggle-lane-track',
                ),
              ),
              matching: find.byType(Icon),
            ),
          )
          .icon,
      Icons.arrow_right,
      reason: 'a collapse verb never opens anything',
    );
  });

  testWidgets('the V row\'s chevron opens its fx chain and NO Transform group '
      '— a track row does not own one', (tester) async {
    await _pumpPanel(tester, project: _project());
    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-track-lane-toggle-lane-track'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-group-toggle-v-track:lane-track-transform-group',
        ),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'storyboard-lane-label-v-track:lane-track-transform-group',
        ),
      ),
      findsNothing,
      reason: 'nor on the rail — the rail ASKS the policy instead of deciding',
    );
  });

  testWidgets('an S row takes the row-order drag — the third surface, and '
      'the track list is what it re-orders', (tester) async {
    final begun = <LayerRowDragSubject>[];
    final updates = <({List<String> rows, int slot})>[];
    final drag = ValueNotifier<LayerRowDragState?>(null);
    addTearDown(drag.dispose);

    await _pumpPanel(
      tester,
      project: _project(
        seLayers: [
          _seLayer(),
          Layer(
            id: const LayerId('lane-se2'),
            name: 'S2',
            kind: LayerKind.se,
            frames: const [],
          ),
        ],
      ),
      onToggleLayerVisibility: (_) {},
      rowDragHooks: TimelineRowDragHooks(
        drag: drag,
        onBegin: begun.add,
        onRowTarget: (_, _, _) {},
        onUpdate: (rows, slot) => updates.add((
          rows: [for (final row in rows) row.id.value],
          slot: slot,
        )),
        onEffectUpdate: (_, _, _) {},
        onEnd: () {},
        onCancel: () {},
      ),
    );

    // The rail lists slots TOP-DOWN, so 'lane-se2' (the higher slot) is the
    // first display row and downward is toward 'lane-se'.
    //
    // ④: the landing is the gap the POINTER is nearest, so WHERE in the row
    // the drag began counts — and this one begins on the visibility button,
    // not in the row's middle. The travel therefore clears the next
    // boundary from anywhere in the row's upper half rather than being
    // exactly one row.
    await tester.drag(
      find.byKey(
        const ValueKey<String>('storyboard-layer-visibility-lane-se2'),
      ),
      const Offset(0, 50),
    );
    await tester.pumpAndSettle();

    expect(begun, [const LayerRowSubject(LayerId('lane-se2'))]);
    expect(updates.last.rows, [
      'lane-se2',
      'lane-se',
    ], reason: 'the display list is the track list reversed');
    expect(
      updates.last.slot,
      2,
      reason: 'one step down clears the row own gap and lands past S1',
    );
  });

  testWidgets('a GAP (no active cut) keeps the SE rail controls up '
      '(UI-R10 #12): track-owned rows never depend on a cut', (tester) async {
    await _pumpPanel(
      tester,
      project: _project(),
      activeCutId: null,
      onToggleLayerVisibility: (_) {},
    );

    expect(
      find.byKey(const ValueKey<String>('storyboard-layer-visibility-lane-se')),
      findsOneWidget,
      reason: 'the SE eye survives the no-cut state',
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

  testWidgets('the S-row Transform lanes edit the slot LAYER\'s track '
      'through the shared layer lane hooks', (tester) async {
    final toggles = <(String, String, int)>[];
    await _pumpPanel(
      tester,
      project: _project(),
      layerLaneEdit: PropertyLaneEditCallbacks(
        onToggleKeyAt: (layer, lane, frame) =>
            toggles.add((layer.id.value, lane.laneId, frame)),
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

  group('timeline-parity S rows (R4-⑨ 완벽통일)', () {
    testWidgets('the rail carries the ACTIVE cut layer\'s eye/speaker/opacity '
        'controls with the shared session hooks — and R10 R3 gave THIS rail '
        'the mixer door the timeline rails had', (tester) async {
      final visibilityToggles = <LayerId>[];
      final mixerOpens = <LayerId>[];
      final opacityChanges = <(LayerId, double)>[];
      await _pumpPanel(
        tester,
        project: _project(),
        onToggleLayerVisibility: visibilityToggles.add,
        onOpenLayerMixer: (_, layerId) => mixerOpens.add(layerId),
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
      expect(mixerOpens, [const LayerId('lane-se')]);
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
          .getCenter(
            find.byKey(const ValueKey<String>('storyboard-se-row-0-1')),
          )
          .dy;

      // Frame 2: inside the row's written block.
      await tester.tapAt(Offset(rowLeft + 2.5 * pixelsPerFrame, rowCentreY));
      await tester.pumpAndSettle();
      // Frame 6: past the writing, where the old per-BLOCK tap zones had
      // nothing to answer with.
      await tester.tapAt(Offset(rowLeft + 6.5 * pixelsPerFrame, rowCentreY));
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

  group('V-row display toggles (R9 #21: the fx column is the TRACK\'s)', () {
    testWidgets('the fx switch acts on the TRACK and the eye on the ACTIVE '
        'cut — a row\'s columns describe the row\'s own subject, and this '
        'row is the track\'s', (tester) async {
      final fxToggles = <Track>[];
      final eyeToggles = <CutId>[];
      await _pumpPanel(
        tester,
        project: _project(),
        cutPictureVisibleOf: (_) => true,
        onToggleCutPictureVisibility: eyeToggles.add,
        trackFxStateOf: (_) => LayerFxState.on,
        onToggleTrackFx: fxToggles.add,
      );

      final fxFinder = find.byKey(
        const ValueKey<String>('storyboard-track-fx-lane-track'),
      );
      final eyeFinder = find.byKey(
        const ValueKey<String>('storyboard-cut-visibility-lane-cut'),
      );
      expect(fxFinder, findsOneWidget);
      expect(eyeFinder, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('storyboard-cut-fx-lane-cut')),
        findsNothing,
        reason:
            'R10 R3 retired the per-cut axis — the track switch is the '
            'film\'s only fx switch',
      );

      await tester.tap(fxFinder);
      await tester.pumpAndSettle();
      expect(fxToggles.single.id.value, 'lane-track');

      await tester.tap(eyeFinder);
      await tester.pumpAndSettle();
      expect(eyeToggles, [const CutId('lane-cut')]);
    });

    testWidgets('a RIGHT-CLICK on the fx switch opens nothing — R10 R3 took '
        'the context menu off the rails for good', (tester) async {
      await _pumpPanel(
        tester,
        project: _project(),
        trackFxStateOf: (_) => LayerFxState.on,
        onToggleTrackFx: (_) {},
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('storyboard-track-fx-lane-track')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuItem<String>), findsNothing);
    });

    testWidgets('the toggles hide without wiring (display-only rail)', (
      tester,
    ) async {
      await _pumpPanel(tester, project: _project());
      expect(
        find.byKey(const ValueKey<String>('storyboard-track-fx-lane-track')),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('storyboard-cut-visibility-lane-cut'),
        ),
        findsNothing,
      );
    });

    testWidgets('the GAP keeps the eye NORMAL — never grayed, never gone; a '
        'press is simply a no-op because no cut exists at the index '
        '(UI-R13 #2). The fx switch is unaffected: its subject is the '
        'track, which is always there', (tester) async {
      await _pumpPanel(
        tester,
        project: _project(),
        activeCutId: null, // gap: no cut selected anywhere
        cutPictureVisibleOf: (_) => true,
        onToggleCutPictureVisibility: (_) =>
            fail('no subject cut — presses must no-op'),
        trackFxStateOf: (_) => LayerFxState.on,
        onToggleTrackFx: (_) {},
      );

      final eye = find.byKey(
        const ValueKey<String>('storyboard-cut-visibility-none-lane-track'),
      );
      expect(eye, findsOneWidget);
      expect(
        tester.widget<IconButton>(eye).onPressed,
        isNotNull,
        reason: 'the button stays fully NORMAL (no disabled look)',
      );
      // Pressing is a no-op (the fail() wiring proves nothing fires).
      await tester.tap(eye);
      await tester.pumpAndSettle();
    });

    testWidgets('the V row\'s opacity bar commits ONCE on release', (
      tester,
    ) async {
      final commits = <double>[];
      await _pumpPanel(
        tester,
        project: _project(),
        trackOpacityOf: (_) => 1.0,
        onTrackOpacityChangeEnd: (_, opacity) => commits.add(opacity),
      );

      final bar = find.byKey(
        const ValueKey<String>('storyboard-track-opacity-lane-track'),
      );
      expect(bar, findsOneWidget);

      final rect = tester.getRect(bar);
      await tester.dragFrom(
        rect.centerRight - const Offset(2, 0),
        Offset(-rect.width / 2, 0),
      );
      await tester.pumpAndSettle();
      expect(commits, hasLength(1));
      expect(commits.single, lessThan(1.0));
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

    // ㉑ (user, 2026-08-12). The WIRED half of the rule: the law itself is
    // covered in timeline_section_test, but only a pumped panel proves the
    // band measures ITS OWN box — a fit computed against the wrong height
    // would pass every pure test and still ship `C⋮`.
    testWidgets('the one-row transition band shortens CAM to C, while the '
        'SE band beside it keeps SE', (tester) async {
      await _pumpPanel(tester, project: _project(seLayers: twoSeRows));

      String bandText(String keyValue) => tester
          .widget<VerticalWritingText>(
            find.descendant(
              of: find.byKey(ValueKey<String>(keyValue)),
              matching: find.byType(VerticalWritingText),
            ),
          )
          .text;

      expect(bandText('storyboard-section-zone-lane-track-transition'), 'C');
      expect(bandText('storyboard-section-zone-lane-track-se'), 'SE');

      // The REGION still announces the whole word: shortening is a drawing
      // decision, and a reader that said 'C' would be reading geometry.
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>(
              'storyboard-section-zone-lane-track-transition',
            ),
          ),
          // The widget, not the semantics tree: `bySemanticsLabel` needs the
          // binding turned on, and what is being asserted here is what the
          // band DECLARES, which is exactly this property.
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == 'CAM',
          ),
        ),
        findsOneWidget,
      );
    });
  });
}

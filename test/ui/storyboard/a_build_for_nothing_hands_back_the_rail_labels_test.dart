import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show FxToggleButton, LayerVisibilityToggleButton;
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show LayerFoldTwirl;
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show LayerRowDragState, LayerRowDragTarget, TimelineRowDragHooks;
import 'package:anicel/src/ui/timeline/property_lane_model.dart'
    show laneGroupKey;
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';
import 'package:anicel/src/ui/widgets/rail_glyph_button.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_twirls.dart';
import '../../helpers/rail_label_name.dart';

/// 🚨I-57 (10-14): A STORYBOARD BUILT AGAIN FOR NOTHING — OR ACROSS A CUT —
/// HANDS BACK EVERY ROW OF ITS RAIL AS IT WAS, its label and the drag
/// wrapper on it, and builds one again the moment what it shows changes.
///
/// Its host builds it again on every notify it hears — a cut crossed under
/// the playhead among them — and every label of the rail was built again
/// with it: 🔬953 of a crossing's 1,088 widget rebuilds on the AMMI OP, the
/// heads (the timeline's own rows) 464 of them; then the wrappers, 64 of
/// the 330 left. A head is kept by its FACE, as the timeline's rail keeps
/// its rows: a crossing that hands it the next cut's row of the same face
/// hands it back whole, wearing the row it has in hand now. What a kept
/// row's wrapper reads of the track it reads at the event.
void main() {
  const trackId = TrackId('t1');

  Layer conte(String cut) => Layer(
    id: LayerId('$cut-conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    frames: [
      Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const []),
    ],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
    },
  );

  /// Cut [id], its conte — [conteLayer] — ridden by [attachRows] attach
  /// rows above it, at seats +1 up; its camera wearing [cameraMark].
  Cut cutOf(
    String id, {
    Layer? conteLayer,
    Layer? folder,
    int attachRows = 0,
    LayerMark cameraMark = LayerMark.none,
  }) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    camera: CutCamera(
      keyframes: {0: CameraPose(center: CanvasPoint(x: 320, y: 180))},
    ),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        mark: cameraMark,
        frames: const [],
      ),
      ?folder,
      ?conteLayer,
      for (var seat = 1; seat <= attachRows; seat += 1)
        Layer(
          id: LayerId('$id-conte+$seat'),
          name: 'Conte+$seat',
          kind: LayerKind.storyboard,
          attachedToLayerId: LayerId('$id-conte'),
          frames: const [],
        ),
    ],
  );

  Layer seLayer(int n) => Layer(
    id: LayerId('t1-s$n'),
    name: 'S$n',
    kind: LayerKind.se,
    frames: const [],
  );

  /// Cuts a and b, each with a camera and a conte of the same face — b's
  /// conte as [bConte] makes it, beside [bFolder] where given, and b's
  /// camera wearing [bCameraMark] — on one track with [seRows] S rows; a's
  /// conte ridden by [attachRows].
  Project film({
    Layer? bConte,
    Layer? bFolder,
    LayerMark bCameraMark = LayerMark.none,
    int seRows = 1,
    int attachRows = 0,
  }) => Project(
    id: const ProjectId('rail-labels'),
    name: 'Rail labels',
    createdAt: DateTime.utc(2026, 10, 14),
    tracks: [
      Track(
        id: trackId,
        name: 'V1',
        seLayers: [for (var n = 1; n <= seRows; n += 1) seLayer(n)],
        cuts: [
          cutOf('a', conteLayer: conte('a'), attachRows: attachRows),
          cutOf(
            'b',
            conteLayer: bConte ?? conte('b'),
            folder: bFolder,
            cameraMark: bCameraMark,
          ),
        ],
      ),
    ],
  );

  /// The tab as the workspace mounts it, on [project]: built again on every
  /// notify the session makes and every twirl its rows turn. [turned] hears
  /// every lane twirl the rail turns, in place of the session's verb;
  /// [openLanes] are the layers whose lanes stand open and [openGroups] the
  /// conte rows' lane groups that do, in place of the session's; [rowFilter]
  /// is the legend's.
  Future<EditorSessionManager> pumpPanel(
    WidgetTester tester,
    Project project, {
    List<LayerId>? turned,
    Set<LayerId>? openLanes,
    Set<String>? openGroups,
    TimelineRowFilter rowFilter = TimelineRowFilter.none,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: withStoryboardTwirls(
            session,
            (twirls) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
              rowFilter: rowFilter,
              expandedLaneLayerIds: openLanes ?? twirls.expandedLaneLayerIds,
              expandedLaneGroupKeys: openGroups ?? twirls.expandedLaneGroupKeys,
              onToggleLayerLanes: turned?.add ?? twirls.onToggleLayerLanes,
              onToggleLaneGroupKey: twirls.onToggleLaneGroupKey,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));
  final cameraLabel = key('storyboard-camera-label-t1');
  final conteLabel = key('storyboard-conte-label-t1');
  final seLabel = key('storyboard-se-label-t1-1');
  final transitionLabel = key('storyboard-transition-label-t1');
  final vLabel = key('storyboard-track-select-t1');

  Finder headIn(Finder label) => find.descendant(
    of: label,
    matching: find.byType(TimelineLayerControlsRow),
  );

  /// The drag wrapper the rail puts on [label]'s row.
  Finder wrapperOf(Finder label) => find
      .ancestor(of: label, matching: find.byType(LayerRowDragTarget))
      .first;

  LayerRowDragTarget wrapper(WidgetTester tester, Finder label) =>
      tester.widget(wrapperOf(label));

  /// Every row of the rail as it is built: its label — a head's, the
  /// timeline's row it builds — and the drag wrapper on it, for the S row,
  /// the transition row, the V row and the two heads.
  Map<String, Widget> rowsNow(WidgetTester tester) => {
    'se': tester.widget(seLabel),
    'transition': tester.widget(transitionLabel),
    'v': tester.widget(vLabel),
    'camera': tester.widget(headIn(cameraLabel)),
    'conte': tester.widget(headIn(conteLabel)),
    for (final (name, label) in [
      ('se', seLabel),
      ('transition', transitionLabel),
      ('v', vLabel),
      ('camera', cameraLabel),
      ('conte', conteLabel),
    ])
      '$name wrapper': wrapper(tester, label),
  };

  void expectRowsAsThey(
    WidgetTester tester,
    Map<String, Widget> before, {
    Set<String> builtAgain = const {},
  }) {
    for (final MapEntry(:key, value: row) in rowsNow(tester).entries) {
      expect(
        row,
        builtAgain.contains(key) ? isNot(same(before[key])) : same(before[key]),
        reason: key,
      );
    }
  }

  bool eyeOn(WidgetTester tester, Finder label) => tester
      .widget<LayerVisibilityToggleButton>(
        find.descendant(
          of: label,
          matching: find.byType(LayerVisibilityToggleButton),
        ),
      )
      .isVisible;

  testWidgets('built again for nothing, every row of its rail — the label and '
      'the drag wrapper on it — is the row it had', (tester) async {
    final session = await pumpPanel(tester, film());
    final before = rowsNow(tester);

    session.notifyChanged();
    await tester.pump();

    expectRowsAsThey(tester, before);
  });

  testWidgets('🚨a cut crossed builds no row of the rail — each head wears '
      'the next cut\'s row of the same face', (tester) async {
    final session = await pumpPanel(tester, film());
    expect(session.activeCutId, const CutId('a'), reason: 'premise');
    final before = rowsNow(tester);

    session.selectCut(const CutId('b'));
    await tester.pump();

    expectRowsAsThey(tester, before);
  });

  testWidgets('🚨the camera head shows its eye as it flips — the eye is no '
      'part of the face it is kept by', (tester) async {
    final session = await pumpPanel(tester, film());
    expect(eyeOn(tester, cameraLabel), isTrue, reason: 'premise');

    // The camera view's own switch (F-363): the camera row's eye.
    session.cameraViewMode.toggle();
    await tester.pump();

    expect(eyeOn(tester, cameraLabel), isFalse);
  });

  /// A head kept across a cut shows the eye of the row it wears NOW.
  ///
  /// ↩️That was pinned on a conte of its own eye too — b's shut while a's
  /// stood open. F-343 makes that a film no session holds: the eye is the
  /// track conte's head ([ConteHead]), and every cut's conte wears it, so
  /// what tells a cut's eye from the next one's is the folder above it.
  testWidgets('🚨a head kept across a cut wears the eye its row has on the '
      'timeline there: a folder above that hides the row dims it (F-185)', (
    tester,
  ) async {
    const folderId = LayerId('b-folder');
    final session = await pumpPanel(
      tester,
      film(
        bConte: conte('b').copyWith(folderId: folderId),
        bFolder: Layer(
          id: folderId,
          name: 'F',
          kind: LayerKind.folder,
          isVisible: false,
          frames: const [],
        ),
      ),
    );
    LayerVisibilityToggleButton eye() => tester.widget(
      find.descendant(
        of: conteLabel,
        matching: find.byType(LayerVisibilityToggleButton),
      ),
    );
    final before = tester.widget(headIn(conteLabel));
    expect(eye().hiddenAbove, isFalse, reason: 'premise: a\'s conte');

    session.selectCut(const CutId('b'));
    await tester.pump();

    expect(
      tester.widget(headIn(conteLabel)),
      same(before),
      reason: 'kept: the folder a row is filed in is no part of its face',
    );
    expect(eye().hiddenAbove, isTrue);
    expect(eye().isVisible, isTrue, reason: 'its own switch keeps its value');
  });

  /// ↩️It was pinned on the conte head — b's conte named Layout. F-343
  /// makes that a film no session holds: the name is the track conte's
  /// head. A camera's colour label is each cut's own (I-73 ④, 「색라벨은
  /// 컷마다 있는게 좋을거같은데」), and the two heads are kept as one piece.
  testWidgets('a head handed a row of another face is built again — it wears '
      'the next cut\'s colour label', (tester) async {
    const label = LayerMark(process: LayerProcess.key);
    final session = await pumpPanel(tester, film(bCameraMark: label));
    final before = rowsNow(tester);

    session.selectCut(const CutId('b'));
    await tester.pump();

    expectRowsAsThey(
      tester,
      before,
      builtAgain: {'camera', 'camera wrapper'},
    );
    expect(
      tester.widget<TimelineLayerControlsRow>(headIn(cameraLabel)).layer.mark,
      label,
    );
  });

  /// ↩️It was pinned the other way — 「an S row's layer edited is its label
  /// built again — the eye it shows」 — while the S row was a label of this
  /// rail's own, kept while its layer's eye held. It is the timeline's row
  /// now (I-89 ①), kept by its FACE as every head is: the eye rides past
  /// the keep ([RailEyes]), so a flip builds the eye alone (I-19).
  testWidgets('🚨an S row shows its eye as it flips — the eye is no part of '
      'the face it is kept by, as on the timeline', (tester) async {
    final session = await pumpPanel(tester, film());
    final before = rowsNow(tester);
    expect(eyeOn(tester, seLabel), isTrue, reason: 'premise');

    SessionRowButtonPresses(
      session,
    ).toggleVisibility(const LayerId('t1-s1'));
    await tester.pump();

    expectRowsAsThey(tester, before);
    expect(eyeOn(tester, seLabel), isFalse);
  });

  /// [project]'s tracks, each as [edit] makes it.
  Project editTracks(Project project, Track Function(Track track) edit) =>
      project.copyWith(
        tracks: [for (final track in project.tracks) edit(track)],
      );

  testWidgets('an S row\'s layer given another face is its row built again '
      '— the name it shows', (tester) async {
    final session = await pumpPanel(tester, film());
    final before = rowsNow(tester);

    session.repository.updateProject(
      (project) => editTracks(
        project,
        (track) => track.copyWith(
          seLayers: [
            for (final row in track.seLayers) row.copyWith(name: 'Rain'),
          ],
        ),
      ),
    );
    session.notifyChanged();
    await tester.pump();

    expectRowsAsThey(tester, before, builtAgain: {'se', 'se wrapper'});
    expect(railLabelName(seLabel, 'Rain'), findsOneWidget);
  });

  testWidgets('🚨an S row added over S1 builds S1\'s wrapper again, its caret '
      'at the slot it stands at now', (tester) async {
    final session = await pumpPanel(tester, film());
    expect(wrapper(tester, seLabel).slotBefore, 0, reason: 'premise');

    session.repository.updateProject(
      (project) => editTracks(
        project,
        (track) => track.copyWith(seLayers: [...track.seLayers, seLayer(2)]),
      ),
    );
    session.notifyChanged();
    await tester.pump();

    expect(wrapper(tester, seLabel).slotBefore, 1);
  });

  testWidgets('🚨an S row handed another row of the same face is built '
      'again — its switches press the row it shows now', (tester) async {
    // Two S rows that show the same: only which row each is tells them
    // apart, and the label names its switches by it.
    final session = await pumpPanel(
      tester,
      editTracks(
        film(seRows: 2),
        (track) => track.copyWith(
          seLayers: [
            for (final row in track.seLayers) row.copyWith(name: 'S'),
          ],
        ),
      ),
    );
    String eyeName() => tester
        .widget<LayerVisibilityToggleButton>(
          find.descendant(
            of: seLabel,
            matching: find.byType(LayerVisibilityToggleButton),
          ),
        )
        .name;
    expect(eyeName(), 'storyboard-layer-visibility-t1-s1', reason: 'premise');

    session.repository.updateProject(
      (project) => editTracks(
        project,
        (track) => track.copyWith(seLayers: track.seLayers.reversed.toList()),
      ),
    );
    session.notifyChanged();
    await tester.pump();

    expect(eyeName(), 'storyboard-layer-visibility-t1-s2');
  });

  testWidgets('🚨the V row\'s wrapper takes its group\'s height as an S row '
      'opens its lanes', (tester) async {
    await pumpPanel(tester, film());
    final closed = wrapper(tester, vLabel).rowExtent;

    await tester.tap(
      find.descendant(of: seLabel, matching: find.byType(LayerFoldTwirl)),
    );
    await tester.pump();

    expect(wrapper(tester, vLabel).rowExtent, greaterThan(closed));
  });

  /// ↩️A conte row's grip was pinned beside it: a's conte renamed while b's
  /// head was kept. F-343 makes that rename the seat's in every cut, so the
  /// head says the new name and is built again — no conte row is kept while
  /// its grip would name another.
  testWidgets('🚨a kept S row\'s grip names the rows it carries as the track '
      'holds them at the press', (tester) async {
    final session = await pumpPanel(tester, film(seRows: 2));
    session.rowSelection.value = [
      const LayerRowAddress(LayerId('t1-s1')),
      const LayerRowAddress(LayerId('t1-s2')),
    ];
    await tester.pump();
    final before = wrapper(tester, seLabel);
    // S2 is renamed: S1 shows nothing new and is kept.
    session.repository.updateProject(
      (project) => editTracks(
        project,
        (track) => track.copyWith(
          seLayers: [
            for (final layer in track.seLayers)
              if (layer.id == const LayerId('t1-s2'))
                layer.copyWith(name: 'Rain')
              else
                layer,
          ],
        ),
      ),
    );
    session.notifyChanged();
    await tester.pump();
    expect(
      wrapper(tester, seLabel),
      same(before),
      reason: 'premise: S1 is kept',
    );

    expect([
      for (final chip in before.grip!()) chip.label,
    ], unorderedEquals(['S1', 'Rain']));
  });

  testWidgets('🚨a solo the session answers is what the S row\'s speaker '
      'shows — no part of its layer', (tester) async {
    final session = await pumpPanel(tester, film());
    final speaker = find.named('storyboard-layer-mute-t1-s1');
    bool soloed() =>
        (tester.widget<RailGlyphButton>(speaker).glyph as RailIconGlyph)
            .color ==
        Theme.of(tester.element(speaker)).colorScheme.primary;
    expect(soloed(), isFalse, reason: 'premise');

    session.visibilitySolo.toggleLayerSolo(const LayerId('t1-s1'));
    await tester.pump();

    expect(soloed(), isTrue);
  });

  testWidgets('the V row\'s fx switch shows the track\'s fx as the session '
      'answers it', (tester) async {
    final session = await pumpPanel(tester, film());
    LayerFxState shown() => tester
        .widget<FxToggleButton>(
          find.ancestor(
            of: find.named('storyboard-track-fx-t1'),
            matching: find.byType(FxToggleButton),
          ),
        )
        .state;
    expect(shown(), LayerFxState.on, reason: 'premise');

    session.effectsAndFx.toggleTrackFx(trackId);
    await tester.pump();

    expect(shown(), LayerFxState.off);
  });

  testWidgets('the S row\'s fx switch shows its layer\'s fx as the session '
      'answers it', (tester) async {
    final session = await pumpPanel(tester, film());
    LayerFxState shown() => tester
        .widget<FxToggleButton>(
          find.ancestor(
            of: find.named('storyboard-layer-fx-t1-s1'),
            matching: find.byType(FxToggleButton),
          ),
        )
        .state;
    expect(shown(), LayerFxState.on, reason: 'premise');

    session.effectsAndFx.toggleLayerFx(const LayerId('t1-s1'));
    await tester.pump();

    expect(shown(), LayerFxState.off);
  });

  testWidgets('the camera head\'s fx switch shows its camera\'s fx as the '
      'session answers it', (tester) async {
    final session = await pumpPanel(tester, film());
    LayerFxState shown() => tester
        .widget<FxToggleButton>(
          find.descendant(
            of: cameraLabel,
            matching: find.byType(FxToggleButton),
          ),
        )
        .state;
    expect(shown(), LayerFxState.on, reason: 'premise');

    session.effectsAndFx.toggleLayerFx(const LayerId('a-cam'));
    await tester.pump();

    expect(shown(), LayerFxState.off);
  });

  testWidgets('🚨a kept head\'s twirl turns the row as the track holds it at '
      'the press, never as it was when the head was built', (tester) async {
    final turned = <LayerId>[];
    final session = await pumpPanel(tester, film(), turned: turned);
    session.selectCut(const CutId('b'));
    await tester.pump();
    final before = tester.widget(headIn(conteLabel));
    // a's conte goes: the head — b's — shows nothing new and is kept.
    session.repository.updateProject(
      (project) => project.copyWith(
        tracks: [
          for (final track in project.tracks)
            track.copyWith(
              cuts: [
                for (final cut in track.cuts)
                  if (cut.id == const CutId('a'))
                    cut.copyWith(
                      layers: [
                        for (final layer in cut.layers)
                          if (layer.id != const LayerId('a-conte')) layer,
                      ],
                    )
                  else
                    cut,
              ],
            ),
        ],
      ),
    );
    session.notifyChanged();
    await tester.pump();
    expect(
      tester.widget(headIn(conteLabel)),
      same(before),
      reason: 'premise: the head is kept',
    );

    await tester.tap(
      find.descendant(of: conteLabel, matching: find.byType(LayerFoldTwirl)),
    );
    await tester.pump();

    expect(turned, [const LayerId('b-conte')]);
  });

  testWidgets('🚨the camera head\'s twirl too: the cameras it shuts are the '
      'track\'s at the press', (tester) async {
    final turned = <LayerId>[];
    // Both cameras' lanes open — each opened on the timeline, in its cut.
    final session = await pumpPanel(
      tester,
      film(),
      turned: turned,
      openLanes: {const LayerId('a-cam'), const LayerId('b-cam')},
    );
    session.selectCut(const CutId('b'));
    await tester.pump();
    final before = tester.widget(headIn(cameraLabel));
    // Cut a goes: the head — b's camera, its lanes still open — shows
    // nothing new and is kept.
    session.repository.updateProject(
      (project) => project.copyWith(
        tracks: [
          for (final track in project.tracks)
            track.copyWith(
              cuts: [
                for (final cut in track.cuts)
                  if (cut.id != const CutId('a')) cut,
              ],
            ),
        ],
      ),
    );
    session.notifyChanged();
    await tester.pump();
    expect(
      tester.widget(headIn(cameraLabel)),
      same(before),
      reason: 'premise: the head is kept',
    );

    await tester.tap(
      find.descendant(of: cameraLabel, matching: find.byType(LayerFoldTwirl)),
    );
    await tester.pump();

    expect(turned, [const LayerId('b-cam')]);
  });

  // 🧪What a kept row's wrapper is built from, field by field (the mutants
  // of 10-14): each pin changes ONE of them while the label shows nothing
  // new, so the label is kept and only that field can build the wrapper
  // again. The fields a label's own facts already carry — the S row's
  // layer, the transition row's, the camera row's name, the V row's index
  // (its name says it) — need none.

  /// [layer] on the sheet unless [off] names it — the same instance when it
  /// already stands so.
  Layer sheeted(Layer layer, Set<String> off) {
    final on = !off.contains(layer.id.value);
    return layer.onTimesheet == on ? layer : layer.copyWith(onTimesheet: on);
  }

  /// [project] with the rows [off] names off the sheet and every other row
  /// on it — each row that already stands so kept as it was.
  Project sheetedOff(Project project, Set<String> off) => editTracks(
    project,
    (track) => track.copyWith(
      seLayers: [for (final layer in track.seLayers) sheeted(layer, off)],
      cuts: [
        for (final cut in track.cuts)
          cut.copyWith(
            layers: [for (final layer in cut.layers) sheeted(layer, off)],
          ),
      ],
    ),
  );

  /// The legend's filter that shows the rows on the sheet.
  const onTheSheet = TimelineRowFilter(onTimesheetOnly: true);

  Future<void> resheet(
    WidgetTester tester,
    EditorSessionManager session,
    Set<String> off,
  ) async {
    session.repository.updateProject((project) => sheetedOff(project, off));
    session.notifyChanged();
    await tester.pump();
  }

  testWidgets('🚨an S row the filter shows somewhere else builds its wrapper '
      'again — its caret at the slot it shows at, last or not as it is', (
    tester,
  ) async {
    final session = await pumpPanel(
      tester,
      sheetedOff(film(seRows: 3), {'t1-s1'}),
      rowFilter: onTheSheet,
    );
    final s2 = key('storyboard-se-label-t1-2');
    // S3 over S2: S2 the lower of the two shown.
    expect(wrapper(tester, s2).slotBefore, 1, reason: 'premise');
    expect(wrapper(tester, s2).drawsTheGapAfter, isTrue, reason: 'premise');

    // S2 over S1: the upper of two.
    await resheet(tester, session, {'t1-s3'});
    expect(wrapper(tester, s2).slotBefore, 0);
    expect(wrapper(tester, s2).drawsTheGapAfter, isFalse);

    // S2 alone: the upper, and the last.
    await resheet(tester, session, {'t1-s1', 't1-s3'});
    expect(wrapper(tester, s2).slotBefore, 0);
    expect(wrapper(tester, s2).drawsTheGapAfter, isTrue);
  });

  /// Turns cut a's conte rows [off] the sheet and the others on, as their
  /// head's switch does: a conte row's flag is its head's, one for every cut
  /// (I-89-Q22), so it is written through the session's verb, which lays it
  /// on the cut b rows of the same seats too.
  Future<void> resheetConte(
    WidgetTester tester,
    EditorSessionManager session,
    Set<String> off,
  ) async {
    for (final id in const ['a-conte', 'a-conte+1', 'a-conte+2']) {
      final row = LayerId(id);
      if (session.layerSwitches.isLayerOnTimesheet(row) == off.contains(id)) {
        session.layerSwitches.toggleLayerTimesheet(row);
      }
    }
    await tester.pump();
  }

  testWidgets('🚨a conte row the filter shows somewhere else builds its '
      'wrapper again — its caret at the seat it shows at, last or not as it '
      'is', (tester) async {
    final session = await pumpPanel(
      tester,
      film(attachRows: 2),
      rowFilter: onTheSheet,
    );
    await resheetConte(tester, session, {'a-conte'});
    final seat1 = key('storyboard-conte+1-label-t1');
    // +2 over +1: +1 the lower of the two shown.
    expect(wrapper(tester, seat1).slotBefore, 1, reason: 'premise');
    expect(wrapper(tester, seat1).drawsTheGapAfter, isTrue, reason: 'premise');

    // +1 over the conte: the upper of two.
    await resheetConte(tester, session, {'a-conte+2'});
    expect(wrapper(tester, seat1).slotBefore, 0);
    expect(wrapper(tester, seat1).drawsTheGapAfter, isFalse);

    // +1 alone: the upper, and the last.
    await resheetConte(tester, session, {'a-conte', 'a-conte+2'});
    expect(wrapper(tester, seat1).slotBefore, 0);
    expect(wrapper(tester, seat1).drawsTheGapAfter, isTrue);
  });

  /// The twirl that opens the Transform group of the lanes now open.
  final transformGroupTwirl = find.byWidgetPredicate(
    (widget) =>
        widget is LayerFoldTwirl &&
        widget.name.endsWith('-transform-group'),
  );

  /// ↩️It read the S row's label itself, kept whole while its wrapper was
  /// built again. The label is the timeline's row now (I-89 ①), made anew
  /// with the wrapper and keeping what it built while its face holds — the
  /// head, as the conte row's twin below reads it.
  testWidgets('🚨an S row\'s wrapper takes its group\'s height as a group of '
      'its lanes twirls open — its head as it was', (tester) async {
    await pumpPanel(tester, film());
    await tester.tap(
      find.descendant(of: seLabel, matching: find.byType(LayerFoldTwirl)),
    );
    await tester.pump();
    final head = tester.widget(headIn(seLabel));
    final open = wrapper(tester, seLabel).rowExtent;

    await tester.tap(transformGroupTwirl.first);
    await tester.pump();

    expect(tester.widget(headIn(seLabel)), same(head), reason: 'kept');
    expect(wrapper(tester, seLabel).rowExtent, greaterThan(open));
  });

  testWidgets('🚨a conte row\'s wrapper takes its group\'s height as a group '
      'of its lanes twirls open — its head as it was', (tester) async {
    // The host's set, which it turns in place as its twirl is pressed.
    final groups = <String>{};
    final session = await pumpPanel(
      tester,
      film(),
      openLanes: {const LayerId('a-conte')},
      openGroups: groups,
    );
    final head = tester.widget(headIn(conteLabel));
    final open = wrapper(tester, conteLabel).rowExtent;

    groups.add(laneGroupKey(const LayerId('a-conte'), 'transform-group'));
    session.notifyChanged();
    await tester.pump();

    expect(tester.widget(headIn(conteLabel)), same(head), reason: 'kept');
    expect(wrapper(tester, conteLabel).rowExtent, greaterThan(open));
  });

  /// [film] with a second track, t2, of one cut — 'c'.
  Project twoTracks() {
    final one = film();
    return one.copyWith(
      tracks: [
        ...one.tracks,
        Track(id: const TrackId('t2'), name: 'V2', cuts: [cutOf('c')]),
      ],
    );
  }

  testWidgets('🚨a V row\'s wrapper is built again as a track is added under '
      'it — it is not the last row any more', (tester) async {
    final session = await pumpPanel(tester, twoTracks());
    final v2 = key('storyboard-track-select-t2');
    expect(wrapper(tester, v2).drawsTheGapAfter, isTrue, reason: 'premise');

    session.repository.updateProject(
      (project) => project.copyWith(
        tracks: [
          ...project.tracks,
          Track(id: const TrackId('t3'), name: 'V3', cuts: [cutOf('d')]),
        ],
      ),
    );
    session.notifyChanged();
    await tester.pump();

    expect(wrapper(tester, v2).drawsTheGapAfter, isFalse);
  });

  testWidgets('🚨a V row its tracks can re-order takes its group\'s height '
      'as a group of its own lanes twirls open — its label as it was', (
    tester,
  ) async {
    // Its own lanes run BELOW it: the group grows, the part above it — the
    // grip's offset, which an S row's lanes move as well — does not.
    final two = twoTracks();
    await pumpPanel(
      tester,
      editTracks(
        two,
        (track) => track.id == trackId
            ? track.copyWith(
                effects: [
                  LayerEffect.defaults(
                    id: const EffectId('fx-a'),
                    kind: EffectKind.blur,
                  ),
                ],
              )
            : track,
      ),
    );
    await tester.tap(find.named('storyboard-track-lane-toggle-t1'));
    await tester.pump();
    final label = tester.widget(vLabel);
    final open = wrapper(tester, vLabel).rowExtent;

    await tester.tap(
      find.named('storyboard-lane-group-toggle-v-track:t1-fx-group:fx-a'),
    );
    await tester.pump();

    expect(tester.widget(vLabel), same(label), reason: 'premise: kept');
    expect(wrapper(tester, vLabel).rowExtent, greaterThan(open));
  });

  /// Hooks hearing every move a row's drag makes: the rows it was handed,
  /// by name.
  TimelineRowDragHooks hooksHearing(List<List<String>> moves) =>
      TimelineRowDragHooks(
        drag: ValueNotifier<LayerRowDragState?>(null),
        onBegin: (_) {},
        onRowTarget: (_, _, _) {},
        onUpdate: (rows, slot, {pointerInRow}) =>
            moves.add([for (final row in rows) row.name]),
        onTrackUpdate: (_) {},
        onEffectUpdate: (_, _, _) {},
        onEnd: () {},
        onCancel: () {},
      );

  /// The panel alone, built by a host that hands it what [host] holds — the
  /// film, the hooks, whether it wires a span and whether the V rows'
  /// lanes resize — and built again as [host] changes.
  Future<void> pumpBare(
    WidgetTester tester,
    ValueNotifier<_BareHost> host,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: host,
            builder: (context, now, _) => StoryboardPanel(
              project: now.film,
              activeCutId: const CutId('a'),
              pixelsPerFrame: 12,
              projectFrameRate: ProjectFrameRate.fps24,
              poseDisplaySize: const CanvasSize(width: 640, height: 360),
              rowDragHooks: now.hooks,
              onRowSelectionSpan: now.span ? (_, _) {} : null,
              onResizeTrackLanes: now.resize ? (delta) => delta : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('🚨a row\'s wrapper is built again for the hooks its host hands '
      'it now, and for a span it no longer wires', (tester) async {
    final f = film();
    final first = hooksHearing([]);
    final host = ValueNotifier<_BareHost>(
      (film: f, hooks: first, span: true, resize: false),
    );
    addTearDown(host.dispose);
    await pumpBare(tester, host);
    expect(wrapper(tester, seLabel).hooks, same(first), reason: 'premise');
    expect(
      wrapper(tester, seLabel).onSelectCrossed,
      isNotNull,
      reason: 'premise',
    );

    final second = hooksHearing([]);
    host.value = (film: f, hooks: second, span: true, resize: false);
    await tester.pump();
    expect(wrapper(tester, seLabel).hooks, same(second));

    host.value = (film: f, hooks: second, span: false, resize: false);
    await tester.pump();
    expect(wrapper(tester, seLabel).onSelectCrossed, isNull);
  });

  testWidgets('🚨a V row its tracks can re-order wears the lane splitter '
      'its host offers now', (tester) async {
    final two = twoTracks();
    final hooks = hooksHearing([]);
    final host = ValueNotifier<_BareHost>(
      (film: two, hooks: hooks, span: true, resize: false),
    );
    addTearDown(host.dispose);
    await pumpBare(tester, host);
    final splitter = key('storyboard-track-lane-splitter-t1');
    expect(splitter, findsNothing, reason: 'premise');

    host.value = (film: two, hooks: hooks, span: true, resize: true);
    await tester.pump();

    expect(splitter, findsOneWidget);
  });

  testWidgets('🚨a kept S row\'s drag moves it among the rows as the track '
      'holds them at the move', (tester) async {
    final moves = <List<String>>[];
    final hooks = hooksHearing(moves);
    final before = film(seRows: 2);
    final host = ValueNotifier<_BareHost>(
      (film: before, hooks: hooks, span: true, resize: false),
    );
    addTearDown(host.dispose);
    await pumpBare(tester, host);
    final kept = wrapper(tester, seLabel);
    // S2 is renamed: S1 shows nothing new and is kept.
    host.value = (
      film: editTracks(
        before,
        (track) => track.copyWith(
          seLayers: [
            for (final layer in track.seLayers)
              if (layer.id == const LayerId('t1-s2'))
                layer.copyWith(name: 'Rain')
              else
                layer,
          ],
        ),
      ),
      hooks: hooks,
      span: true,
      resize: false,
    );
    await tester.pump();
    expect(wrapper(tester, seLabel), same(kept), reason: 'premise: kept');

    kept.onCrossed(-1, null, 0);

    expect(moves.single, ['Rain', 'S1']);
  });
}

/// What [pumpBare]'s host hands the panel.
typedef _BareHost = ({
  Project film,
  TimelineRowDragHooks hooks,
  bool span,
  bool resize,
});

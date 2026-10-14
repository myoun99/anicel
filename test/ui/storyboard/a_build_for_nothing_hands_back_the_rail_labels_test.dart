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
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_row_button_presses.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show FxToggleButton, LayerMuteToggleButton, LayerVisibilityToggleButton;
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart'
    show LayerFoldTwirl;
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';

import '../../helpers/named_finders.dart';

/// 🚨I-57 (10-14): A STORYBOARD BUILT AGAIN FOR NOTHING — OR ACROSS A CUT —
/// HANDS BACK EVERY LABEL OF ITS RAIL AS IT WAS, and builds one again the
/// moment what it shows changes.
///
/// Its host builds it again on every notify it hears — a cut crossed under
/// the playhead among them — and every label of the rail was built again
/// with it: 🔬953 of a crossing's 1,088 widget rebuilds on the AMMI OP, the
/// heads (the timeline's own rows) 464 of them. A head is kept by its FACE,
/// as the timeline's rail keeps its rows: a crossing that hands it the next
/// cut's row of the same face hands it back whole, wearing the row it has
/// in hand now.
void main() {
  const trackId = TrackId('t1');

  Layer conte(String cut, {String name = 'Conte', bool visible = true}) =>
      Layer(
        id: LayerId('$cut-conte'),
        name: name,
        kind: LayerKind.storyboard,
        isVisible: visible,
        frames: [
          Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
        },
      );

  Cut cutOf(String id, {Layer? conteLayer, Layer? folder}) => Cut(
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
        frames: const [],
      ),
      ?folder,
      ?conteLayer,
    ],
  );

  /// Cuts a and b, each with a camera and a conte of the same face — b's
  /// conte as [bConte] makes it, beside [bFolder] where given — on one
  /// track with an S row.
  Project film({Layer? bConte, Layer? bFolder}) => Project(
    id: const ProjectId('rail-labels'),
    name: 'Rail labels',
    createdAt: DateTime.utc(2026, 10, 14),
    tracks: [
      Track(
        id: trackId,
        name: 'V1',
        seLayers: [
          Layer(
            id: const LayerId('t1-s1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: const [],
          ),
        ],
        cuts: [
          cutOf('a', conteLayer: conte('a')),
          cutOf('b', conteLayer: bConte ?? conte('b'), folder: bFolder),
        ],
      ),
    ],
  );

  /// The tab as the workspace mounts it, on [project]: built again on every
  /// notify the session makes — and on the camera VIEW [cameraView], which
  /// is none. [turned] hears every lane twirl the rail turns; [openLanes]
  /// are the layers whose lanes stand open.
  Future<EditorSessionManager> pumpPanel(
    WidgetTester tester,
    Project project, {
    ValueNotifier<bool>? cameraView,
    List<LayerId>? turned,
    Set<LayerId> openLanes = const {},
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnails: null,
              rowFilter: TimelineRowFilter.none,
              cameraViewEnabled: cameraView,
              expandedLaneLayerIds: openLanes,
              onToggleLayerLanes: turned?.add,
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

  Finder headIn(Finder label) => find.descendant(
    of: label,
    matching: find.byType(TimelineLayerControlsRow),
  );

  /// Every label of the rail, as it is built: the S row's, the transition
  /// row's and the V row's, and the two heads.
  Map<String, Widget> labelsNow(WidgetTester tester) => {
    'se': tester.widget(seLabel),
    'transition': tester.widget(key('storyboard-transition-label-t1')),
    'v': tester.widget(key('storyboard-track-select-t1')),
    'camera': tester.widget(headIn(cameraLabel)),
    'conte': tester.widget(headIn(conteLabel)),
  };

  void expectLabelsAsThey(
    WidgetTester tester,
    Map<String, Widget> before, {
    Set<String> builtAgain = const {},
  }) {
    for (final MapEntry(:key, value: label) in labelsNow(tester).entries) {
      expect(
        label,
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

  testWidgets('built again for nothing, every label of its rail is the label '
      'it had', (tester) async {
    final session = await pumpPanel(tester, film());
    final before = labelsNow(tester);

    session.notifyChanged();
    await tester.pump();

    expectLabelsAsThey(tester, before);
  });

  testWidgets('🚨a cut crossed builds no label of the rail — each head wears '
      'the next cut\'s row of the same face', (tester) async {
    final session = await pumpPanel(tester, film());
    expect(session.activeCutId, const CutId('a'), reason: 'premise');
    final before = labelsNow(tester);

    session.selectCut(const CutId('b'));
    await tester.pump();

    expectLabelsAsThey(tester, before);
  });

  testWidgets('🚨a head kept across a cut shows the eye of the row it wears '
      'now', (tester) async {
    final session = await pumpPanel(
      tester,
      film(bConte: conte('b', visible: false)),
    );
    final before = tester.widget(headIn(conteLabel));
    expect(eyeOn(tester, conteLabel), isTrue, reason: 'premise: a\'s eye');

    session.selectCut(const CutId('b'));
    await tester.pump();

    expect(tester.widget(headIn(conteLabel)), same(before));
    expect(eyeOn(tester, conteLabel), isFalse);
  });

  testWidgets('🚨the camera head shows the VIEW as it flips — the view is no '
      'part of the face it is kept by', (tester) async {
    final view = ValueNotifier<bool>(true);
    addTearDown(view.dispose);
    await pumpPanel(tester, film(), cameraView: view);
    expect(eyeOn(tester, cameraLabel), isTrue, reason: 'premise');

    view.value = false;
    await tester.pump();

    expect(eyeOn(tester, cameraLabel), isFalse);
  });

  testWidgets('🚨a head wears the eye its row has on the timeline: a folder '
      'above that hides the row dims it (F-185)', (tester) async {
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
    expect(eye().hiddenAbove, isFalse, reason: 'premise: a\'s conte');

    session.selectCut(const CutId('b'));
    await tester.pump();

    expect(eye().hiddenAbove, isTrue);
    expect(eye().isVisible, isTrue, reason: 'its own switch keeps its value');
  });

  testWidgets('a head handed a row of another face is built again — it says '
      'the next cut\'s name', (tester) async {
    final session = await pumpPanel(
      tester,
      film(bConte: conte('b', name: 'Layout')),
    );
    final before = labelsNow(tester);

    session.selectCut(const CutId('b'));
    await tester.pump();

    expectLabelsAsThey(tester, before, builtAgain: {'conte'});
    expect(
      find.descendant(of: conteLabel, matching: find.text('Layout')),
      findsOneWidget,
    );
  });

  testWidgets('an S row\'s layer edited is its label built again — the eye '
      'it shows', (tester) async {
    final session = await pumpPanel(tester, film());
    final before = labelsNow(tester);
    expect(eyeOn(tester, seLabel), isTrue, reason: 'premise');

    SessionRowButtonPresses(
      session,
    ).toggleVisibility(const LayerId('t1-s1'));
    await tester.pump();

    expectLabelsAsThey(tester, before, builtAgain: {'se'});
    expect(eyeOn(tester, seLabel), isFalse);
  });

  testWidgets('🚨a solo the session answers is what the S row\'s speaker '
      'shows — no part of its layer', (tester) async {
    final session = await pumpPanel(tester, film());
    bool soloed() => tester
        .widget<LayerMuteToggleButton>(
          find.descendant(
            of: seLabel,
            matching: find.byType(LayerMuteToggleButton),
          ),
        )
        .soloed;
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
}

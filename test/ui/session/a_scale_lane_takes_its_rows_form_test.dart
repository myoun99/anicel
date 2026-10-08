import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/lane_verbs.dart';
import 'package:anicel/src/ui/text/app_strings.dart' show AppText;
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/session_lane_callbacks.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_provider.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// A ROW'S SCALE LANE TAKES THE ROW'S FORM, from the rail's print to the key
/// the verb writes (`transform-fx-scale-x-y`, stage three).
///
/// 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y(마이너스 =
/// 반전)」 · 「카메라는 줌 하나 그대로」.
/// 🗣️`transform-fx-scale-x-y-Q1` (유저 2026-10-07): 「Scale 행에 사슬 버튼 —
/// 변형 도구의 「배율 연동」과 한 스위치」.
///
/// The form's own arithmetic is `scale_lane_form_test`. This half pins who
/// asks it: the lane list that prints, the verb that writes, and the lane
/// callbacks that read the tool's switch.
///
/// The collaborator the law lives in — named so `tool/mutation_run.dart`
/// runs this file for it.
LaneVerbs laneVerbsOf(EditorSessionManager session) => session.laneVerbs;

void main() {
  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    return session;
  }

  Layer cameraOf(EditorSessionManager session) => session
      .requireActiveCut
      .layers
      .firstWhere((layer) => layer.kind == LayerKind.camera);

  /// The Scale lane the rail builds for [row], its group twirled open.
  PropertyLaneRow scaleLaneOf(EditorSessionManager session, Layer row) =>
      timelineLanesForLayer(
        layer: session.layerById(row.id)!,
        session: session,
        expandedGroupKeys: {
          laneGroupKey(row.id, transformGroupHeaderLane.laneId),
        },
      ).singleWhere((lane) => lane.laneId == 'scale');

  CanvasPoint? scaleKeyOf(EditorSessionManager session, Layer row) => session
      .requireActiveCut
      .layers
      .byId(row.id)!
      .transformTrack
      .scale
      .keyAt(0)
      ?.value;

  void set(
    EditorSessionManager session,
    Layer row,
    String input, {
    required bool linked,
  }) => laneVerbsOf(session).setLaneValueAt(
    row.id,
    'scale',
    0,
    input,
    frameIsGlobal: false,
    description: 'Set Scale',
    scaleLinked: linked,
  );

  group('the rail prints', () {
    test("a layer's Scale as two numbers and the camera's as one", () {
      final session = open();

      expect(
        scaleLaneOf(session, session.activeLayer!).valueLabel!(0),
        '100, 100%',
      );
      expect(scaleLaneOf(session, cameraOf(session)).valueLabel!(0), '100%');
    });

    test('what a layer was keyed to, each number its own', () {
      final session = open();
      final row = session.activeLayer!;

      set(session, row, '150, -80%', linked: false);

      expect(scaleLaneOf(session, row).valueLabel!(0), '150, -80%');
    });

    test('and scrubs each in the form it prints', () {
      final session = open();
      const drag = Offset(20, 0);

      expect(
        scaleLaneOf(session, session.activeLayer!).scrubValue!(
          '100, 100%',
          drag,
        ),
        '110, 100%',
      );
      expect(
        scaleLaneOf(session, cameraOf(session)).scrubValue!('100%', drag),
        '110%',
      );
    });
  });

  group('the verb writes', () {
    test("a layer's two numbers as its two scales", () {
      final session = open();
      final row = session.activeLayer!;

      set(session, row, '150, -80%', linked: false);

      expect(scaleKeyOf(session, row), CanvasPoint(x: 1.5, y: -0.8));
    });

    test('🔗linked, the number left as shown by the step of the other — '
        'and unlinked, as it was typed', () {
      final session = open();
      final row = session.activeLayer!;
      set(session, row, '150, -80%', linked: false);

      set(session, row, '300, -80%', linked: true);
      expect(scaleKeyOf(session, row), CanvasPoint(x: 3, y: -1.6));

      set(session, row, '150, -160%', linked: false);
      expect(scaleKeyOf(session, row), CanvasPoint(x: 1.5, y: -1.6));
    });

    test('🔗a scrub in flight shows the linked scale its release writes', () {
      final session = open();
      final row = session.activeLayer!;
      set(session, row, '150, 75%', linked: false);

      laneVerbsOf(session).previewLaneValueAt(
        row.id,
        'scale',
        0,
        '300, 75%',
        frameIsGlobal: false,
        scaleLinked: true,
      );

      final shown = session.dragPreview.value;
      expect(shown, isA<LaneEditPreview>());
      expect(
        (shown! as LaneEditPreview).row!.transformTrack.scale.keyAt(0)!.value,
        CanvasPoint(x: 3, y: 1.5),
      );
      expect(
        scaleKeyOf(session, row),
        CanvasPoint(x: 1.5, y: 0.75),
        reason: 'DISPLAY only',
      );
    });

    test("⛔two numbers are not a camera's zoom — and one is", () {
      final session = open();
      final camera = cameraOf(session);

      set(session, camera, '150, 80%', linked: false);
      expect(
        session.requireActiveCut.camera.isEmpty,
        isTrue,
        reason: 'the camera keeps one zoom: nothing was written',
      );

      set(session, camera, '150%', linked: true);
      expect(
        session.requireActiveCut.camera.track.scale.keyAt(0)!.value,
        uniformScale(1.5),
      );
    });
  });

  group("the lane callbacks read the transform tool's one switch", () {
    test('at the moment a value lands — on, off, and on again', () {
      final session = open();
      final row = session.activeLayer!;
      final options = ValueNotifier(TransformToolOptions.defaults);
      addTearDown(options.dispose);
      final laneEdit = sessionLaneEditCallbacks(
        session,
        frameIsGlobal: false,
        transformOptions: options,
      );
      void type(String input) =>
          laneEdit.onSetValue!(row, scaleLaneOf(session, row), 0, input);

      expect(options.value.scaleLinked, isTrue, reason: "the tool's default");
      type('200, 100%');
      expect(scaleKeyOf(session, row), uniformScale(2));

      options.value = options.value.copyWith(scaleLinked: false);
      type('100, 200%');
      expect(scaleKeyOf(session, row), CanvasPoint(x: 1, y: 2));

      options.value = options.value.copyWith(scaleLinked: true);
      type('100, 400%');
      expect(scaleKeyOf(session, row), CanvasPoint(x: 2, y: 4));
    });

    test('a scrub is shown by the same switch', () {
      final session = open();
      final row = session.activeLayer!;
      final options = ValueNotifier(TransformToolOptions.defaults);
      addTearDown(options.dispose);
      final laneEdit = sessionLaneEditCallbacks(
        session,
        frameIsGlobal: false,
        transformOptions: options,
      );
      CanvasPoint shownAfter(String input) {
        laneEdit.onPreviewValue!(row, scaleLaneOf(session, row), 0, input);
        final preview = session.dragPreview.value! as LaneEditPreview;
        return preview.row!.transformTrack.scale.keyAt(0)!.value;
      }

      expect(shownAfter('200, 100%'), uniformScale(2));

      options.value = options.value.copyWith(scaleLinked: false);
      expect(shownAfter('200, 100%'), CanvasPoint(x: 2, y: 1));
    });

    test("a rail with no tool beside it reads the tool's defaults", () {
      final session = open();
      final row = session.activeLayer!;
      final laneEdit = sessionLaneEditCallbacks(
        session,
        frameIsGlobal: false,
        transformOptions: null,
      );

      laneEdit.onSetValue!(row, scaleLaneOf(session, row), 0, '200, 100%');

      expect(
        scaleKeyOf(session, row),
        TransformToolOptions.defaults.scaleLinked
            ? uniformScale(2)
            : CanvasPoint(x: 2, y: 1),
      );
    });
  });

  group('the chain the rail hands its rows', () {
    test("is the transform tool's switch: it reads it, flips it alone, and "
        'says when it changed', () {
      final options = ValueNotifier(const TransformToolOptions(meshColumns: 5));
      addTearDown(options.dispose);
      final link = sessionLaneEditCallbacks(
        open(),
        frameIsGlobal: false,
        transformOptions: options,
      ).valueLink!;
      var changes = 0;
      link.changes.addListener(() => changes += 1);

      expect(link.isOn(), isTrue);
      expect(link.tooltip, AppText.strings.trScaleLink);

      link.toggle();
      expect(link.isOn(), isFalse);
      expect(
        options.value,
        const TransformToolOptions(meshColumns: 5, scaleLinked: false),
        reason: "its own field, and none of the tool's others",
      );
      expect(changes, 1);

      link.toggle();
      expect(options.value.scaleLinked, isTrue);
      expect(changes, 2);

      // Flipped from the tool's side, the chain reads the same field.
      options.value = options.value.copyWith(scaleLinked: false);
      expect(link.isOn(), isFalse);
    });

    test('a rail with no tool beside it has no chain to show', () {
      expect(
        sessionLaneEditCallbacks(
          open(),
          frameIsGlobal: false,
          transformOptions: null,
        ).valueLink,
        isNull,
      );
    });

    test("a layer's Scale lane wears it and the camera's does not", () {
      final session = open();

      expect(scaleLaneOf(session, session.activeLayer!).linkable, isTrue);
      expect(scaleLaneOf(session, cameraOf(session)).linkable, isFalse);
    });
  });
}

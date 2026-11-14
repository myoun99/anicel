import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_drop_policy.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_display_adapter.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// 🗣️F-538 (유저 2026-11-02): 「스샷과 같은 상황에서 선택한 레이어를 TAP레이어
/// 밑에 드래그로 움직이는게 불가능」 · 「반대로 TAP을 스샷 선택한레이어 위로
/// 올리는것도 불가. 액션란 양 끝? 해당 란 양 끝에 옮기는게 불가능한듯」.
///
/// The scene: two pictures ALONE in ACTION, the track's SE rows over them,
/// and in the STACK they stand across the camera section — a row is made
/// over the row stood on, whichever section that is. Every surface sorts
/// that out, so nothing on screen tells it; the drop policy read the stack
/// as it stood.
Layer _picture(String id, {LayerMark mark = LayerMark.none}) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.image,
  frames: const [],
  timeline: const {},
  mark: mark,
  mediaReference: MediaReference(
    assetPath: '/$id.png',
    pose: TransformPose(center: CanvasPoint(x: 320, y: 180)),
    pictureSize: const CanvasSize(width: 64, height: 36),
  ),
);

Layer _sound(String id) => Layer(
  id: LayerId(id),
  name: id,
  kind: LayerKind.se,
  frames: const [],
  timeline: const {},
);

final _direction = Layer(
  id: const LayerId('direction'),
  name: 'Direction',
  kind: LayerKind.instruction,
  frames: const [],
);

final _camera = Layer(
  id: const LayerId('cam'),
  name: 'Camera',
  kind: LayerKind.camera,
  frames: const [],
);

/// [pictures] in the stack where a scene puts them.
typedef _Scene = List<Layer> Function(List<Layer> pictures);

final _scenes = <String, _Scene>{
  'over the camera rows': (pictures) => [_direction, _camera, ...pictures],
  'between the camera rows': (pictures) => [_direction, ...pictures, _camera],
};

final _two = [
  _picture('tap', mark: const LayerMark.paper(LayerProcess.layout)),
  _picture('csm'),
];

Project _project(List<Layer> layers) => Project(
  id: const ProjectId('ends'),
  name: 'Ends',
  createdAt: DateTime.utc(2026, 11, 2),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video Track',
      seLayers: [_sound('s1'), _sound('s2')],
      cuts: [
        Cut(
          id: const CutId('cut'),
          name: 'Cut',
          duration: 12,
          canvasSize: const CanvasSize(width: 1280, height: 720),
          camera: CutCamera.empty(),
          layers: layers,
        ),
      ],
    ),
  ],
);

List<String> _pictures(EditorSessionManager session) => [
  for (final layer in session.requireActiveCut.layers)
    if (layer.kind == LayerKind.image) layer.id.value,
];

Layer _layerOf(EditorSessionManager session, String id) => session
    .requireActiveCut
    .layers
    .firstWhere((layer) => layer.id == LayerId(id));

void main() {
  final carets = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'timeline-row-caret-',
        ),
  );

  List<Key?> caretsUp() => [
    for (final caret in carets.evaluate()) caret.widget.key,
  ];

  /// [id], selected and held at its name.
  Future<({TestGesture gesture, double dx})> lift(
    WidgetTester tester,
    String id,
  ) async {
    final grip = find.named('timeline-layer-name-$id');
    await tester.ensureVisible(grip);
    await tester.pumpAndSettle();
    await tester.drag(grip, const Offset(30, 0));
    await tester.pumpAndSettle();
    final at = Offset(
      tester.getCenter(grip).dx,
      tester.getCenter(find.named('timeline-layer-row-$id')).dy,
    );
    final gesture = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 16));
    return (gesture: gesture, dx: at.dx);
  }

  Future<void> pointInto(
    WidgetTester tester,
    ({TestGesture gesture, double dx}) held,
    String into, {
    required double fraction,
  }) async {
    final row = tester.getRect(find.named('timeline-layer-row-$into'));
    await held.gesture.moveTo(
      Offset(held.dx, row.top + row.height * fraction),
    );
    await tester.pump();
  }

  test('⛔전제: a row made standing on the camera row stands over it in the '
      'stack, and the rail shows it under it', () {
    final session = EditorSessionManager(
      initialProject: _project([_direction, _camera]),
    );
    addTearDown(session.dispose);
    session.selectLayer(_camera.id);

    session.layerStack.addLayerOfKind(LayerKind.image);

    final stack = session.requireActiveCut.layers;
    expect([for (final layer in stack) layer.kind], [
      LayerKind.instruction,
      LayerKind.camera,
      LayerKind.image,
    ]);
    expect(horizontalLayerDisplayOrder(stack).last.kind, LayerKind.image);
  });

  for (final MapEntry(key: where, value: scene) in _scenes.entries) {
    group('pictures $where in the stack', () {
      final stack = scene(_two);

      Future<EditorSessionManager> pump(WidgetTester tester) =>
          pumpTimelineHost(
            tester,
            _project(stack),
            surface: const Size(790, 446),
          );

      group('the rail', () {
        testWidgets('🎯the top row of ACTION carried past the last row lands '
            'at its foot', (tester) async {
          final session = await pump(tester);
          final held = await lift(tester, 'csm');

          await pointInto(tester, held, 'tap', fraction: 0.85);
          expect(caretsUp(), [
            const ValueKey<String>('timeline-row-caret-after-tap'),
          ]);
          await pointInto(tester, held, 'tap', fraction: 2);
          expect(caretsUp(), [
            const ValueKey<String>('timeline-row-caret-after-tap'),
          ]);
          await held.gesture.up();
          await tester.pumpAndSettle();

          expect(_pictures(session), ['csm', 'tap']);
        });

        testWidgets('🎯the last row of ACTION carried past the top row lands '
            'at its head', (tester) async {
          final session = await pump(tester);
          final held = await lift(tester, 'tap');

          await pointInto(tester, held, 'csm', fraction: 0.15);
          expect(caretsUp(), [
            const ValueKey<String>('timeline-row-caret-before-csm'),
          ]);
          await pointInto(tester, held, 'csm', fraction: -1);
          expect(caretsUp(), [
            const ValueKey<String>('timeline-row-caret-before-csm'),
          ]);
          await held.gesture.up();
          await tester.pumpAndSettle();

          expect(_pictures(session), ['csm', 'tap']);
        });

        testWidgets('a row still in its own place goes nowhere', (
          tester,
        ) async {
          final session = await pump(tester);
          final held = await lift(tester, 'csm');

          await pointInto(tester, held, 'csm', fraction: 0.85);
          expect(caretsUp(), isEmpty);
          await held.gesture.up();
          await tester.pumpAndSettle();

          expect(
            session.requireActiveCut.layers,
            stack,
            reason: 'no landing, so nothing is written',
          );
        });

        testWidgets('🎯carried up ON the row above it, a row rides that row '
            'from below', (tester) async {
          final session = await pump(tester);
          final held = await lift(tester, 'tap');

          await pointInto(tester, held, 'csm', fraction: 0.5);
          await held.gesture.up();
          await tester.pumpAndSettle();

          final tap = _layerOf(session, 'tap');
          expect(tap.attachedToLayerId, const LayerId('csm'));
          expect(tap.attachedPlacement, AttachedPlacement.below);
        });
      });

      group('the sheet', () {
        Future<EditorSessionManager> pumpSheet(WidgetTester tester) async {
          final session = await pump(tester);
          await tester.tap(
            find.byKey(
              const ValueKey<String>('timeline-orientation-toggle-button'),
            ),
          );
          await tester.pumpAndSettle();
          return session;
        }

        Future<void> carry(
          WidgetTester tester,
          String id,
          double columns,
        ) async {
          final grip = find.named('xsheet-layer-name-$id');
          await tester.ensureVisible(grip);
          await tester.pumpAndSettle();
          await tester.drag(grip, const Offset(0, 30));
          await tester.pumpAndSettle();
          final width = tester
              .getSize(find.named('xsheet-layer-row-$id'))
              .width;
          await tester.drag(grip, Offset(width * columns, 0));
          await tester.pumpAndSettle();
        }

        testWidgets('🎯the left column of ACTION carried past the right one '
            'lands at its far end', (tester) async {
          final session = await pumpSheet(tester);

          await carry(tester, 'tap', 1.5);

          expect(_pictures(session), ['csm', 'tap']);
        });

        testWidgets('🎯the right column carried past the left one lands '
            'first', (tester) async {
          final session = await pumpSheet(tester);

          await carry(tester, 'csm', -1.5);

          expect(_pictures(session), ['csm', 'tap']);
        });
      });

      test('🎯the menu: a rider let go steps out of its group, the camera '
          'rows in the stack or not', () {
        final session = EditorSessionManager(
          initialProject: _project(
            scene([
              _picture('far').copyWith(
                attachedToLayerId: const LayerId('base'),
                attachedPlacement: AttachedPlacement.below,
              ),
              _picture('near').copyWith(
                attachedToLayerId: const LayerId('base'),
                attachedPlacement: AttachedPlacement.below,
              ),
              _picture('base'),
            ]),
          ),
        );
        addTearDown(session.dispose);
        session.selectLayer(const LayerId('near'));

        session.folders.detachRows();

        expect(_layerOf(session, 'near').attachedToLayerId, isNull);
        expect(_pictures(session), ['near', 'far', 'base']);
      });

      test("🎯a file: each of ACTION's gaps lands where its line stands", () {
        final listed = horizontalLayerDisplayOrder(stack);
        final rows = [
          ...listed.take(2),
          _sound('s2'),
          _sound('s1'),
          ...listed.skip(2),
        ];
        List<String> landing(int slot) {
          final index = newRowInsertionForSlot(
            stack: stack,
            displayRows: rows,
            slot: slot,
          );
          expect(index, isNotNull, reason: 'slot $slot takes a row');
          final landed = [...stack]..insert(index!, _picture('new'));
          return [
            for (final layer in xsheetLayerDisplayOrder(landed))
              if (layer.kind == LayerKind.image) layer.id.value,
          ];
        }

        expect(landing(4), ['tap', 'csm', 'new'], reason: 'over csm');
        expect(landing(5), ['tap', 'new', 'csm'], reason: 'between');
        expect(landing(6), ['new', 'tap', 'csm'], reason: 'under tap');
      });
    });
  }
}

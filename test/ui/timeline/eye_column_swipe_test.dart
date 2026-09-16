import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/ui/input/value_control_pointers.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';

/// The Krita-style EYE SWIPE (R2): a vertical drag down the eye column
/// toggles every row it crosses to the value latched from the first.
///
/// The band it hunts for was arithmetic written out in a comment — '8px
/// padding, opacity(64), mute(18)' — and R27 #6 put the BLEND column to
/// opacity's right without updating it, so from then on the band sat 58px
/// off the eye whenever blend was shown, and nothing noticed because
/// nothing tested it. R10 R6 reads the tail from the slot skeleton instead;
/// this pins the behaviour at the gesture, where a wrong band shows up as
/// "the swipe does nothing".

Layer _layer(String id, {bool visible = true}) {
  return Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.animation,
    isVisible: visible,
    frames: [Frame(id: FrameId('frame-$id'), duration: 2, strokes: const [])],
  );
}

Widget _grid({
  required List<Layer> layers,
  required ValueChanged<LayerId> onToggleLayerVisibility,
  required bool withBlendColumn,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1000,
        height: 400,
        child: LayerTimelineGrid(
          hooks: TimelineGridHooks(
            activeLayerId: layers.first.id,
            frameCursor: ValueNotifier<int>(0),
            playbackFrameCount: 8,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onToggleLayerVisibility: onToggleLayerVisibility,
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            onLayerBlendModeSelected: withBlendColumn
                ? (LayerId _, LayerBlendMode _) {}
                : null,
          ),
          layers: layers,
        ),
      ),
    ),
  );
}

Future<List<LayerId>> _swipeDownTheEyeColumn(
  WidgetTester tester, {
  required bool withBlendColumn,
  List<double> stepsInRows = const [1, 1],
}) async {
  // 🚨THE FIXTURE HAS TO ACTUALLY FLIP. A harness that only RECORDS the
  // toggle cannot measure the law the sweep follows now: the button fires on
  // the DOWN (유저 2026-08-30) and the sweep spreads the value the pressed
  // row is left holding. Frozen, the pressed row never changes and the sweep
  // reads a row that disagrees with what the press just did — measured, and
  // it looked exactly like the feature being broken.
  final toggled = <LayerId>[];
  var layers = [_layer('layer-a'), _layer('layer-b'), _layer('layer-c')];
  await tester.pumpWidget(
    StatefulBuilder(
      builder: (context, setState) => _grid(
        layers: layers,
        withBlendColumn: withBlendColumn,
        onToggleLayerVisibility: (id) {
          toggled.add(id);
          setState(() {
            layers = [
              for (final layer in layers)
                if (layer.id == id)
                  layer.copyWith(isVisible: !layer.isVisible)
                else
                  layer,
            ];
          });
        },
      ),
    ),
  );

  // Start ON the real eye button of the first row and drag down through the
  // next two — measured from the mounted widget, never from a constant, so
  // the test cannot agree with a wrong band by construction.
  final firstEye = tester.getCenter(
    find.byKey(const ValueKey<String>('timeline-layer-visibility-layer-a')),
  );
  final secondEye = tester.getCenter(
    find.byKey(const ValueKey<String>('timeline-layer-visibility-layer-b')),
  );
  final rowPitch = secondEye.dy - firstEye.dy;

  // Start near the TOP of the first row and latch with a short move: the
  // recognizer reports where the drag was recognised, not where the pointer
  // went down, so a first step of a whole row would hand the swipe row TWO
  // and quietly skip row one.
  final gesture = await tester.startGesture(
    firstEye - Offset(0, rowPitch / 2 - 2),
  );
  await tester.pump();
  await gesture.moveBy(const Offset(0, 20));
  await tester.pump();
  // ⚠️Each step is ONE pointer event however far it goes — which is the
  // whole of F-66: a step of two rows is what a dropped frame looks like,
  // and the row it flew over is never named by any event.
  for (final rows in stepsInRows) {
    await gesture.moveBy(Offset(0, rowPitch * rows));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
  return toggled;
}

void main() {
  // ⛔THE CLAIM SET IS GLOBAL. A sweep that ends without a matching release
  // leaves its pointer claimed, and the next case's press — the same id 1 —
  // is then read as 「a button already handled this row」, so the sweep skips
  // the row it started on. Measured: these cases pass alone and fail after
  // another one in the same file.
  tearDown(debugClearValueControlPointers);

  testWidgets('the swipe crosses every row it passes', (tester) async {
    final toggled = await _swipeDownTheEyeColumn(
      tester,
      withBlendColumn: false,
    );
    expect(toggled, [
      const LayerId('layer-a'),
      const LayerId('layer-b'),
      const LayerId('layer-c'),
    ]);
  });

  testWidgets('and still does with the BLEND column mounted — the '
      'regression', (tester) async {
    final toggled = await _swipeDownTheEyeColumn(tester, withBlendColumn: true);
    expect(
      toggled,
      [
        const LayerId('layer-a'),
        const LayerId('layer-b'),
        const LayerId('layer-c'),
      ],
      reason:
          'the eye band must follow the rail\'s own trailing order, not a '
          'hand-written tail that predates the blend column',
    );
  });

  // 🚨★★★F-66 ON THE REAL RAIL (유저 2026-09-10): 「**렉걸리는** 상태에서
  // 아래로 끌면 **중간에 조작이 안 걸리는 레이어가 생긴다**」. The two cases
  // above step a row at a time, so they pass just as well when the sweep
  // only ever paints the row under the cursor. This one drops the frame.
  testWidgets('a pointer that JUMPS a row still paints the row it flew '
      'over', (tester) async {
    final toggled = await _swipeDownTheEyeColumn(
      tester,
      withBlendColumn: false,
      // ONE event from row a to row c. layer-b is never under the cursor
      // when anything is reported.
      stepsInRows: const [2],
    );
    expect(
      toggled,
      [
        const LayerId('layer-a'),
        const LayerId('layer-b'),
        const LayerId('layer-c'),
      ],
      reason: 'the segment between two events is what the sweep paints',
    );
  });
}

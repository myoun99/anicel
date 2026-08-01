import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
          layers: layers,
          activeLayerId: layers.first.id,
          frameCursor: ValueNotifier<int>(0),
          playbackFrameCount: 8,
          exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          onAddLayer: () {},
          onToggleLayerVisibility: onToggleLayerVisibility,
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          // Non-null is what mounts the BLEND column, and therefore what
          // used to move the eye 58px away from where the band looked.
          onLayerBlendModeSelected: withBlendColumn
              ? (LayerId _, LayerBlendMode _) {}
              : null,
        ),
      ),
    ),
  );
}

Future<List<LayerId>> _swipeDownTheEyeColumn(
  WidgetTester tester, {
  required bool withBlendColumn,
}) async {
  final toggled = <LayerId>[];
  final layers = [_layer('layer-a'), _layer('layer-b'), _layer('layer-c')];
  await tester.pumpWidget(
    _grid(
      layers: layers,
      withBlendColumn: withBlendColumn,
      onToggleLayerVisibility: toggled.add,
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
  await gesture.moveBy(Offset(0, rowPitch));
  await tester.pump();
  await gesture.moveBy(Offset(0, rowPitch));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
  return toggled;
}

void main() {
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
    final toggled = await _swipeDownTheEyeColumn(
      tester,
      withBlendColumn: true,
    );
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
}

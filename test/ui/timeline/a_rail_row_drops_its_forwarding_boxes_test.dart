// Card frame-panels-build-in-one-frame (2026-10-25): three boxes that only
// handed their child on are gone from every rail row — the section slot's
// three boxes are one, the name's Flex of one Flexible is an Align, and the
// finger mode listens itself. Each is held to what it replaced, in every
// way a rail lays it.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/input/finger_mode_devices.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';

const _probe = ValueKey<String>('probe');
const _beside = ValueKey<String>('beside');

/// What stands beside the slot along [axis], cross-sized or not.
Widget _neighbour(Axis axis, {required bool sized}) => KeyedSubtree(
  key: _beside,
  child: alongBox(axis, 30, child: sized ? acrossBox(axis, 12) : null),
);

/// The ways a rail lays a slot along [axis]: in a line whose cross axis is
/// centred, or stretched.
final _lines = <String, Widget Function(Axis axis, Widget slot)>{
  'centred': (axis, slot) => Flex(
    direction: axis,
    children: [slot, _neighbour(axis, sized: true)],
  ),
  'stretched': (axis, slot) => Flex(
    direction: axis,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [slot, _neighbour(axis, sized: false)],
  ),
};

Future<({Rect slot, Rect beside})> _laid(
  WidgetTester tester,
  Widget line,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: 240, height: 240, child: line)),
    ),
  );
  return (
    slot: tester.getRect(find.byKey(_probe)),
    beside: tester.getRect(find.byKey(_beside)),
  );
}

void main() {
  for (final axis in Axis.values) {
    for (final MapEntry(key: lineName, value: line) in _lines.entries) {
      testWidgets('the section slot along $axis, $lineName, stands as the '
          'box around a box that fills did', (tester) async {
        final now = await _laid(
          tester,
          line(axis, LayerSectionBandCell(key: _probe, axis: axis)),
        );
        final old = await _laid(
          tester,
          line(
            axis,
            KeyedSubtree(
              key: _probe,
              child: alongBox(
                axis,
                layerSectionLabelSlotWidth,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        expect(now, old);
      });

      for (final (extent, size) in [(20.0, 'short'), (400.0, 'long')]) {
        testWidgets('a $size name along $axis, $lineName, lands where a Flex '
            'of one Flexible laid it', (tester) async {
          Widget name() => SizedBox.fromSize(
            key: _probe,
            size: sizeAlong(axis, along: extent, across: 10),
          );
          final now = await _laid(
            tester,
            line(
              axis,
              Expanded(
                child: Align(alignment: centerStartAlong(axis), child: name()),
              ),
            ),
          );
          final old = await _laid(
            tester,
            line(
              axis,
              Expanded(
                child: Flex(
                  direction: axis,
                  children: [Flexible(child: name())],
                ),
              ),
            ),
          );
          expect(now, old);
        });
      }
    }
  }

  testWidgets('the section slot alone in a box fills it across, as the box '
      'that filled did', (tester) async {
    Future<Size> sizeOf(Widget slot) async {
      await tester.pumpWidget(Center(child: SizedBox(height: 28, child: slot)));
      return tester.getSize(find.byKey(_probe));
    }

    expect(
      await sizeOf(const LayerSectionBandCell(key: _probe)),
      await sizeOf(
        KeyedSubtree(
          key: _probe,
          child: alongBox(
            Axis.horizontal,
            layerSectionLabelSlotWidth,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  });

  testWidgets('the section slot is one element', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: [LayerSectionBandCell(key: _probe)]),
      ),
    );
    var under = 0;
    tester.element(find.byKey(_probe)).visitChildren((_) => under += 1);
    expect(under, 0);
  });

  testWidgets('the finger mode is one element over its detector, and builds '
      'it again with the set a new setting makes', (tester) async {
    final kept = AppInput.settings.value;
    addTearDown(() => AppInput.settings.value = kept);
    AppInput.settings.value = _navigating;
    final handed = <Set<PointerDeviceKind>?>[];
    await tester.pumpWidget(
      FingerModeDevices.timelineEditPan(
        key: _probe,
        builder: (context, devices) {
          handed.add(devices);
          return const SizedBox(key: _beside);
        },
      ),
    );
    final under = <Key?>[];
    tester
        .element(find.byKey(_probe))
        .visitChildren((child) => under.add(child.widget.key));
    expect(under, [_beside]);
    expect(handed.last, isNot(contains(PointerDeviceKind.touch)));

    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      touchDragOneFinger: CanvasTouchDragAction.draw,
    );
    await tester.pump();
    expect(handed.last, contains(PointerDeviceKind.touch));

    await tester.pumpWidget(const SizedBox());
    AppInput.settings.value = _navigating;
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'it stopped listening');
  });
}

/// One finger moves the view — so the timeline's edit pans leave it.
final _navigating = AppInputSettings.testCorpusBaseline.copyWith(
  touchDragOneFinger: CanvasTouchDragAction.navigate,
);

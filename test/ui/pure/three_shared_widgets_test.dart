import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/dialogs/size_fields_row.dart';
import 'package:anicel/src/ui/panels/editor_panel_header.dart';
import 'package:anicel/src/ui/timeline/layer_opacity_field.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// Three shared widgets the audit pulled out of copies, none named by a
/// test (2026-09-05).
void main() {
  Layer row(String id, {double opacity = 1}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: LayerKind.image,
    opacity: opacity,
  );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, child: child)),
    ),
  );

  group('the size fields row', () {
    testWidgets('🚨the WIDTH is focused first — a size window is typed into '
        'immediately, and the caret landing in the wrong box costs a '
        'retype', (tester) async {
      final width = TextEditingController(text: '1920');
      final height = TextEditingController(text: '1080');
      addTearDown(width.dispose);
      addTearDown(height.dispose);

      await pump(
        tester,
        SizeFieldsRow(
          keyPrefix: 'canvas',
          widthController: width,
          heightController: height,
          onChanged: () {},
        ),
      );

      final focused = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('canvas-width-field')),
      );
      expect(focused.autofocus, isTrue);
    });

    testWidgets('the key prefix names BOTH fields, so two windows on screen '
        'do not answer for each other', (tester) async {
      final width = TextEditingController();
      final height = TextEditingController();
      addTearDown(width.dispose);
      addTearDown(height.dispose);

      await pump(
        tester,
        SizeFieldsRow(
          keyPrefix: 'camera',
          widthController: width,
          heightController: height,
          onChanged: () {},
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('camera-width-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('camera-height-field')),
        findsOneWidget,
      );
    });

    testWidgets('⛔only digits go in — a size is not a place for a minus '
        'sign or a decimal point', (tester) async {
      final width = TextEditingController();
      final height = TextEditingController();
      addTearDown(width.dispose);
      addTearDown(height.dispose);

      await pump(
        tester,
        SizeFieldsRow(
          keyPrefix: 'canvas',
          widthController: width,
          heightController: height,
          onChanged: () {},
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('canvas-width-field')),
        '-12.5a',
      );

      expect(width.text, '125');
    });

    testWidgets('either field reports a change', (tester) async {
      final width = TextEditingController();
      final height = TextEditingController();
      addTearDown(width.dispose);
      addTearDown(height.dispose);
      var changes = 0;

      await pump(
        tester,
        SizeFieldsRow(
          keyPrefix: 'canvas',
          widthController: width,
          heightController: height,
          onChanged: () => changes += 1,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('canvas-width-field')),
        '8',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('canvas-height-field')),
        '9',
      );

      expect(changes, 2);
    });
  });

  group('the panel header', () {
    testWidgets('⛔it never repeats the panel title — the TAB names the '
        'panel', (tester) async {
      await pump(tester, const EditorPanelHeader(trailing: Text('a control')));

      expect(find.text('a control'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('🚨its controls are right-aligned and SCROLL when the panel '
        'is squeezed — a bare Row overflowed at the ~100px a drop-zone '
        'preview shrinks to', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              child: EditorPanelHeader(
                trailing: Row(
                  children: [
                    for (var i = 0; i < 8; i += 1)
                      const SizedBox(width: 40, height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('the layer opacity field', () {
    double sliderValue(WidgetTester tester) =>
        tester.widget<FieldSlider>(find.byType(FieldSlider)).value;

    testWidgets('it shows the row\'s own opacity', (tester) async {
      await pump(
        tester,
        layerOpacityField(
          layer: row('a', opacity: 0.4),
          keyPrefix: 'timeline',
          onChanged: (_, _) {},
        ),
      );

      expect(sliderValue(tester), closeTo(0.4, 1e-9));
    });

    testWidgets('🚨it FOLLOWS a drag preview that names this row — the '
        'master bar sweep moves every selected slider live', (tester) async {
      final preview = ValueNotifier<({Set<LayerId> layerIds, double opacity})?>(
        null,
      );
      addTearDown(preview.dispose);

      await pump(
        tester,
        layerOpacityField(
          layer: row('a', opacity: 0.4),
          keyPrefix: 'timeline',
          dragPreview: preview,
          onChanged: (_, _) {},
        ),
      );

      preview.value = (layerIds: {const LayerId('a')}, opacity: 0.9);
      await tester.pump();

      expect(sliderValue(tester), closeTo(0.9, 1e-9));
    });

    testWidgets('⛔a preview naming OTHER rows leaves this one resting', (
      tester,
    ) async {
      final preview = ValueNotifier<({Set<LayerId> layerIds, double opacity})?>(
        null,
      );
      addTearDown(preview.dispose);

      await pump(
        tester,
        layerOpacityField(
          layer: row('a', opacity: 0.4),
          keyPrefix: 'timeline',
          dragPreview: preview,
          onChanged: (_, _) {},
        ),
      );

      preview.value = (layerIds: {const LayerId('b')}, opacity: 0.9);
      await tester.pump();

      expect(sliderValue(tester), closeTo(0.4, 1e-9));
    });

    testWidgets('an OVERRIDE notifier wins outright — the camera row\'s '
        'opacity IS a view notifier, and the slider follows it with no '
        'host rebuild in the loop', (tester) async {
      final override = ValueNotifier<double>(0.2);
      addTearDown(override.dispose);

      await pump(
        tester,
        layerOpacityField(
          layer: row('a', opacity: 0.4),
          keyPrefix: 'timeline',
          override: override,
          onChanged: (_, _) {},
        ),
      );
      expect(sliderValue(tester), closeTo(0.2, 1e-9));

      override.value = 0.7;
      await tester.pump();
      expect(sliderValue(tester), closeTo(0.7, 1e-9));
    });
  });
}

// 🗣️I-177 (유저 2026-11-17): 「레이어의 불투명도/오디오막대만 추가기능. 막대
// 안에서 더블클릭하면 수동편집가능하게. 아래에 공용 넘버패드ui 열어서.
// 콘티,타임라인/x시트패널 동일. 레이어의 불투명도랑 총볼륨막대만」.
//
// The rail's row ([TimelineLayerControlsRow]) is the timeline's, the
// conte's, the X-sheet's stood up and the collapsed rows' — one row, so one
// pin. The bar's own law is `a_double_click_in_a_bar_types_its_number_test`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show buildAppTheme;
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/dart_sources.dart';
import '../../helpers/named_finders.dart';
import '../../helpers/number_pad_keyboard.dart';

void main() {
  setUpAll(loadTheAppFaces);

  final picture = Layer(
    id: const LayerId('pic'),
    name: 'pic',
    kind: LayerKind.animation,
    frames: const [],
  );
  final sound = Layer(
    id: const LayerId('se'),
    name: 'se',
    kind: LayerKind.se,
    frames: const [],
  );

  /// A picture's row and a sound's, as a host lays them — and what each
  /// bar handed over.
  Future<({List<double> opacity, List<double> total})> pumpRail(
    WidgetTester tester,
  ) async {
    final opacity = <double>[];
    final total = <double>[];
    await tester.binding.setSurfaceSize(const Size(900, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget row(Layer layer, TimelineGridMetrics metrics) =>
        TimelineLayerControlsRow(
          layer: layer,
          active: false,
          metrics: metrics,
          onSelectLayer: (_) {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, value) => opacity.add(value),
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          onToggleLayerMute: (_) {},
          onLayerTotalVolumeChangeEnd: (_, value) => total.add(value),
          onLayerBlendModeSelected: (_, _) {},
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (context) {
                final columns = layerRailColumnWidthsIn(context);
                final metrics = TimelineGridMetrics.defaults.copyWith(
                  layerControlsWidth: timelineLayerControlsWidthFor(columns),
                  railColumns: columns,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [row(picture, metrics), row(sound, metrics)],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (opacity: opacity, total: total);
  }

  /// Double clicks [bar] and types [number] into the pad it opens.
  Future<void> typeInto(WidgetTester tester, Finder bar, String number) async {
    for (var click = 0; click < 2; click += 1) {
      await tester.tap(bar);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    expect(theNumberPadsNumber, findsOneWidget, reason: 'the pad opened');
    await openThePadsKeyboard(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('field-slider-type-input')),
      number,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }

  testWidgets('🎯a row\'s opacity bar types its number on a double click', (
    tester,
  ) async {
    final seen = await pumpRail(tester);
    await typeInto(tester, find.named('timeline-layer-opacity-pic'), '40');
    expect(seen.opacity.last, closeTo(0.4, 1e-9));
  });

  testWidgets('🎯an S row\'s Total types its number on a double click — to '
      'its 200', (tester) async {
    final seen = await pumpRail(tester);
    await typeInto(tester, find.named('timeline-layer-total-volume-se'), '150');
    expect(seen.total.last, closeTo(1.5, 1e-9));
  });

  // 「레이어의 불투명도랑 총볼륨막대만」: no other bar of the program says so.
  test('the two rail bars are the only bars that type on a double click', () {
    final saying = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final source = file.readAsStringSync();
      final times = 'typesOnDoubleClick: true'.allMatches(source).length;
      for (var time = 0; time < times; time += 1) {
        saying.add(file.uri.pathSegments.last);
      }
    }
    expect(saying, ['layer_opacity_field.dart', 'layer_opacity_field.dart']);
  });
}

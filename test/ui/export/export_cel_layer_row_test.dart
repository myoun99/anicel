import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/export/export_cel_layer_row.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart';
import 'package:anicel/src/ui/timeline/layer_rail_columns.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';

/// The Cels tab's layer list is THE TIMELINE ROW'S leading cells behind an
/// include dot (유저 2026-09-09: 「타임라인 그대로 옮겨줘 … 어태치 아이콘같은
/// 거나 폴더는 지금 폴더 내부 레이어를 ㅣ 로 표현하는데 그런거 전부」).
void main() {
  const key = LayerMark(process: LayerProcess.key);

  Layer layer(
    String id, {
    String? attachedTo,
    String? folder,
    LayerMark mark = key,
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: const [],
    mark: mark,
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    attachedMode: AttachedMode.synced,
    folderId: folder == null ? null : LayerId(folder),
  );

  // Loose constraints inside a 400px column: the dot keeps its own size,
  // the row takes the width.
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );

  group('ExportIncludeDot', () {
    testWidgets('on fires its tap; off fires it too; a dot without a tap '
        'keeps its place and stays quiet', (tester) async {
      var taps = 0;
      await pump(tester, ExportIncludeDot(value: true, onTap: () => taps += 1));
      await tester.tap(find.byType(ExportIncludeDot));
      expect(taps, 1);

      await pump(tester, const ExportIncludeDot(value: false));
      expect(find.byType(ExportIncludeDot), findsOneWidget);
      await tester.tap(find.byType(ExportIncludeDot));
      expect(taps, 1);
      expect(
        tester.getSize(find.byType(ExportIncludeDot)).width,
        ExportIncludeDot.slotWidth,
      );
    });

    testWidgets('a mixed folder reads half — the fill covers half the dot',
        (tester) async {
      await pump(tester, const ExportIncludeDot(value: false, indeterminate: true));
      final half = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(half.widthFactor, 0.5);

      await pump(tester, const ExportIncludeDot(value: true));
      expect(find.byType(FractionallySizedBox), findsNothing);
    });
  });

  group('ExportCelLayerRow', () {
    testWidgets('carries the rail\'s cells at the rail\'s row height, keyed '
        'by the layer', (tester) async {
      final layers = [layer('a')];
      var toggles = 0;
      await pump(
        tester,
        ExportCelLayerRow(
          keyPrefix: 'x',
          layer: layers.single,
          layers: layers,
          included: true,
          onToggle: () => toggles += 1,
        ),
      );

      expect(
        tester.getSize(find.byType(ExportCelLayerRow)).height,
        timelineLayerRowHeight,
      );
      expect(find.byKey(const ValueKey<String>('x-dot-a')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('x-name-a')), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.byType(LayerMarkPlates), findsOneWidget);
      expect(find.byType(LayerTypeButton), findsOneWidget);
      expect(find.byType(LayerAttachArrowCell), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('x-dot-a')));
      expect(toggles, 1);
    });

    testWidgets('an attach row shows the rail\'s attach arrow; a nested row '
        'its depth guides', (tester) async {
      final folder = createFolderLayer(id: const LayerId('f'), name: 'F');
      final layers = [
        layer('base'),
        layer('rider', attachedTo: 'base'),
        folder,
        layer('leaf', folder: 'f'),
      ];

      await pump(
        tester,
        ExportCelLayerRow(
          keyPrefix: 'x',
          layer: layers[1],
          layers: layers,
          included: true,
        ),
      );
      expect(find.byType(LayerAttachArrowCell), findsOneWidget);

      await pump(
        tester,
        Column(
          children: [
            ExportCelLayerRow(
              keyPrefix: 'x',
              layer: layers[0],
              layers: layers,
              included: true,
            ),
            ExportCelLayerRow(
              keyPrefix: 'x',
              layer: layers[3],
              layers: layers,
              included: true,
            ),
          ],
        ),
      );
      // The nested row's name starts further right by the guide's width.
      final baseName = tester.getTopLeft(
        find.byKey(const ValueKey<String>('x-name-base')),
      );
      final leafName = tester.getTopLeft(
        find.byKey(const ValueKey<String>('x-name-leaf')),
      );
      expect(leafName.dx, greaterThan(baseName.dx));
      expect(
        layerRailDepthGuides(Axis.horizontal, 0, color: Colors.black),
        isNull,
        reason: 'a top-level row draws no guide',
      );
    });

    testWidgets('a row that is not in dims to the rail\'s off alpha; a mixed '
        'folder does not', (tester) async {
      final layers = [layer('a')];
      Opacity opacity() => tester.widget<Opacity>(
        find.descendant(
          of: find.byType(ExportCelLayerRow),
          matching: find.byType(Opacity),
        ),
      );

      await pump(
        tester,
        ExportCelLayerRow(
          keyPrefix: 'x',
          layer: layers.single,
          layers: layers,
          included: false,
        ),
      );
      expect(opacity().opacity, layerRailOffAlpha);

      await pump(
        tester,
        ExportCelLayerRow(
          keyPrefix: 'x',
          layer: layers.single,
          layers: layers,
          included: false,
          indeterminate: true,
        ),
      );
      expect(opacity().opacity, 1);
    });
  });
}

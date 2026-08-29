import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// 🚨F-32 — 유저가 어디가 밀리는지 말해줬다(2026-08-27, `Q-f32-repro`):
///
/// > 「해당 **레이어 영역 자체가 밀림.** 프레임셀쪽도 가능성은 있음.
/// > **레이어 영역이 제일 위에 띠가 있는데, 일단 띠가 살짝 아래로 2px정도?
/// > 밀리는느낌**」
///
/// So the pair is the SECTION BAND (ACTION / SE / CAM, the strip along the
/// top of the header block) against the header block it sits on, and the
/// axis is VERTICAL — not the horizontal one two earlier probes ruled out.
///
/// The band and the legend beside it go through the same
/// `LayerRailWindow(naturalExtent: naturalHeaderBlockExtent)`, so their tops
/// are one line by construction — and this is what fails if they ever stop
/// being.
void main() {
  Layer layer(String id, LayerKind kind) => Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: kind == LayerKind.animation
        ? [Frame(id: FrameId('$id-cel'), duration: 1, strokes: const [])]
        : const [],
    timeline: const {},
  );

  /// The shot's shape: drawing columns, then SE, then the CAM section the
  /// user's transition and camera columns live in.
  final layers = <Layer>[
    for (var i = 0; i < 6; i += 1) layer('draw-$i', LayerKind.animation),
    layer('se-1', LayerKind.se),
    layer('instructions', LayerKind.instruction),
    layer('transitions', LayerKind.transition),
    layer('cam', LayerKind.camera),
  ];

  Future<void> pumpSheet(WidgetTester tester, {required double width}) async {
    // 🚨A FRACTIONAL RATIO. The device-pixel quantiser is the identity at
    // 1.0, and a 2px report is exactly the size of a rounding that only
    // shows between device pixels — 「이음매 테스트는 소수 배율에서」.
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(Size(width, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelinePanel(
            layers: layers,
            activeLayerId: const LayerId('draw-0'),
            frameCursor: cursor,
            playbackFrameCount: 12,
            exposureStateForLayer: (_, _) =>
                TimelineCellExposureState.uncovered,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
            orientation: TimelineOrientation.vertical,
            onOrientationChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the section band starts on the SAME line as the column '
      'headers it caps', (tester) async {
    // Two widths: one that fits the header block whole, and one narrow
    // enough that the rail window has to cut it. A drift that only appears
    // once the window is cutting is still a drift.
    for (final width in const <double>[900, 560]) {
      await pumpSheet(tester, width: width);

      final band = find.byKey(
        const ValueKey<String>('xsheet-section-band-row'),
      );
      final headers = find.byKey(
        const ValueKey<String>('xsheet-layer-header-draw-0'),
      );
      expect(band, findsOneWidget, reason: 'at width $width');
      expect(headers, findsOneWidget, reason: 'at width $width');

      // 🚨AND WHILE SCROLLED — 유저 원문은 「**스크롤에 따라** 위치가
      // 어긋난다」. Both axes: the columns scroll horizontally under the
      // band, and the frames scroll vertically beside it.
      for (final scroll in const <(String, double)>[
        ('rest', 0),
        ('layers', 37),
        ('frames', 53),
        ('both', 91),
      ]) {
        if (scroll.$1 == 'layers' || scroll.$1 == 'both') {
          final horizontal = tester
              .widget<SingleChildScrollView>(
                find.byKey(
                  const ValueKey<String>('xsheet-layer-horizontal-viewport'),
                ),
              )
              .controller!;
          horizontal.jumpTo(
            scroll.$2.clamp(0, horizontal.position.maxScrollExtent),
          );
        }
        if (scroll.$1 == 'frames' || scroll.$1 == 'both') {
          final vertical = tester
              .widget<SingleChildScrollView>(
                find.byKey(
                  const ValueKey<String>('xsheet-frame-vertical-viewport'),
                ),
              )
              .controller!;
          vertical.jumpTo(
            scroll.$2.clamp(0, vertical.position.maxScrollExtent),
          );
        }
        await tester.pumpAndSettle();

        final scrolledBand = tester.getRect(band);
        final scrolledHeader = tester.getRect(headers);
        expect(
          scrolledHeader.top,
          moreOrLessEquals(scrolledBand.bottom, epsilon: 0.01),
          reason:
              'width $width, scrolled ${scroll.$1}: the band and the headers '
              'under it must still meet on one line — 유저: 「띠가 살짝 '
              '아래로 2px정도 밀리는느낌」 (F-32)',
        );
      }

      final bandRect = tester.getRect(band);
      final headerRect = tester.getRect(headers);
      expect(
        headerRect.top,
        moreOrLessEquals(bandRect.bottom, epsilon: 0.01),
        reason:
            'at width $width the band and the headers under it must meet on '
            'one line — 유저: 「띠가 살짝 아래로 2px정도 밀리는느낌」 (F-32)',
      );
    }
  });

  testWidgets('🚨★★★F-32: the frame RAIL and the cells it numbers stay on '
      'one line while scrolled', (tester) async {
    // 유저의 첫 절: 「해당 **레이어 영역 자체가** 밀림」. Everything INSIDE
    // the block has now been measured and holds, so the remaining reading is
    // the block against what is OUTSIDE it — the frame-number rail beside it
    // and the cells under it.
    for (final width in const <double>[900, 560]) {
      await pumpSheet(tester, width: width);

      final header = find.byKey(
        const ValueKey<String>('xsheet-layer-header-draw-0'),
      );
      final cells = find.byKey(
        const ValueKey<String>('xsheet-column-draw-0-cells'),
      );
      final rail = find.byKey(
        const ValueKey<String>('xsheet-frame-number-rail'),
      );
      expect(header, findsOneWidget, reason: 'at width $width');
      expect(cells, findsOneWidget, reason: 'at width $width');
      expect(rail, findsOneWidget, reason: 'at width $width');

      for (final scrolled in const <bool>[false, true]) {
        if (scrolled) {
          final vertical = tester
              .widget<SingleChildScrollView>(
                find.byKey(
                  const ValueKey<String>('xsheet-frame-vertical-viewport'),
                ),
              )
              .controller!;
          vertical.jumpTo(
            53.0.clamp(0, vertical.position.maxScrollExtent).toDouble(),
          );
          await tester.pumpAndSettle();
        }

        // The rail carries the frame numbers the cells are counted by, so
        // its top edge and the cells' top edge are one line or the numbers
        // name the wrong rows.
        expect(
          tester.getRect(rail).top,
          moreOrLessEquals(tester.getRect(cells).top, epsilon: 0.01),
          reason:
              'width $width, scrolled $scrolled: the frame rail and the '
              'cells it numbers must start together (F-32)',
        );
      }
    }
  });
}

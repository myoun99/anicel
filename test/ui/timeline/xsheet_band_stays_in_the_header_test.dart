import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';

/// 🚨F-26 — **x시트 선택 밴드는 헤더 밖으로 나가지 않는다.**
///
/// > 「x시트만 … 지금 스샷보면 **위에 삐져나와서 x버튼을 덮고있었음. 훨씬
/// > 심각함**」
///
/// 🖼️스샷(`board-shots/F-26-1787835771445.png`)에서 「Dire」 컬럼의 청록 밴드가
/// 헤더 위로 올라가 상단 툴바의 `×` 버튼을 덮고 있다. 미관이 아니라 **버튼을 못
/// 누르게 만드는** 문제다.
///
/// ⛔「덮였다」를 눈으로 재지 않는다 — **밴드 rect 와 헤더 rect** 를 비교한다.
void main() {
  Layer layer(String id) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: const {},
  );

  final layers = [layer('A'), layer('B'), layer('C')];

  Widget sheet({required Set<TimelineRowAddress> selected}) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1200,
        height: 700,
        child: TimelinePanel(
          layers: layers,
          activeLayerId: const LayerId('A'),
          frameCursor: ValueNotifier<int>(0),
          playbackFrameCount: 12,
          exposureStateForLayer: (_, _) => TimelineCellExposureState.uncovered,
          onSelectLayer: (_) {},
          onSelectFrame: (_) {},
          onAddLayer: () {},
          onToggleLayerVisibility: (_) {},
          onLayerOpacityChanged: (_, _) {},
          onToggleLayerTimesheet: (_) {},
          onLayerMarkSelected: (_, _) {},
          orientation: TimelineOrientation.vertical,
          onOrientationChanged: (_) {},
          selectedRows: selected,
        ),
      ),
    ),
  );

  testWidgets('선택 밴드가 컬럼 헤더 안에 머문다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      sheet(selected: {const LayerRowAddress(LayerId('B'))}),
    );
    await tester.pumpAndSettle();

    final band = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith(
            'timeline-row-selection-band-',
          ),
    );
    expect(band, findsWidgets, reason: '⛔밴드를 못 찾았다 — 빈 것을 쟀다');

    final header = tester.getRect(
      find.byKey(const ValueKey<String>('xsheet-layer-row-B')),
    );
    final bandRect = tester.getRect(band.first);

    expect(
      bandRect.top,
      greaterThanOrEqualTo(header.top - 1),
      reason:
          '유저: 「위에 삐져나와서 **x버튼을 덮고있었음**」 — 밴드가 헤더 위로 '
          '올라가면 그 위의 버튼을 못 누른다',
    );
  });
}

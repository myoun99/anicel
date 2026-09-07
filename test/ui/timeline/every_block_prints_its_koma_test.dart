import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

/// 🚨F-40 — **블록이면 뭐든 코마 표시가 있다.**
///
/// > 「se블록에 코마표시가 없음. **블록이면 뭐든 반드시 코마블록이 있어야함**」
///
/// ⚠️se 는 눈에 띈 하나였을 뿐이므로 **블록을 가진 모든 종류**를 돈다.
/// 「블록을 가졌나」의 정의는 [LayerKind.holdsDrawings] 다 — 그게 이 앱에서
/// 「이 행에 노출 블록·X칸·코마 드래그가 있나」를 답하는 술어다.
Layer _layer(String id, LayerKind kind) => Layer(
  id: LayerId(id),
  name: id,
  kind: kind,
  // 3코마 — 1코마 블록은 원래 코마를 안 쓴다(D23).
  frames: [Frame(id: FrameId('$id-f'), duration: 3, strokes: const [])],
  timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 3)},
);

Widget _panel(List<Layer> layers) => MaterialApp(
  home: Scaffold(
    body: TimelinePanel(
      layers: layers,
      activeLayerId: layers.first.id,
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
      orientation: TimelineOrientation.horizontal,
      onOrientationChanged: (_) {},
    ),
  ),
);

int _runLabelPainters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .where((paint) => paint.foregroundPainter is TimelineRowRunLabelsPainter)
    .length;

void main() {
  testWidgets('전제 — 애니메이션 블록은 자기 길이를 쓴다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_panel([_layer('anim', LayerKind.animation)]));
    await tester.pumpAndSettle();
    expect(
      _runLabelPainters(tester),
      greaterThan(0),
      reason: '⛔이게 0이면 계측기가 틀렸다 — 아무 행도 코마를 안 쓴다',
    );
  });

  testWidgets('🚨se 블록도 자기 길이를 쓴다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_panel([_layer('se', LayerKind.se)]));
    await tester.pumpAndSettle();
    expect(
      _runLabelPainters(tester),
      greaterThan(0),
      reason: '유저: 「블록이면 뭐든 반드시 코마블록이 있어야함」',
    );
  });

  testWidgets('블록을 가진 종류는 하나도 빠지지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final kind in LayerKind.values.where((kind) => kind.holdsDrawings)) {
      await tester.pumpWidget(_panel([_layer('k-${kind.name}', kind)]));
      await tester.pumpAndSettle();
      expect(
        _runLabelPainters(tester),
        greaterThan(0),
        reason: '${kind.name} — 블록을 가진 종류인데 코마를 안 쓴다',
      );
    }
  });
}

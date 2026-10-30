import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_dab_share.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview_cache.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

/// 유저 2026-10-31, board imported-water-blend-lays-almost-nothing Q3
/// 「파일 값을 따른다」: a brush that came in storing
/// `BrushAdjustFlowByInterval` 0 lays each stamp whole however close they
/// lie. These hold it where the pen and the swatch lay dabs — the model
/// carrying the value is `brush_settings_test`'s and the file's is
/// `sut_decoder_test`'s.
void main() {
  const canvasSize = CanvasSize(width: 256, height: 128);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('layer'),
    frameId: FrameId('frame'),
  );

  /// Closer than a stamp per tenth of its size at every step, so a share
  /// is there to lay.
  BrushSettings brush({required bool adjustsFlow}) => BrushSettings(
    size: 40,
    spacing: 0.02,
    flow: 0.5,
    adjustsFlowBySpacing: adjustsFlow,
  );

  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  /// One pen line through the real canvas.
  Future<List<BrushDab>> dabsOf(
    WidgetTester tester,
    BrushSettings settings,
  ) async {
    final state = BrushToolState.fromBrushSettings(settings);
    final commits = <BrushStrokeCommitData>[];
    final store = BrushFrameEditSessionStore(canvasSize: canvasSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 256,
              height: 128,
              child: InteractiveBrushEditCanvasView(
                key: const ValueKey<String>('ink'),
                celNow: () =>
                    store.getOrCreate(key).canvasState.currentSurface,
                layerId: const LayerId('layer'),
                frameId: const FrameId('frame'),
                inputSettings: state.toInputSettings,
                onSourceStrokeCommitted: commits.add,
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byKey(const ValueKey<String>('ink')));
    Offset at(double t) => origin + Offset(24 + 208 * t, 64);
    const steps = 24;
    for (var i = 0; i <= steps; i += 1) {
      final position = at(i / steps);
      tester.binding.handlePointerEvent(
        i == 0
            ? PointerDownEvent(
                pointer: 1,
                kind: PointerDeviceKind.stylus,
                position: position,
                pressure: 1,
                pressureMin: 0,
                pressureMax: 1,
              )
            : PointerMoveEvent(
                pointer: 1,
                kind: PointerDeviceKind.stylus,
                position: position,
                pressure: 1,
                pressureMin: 0,
                pressureMax: 1,
              ),
      );
      await tester.pump();
    }
    tester.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: at(1),
        pressure: 0,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(commits, hasLength(1));
    return commits.single.sourceDabs;
  }

  testWidgets('every dab a pen lays with such a brush lays whole', (
    tester,
  ) async {
    final dabs = await dabsOf(tester, brush(adjustsFlow: false));

    expect(dabs.length, greaterThan(20));
    expect(dabs.map(stampShareOf), everyElement(1.0));
  });

  testWidgets('every other brush goes on laying its share', (tester) async {
    final dabs = await dabsOf(tester, brush(adjustsFlow: true));

    expect(
      dabs.skip(1).map(stampShareOf),
      everyElement(lessThan(1.0)),
      reason: 'the first dab opens the stroke and lays whole',
    );
  });

  test('its swatch lays what the canvas lays', () {
    double ink(BrushSettings settings) => rasterizeBrushStrokeSample(
      settings,
      96,
      32,
    ).fold(0.0, (sum, value) => sum + value);

    expect(
      ink(brush(adjustsFlow: false)),
      greaterThan(ink(brush(adjustsFlow: true)) * 1.02),
    );
  });
}

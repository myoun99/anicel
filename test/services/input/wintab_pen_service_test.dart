import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/wintab_pen_service.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// PEN-2: the Wintab pressure sidecar — settings model + the polling
/// service against a fake driver stream.
void main() {
  tearDown(() {
    WintabPenService.instance.debugReset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  test('the pressure curve: gamma 1 is identity, soft lifts, hard lowers, '
      'and it round-trips (PEN-3)', () {
    expect(const AppInputSettings().pressureCurveGamma, 1.0);
    expect(AppInput.applyPressureCurve(0.5), 0.5, reason: 'linear default');

    AppInput.settings.value = const AppInputSettings(pressureCurveGamma: 0.5);
    expect(AppInput.applyPressureCurve(0.25), closeTo(0.5, 1e-9));

    AppInput.settings.value = const AppInputSettings(pressureCurveGamma: 2.0);
    expect(AppInput.applyPressureCurve(0.5), closeTo(0.25, 1e-9));
    expect(AppInput.applyPressureCurve(1.2), 1.0, reason: 'clamped input');

    const curved = AppInputSettings(pressureCurveGamma: 1.75);
    expect(AppInputSettings.fromJson(curved.toJson()), curved);
    expect(
      AppInputSettings.fromJson(const {}).pressureCurveGamma,
      1.0,
      reason: 'old settings files stay linear',
    );
  });

  test('the canvas pointer mappings default right=eyedropper/wheel=pan '
      'and round-trip (PEN-7a)', () {
    const defaults = AppInputSettings();
    expect(defaults.canvasRightClick.action, CanvasPointerAction.eyedropper);
    expect(
      defaults.canvasRightClick.release,
      CanvasPointerRelease.returnToTool,
    );
    expect(defaults.canvasWheelClick.action, CanvasPointerAction.pan);
    // Old settings files (no field) get the defaults.
    expect(
      AppInputSettings.fromJson(const {}).canvasRightClick.action,
      CanvasPointerAction.eyedropper,
    );

    const custom = AppInputSettings(
      canvasRightClick: CanvasPointerMapping(
        action: CanvasPointerAction.eraser,
        release: CanvasPointerRelease.keep,
      ),
      canvasWheelClick: CanvasPointerMapping(action: CanvasPointerAction.none),
    );
    expect(AppInputSettings.fromJson(custom.toJson()), custom);
  });

  test('tabletService json round-trips and defaults to standard', () {
    expect(const AppInputSettings().tabletService, TabletService.standard);
    // Old settings files (no field) stay standard.
    expect(
      AppInputSettings.fromJson(const {
        'touchTimelineScroll': true,
      }).tabletService,
      TabletService.standard,
    );
    const wintab = AppInputSettings(tabletService: TabletService.wintab);
    expect(AppInputSettings.fromJson(wintab.toJson()), wintab);
    expect(
      wintab.copyWith(tabletService: TabletService.standard).tabletService,
      TabletService.standard,
    );
  });

  test('the service follows the settings: wintab starts, standard stops', () {
    final service = WintabPenService.instance;
    service.debugPollOverride = () => const [];
    service.bind();
    expect(service.running, isFalse, reason: 'standard = idle');

    AppInput.settings.value = const AppInputSettings(
      tabletService: TabletService.wintab,
    );
    expect(service.running, isTrue);

    AppInput.settings.value = const AppInputSettings();
    expect(service.running, isFalse);
  });

  test('fresh driver pressure overrides; stale or idle yields null', () async {
    final service = WintabPenService.instance;
    // Freeze the freshness clock (tearDown's debugReset clears it): the
    // delivered packet must read fresh however long the poll delay and
    // suite load take between delivery and the pressure read. The "beyond
    // the fresh window" case below builds its stale time off the same
    // frozen base so the age math stays deterministic.
    WintabPenService.debugClockOverride = () => DateTime(2024);
    var queue = <QaTabletPacket>[];
    service.debugPollOverride = () {
      final drained = queue;
      queue = [];
      return drained;
    };

    expect(service.freshContactPressure(), isNull, reason: 'not running yet');

    service.start();
    queue = const [
      QaTabletPacket(
        pressure: 0.37,
        tiltAzimuthDegrees: 12,
        altitude: 0.8,
        timeMs: 1000,
        buttons: 1,
      ),
      QaTabletPacket(
        pressure: 0.62,
        tiltAzimuthDegrees: 12,
        altitude: 0.8,
        timeMs: 1008,
        buttons: 1,
      ),
    ];
    // One poll tick delivers; the newest packet wins.
    await Future<void>.delayed(WintabPenService.pollInterval * 3);
    expect(service.latest.value?.pressure, 0.62);
    expect(service.freshContactPressure(), 0.62);

    // Beyond the fresh window the override stands down — built off the
    // frozen base the packet was delivered at.
    final stale = DateTime(2024).add(
      WintabPenService.freshWindow + const Duration(milliseconds: 1),
    );
    expect(service.freshContactPressure(now: stale), isNull);

    service.stop();
    expect(service.latest.value, isNull);
    expect(service.freshContactPressure(), isNull);
  });
}

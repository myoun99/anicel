import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_form.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';

/// Envelope ink lives in ONE plane: every stroke belongs to the box it
/// started in, and there is no page window because the form has no margin.
void main() {
  const owner = CutId('cut-1');

  CutEnvelopeLayout layoutOf(List<EnvelopeBox> boxes) => CutEnvelopeLayout.fit(
    form: CutEnvelopeForm(
      id: 'test',
      name: 'Test',
      aspectRatio: 1,
      boxes: boxes,
    ),
    paperWidth: 100,
    paperHeight: 100,
  );

  test('one window per inking box, and none for display-only ones', () {
    final windows = envelopeInkWindows(
      layoutOf(const [
        EnvelopeBox(
          id: 'cell',
          rect: EnvelopeRect(x: 0, y: 0, width: 0.5, height: 0.5),
        ),
        EnvelopeBox(
          id: 'logo',
          rect: EnvelopeRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
          takesInk: false,
        ),
      ]),
      owner,
    );

    expect(windows.map((window) => window.boxId), ['cell']);
  });

  test('there is NO page window — a stroke outside every box has nowhere '
      'to go', () {
    final windows = envelopeInkWindows(layoutOf(const []), owner);

    expect(windows, isEmpty);
  });

  test('a window keys on the owner cut, so 겸용 siblings share one set', () {
    final windows = envelopeInkWindows(
      layoutOf(const [
        EnvelopeBox(
          id: 'cell',
          rect: EnvelopeRect(x: 0, y: 0, width: 1, height: 1),
        ),
      ]),
      owner,
    );

    expect(windows.single.key, envelopeInkBoxKey(owner, 'cell'));
    expect(isEnvelopeInkKey(windows.single.key), isTrue);
  });

  test('the surface origin is the BOX corner, so ink follows a moved box', () {
    final window = envelopeInkWindows(
      layoutOf(const [
        EnvelopeBox(
          id: 'cell',
          rect: EnvelopeRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25),
        ),
      ]),
      owner,
    ).single;

    final panel = CanvasViewport(zoom: 2, panX: 10, panY: 20);
    final ink = window.inkViewport(panel);

    expect(ink.zoom, 2 / CutEnvelopeInkController.inkScale);
    expect(ink.panX, 10 + 2 * 25, reason: 'box left is 25 in paper space');
    expect(ink.panY, 20 + 2 * 50);
  });

  test('screenRect follows the panel transform', () {
    final window = envelopeInkWindows(
      layoutOf(const [
        EnvelopeBox(
          id: 'cell',
          rect: EnvelopeRect(x: 0, y: 0, width: 0.5, height: 0.5),
        ),
      ]),
      owner,
    ).single;

    final rect = window.screenRect(CanvasViewport(zoom: 3, panX: 5, panY: 7));

    expect(rect.left, 5);
    expect(rect.top, 7);
    expect(rect.width, 150);
    expect(rect.height, 150);
  });

  test('windows follow FORM order, so an inner box is hit before its host', () {
    final windows = envelopeInkWindows(
      layoutOf(const [
        EnvelopeBox(
          id: 'outer',
          rect: EnvelopeRect(x: 0, y: 0, width: 1, height: 1),
        ),
        EnvelopeBox(
          id: 'inner',
          rect: EnvelopeRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
        ),
      ]),
      owner,
    );

    expect(
      windows.map((window) => window.boxId),
      ['outer', 'inner'],
      reason:
          'bottom-of-stack first — the last one wins a hit, matching '
          'inkBoxAt\'s reverse search',
    );
  });

  test('the analog preset gives every inking box a window', () {
    final layout = CutEnvelopeLayout.fit(
      form: CutEnvelopePresets.analog,
      paperWidth: 660,
      paperHeight: 497,
    );

    final windows = envelopeInkWindows(layout, owner);

    expect(windows, hasLength(CutEnvelopePresets.analog.inkBoxes.length));
    expect(
      windows.map((window) => window.boxId).toSet(),
      hasLength(windows.length),
      reason: 'one surface per box, never two boxes sharing a key',
    );
  });

  group('mount gate', () {
    final analog = CutEnvelopeLayout.fit(
      form: CutEnvelopePresets.analog,
      paperWidth: 660,
      paperHeight: 497,
    );
    final windows = envelopeInkWindows(analog, owner);

    test('zoomed OUT almost nothing mounts — only cells still big enough '
        'to write in', () {
      final mounted = mountedEnvelopeInkWindows(
        windows,
        CanvasViewport(zoom: 0.2, panX: 0, panY: 0),
        const Size(400, 300),
      );

      // Not zero: the sheet-space block is large enough to draw in even
      // here, and refusing it would be wrong. What matters is that the 86
      // collapse to a couple.
      expect(mounted.length, lessThan(5));
    });

    test('zoomed IN the mount count drops to a conte-sized handful', () {
      final mounted = mountedEnvelopeInkWindows(
        windows,
        CanvasViewport(zoom: 3, panX: 0, panY: 0),
        const Size(900, 700),
      );

      expect(windows, hasLength(86), reason: 'measured: the analog preset');
      expect(
        mounted.length,
        lessThan(20),
        reason: 'the whole point — 86 sessions would be mounted otherwise',
      );
      expect(mounted, isNotEmpty);
    });

    test('a window scrolled off screen does not mount', () {
      final far = mountedEnvelopeInkWindows(
        windows,
        CanvasViewport(zoom: 3, panX: -100000, panY: -100000),
        const Size(900, 700),
      );

      expect(far, isEmpty);
    });

    test('the size gate is per-axis: a wide but flat cell stays out', () {
      final flat = envelopeInkWindows(
        layoutOf(const [
          EnvelopeBox(
            id: 'flat',
            rect: EnvelopeRect(x: 0, y: 0, width: 1, height: 0.05),
          ),
        ]),
        owner,
      );

      final mounted = mountedEnvelopeInkWindows(
        flat,
        CanvasViewport(zoom: 1, panX: 0, panY: 0),
        const Size(200, 200),
      );

      expect(mounted, isEmpty, reason: 'height is 5px — nothing fits there');
    });
  });

  group('controller', () {
    test('geometry must be synced before ink is touched', () {
      final controller = CutEnvelopeInkController();
      addTearDown(controller.dispose);

      expect(
        () => controller.sessionStateFor(envelopeInkBoxKey(owner, 'cell')),
        throwsStateError,
      );
    });

    test('the surface covers the whole paper at ink scale', () {
      final controller = CutEnvelopeInkController();
      addTearDown(controller.dispose);

      controller.syncGeometry(paperWidth: 660, paperHeight: 497);

      expect(
        controller.surfaceSize!.width,
        660 * CutEnvelopeInkController.inkScale,
      );
      expect(
        controller.surfaceSize!.height,
        497 * CutEnvelopeInkController.inkScale,
      );
    });

    test('an untouched box reports no ink', () {
      final controller = CutEnvelopeInkController();
      addTearDown(controller.dispose);
      controller.syncGeometry(paperWidth: 100, paperHeight: 100);

      expect(controller.hasInkFor(envelopeInkBoxKey(owner, 'cell')), isFalse);
    });
  });
}

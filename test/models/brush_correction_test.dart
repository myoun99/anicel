import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_settings.dart';

void main() {
  group('the 손떨림 보정 scale (F-418-Q6)', () {
    test('0 steadies nothing', () {
      expect(BrushCorrection.none.steadies, isFalse);
      expect(const BrushCorrection().steadies, isTrue);
    });

    test("1 is Clip Studio's 0, and 100 its 100", () {
      expect(BrushCorrection.fromClipStudio(0), 1);
      expect(BrushCorrection.fromClipStudio(100), 100);
      expect(BrushCorrection.fromClipStudio(50), closeTo(50.5, 1e-9));
      expect(BrushCorrection.fromClipStudio(-3), 1, reason: 'clamped');
      expect(BrushCorrection.fromClipStudio(250), 100, reason: 'clamped');
    });

    test("the line lags Clip Studio's own at its ends, evenly between", () {
      Duration lagAt(double stabilization) =>
          BrushCorrection(stabilization: stabilization).lagAt(0.5);
      expect(lagAt(1), BrushCorrection.lagAtClipStudioZero);
      expect(lagAt(100), BrushCorrection.lagAtClipStudioHundred);
      final halfway = BrushCorrection.fromClipStudio(50);
      final from = BrushCorrection.lagAtClipStudioZero.inMicroseconds;
      final to = BrushCorrection.lagAtClipStudioHundred.inMicroseconds;
      expect(
        lagAt(halfway).inMicroseconds,
        ((from + to) / 2).round(),
      );
      expect(
        lagAt(0.5),
        BrushCorrection.lagAtClipStudioZero,
        reason: "below 1 is still Clip Studio's 0",
      );
    });

    test("a brush that says nothing steadies as Clip Studio's 0", () {
      expect(const BrushCorrection().stabilization, 1);
      expect(BrushSettings().correction, const BrushCorrection());
      expect(BrushCorrection.fromJson(null), const BrushCorrection());
      expect(BrushCorrection.fromJson(const {}), const BrushCorrection());
    });
  });

  group("the brush's own, kept in its preset (F-418-Q6)", () {
    test('a preset carries it there and back', () {
      final brush = BrushSettings(
        correction: const BrushCorrection(stabilization: 37),
      );
      final back = BrushSettings.fromJson(brush.toJson());
      expect(back.correction, const BrushCorrection(stabilization: 37));
      expect(back, brush);
    });

    test('at its default it writes nothing, so an older preset reads the '
        'same bytes back', () {
      expect(BrushSettings().toJson().containsKey('correction'), isFalse);
      expect(
        BrushSettings(correction: BrushCorrection.none)
            .toJson()
            .containsKey('correction'),
        isTrue,
      );
    });

    test('a value off the scale is refused', () {
      for (final stabilization in [-1.0, 100.5, double.nan]) {
        expect(
          () => BrushSettings(
            correction: BrushCorrection(stabilization: stabilization),
          ),
          throwsArgumentError,
          reason: '$stabilization',
        );
      }
      expect(
        BrushSettings(correction: BrushCorrection.none).correction,
        BrushCorrection.none,
      );
      expect(
        BrushSettings(
          correction: const BrushCorrection(stabilization: 100),
        ).correction.stabilization,
        100,
      );
    });
  });

  group('速度による手ブレ補正 (F-418-Q5)', () {
    int lagOf(BrushCorrection correction, double speed) =>
        correction.lagAt(speed).inMicroseconds;
    BrushCorrection at(double clipStudio, BrushSteadyingBySpeed bySpeed) =>
        BrushCorrection(
          stabilization: BrushCorrection.fromClipStudio(clipStudio),
          steadyingBySpeed: bySpeed,
        );
    final zero = BrushCorrection.lagAtClipStudioZero.inMicroseconds;
    final hundred = BrushCorrection.lagAtClipStudioHundred.inMicroseconds;
    int lagAtClipStudio(double value) =>
        (zero + (hundred - zero) * value / 100).round();

    test('off, the speed changes nothing', () {
      final off = at(10, BrushSteadyingBySpeed.off);
      expect(lagOf(off, 0), lagOf(off, 1));
      expect(lagOf(off, 0), lagAtClipStudio(10));
    });

    test('the slow type steadies a slow pen as 30 would, and a setting of '
        '30 or more not at all differently', () {
      final slow = at(10, BrushSteadyingBySpeed.slow);
      expect(lagOf(slow, 0), lagAtClipStudio(30));
      expect(lagOf(slow, 1), lagAtClipStudio(10));
      expect(lagOf(slow, 0.5), lagAtClipStudio(20));
      final high = at(60, BrushSteadyingBySpeed.slow);
      expect(lagOf(high, 0), lagOf(high, 1));
    });

    test('the quick type steadies a quick pen less', () {
      final fast = at(60, BrushSteadyingBySpeed.fast);
      expect(lagOf(fast, 0), lagAtClipStudio(60));
      expect(lagOf(fast, 1), lagAtClipStudio(30));
    });

    test("a .sut's two columns read as one", () {
      expect(
        BrushSteadyingBySpeed.fromClipStudio(bySpeed: 0, type: 1),
        BrushSteadyingBySpeed.off,
      );
      expect(
        BrushSteadyingBySpeed.fromClipStudio(bySpeed: null, type: 2),
        BrushSteadyingBySpeed.off,
      );
      expect(
        BrushSteadyingBySpeed.fromClipStudio(bySpeed: 1, type: 1),
        BrushSteadyingBySpeed.slow,
        reason: 'F-418-Q8 「1 = 천천히 그릴 때 보정」',
      );
      expect(
        BrushSteadyingBySpeed.fromClipStudio(bySpeed: 1, type: 2),
        BrushSteadyingBySpeed.fast,
      );
    });
  });

  group('後補正 (F-418-Q5 · Q7)', () {
    test('0 takes nothing out, whatever else is on', () {
      expect(
        const BrushCorrection().postWithin(zoom: 1, speed: 1),
        isNull,
      );
    });

    test('the strength is how far a wobble may stray', () {
      const plain = BrushCorrection(
        postStrength: 40,
        postBySpeed: false,
        postByViewScale: false,
      );
      final within = plain.postWithin(zoom: 1, speed: 0.3)!;
      expect(
        within,
        closeTo(10, 1e-9),
        reason: 'a quarter of a pixel a step — mine, until it is matched '
            'by hand against Clip Studio',
      );
      expect(plain.postWithin(zoom: 4, speed: 1), within);
      expect(
        plain.copyWith(postStrength: 80).postWithin(zoom: 1, speed: 0),
        closeTo(within * 2, 1e-9),
      );
    });

    test('by the view, a wobble is measured on the screen — a smaller view '
        'takes more out (表示倍率による調整)', () {
      const byView = BrushCorrection(postStrength: 40, postBySpeed: false);
      final atFull = byView.postWithin(zoom: 1, speed: 1)!;
      expect(byView.postWithin(zoom: 0.5, speed: 1), closeTo(atFull * 2, 1e-9));
      expect(byView.postWithin(zoom: 2, speed: 1), closeTo(atFull / 2, 1e-9));
    });

    test('by the speed, the quickest line gets the strength and a slower one '
        'less (速度による調整)', () {
      const bySpeed = BrushCorrection(postStrength: 40, postByViewScale: false);
      final quickest = bySpeed.postWithin(zoom: 1, speed: 1)!;
      expect(
        bySpeed.postWithin(zoom: 1, speed: 0.25),
        closeTo(quickest / 4, 1e-9),
      );
      expect(bySpeed.postWithin(zoom: 1, speed: 0), isNull);
    });
  });

  test('every part tells two corrections apart, and a copy keeps it', () {
    expect(_every.copyWith(), _every);
    expect(_every.copyWith().hashCode, _every.hashCode);
    for (final other in [
      _every.copyWith(sharpenCorners: false),
      _every.copyWith(stabilization: 23),
      _every.copyWith(steadyingBySpeed: BrushSteadyingBySpeed.slow),
      _every.copyWith(postStrength: 36),
      _every.copyWith(postBySpeed: true),
      _every.copyWith(postByViewScale: true),
      _every.copyWith(postBezier: false),
    ]) {
      expect(other, isNot(_every), reason: '$other');
    }
  });

  test('every part goes into a preset and comes back', () {
    expect(BrushCorrection.fromJson(_every.toJson()), _every);
    final brush = BrushSettings(correction: _every);
    expect(BrushSettings.fromJson(brush.toJson()).correction, _every);
    expect(
      BrushCorrection.fromJson(const {'steadyingBySpeed': 'sideways'}),
      const BrushCorrection(),
      reason: 'a speed type it does not know is the default',
    );
  });

  test('a post-correction off the scale is refused', () {
    for (final postStrength in [-1.0, 100.5, double.nan]) {
      expect(
        () => BrushSettings(
          correction: BrushCorrection(postStrength: postStrength),
        ),
        throwsArgumentError,
        reason: '$postStrength',
      );
    }
  });
}

/// A correction with every part off its default.
const _every = BrushCorrection(
  sharpenCorners: true,
  stabilization: 22,
  steadyingBySpeed: BrushSteadyingBySpeed.fast,
  postStrength: 35,
  postBySpeed: false,
  postByViewScale: false,
  postBezier: true,
);

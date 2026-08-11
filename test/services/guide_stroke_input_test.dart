import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/services/guide_stroke_input.dart';
import 'package:flutter_test/flutter_test.dart';

CanvasPoint _point(double x, double y) => CanvasPoint(x: x, y: y);

void _expectPoint(CanvasPoint actual, double x, double y) {
  expect(actual.x, closeTo(x, 1e-9));
  expect(actual.y, closeTo(y, 1e-9));
}

BrushDab _dab({
  required double x,
  required double y,
  int sequence = 0,
  double angleDegrees = 0,
}) => BrushDab(
  center: _point(x, y),
  color: 0xFF000000,
  size: 10,
  opacity: 1,
  flow: 1,
  hardness: 1,
  tipShape: BrushTipShape.round,
  pressure: 1,
  sequence: sequence,
  angleDegrees: angleDegrees,
);

CutGuides _guidesWith(PerspectiveShape shape) => CutGuides(
  guides: [
    DrawingGuide(
      id: const GuideId('p'),
      name: 'Perspective',
      shape: shape,
    ),
  ],
);

PerspectiveShape _horizontalVanishing({bool snapEnabled = true}) =>
    PerspectiveShape(
      vanishingPoints: [VanishingPointTowards(dx: 1, dy: 0)],
      eyeLevel: GuideAxis(origin: _point(0, 0), angleDegrees: 0),
      snapEnabled: snapEnabled,
    );

void main() {
  group('PerspectiveSnapSession', () {
    test('no snapping guide means no session at all', () {
      expect(
        PerspectiveSnapSession.maybeStart(
          guides: CutGuides.empty,
          start: _point(0, 0),
          zoom: 1,
        ),
        isNull,
      );
      expect(
        PerspectiveSnapSession.maybeStart(
          guides: _guidesWith(_horizontalVanishing(snapEnabled: false)),
          start: _point(0, 0),
          zoom: 1,
        ),
        isNull,
      );
    });

    test('holds early points, then releases them all on the ray', () {
      final session = PerspectiveSnapSession.maybeStart(
        guides: _guidesWith(_horizontalVanishing()),
        start: _point(0, 0),
        zoom: 1,
      )!;

      // Under the lock travel: nothing is drawn yet. Drawing these unsnapped
      // and correcting later would put a wrong frame on screen.
      expect(session.follow(_point(2, 1)), isEmpty);
      expect(session.follow(_point(4, 2)), isEmpty);
      expect(session.lockedRay, isNull);

      final released = session.follow(_point(20, 3));

      expect(released.length, 3, reason: 'every held point arrives at once');
      expect(session.lockedRay, isNotNull);
      _expectPoint(released[0], 2, 0);
      _expectPoint(released[1], 4, 0);
      _expectPoint(released[2], 20, 0);
    });

    test('once locked, later points project immediately', () {
      final session = PerspectiveSnapSession.maybeStart(
        guides: _guidesWith(_horizontalVanishing()),
        start: _point(0, 0),
        zoom: 1,
      )!;
      session.follow(_point(20, 3));

      final next = session.follow(_point(50, -80));

      expect(next.length, 1);
      _expectPoint(next.single, 50, 0);
    });

    test('the ray never changes once chosen', () {
      // A stroke that curves away must stay on the family it started in
      // rather than hopping to the nearer one.
      final session = PerspectiveSnapSession.maybeStart(
        guides: _guidesWith(
          PerspectiveShape(
            vanishingPoints: [
              VanishingPointTowards(dx: 1, dy: 0),
              VanishingPointTowards(dx: 0, dy: 1),
            ],
            eyeLevel: GuideAxis(origin: _point(0, 0), angleDegrees: 0),
          ),
        ),
        start: _point(0, 0),
        zoom: 1,
      )!;

      session.follow(_point(20, 0));
      final locked = session.lockedRay;
      // Now travel hard along the OTHER family.
      final wandered = session.follow(_point(20, 500));

      expect(session.lockedRay, locked);
      _expectPoint(wandered.single, 20, 0);
    });

    test('a short flick still draws — pen-up settles on a best guess', () {
      final session = PerspectiveSnapSession.maybeStart(
        guides: _guidesWith(_horizontalVanishing()),
        start: _point(0, 0),
        zoom: 1,
      )!;
      expect(session.follow(_point(3, 1)), isEmpty);

      final released = session.finish();

      expect(released.length, 1);
      _expectPoint(released.single, 3, 0);
    });

    test('finishing an already-locked stroke releases nothing extra', () {
      final session = PerspectiveSnapSession.maybeStart(
        guides: _guidesWith(_horizontalVanishing()),
        start: _point(0, 0),
        zoom: 1,
      )!;
      session.follow(_point(30, 4));

      expect(session.finish(), isEmpty);
    });

    test('a stroke that never moves locks onto nothing', () {
      final session = PerspectiveSnapSession.maybeStart(
        guides: _guidesWith(_horizontalVanishing()),
        start: _point(5, 5),
        zoom: 1,
      )!;
      session.follow(_point(5, 5));

      expect(session.finish(), isEmpty);
      expect(session.lockedRay, isNull);
    });

    test('the lock travel is screen distance, so zoom does not change feel', () {
      // Zoomed 10x in, the same SCREEN travel is a tenth of the canvas
      // distance — the stroke must lock at the same point under the pen.
      final zoomedIn = PerspectiveSnapSession.maybeStart(
        guides: _guidesWith(_horizontalVanishing()),
        start: _point(0, 0),
        zoom: 10,
      )!;

      final released = zoomedIn.follow(
        _point(kPerspectiveSnapLockTravel / 10, 0),
      );

      expect(released, isNotEmpty);
    });
  });

  group('replicateDabs', () {
    final transforms = symmetryTransforms(
      SymmetryShape(
        axis: GuideAxis(origin: _point(100, 0), angleDegrees: 90),
        lineCount: 2,
      ),
    );

    test('no acting symmetry leaves the dabs exactly as they were', () {
      final dabs = [_dab(x: 1, y: 2, sequence: 7)];

      expect(replicateDabs(dabs, const [], firstSequence: 7), same(dabs));
      expect(
        replicateDabs(
          dabs,
          const [GuideTransform.identity()],
          firstSequence: 7,
        ),
        same(dabs),
      );
    });

    test('produces one run per copy, original first', () {
      final dabs = [
        _dab(x: 150, y: 10, sequence: 4),
        _dab(x: 160, y: 10, sequence: 5),
      ];

      final replicated = replicateDabs(dabs, transforms, firstSequence: 4);

      expect(replicated.length, 4);
      _expectPoint(replicated[0].center, 150, 10);
      _expectPoint(replicated[1].center, 160, 10);
      _expectPoint(replicated[2].center, 50, 10);
      _expectPoint(replicated[3].center, 40, 10);
    });

    test('sequence numbers stay contiguous from firstSequence', () {
      final dabs = [
        _dab(x: 150, y: 10, sequence: 9),
        _dab(x: 160, y: 10, sequence: 10),
      ];

      final replicated = replicateDabs(dabs, transforms, firstSequence: 9);

      expect(
        replicated.map((dab) => dab.sequence).toList(),
        [9, 10, 11, 12],
        reason: 'the caller advances _nextSequence by the emitted length',
      );
    });

    test('the original run keeps every field but its position', () {
      final dab = _dab(x: 150, y: 10, sequence: 3, angleDegrees: 22);

      final replicated = replicateDabs([dab], transforms, firstSequence: 3);

      expect(replicated.first.center, dab.center);
      expect(replicated.first.angleDegrees, dab.angleDegrees);
      expect(replicated.first.size, dab.size);
      expect(replicated.first.pressure, dab.pressure);
    });

    test('a mirrored copy mirrors the tip angle too', () {
      // An asymmetric tip drawn on the left must lean the other way on the
      // right, or the two halves are not each other's reflection.
      //
      // 30° is the visual counter-clockwise lean of the tip's major axis, so
      // in y-down canvas space it points up-and-RIGHT. Mirrored across a
      // vertical axis it must point up-and-LEFT, which reads as 150°. The
      // tempting answer, -30°, points down-and-right — that is the mirror
      // across a HORIZONTAL axis. The two differ by 180°, which an ellipse
      // would not notice but a bitmap tip mask certainly would: it would
      // come out upside down.
      final dab = _dab(x: 150, y: 10, sequence: 0, angleDegrees: 30);

      final replicated = replicateDabs([dab], transforms, firstSequence: 0);

      expect(replicated[1].angleDegrees, closeTo(150, 1e-9));
    });

    test('mirroring a tip angle twice returns it unchanged', () {
      // The guard against a mirror that is right up to a half turn: applying
      // the same reflection twice is the identity, and a 180° slip would
      // show up here as a 360° round trip that lands 180° away.
      final reflection = transforms[1];

      for (final angle in [0.0, 30.0, 95.0, -140.0]) {
        final once = reflection.mapTipAngleDegrees(angle);
        final twice = reflection.mapTipAngleDegrees(once);
        expect(
          twice,
          closeTo(angle, 1e-9),
          reason: 'reflecting $angle twice should come home',
        );
      }
    });

    test('a rotational copy turns the tip by the rotation', () {
      final rotational = symmetryTransforms(
        SymmetryShape(
          axis: GuideAxis(origin: _point(0, 0), angleDegrees: 90),
          lineCount: 4,
          lineSymmetry: false,
        ),
      );
      final dab = _dab(x: 10, y: 0, sequence: 0, angleDegrees: 0);

      final replicated = replicateDabs([dab], rotational, firstSequence: 0);

      // Copy 1 is a quarter turn clockwise; the tip angle is measured the
      // other way round, so it reads as -90.
      expect(replicated[1].angleDegrees, closeTo(-90, 1e-9));
    });

    test('a sixteen-line kaleidoscope emits sixteen runs', () {
      final wide = symmetryTransforms(
        SymmetryShape(
          axis: GuideAxis(origin: _point(0, 0), angleDegrees: 90),
          lineCount: maxSymmetryLineCount,
        ),
      );
      final dabs = [_dab(x: 30, y: 40, sequence: 0), _dab(x: 31, y: 41)];

      final replicated = replicateDabs(dabs, wide, firstSequence: 0);

      expect(replicated.length, maxSymmetryLineCount * 2);
      expect(replicated.last.sequence, maxSymmetryLineCount * 2 - 1);
    });

    test('replication preserves spacing, because the maps are rigid', () {
      // Spacing is computed once, before replication; a copy that stretched
      // it would show as a different dab density on one side.
      final dabs = [
        _dab(x: 150, y: 0),
        _dab(x: 160, y: 0),
        _dab(x: 170, y: 0),
      ];

      final replicated = replicateDabs(dabs, transforms, firstSequence: 0);

      double gap(BrushDab a, BrushDab b) =>
          (a.center.x - b.center.x).abs() + (a.center.y - b.center.y).abs();
      expect(gap(replicated[0], replicated[1]), closeTo(10, 1e-9));
      expect(gap(replicated[3], replicated[4]), closeTo(10, 1e-9));
    });
  });
}

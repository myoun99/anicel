import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/selection_affine.dart';

/// 🚨★★★**THE ANCHOR TURNS THE ROTATION AND NOTHING ELSE.**
///
/// 🗣️유저 2026-09-20: 「**확대/축소의 기준점은 항상 상자의 중심**이야」 and
/// 「**앵커포인트는 회전시 앵커를 기준으로 회전**해」. Two centres, two
/// questions — and they have to ride ONE matrix, because the outline and
/// the resampled pixels read the same affine and may never disagree about
/// where the rotation went.
///
/// ⛔The trick that makes one matrix enough is an identity, not a special
/// case: rotating about the anchor IS rotating about the pivot and then
/// shifting by `anchor − R·anchor`. These pins are that identity, stated
/// as the three things a user can see.
void main() {
  final pivot = CanvasPoint(x: 100, y: 50);

  test('🚨the anchor is the FIXED POINT of the rotation', () {
    // The anchor sits 30 right and 40 down from the box centre.
    final affine = SelectionAffine(
      pivot: pivot,
      rotationDegrees: 90,
      anchorX: 30,
      anchorY: 40,
    );
    final anchorPoint = CanvasPoint(x: pivot.x + 30, y: pivot.y + 40);
    final turned = affine.apply(anchorPoint);

    expect(turned.x, closeTo(anchorPoint.x, 1e-9));
    expect(turned.y, closeTo(anchorPoint.y, 1e-9));
  });

  /// 🚨★★★**WHERE THE CROSS IS DRAWN**, which is one derivation and not
  /// three: the chrome, the hit test and the tool panel all read
  /// `anchorCanvas`.
  test('🚨the cross sits on the rotation centre, at every angle', () {
    // The same anchor under four different turns and a scale. The cross
    // must not orbit itself — a cross that moved when the box turned would
    // be a cross you could not aim at while turning.
    for (final degrees in const [0.0, 37.0, 90.0, 213.0]) {
      final affine = SelectionAffine(
        pivot: pivot,
        sx: 2,
        sy: 2,
        rotationDegrees: degrees,
        anchorX: 30,
        anchorY: -40,
      );
      final cross = affine.anchorCanvas;
      expect(cross.x, closeTo(pivot.x + 30, 1e-9), reason: 'at $degrees°');
      expect(cross.y, closeTo(pivot.y - 40, 1e-9), reason: 'at $degrees°');

      // …and it really IS the turn's centre: the point that lands there
      // lands there whatever the angle is.
      final source = CanvasPoint(x: pivot.x + 15, y: pivot.y - 20);
      final landed = affine.apply(source);
      expect(landed.x, closeTo(cross.x, 1e-9), reason: 'at $degrees°');
      expect(landed.y, closeTo(cross.y, 1e-9), reason: 'at $degrees°');
    }
  });

  test('⚠️the cross RIDES the move — tx/ty carry it like everything else', () {
    final affine = SelectionAffine(
      pivot: pivot,
      tx: 11,
      ty: -7,
      anchorX: 30,
      anchorY: 40,
    );
    expect(affine.anchorCanvas.x, closeTo(pivot.x + 30 + 11, 1e-9));
    expect(affine.anchorCanvas.y, closeTo(pivot.y + 40 - 7, 1e-9));
  });

  test('⛔and the PIVOT is not, once the anchor has moved', () {
    // The control for the pin above: with the anchor off-centre, the box
    // centre is carried around it, so the first pin is not passing by
    // accident on an affine that moves nothing.
    final affine = SelectionAffine(
      pivot: pivot,
      rotationDegrees: 90,
      anchorX: 30,
      anchorY: 40,
    );
    final turned = affine.apply(pivot);

    // Rotating (0,0) about (30,40) by +90° lands at (30+40, 40−30) =
    // (70,10) relative to the pivot — a quarter turn takes (x,y) to
    // (−y,x), so the offset (−30,−40) becomes (40,−30).
    expect(turned.x, closeTo(pivot.x + 70, 1e-9));
    expect(turned.y, closeTo(pivot.y + 10, 1e-9));
  });

  test('🚨SCALE ignores the anchor — it is always about the box centre', () {
    final anchored = SelectionAffine(
      pivot: pivot,
      sx: 2,
      sy: 2,
      anchorX: 30,
      anchorY: 40,
    );
    final plain = SelectionAffine(pivot: pivot, sx: 2, sy: 2);
    final point = CanvasPoint(x: 160, y: 90);

    final a = anchored.apply(point);
    final b = plain.apply(point);
    expect(a.x, closeTo(b.x, 1e-9));
    expect(a.y, closeTo(b.y, 1e-9));
    // ⛔CONTROL: the scale did something, so this is not two identities.
    expect(b.x, closeTo(pivot.x + 120, 1e-9));
  });

  test('⚠️tx/ty stay the USER\'S move — the panel digits must not drift', () {
    final affine = SelectionAffine(
      pivot: pivot,
      rotationDegrees: 37,
      tx: 15,
      ty: -4,
      anchorX: 30,
      anchorY: 40,
    );

    expect(affine.tx, 15, reason: 'X is what the user asked for');
    expect(affine.ty, -4, reason: 'and so is Y');
    // ⛔CONTROL: the anchor's shift is REAL, so the pin above is not
    // passing because the two happen to be equal.
    expect(affine.appliedTx, isNot(closeTo(15, 1e-6)));
  });

  test('with no anchor nothing moved — the old composite, byte for byte', () {
    final before = SelectionAffine(
      pivot: pivot,
      sx: 1.5,
      sy: 1.5,
      rotationDegrees: 30,
      tx: 7,
      ty: -3,
    );
    expect(before.appliedTx, 7);
    expect(before.appliedTy, -3);
  });

  test('applyInverse undoes apply with an anchor in play', () {
    final affine = SelectionAffine(
      pivot: pivot,
      sx: 1.5,
      sy: 0.8,
      rotationDegrees: 23,
      tx: 11,
      ty: 6,
      anchorX: -20,
      anchorY: 35,
    );
    final point = CanvasPoint(x: 42, y: 77);
    final back = affine.applyInverse(affine.apply(point));

    expect(back.x, closeTo(point.x, 1e-9));
    expect(back.y, closeTo(point.y, 1e-9));
  });

  test('⛔moving the anchor alone lands nothing — isIdentity holds', () {
    final affine = SelectionAffine(pivot: pivot, anchorX: 30, anchorY: 40);
    expect(affine.isIdentity, isTrue);
    expect(affine.appliedTx, 0, reason: 'no rotation, so it costs nothing');
  });

  test('copyWith carries the anchor', () {
    final affine = SelectionAffine(
      pivot: pivot,
      anchorX: 30,
      anchorY: 40,
    ).copyWith(rotationDegrees: 90);

    expect(affine.anchorX, 30);
    expect(affine.anchorY, 40);
  });
}

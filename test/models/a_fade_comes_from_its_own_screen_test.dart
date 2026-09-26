import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/transition_geometry.dart';

/// 🗣️F-192 (유저 2026-09-27): 「컷의 f.i은 빈공간에서가 생기는게 아니라,
/// 컷의 페이드인은 애초에 쌩 검은화면에서 바뀐단거였음. 화이트인은 쌩
/// 흰화면에서 바뀌는거고. 그러니 페이드인아웃이랑 화이트인아웃 변경.
/// 백그라운드색을 바꾸는거말고 구조적으로 흰화면에서 바뀌도록」.
///
/// A one-sided transition no longer thins its cut's picture (which showed
/// whatever lay below — black only while the backdrop was) — it lays its
/// own SCREEN over it: black for F.I/F.O, white for W.I/W.O.
void main() {
  const black = 0xFF000000;
  const white = 0xFFFFFFFF;
  // One cut, [0, 24).
  const cutStart = 0;
  const cutEnd = 24;

  List<TransitionVeil> veilsAt(TransitionSpan span, int frame) =>
      cutTransitionVeilsAt(
        cutStart: cutStart,
        cutEnd: cutEnd,
        spans: [span],
        globalFrame: frame,
      );

  double opacityAt(TransitionSpan span, int frame) => cutOpacityAt(
    cutStart: cutStart,
    cutEnd: cutEnd,
    spans: [span],
    globalFrame: frame,
  );

  test('each wedge names its screen — black for F, white for W, none for '
      'the bowtie', () {
    expect(transitionScreenColorOf(CameraInstructionMarkType.fi), black);
    expect(transitionScreenColorOf(CameraInstructionMarkType.fo), black);
    expect(transitionScreenColorOf(CameraInstructionMarkType.wi), white);
    expect(transitionScreenColorOf(CameraInstructionMarkType.wo), white);
    expect(transitionScreenColorOf(CameraInstructionMarkType.ol), isNull);
    expect(transitionScreenColorOf(CameraInstructionMarkType.bar), isNull);
    expect(
      transitionSidesOf(CameraInstructionMarkType.wi),
      TransitionSides.fadesIn,
    );
    expect(
      transitionSidesOf(CameraInstructionMarkType.wo),
      TransitionSides.fadesOut,
    );
  });

  test('an F.O closes its black screen over a WHOLE picture', () {
    const fo = (start: 19, length: 5, mark: CameraInstructionMarkType.fo);
    expect(veilsAt(fo, 19), isEmpty, reason: 'the first frame is clear');
    expect(veilsAt(fo, 21), [(color: black, opacity: 0.5)]);
    expect(veilsAt(fo, 23), [(color: black, opacity: 1.0)]);
    for (final frame in [19, 21, 23]) {
      expect(
        opacityAt(fo, frame),
        1.0,
        reason: 'frame $frame: the picture is not thinned — nothing below '
            'it ever shows through a fade',
      );
    }
  });

  test('an F.I opens from a solid black screen', () {
    const fi = (start: 0, length: 5, mark: CameraInstructionMarkType.fi);
    expect(veilsAt(fi, 0), [(color: black, opacity: 1.0)]);
    expect(veilsAt(fi, 2), [(color: black, opacity: 0.5)]);
    expect(veilsAt(fi, 4), isEmpty, reason: 'clear on its last frame');
    expect(opacityAt(fi, 0), 1.0);
  });

  test('W.I and W.O are the same shapes on a WHITE screen', () {
    const wi = (start: 0, length: 5, mark: CameraInstructionMarkType.wi);
    const wo = (start: 19, length: 5, mark: CameraInstructionMarkType.wo);
    expect(veilsAt(wi, 0), [(color: white, opacity: 1.0)]);
    expect(veilsAt(wo, 23), [(color: white, opacity: 1.0)]);
    expect(opacityAt(wo, 23), 1.0);
  });

  test('D26 still refuses a crossing fade — no screen either', () {
    const across = (start: 20, length: 8, mark: CameraInstructionMarkType.fo);
    for (final frame in [20, 23]) {
      expect(veilsAt(across, frame), isEmpty, reason: 'frame $frame');
    }
  });

  test('an O.L lays no screen — it is two pictures crossing', () {
    const ol = (start: 20, length: 8, mark: CameraInstructionMarkType.ol);
    for (final frame in [20, 23]) {
      expect(veilsAt(ol, frame), isEmpty, reason: 'frame $frame');
    }
    expect(opacityAt(ol, 23), lessThan(1.0), reason: 'and still dissolves');
  });

  group('the vocabulary', () {
    test('the standard W terms wear their own marks', () {
      final standard = CameraInstructionSet.standard;
      expect(standard.defById('wi')!.markType, CameraInstructionMarkType.wi);
      expect(standard.defById('wo')!.markType, CameraInstructionMarkType.wo);
      expect(standard.defById('fi')!.markType, CameraInstructionMarkType.fi);
      expect(standard.defById('fo')!.markType, CameraInstructionMarkType.fo);
    });

    test('a file from before, whose W terms wore the black wedges, reads '
        'them as white', () {
      CameraInstructionMarkType read(String id, String mark) =>
          CameraInstructionDef.fromJson({
            'id': id,
            'name': id.toUpperCase(),
            'iconKey': id,
            'markType': mark,
          }).markType;
      expect(read('wi', 'fi'), CameraInstructionMarkType.wi);
      expect(read('wo', 'fo'), CameraInstructionMarkType.wo);
      expect(
        read('custom-1', 'fi'),
        CameraInstructionMarkType.fi,
        reason: 'a custom fade keeps the screen it chose',
      );
      expect(
        read('wi', 'wi'),
        CameraInstructionMarkType.wi,
        reason: 'and a new file round-trips',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/envelope/cut_envelope_form.dart';
import 'package:anicel/src/models/envelope/cut_envelope_layout.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';

/// Fitting a form onto paper. The paper is either a real 봉투 size or the
/// cut's own canvas (so the export drops into a working file as a layer);
/// the form keeps its ratio either way and the remainder stays margin.
void main() {
  CutEnvelopeForm form(double aspect, List<EnvelopeBox> boxes) =>
      CutEnvelopeForm(
        id: 'test',
        name: 'Test',
        aspectRatio: aspect,
        boxes: boxes,
      );

  const full = EnvelopeBox(
    id: 'full',
    rect: EnvelopeRect(x: 0, y: 0, width: 1, height: 1),
  );

  test('paper of the same shape holds the form with no margin', () {
    final layout = CutEnvelopeLayout.fit(
      form: form(2, const [full]),
      paperWidth: 400,
      paperHeight: 200,
    );

    expect(layout.formX, 0);
    expect(layout.formY, 0);
    expect(layout.formWidth, 400);
    expect(layout.formHeight, 200);
    expect(layout.hasMargin, isFalse);
  });

  test('a TALLER paper leaves the margin above and below', () {
    final layout = CutEnvelopeLayout.fit(
      form: form(2, const [full]),
      paperWidth: 400,
      paperHeight: 400,
    );

    expect(layout.formWidth, 400);
    expect(layout.formHeight, 200);
    expect(layout.formY, 100, reason: 'centred, remainder left as margin');
    expect(layout.hasMargin, isTrue);
  });

  test('a WIDER paper leaves the margin at the sides', () {
    final layout = CutEnvelopeLayout.fit(
      form: form(1, const [full]),
      paperWidth: 400,
      paperHeight: 200,
    );

    expect(layout.formWidth, 200);
    expect(layout.formHeight, 200);
    expect(layout.formX, 100);
  });

  test('the form CONTAINS rather than covers — no box is cropped', () {
    final layout = CutEnvelopeLayout.fit(
      form: form(3, const [full]),
      paperWidth: 300,
      paperHeight: 300,
    );

    final placed = layout.place(full);
    expect(placed.right, lessThanOrEqualTo(300));
    expect(placed.bottom, lessThanOrEqualTo(300));
  });

  test('a box lands where its fractions say', () {
    final layout = CutEnvelopeLayout.fit(
      form: form(1, const [
        EnvelopeBox(
          id: 'quarter',
          rect: EnvelopeRect(x: 0.5, y: 0.25, width: 0.5, height: 0.5),
        ),
      ]),
      paperWidth: 200,
      paperHeight: 200,
    );

    final placed = layout.placedBoxes.single;
    expect(placed.x, 100);
    expect(placed.y, 50);
    expect(placed.width, 100);
    expect(placed.height, 100);
  });

  test('inkBoxAt finds the box under a point and skips display-only ones', () {
    final layout = CutEnvelopeLayout.fit(
      form: form(1, const [
        EnvelopeBox(
          id: 'cell',
          rect: EnvelopeRect(x: 0, y: 0, width: 1, height: 1),
        ),
        EnvelopeBox(
          id: 'logo',
          rect: EnvelopeRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
          takesInk: false,
        ),
      ]),
      paperWidth: 100,
      paperHeight: 100,
    );

    expect(layout.inkBoxAt(10, 10)?.id, 'cell');
    expect(
      layout.inkBoxAt(75, 75)?.id,
      'cell',
      reason: 'the logo takes no ink, so the cell under it keeps the stroke',
    );
    expect(layout.inkBoxAt(-1, 10), isNull);
  });

  test('an inner box wins over the one it sits on', () {
    final layout = CutEnvelopeLayout.fit(
      form: form(1, const [
        EnvelopeBox(
          id: 'outer',
          rect: EnvelopeRect(x: 0, y: 0, width: 1, height: 1),
        ),
        EnvelopeBox(
          id: 'inner',
          rect: EnvelopeRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
        ),
      ]),
      paperWidth: 100,
      paperHeight: 100,
    );

    expect(layout.inkBoxAt(50, 50)?.id, 'inner');
    expect(layout.inkBoxAt(5, 5)?.id, 'outer');
  });

  test('paper with no size is refused rather than dividing by zero', () {
    expect(
      () => CutEnvelopeLayout.fit(
        form: form(1, const [full]),
        paperWidth: 0,
        paperHeight: 100,
      ),
      throwsArgumentError,
    );
  });

  group('bundled presets on real paper', () {
    test('the analog form fits a cut canvas with margin top and bottom', () {
      final layout = CutEnvelopeLayout.fit(
        form: CutEnvelopePresets.analog,
        paperWidth: 1920,
        paperHeight: 1080,
      );

      expect(layout.formWidth, lessThanOrEqualTo(1920));
      expect(layout.formHeight, lessThanOrEqualTo(1080));
      expect(layout.hasMargin, isTrue);
      for (final placed in layout.placedBoxes) {
        expect(placed.x, greaterThanOrEqualTo(-0.01), reason: placed.box.id);
        expect(placed.right, lessThanOrEqualTo(1920.01), reason: placed.box.id);
      }
    });

    test('text scales with the form, not with the paper', () {
      final small = CutEnvelopeLayout.fit(
        form: CutEnvelopePresets.analog,
        paperWidth: 660,
        paperHeight: 497,
      );
      final large = CutEnvelopeLayout.fit(
        form: CutEnvelopePresets.analog,
        paperWidth: 1320,
        paperHeight: 994,
      );

      expect(small.textScale, closeTo(1, 0.001));
      expect(large.textScale, closeTo(2, 0.001));
    });
  });
}

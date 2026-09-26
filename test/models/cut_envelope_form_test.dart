import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/envelope/cut_envelope_counts.dart';
import 'package:anicel/src/models/envelope/cut_envelope_form.dart';
import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';
import 'package:anicel/src/models/envelope/cut_envelope_source.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timesheet_info.dart';

/// The envelope FORM is data: boxes in form-space fractions, each holding
/// a printed label, a bound value, or nothing but handwriting space.
void main() {
  const source = CutEnvelopeSource(
    title: 'ゴールデンタイム',
    episode: '13',
    note: 'PAN (A)→(B)',
    cuts: [
      CutEnvelopeCutLine(name: '20', durationFrames: 120, fps: 24),
      CutEnvelopeCutLine(name: '39A', durationFrames: 60, fps: 24),
    ],
    cels: [
      CutEnvelopeCelCount(name: 'A', genga: 16, dougaEstimate: 23),
      CutEnvelopeCelCount(name: 'B', genga: 11, dougaEstimate: 14),
    ],
    staff: {'key': '大川', 'inbetween': '山田'},
    logoAssetPath: 'logos/studio.png',
    canvasWidth: 2340,
    canvasHeight: 1654,
  );

  group('text bindings', () {
    test('project and cut fields resolve', () {
      expect(resolveEnvelopeText('{title}', source), 'ゴールデンタイム');
      expect(resolveEnvelopeText('{episode}', source), '13');
      expect(resolveEnvelopeText('{note}', source), 'PAN (A)→(B)');
      expect(resolveEnvelopeText('{cut[0].name}', source), '20');
      expect(resolveEnvelopeText('{cut[0].seconds}', source), '5');
      expect(resolveEnvelopeText('{cut[0].frames}', source), '0');
      expect(resolveEnvelopeText('{cut[1].length}', source), '2+12');
    });

    test('a cut name prints VERBATIM — no prefix, no padding', () {
      expect(
        resolveEnvelopeText('{cut[1].name}', source),
        '39A',
        reason: 'the form already prints C; the name is the user\'s string',
      );
    });

    test('cel rows and the total resolve', () {
      expect(resolveEnvelopeText('{cel[0].name}', source), 'A');
      expect(resolveEnvelopeText('{cel[0].genga}', source), '16');
      expect(resolveEnvelopeText('{cel[1].douga}', source), '14');
      expect(resolveEnvelopeText('{total.genga}', source), '27');
      expect(resolveEnvelopeText('{total.douga}', source), '37');
    });

    test('staff names resolve; an unheld role prints nothing', () {
      expect(resolveEnvelopeText('{staff.key.name}', source), '大川');
      expect(resolveEnvelopeText('{staff.layout.name}', source), isNull);
    });

    test('an index past the end prints nothing rather than throwing', () {
      expect(resolveEnvelopeText('{cut[7].name}', source), isNull);
      expect(resolveEnvelopeText('{cel[7].genga}', source), isNull);
    });

    test('an unmeasured size prints nothing rather than 0', () {
      expect(resolveEnvelopeText('{canvas.width}', source), '2340');
      expect(
        resolveEnvelopeText('{camera.width}', source),
        isNull,
        reason: 'this source never measured the camera',
      );
    });

    test('an unknown token prints nothing, never a literal brace', () {
      expect(resolveEnvelopeText('{nope}', source), isNull);
      expect(resolveEnvelopeText('{cut[0].nope}', source), isNull);
      expect(resolveEnvelopeText('not a token', source), isNull);
    });
  });

  group('image bindings', () {
    test('the logo resolves to its asset path', () {
      expect(resolveEnvelopeImage('{logo}', source), 'logos/studio.png');
    });
  });

  group('🚨the staff a form prints is the colour labels\' staff', () {
    // The info window wrote the process keys (`key` · `inbetween` …) while
    // the bundled forms read a vocabulary of their own (`genga` · `douga`
    // · `director` …): the two sets never met, so no name ever reached an
    // envelope (09-25). The probe below used to re-point every role at one
    // entry, which is exactly how the mismatch stayed green.
    final labels = {
      for (final mark in everyLayerMark())
        if (!mark.isNone) mark.keySlug,
    };
    final staffName = RegExp(r'^\{staff\.(.+)\.name\}$');

    for (final form in CutEnvelopePresets.all) {
      test('${form.id}: every staff binding names a colour label', () {
        for (final box in form.boxes) {
          final match = staffName.firstMatch(box.binding ?? '');
          if (match == null) {
            continue;
          }
          expect(labels, contains(match.group(1)), reason: box.id);
        }
      });
    }

    test('a name written through the work\'s staff reaches the 原画 and 動画 '
        'boxes', () {
      final info = TimesheetInfo.empty
          .withStaffName(const LayerMark(process: LayerProcess.key), '大川')
          .withStaffName(
            const LayerMark(process: LayerProcess.inbetween),
            '山田',
          );
      final written = CutEnvelopeSource(staff: info.staff);
      String? printed(String boxId) => resolveEnvelopeText(
        CutEnvelopePresets.analog.boxById(boxId)!.binding!,
        written,
      );

      expect(printed('staff-name-genga'), '大川');
      expect(printed('staff-name-douga'), '山田');
    });

    test('the roles the labels do not have are left for the pen', () {
      // 유저 답 envelope-roles-without-label: 「빈칸으로 두고 손으로 쓴다」.
      for (final id in [
        'staff-name-colorDesign',
        'staff-name-scan',
        'staff-name-tracePaint',
      ]) {
        final box = CutEnvelopePresets.analog.boxById(id)!;
        expect(box.contentKind, EnvelopeContentKind.blank, reason: id);
        expect(box.takesInk, isTrue, reason: id);
      }
    });

    test('⛔a stamp space binds nothing — a 도장 is made per cut on the '
        'envelope', () {
      // 유저 09-25: 「도장이나 체크나 이런거는 그냥 전처럼 컷봉투 내에서
      // 조작」 — the work's staff carries no stamp.
      final analog = CutEnvelopePresets.analog;
      final digital = CutEnvelopePresets.digital;
      for (final box in [
        for (final role in [
          'director',
          'animationDirector',
          'inbetweenCheck',
          'colorCheck',
        ])
          analog.boxById('approval-$role')!,
        for (var index = 0; index < 4; index += 1)
          digital.boxById('lo-stamp-$index')!,
        for (var index = 0; index < 2; index += 1)
          digital.boxById('genga-stamp-$index')!,
      ]) {
        expect(box.contentKind, EnvelopeContentKind.blank, reason: box.id);
        expect(box.takesInk, isTrue, reason: box.id);
      }
    });
  });

  group('bundled presets', () {
    for (final form in CutEnvelopePresets.all) {
      test('${form.id}: box ids are unique', () {
        final ids = form.boxes.map((box) => box.id).toList();
        expect(ids.toSet(), hasLength(ids.length));
      });

      test('${form.id}: every box sits inside the form', () {
        for (final box in form.boxes) {
          expect(box.rect.x, greaterThanOrEqualTo(0), reason: box.id);
          expect(box.rect.y, greaterThanOrEqualTo(0), reason: box.id);
          expect(box.rect.right, lessThanOrEqualTo(1.0001), reason: box.id);
          expect(box.rect.bottom, lessThanOrEqualTo(1.0001), reason: box.id);
          expect(box.rect.width, greaterThan(0), reason: box.id);
          expect(box.rect.height, greaterThan(0), reason: box.id);
        }
      });

      test('${form.id}: every bound box resolves against a full source', () {
        for (final box in form.boxes) {
          if (box.contentKind == EnvelopeContentKind.blank) {
            continue;
          }
          final binding = box.binding!;
          // A binding may legitimately resolve to null (an index past the
          // end, an unheld role) — what must not happen is a token the
          // grammar does not know at all.
          final known =
              resolveEnvelopeText(binding, source) != null ||
              resolveEnvelopeImage(binding, source) != null ||
              _isAddressable(binding);
          expect(known, isTrue, reason: '${box.id} binds $binding');
        }
      });

      test('${form.id}: round-trips through JSON', () {
        expect(CutEnvelopeForm.fromJson(form.toJson()), form);
      });

      test('${form.id}: display-only boxes take no ink', () {
        final logo = form.boxById('logo');
        expect(logo, isNotNull);
        expect(
          logo!.takesInk,
          isFalse,
          reason: 'a box that only shows a mark must not compete for strokes',
        );
      });
    }

    test('the analog form is the WIT sheet: kraft paper, four cut lines', () {
      final form = CutEnvelopePresets.analog;

      expect(form.paperArgb, 0xFFE3D5B0);
      expect([
        for (var i = 0; i < 4; i += 1) form.boxById('cut-$i-number'),
      ], everyElement(isNotNull));
      expect(form.boxById('cut-4-number'), isNull);
    });

    test('the digital form has no cut lines and no kraft', () {
      final form = CutEnvelopePresets.digital;

      expect(form.paperArgb, 0xFFFFFFFF);
      expect(form.boxById('cut-0-number'), isNull);
      expect(form.boxById('memo'), isNotNull);
    });

    test('byId falls back to the analog form for an unknown id', () {
      expect(CutEnvelopePresets.byId('nope').id, CutEnvelopePresets.analogId);
      expect(
        CutEnvelopePresets.byId(CutEnvelopePresets.digitalId).id,
        CutEnvelopePresets.digitalId,
      );
    });
  });
}

/// Whether a binding names something the grammar can address at all, even
/// when this particular source has nothing for it.
bool _isAddressable(String binding) {
  // Deep enough that any index a bundled form prints is addressable — the
  // question here is whether the GRAMMAR knows the token, not whether this
  // project happens to fill it.
  final empty = CutEnvelopeSource(
    cuts: [
      for (var i = 0; i < 32; i += 1)
        const CutEnvelopeCutLine(name: 'x', durationFrames: 1, fps: 24),
    ],
    cels: [
      for (var i = 0; i < 32; i += 1)
        const CutEnvelopeCelCount(name: 'x', genga: 0, dougaEstimate: 0),
    ],
    staff: const {'probe': 'x'},
    logoAssetPath: 'x',
    canvasWidth: 1,
    canvasHeight: 1,
    cameraWidth: 1,
    cameraHeight: 1,
  );
  // Re-point any staff role at the probe entry so role-shaped tokens are
  // recognised even when nobody holds that role here. ⚠️Only the GRAMMAR:
  // whether the role is one the labels have is the group above.
  final probed = binding.replaceAll(
    RegExp(r'\{staff\.[\w-]+\.'),
    '{staff.probe.',
  );
  return resolveEnvelopeText(probed, empty) != null ||
      resolveEnvelopeImage(probed, empty) != null;
}

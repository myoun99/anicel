import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_hand_settings.dart';
import 'package:anicel/src/models/brush_input_source.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_order.dart';
import 'package:anicel/src/services/brush_hand_overlay.dart';

/// 🚨H25-again (유저 2026-09-11): 「사이즈말고도 불투명도나 필압이나 이런거
/// 문제있을수있으니 싹 다 확인하고 법 하나로 통일」.
///
/// The law these hold: what the hand set on a brush comes back with that
/// brush, WHICHEVER setting it was — and what it did not touch keeps
/// following the brush's own file.
void main() {
  BrushTipMask tip(String id, [int shade = 255]) => BrushTipMask(
    id: id,
    size: 2,
    alpha: Uint8List.fromList([0, 90, 180, shade]),
  );

  final file = BrushSettings(
    size: 10,
    hardness: 1.0,
    spacing: 0.08,
    sizePressureCurve: BrushPressureCurve.linearFrom(0.08),
    tips: [tip('nib')],
  );

  bool nameable(BrushTipMask _) => true;
  bool unnameable(BrushTipMask _) => false;

  /// The hand's copy of [file] with [edit] made to it.
  BrushSettings handOf(BrushSettings Function(BrushSettings) edit) =>
      edit(file);

  String jsonOf(BrushSettings settings) => jsonEncode(settings.toJson());

  test('an untouched brush has nothing to remember', () {
    expect(brushHandOverlay(file: file, hand: file, byName: nameable), isEmpty);
  });

  test('⛔the COLOUR is never remembered per brush (R9 #2)', () {
    final hand = BrushSettings.fromShape(file.shape.copyWith(color: 0xFFFF0000));

    expect(brushHandOverlay(file: file, hand: hand, byName: nameable), isEmpty);
  });

  // Every kind of setting the panel changes, through the ONE law — the list
  // the bank kept before had three entries, and these are the rest.
  final edits = <String, BrushSettings Function(BrushSettings)>{
    'size': (s) => s.copyWith(size: 44),
    'opacity': (s) => s.copyWith(opacity: 0.4),
    'flow': (s) => s.copyWith(flow: 0.3),
    'hardness': (s) => s.copyWith(hardness: 0.5),
    'spacing': (s) => s.copyWith(spacing: 0.3),
    'the size pressure curve': (s) =>
        s.copyWith(sizePressureCurve: BrushPressureCurve.linearFrom(0.6)),
    'an opacity pressure curve': (s) =>
        s.copyWith(opacityPressureCurve: BrushPressureCurve.identity()),
    'the blend': (s) => s.copyWith(blendMode: BrushBlendMode.multiply),
    'the edge': (s) => s.copyWith(antiAlias: BrushAntiAlias.none),
    // A row with a floor of its own: the curve's object form (F-176-Q2).
    'the size random row': (s) => BrushSettings.fromShape(
      s.shape.withCurve(
        BrushPressureTarget.size,
        BrushInputSource.random,
        BrushPressureCurve.linearFrom(0.6),
      ),
    ),
  };
  for (final MapEntry(key: what, value: edit) in edits.entries) {
    test('🚨$what comes back with its brush', () {
      final hand = handOf(edit);

      final overlay = brushHandOverlay(file: file, hand: hand, byName: nameable);

      expect(overlay, isNotEmpty, reason: 'premise: the edit changed it');
      expect(jsonOf(brushSettingsUnderHand(file, overlay)), jsonOf(hand));
    });
  }

  test('a setting the hand REMOVED stays removed', () {
    final hand = BrushSettings.fromJson(
      file.toJson(withMasks: false)..remove('sizePressureCurve'),
    ).copyWith(tips: file.tips);

    final overlay = brushHandOverlay(file: file, hand: hand, byName: nameable);

    expect(overlay, {'sizePressureCurve': null});
    expect(brushSettingsUnderHand(file, overlay).sizePressureCurve, isNull);
  });

  test('🚨what the hand did NOT touch keeps following the file — even a file '
      'that changed since', () {
    final overlay = brushHandOverlay(
      file: file,
      hand: file.copyWith(size: 44),
      byName: nameable,
    );
    final newer = file.copyWith(hardness: 0.25);

    final back = brushSettingsUnderHand(newer, overlay);

    expect(back.size, 44, reason: 'what the hand set');
    expect(back.hardness, 0.25, reason: 'what the file says now');
  });

  group('tips', () {
    test('a tip the library can hand back is written by its id, and comes '
        'back through it', () {
      final other = tip('other', 128);
      final overlay = brushHandOverlay(
        file: file,
        hand: file.copyWith(tips: [other]),
        byName: nameable,
      );

      expect(overlay, {'tipMaskId': 'other'});
      expect(
        brushSettingsUnderHand(
          file,
          overlay,
          resolveTip: (id) => id == 'other' ? other : null,
        ).tipMask,
        same(other),
      );
    });

    test('🚨one it CANNOT hand back travels whole — nothing is left pointing '
        'at a tip that is not there', () {
      final stray = tip('stray', 77);
      final overlay = brushHandOverlay(
        file: file,
        hand: file.copyWith(tips: [stray]),
        byName: unnameable,
      );

      final back = brushSettingsUnderHand(
        file,
        jsonDecode(jsonEncode(overlay)) as Map<String, Object?>,
      );

      expect(back.tipMask?.id, 'stray');
      expect(back.tipMask?.alpha, stray.alpha);
    });

    test('an id nothing answers leaves the FILE\'s tip — a missing tip costs '
        'the brush its texture, never the pick', () {
      final back = brushSettingsUnderHand(
        file,
        {'tipMaskId': 'gone'},
        resolveTip: (_) => null,
      );

      expect(back.tipMask, same(file.tipMask));
    });

    test('a tip the hand cleared stays cleared', () {
      final overlay = brushHandOverlay(
        file: file,
        hand: BrushSettings.fromJson(file.toJson(withMasks: false)),
        byName: nameable,
      );

      expect(overlay, {'tipMask': null});
      expect(brushSettingsUnderHand(file, overlay).tipMask, isNull);
    });

    // F-176-Q3: a brush carries several tips, in an order of the hand's.
    List<String> idsOf(BrushSettings settings) => [
      for (final tip in settings.tips) tip.id,
    ];

    test('the tips after the first are written by their ids, in order, and '
        'come back so', () {
      final a = tip('a', 10);
      final b = tip('b', 20);
      final overlay = brushHandOverlay(
        file: file,
        hand: file.copyWith(tips: [file.tipMask!, a, b]),
        byName: nameable,
      );

      expect(overlay, {
        'moreTipMasksId': ['a', 'b'],
      });
      final back = brushSettingsUnderHand(
        file,
        overlay,
        resolveTip: (id) => {'a': a, 'b': b}[id],
      );
      expect(idsOf(back), ['nib', 'a', 'b']);
    });

    test('🚨a list holding one tip the library cannot hand back travels '
        'WHOLE — names and pixels never mix in one entry', () {
      final a = tip('a', 10);
      final stray = tip('stray', 77);
      final overlay = brushHandOverlay(
        file: file,
        hand: file.copyWith(tips: [file.tipMask!, a, stray]),
        byName: (tip) => tip.id != 'stray',
      );

      expect(overlay.keys, ['moreTipMasks']);
      final back = brushSettingsUnderHand(
        file,
        jsonDecode(jsonEncode(overlay)) as Map<String, Object?>,
      );
      expect(idsOf(back), ['nib', 'a', 'stray']);
      expect(back.tips.last.alpha, stray.alpha);
    });

    test('a brush the hand cut back to one tip stays cut', () {
      final several = file.copyWith(tips: [file.tipMask!, tip('a', 10)]);
      final overlay = brushHandOverlay(
        file: several,
        hand: file,
        byName: nameable,
      );

      expect(overlay, {'moreTipMasks': null});
      expect(idsOf(brushSettingsUnderHand(several, overlay)), ['nib']);
    });

    test('ids that are not ALL answered leave the file\'s tips', () {
      final a = tip('a', 10);
      final several = file.copyWith(tips: [file.tipMask!, tip('b', 20)]);
      final back = brushSettingsUnderHand(
        several,
        {
          'moreTipMasksId': ['a', 'gone'],
        },
        resolveTip: (id) => id == 'a' ? a : null,
      );

      expect(idsOf(back), ['nib', 'b']);
    });

    test('the order the dabs take them in is the hand\'s too', () {
      final overlay = brushHandOverlay(
        file: file,
        hand: file.copyWith(tipOrder: BrushTipOrder.random),
        byName: nameable,
      );

      expect(overlay, {'tipOrder': 'random'});
      expect(
        brushSettingsUnderHand(file, overlay).tipOrder,
        BrushTipOrder.random,
      );
    });
  });

  test('🚨an exported file carries every brush the hand set, each changed '
      'tip WHOLE — and leaves the eraser\'s entries home', () {
    final other = tip('other', 128);
    final bank = <String, BrushHandSettings>{
      'pen': {'tipMaskId': 'other', 'flow': 0.3},
      'eraser:pen': {'size': 80.0},
      'deleted': {'size': 5.0},
    };

    final carried = brushHandSettingsToCarry(
      bank,
      fileOf: (key) => key == 'pen' ? file : null,
      resolveTip: (id) => id == 'other' ? other : null,
    );

    expect(carried.keys, ['pen'], reason: 'only a brush the file can name');
    expect(carried['pen']?['flow'], 0.3);
    expect(
      carried['pen']?.containsKey('tipMaskId'),
      isFalse,
      reason: 'the other side has no tip library to resolve an id against',
    );
    expect(
      (carried['pen']?['tipMask'] as Map<String, dynamic>?)?['id'],
      'other',
    );
  });

  test('⚠️an overlay this build cannot read degrades to the FILE, whole', () {
    expect(
      jsonOf(brushSettingsUnderHand(file, {'size': 'not a number'})),
      jsonOf(file),
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/key_mark.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/timeline_frame_range.dart'
    show TimelineLaneSelection;
import 'package:anicel/src/ui/timeline/effect_lane_editing.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart';
import 'package:anicel/src/ui/timeline/lane_span_keys_shift.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_row_span_resolver.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// The effect lanes' side of the shared lane substrate (R6): the addresses,
/// the rows, and the pure key edits the host commits as one undo.
void main() {
  LayerEffect blur({
    double blurriness = 0,
    double dimensions = 0,
    String id = 'e1',
  }) =>
      LayerEffect(
        id: EffectId(id),
        kind: EffectKind.blur,
        parameters: {
          'blurriness': EffectParameter(value: blurriness),
          'blurDimensions': EffectParameter(value: dimensions),
        },
      );

  LayerEffect hue({String id = 'e2'}) =>
      LayerEffect.defaults(id: EffectId(id), kind: EffectKind.hueSaturation);

  group('lane addresses', () {
    test('round-trip, and never collide with the transform lane ids', () {
      const effectId = EffectId('e1');
      final laneId = effectLaneId(effectId, 'blurriness');
      final address = parseEffectLaneId(laneId);
      expect(address!.effectId, effectId);
      expect(address.parameterId, 'blurriness');

      final header = parseEffectLaneId(effectGroupLaneId(effectId));
      expect(header!.effectId, effectId);
      expect(header.parameterId, isNull);

      for (final transformLane in transformLaneDisplayOrder) {
        expect(parseEffectLaneId(transformLane), isNull, reason: transformLane);
      }
      expect(parseEffectLaneId(transformGroupHeaderLane.laneId), isNull);
      expect(parseEffectLaneId('se-audio'), isNull);
    });

    test('malformed addresses answer null instead of a wrong effect', () {
      expect(parseEffectLaneId('fx:'), isNull);
      expect(parseEffectLaneId('fx:only-an-id'), isNull);
      expect(parseEffectLaneId('fx:e1:'), isNull);
      expect(parseEffectLaneId('fx-group:'), isNull);
    });
  });

  group('lane rows', () {
    test('a collapsed effect shows its header alone, with the key union', () {
      final animated = LayerEffect(
        id: const EffectId('e1'),
        kind: EffectKind.blur,
        parameters: {
          'blurriness': EffectParameter(
            track: PropertyTrack<double>(
              keys: {3: const PropertyKey<double>(4)},
            ),
          ),
          'blurDimensions': EffectParameter(
            track: PropertyTrack<double>(
              keys: {7: const PropertyKey<double>(2)},
            ),
          ),
        },
      );
      final rows = effectPropertyLanes([animated], isExpanded: (_) => false);
      expect(rows, hasLength(1));
      expect(rows.single.isGroupHeader, isTrue);
      expect(rows.single.groupExpanded, isFalse);
      expect(rows.single.keyedFrames, {3, 7});
      expect(rows.single.showsKeyNavigator, isFalse);
    });

    test('a parameter lane marks the keys that hold out of them', () {
      final held = LayerEffect(
        id: const EffectId('e1'),
        kind: EffectKind.blur,
        parameters: {
          'blurriness': EffectParameter(
            track: PropertyTrack<double>(
              keys: {
                3: const PropertyKey<double>(4, outgoing: KeyExit.hold),
                7: const PropertyKey<double>(2),
              },
            ),
          ),
        },
      );
      final rows = effectPropertyLanes([held], isExpanded: (_) => true);
      final lane = rows.singleWhere(
        (row) => row.laneId == effectLaneId(const EffectId('e1'), 'blurriness'),
      );
      expect(lane.keyMarks, {
        3: const SidesKeyMark(
          incoming: KeySideKind.linear,
          outgoing: KeySideKind.hold,
        ),
        7: KeyMark.linear,
      });
    });

    test('an expanded effect adds one lane per parameter, in spec order', () {
      final rows = effectPropertyLanes([hue()], isExpanded: (_) => true);
      expect(rows.map((row) => row.label), [
        'Hue/Saturation',
        'Master Hue',
        'Master Saturation',
        'Master Lightness',
      ]);
      expect(rows.skip(1).every((row) => row.showsKeyNavigator), isTrue);
    });

    test('two effects of the SAME kind keep separate lanes', () {
      final rows = effectPropertyLanes([
        blur(id: 'a'),
        blur(id: 'b'),
      ], isExpanded: (_) => true);
      final ids = rows.map((row) => row.laneId).toSet();
      expect(ids, hasLength(rows.length), reason: 'no address collision');
    });

    test('a disabled effect says so through the header\'s own fx switch', () {
      // The label stays the effect's NAME; the switch (AE's per-effect
      // eyeball) is what reads on/off.
      final rows = effectPropertyLanes([
        blur().copyWith(enabled: false),
      ], isExpanded: (_) => false);
      expect(rows.single.label, EffectKind.blur.label);
      expect(rows.single.groupEnabled, isFalse);
      expect(
        effectPropertyLanes([
          blur(),
        ], isExpanded: (_) => false).single.groupEnabled,
        isTrue,
      );
    });

    test('the value column formats per unit and parses back', () {
      final rows = effectPropertyLanes(
        [blur(blurriness: 8)],
        isExpanded: (_) => true,
        valueAt: (effectId, parameterId, frameIndex) =>
            parameterId == 'blurriness' ? 8 : 0,
      );
      final lane = rows.firstWhere((row) => row.label == 'Blurriness');
      expect(lane.valueLabel!(0), '8.00 px');
      final spec = EffectKind.blur.parameters.first;
      expect(parseEffectLaneValue(spec, '8.00 px'), 8);
      expect(parseEffectLaneValue(spec, '12'), 12);
      expect(parseEffectLaneValue(spec, 'wide'), isNull);
      expect(
        parseEffectLaneValue(spec, '-5'),
        0,
        reason: 'clamped to the spec',
      );
    });

    test('a MENU lane reads its word, takes a word back, and is no number '
        '(I-132-Q6)', () {
      final key = LayerEffect.defaults(
        id: const EffectId('k'),
        kind: EffectKind.colorKey,
      );
      final rows = effectPropertyLanes(
        [key],
        isExpanded: (_) => true,
        valueAt: (effectId, parameterId, frameIndex) =>
            parameterId == 'keyOperation' ? 1 : 0,
      );
      final lane = rows.firstWhere((row) => row.label == 'Key Operation');
      expect(lane.valueKind, PropertyLaneValueKind.choice);
      expect(lane.choices, ['Key Colors', 'Keep Colors']);
      expect(lane.valueLabel!(0), 'Keep Colors');
      expect(lane.scrubValue, isNull, reason: 'nothing between two words');
      final spec = EffectKind.colorKey.parameterSpec('keyOperation')!;
      expect(parseEffectLaneValue(spec, 'Keep Colors'), 1);
      expect(parseEffectLaneValue(spec, 'Key Colors'), 0);
      expect(parseEffectLaneValue(spec, '1'), isNull);
    });

    test('scrubbing moves the value in the form the editor parses', () {
      final spec = EffectKind.hueSaturation.parameters.first;
      expect(scrubEffectLaneValue(spec, '10°', const Offset(20, 0)), '20.00°');
      expect(
        scrubEffectLaneValue(spec, '10°', const Offset(-100, 0)),
        '-40.00°',
      );
      // Clamped at the spec edge, never past it.
      expect(
        scrubEffectLaneValue(spec, '170°', const Offset(200, 0)),
        '180.00°',
      );
    });
  });

  group('the lane span (R26 #3) — sliced out of the rows the rail DREW', () {
    const layerId = LayerId('l');
    final header = effectGroupLaneId(const EffectId('e2'));
    final order = effectLaneDisplayOrder(hue());
    // The rail's rows for one layer with its hue effect twirled open:
    // the cells row, the effect's header, then its members in order.
    final rows = <TimelineRowAddress?>[
      const LayerRowAddress(layerId),
      LaneRowAddress(layerId, header),
      for (final laneId in order) LaneRowAddress(layerId, laneId),
    ];
    List<String> span(String anchor, String head) => laneSpanOverDrawnRows(
      rows: rows,
      layerId: layerId,
      laneId: anchor,
      headLaneId: head,
    );

    test('R9 #20: the header is a ROW in the span — header to the LAST '
        'parameter still covers the whole effect, by the range rule', () {
      expect(span(header, order.last), [header, ...order]);
      expect(
        span(header, order.first),
        [header, order.first],
        reason: 'a drag over two rows selects two rows',
      );
      expect(
        span(header, 'x'),
        [header],
        reason: 'an unknown head leaves the anchor alone',
      );
    });

    test('two parameter lanes select the range between them', () {
      expect(
        span(
          effectLaneId(const EffectId('e2'), 'hue'),
          effectLaneId(const EffectId('e2'), 'saturation'),
        ),
        [
          effectLaneId(const EffectId('e2'), 'hue'),
          effectLaneId(const EffectId('e2'), 'saturation'),
        ],
      );
    });

    test('R9 #20: the header washes when IT is in the span, like every '
        'other row', () {
      const layerId = LayerId('l');
      final header = effectGroupLaneId(const EffectId('e2'));
      final members = effectLaneDisplayOrder(hue());
      bool covered(List<String> span) => laneSelectionCoversBandRow(
        TimelineLaneSelection(
          layerId: layerId,
          laneId: span.first,
          startIndex: 0,
          endIndexExclusive: 2,
          laneIds: span,
        ),
        layerId,
        header,
      );

      expect(covered([header, ...members]), isTrue);
      expect(
        covered(members),
        isFalse,
        reason: 'every MEMBER selected is not the header selected — the '
            'special case #20 retired',
      );
      expect(covered([members.first]), isFalse);
      expect(covered(transformLaneDisplayOrder), isFalse);
    });
  });

  group('key edits', () {
    test(
      'the diamond toggles a key at the RESOLVED value, then removes it',
      () {
        final effects = [blur(blurriness: 6)];
        final keyed = effectsWithLaneKeyToggled(
          effects,
          laneId: effectLaneId(const EffectId('e1'), 'blurriness'),
          frameIndex: 4,
        )!;
        expect(keyed.single.parameterOf('blurriness').track.keyAt(4)!.value, 6);
        final unkeyed = effectsWithLaneKeyToggled(
          keyed,
          laneId: effectLaneId(const EffectId('e1'), 'blurriness'),
          frameIndex: 4,
        )!;
        expect(unkeyed.single.parameterOf('blurriness').track.isEmpty, isTrue);
      },
    );

    test('R9 #18: a value edit KEYS even on an unanimated parameter — one '
        'rule with the transform lanes, which key unconditionally', () {
      final edited = effectsWithLaneValueEdited(
        [blur()],
        laneId: effectLaneId(const EffectId('e1'), 'blurriness'),
        frameIndex: 7,
        input: '9',
        scaleLinked: false,
      )!;
      final parameter = edited.single.parameterOf('blurriness');

      expect(parameter.track.keyAt(7)!.value, 9);
      expect(parameter.isAnimated, isTrue);
      // The pixels do not move on that first edit: one key resolves to
      // itself at every frame, exactly as the static slot did.
      expect(parameter.resolveAt(0), 9);
      expect(parameter.resolveAt(7), 9);
      expect(parameter.resolveAt(999), 9);
      // The static slot SURVIVES (the user's note: an AE stopwatch would
      // switch off into it) — the edit simply no longer writes it.
      expect(parameter.value, blur().parameterOf('blurriness').value);
    });

    test('a value edit KEYS at the playhead once animated (AE rule)', () {
      final animated = effectsWithLaneKeyToggled(
        [blur(blurriness: 6)],
        laneId: effectLaneId(const EffectId('e1'), 'blurriness'),
        frameIndex: 0,
      )!;
      final edited = effectsWithLaneValueEdited(
        animated,
        laneId: effectLaneId(const EffectId('e1'), 'blurriness'),
        frameIndex: 5,
        input: '9',
        scaleLinked: false,
      )!;
      expect(edited.single.parameterOf('blurriness').track.keyAt(5)!.value, 9);
    });

    test('a MENU lane\'s keys are steps — by its space, whatever sides a key '
        'wears (I-132-Q6 「키프레임은 계단」)', () {
      // Plain linear keys, as a paste from a number lane would bring them.
      LayerEffect keyed(String parameterId) => LayerEffect(
        id: const EffectId('k'),
        kind: EffectKind.colorKey,
        parameters: {
          'amount': EffectParameter(value: 100),
          parameterId: EffectParameter(
            track: PropertyTrack<double>(
              keys: {
                0: const PropertyKey<double>(0),
                10: const PropertyKey<double>(1),
              },
            ),
          ),
        },
      );
      double at(String parameterId, int frame) => resolveLayerEffectsAt(
        effects: [keyed(parameterId)],
        frameIndex: frame,
      ).single.parameter(parameterId);

      expect(at('keyOperation', 9), 0);
      expect(at('keyOperation', 10), 1);
      // ⛔The control: the same keys on a number lane pass between.
      expect(at('tolerance', 5), closeTo(0.5, 1e-9));
    });

    test('a pick on a MENU lane keys its word, leaving the key a hold', () {
      final laneId = effectLaneId(const EffectId('k'), 'keyOperation');
      final edited = effectsWithLaneValueEdited(
        [
          LayerEffect.defaults(
            id: const EffectId('k'),
            kind: EffectKind.colorKey,
          ),
        ],
        laneId: laneId,
        frameIndex: 4,
        input: 'Keep Colors',
        scaleLinked: false,
      )!;
      final key = edited.single.parameterOf('keyOperation').track.keyAt(4)!;
      expect(key.value, 1);
      expect(key.outgoing, KeyExit.hold);
    });

    test('the toggle keys and unkeys like the transform lanes', () {
      // The single-key MOVE left with the key marker's private drag
      // (2026-08-08). Re-timing is the span's move now (`LaneHome.shifted`)
      // — select the span, move the span. ↩️A remover of its own went when
      // a span's Delete became one edit for every home (F-374).
      final laneId = effectLaneId(const EffectId('e1'), 'blurriness');
      var effects = effectsWithLaneKeyToggled(
        [blur(blurriness: 6)],
        laneId: laneId,
        frameIndex: 9,
      )!;
      expect(effects.single.parameterOf('blurriness').track.keyAt(9)!.value, 6);

      effects = effectsWithLaneKeyToggled(
        effects,
        laneId: laneId,
        frameIndex: 9,
      )!;
      expect(effects.single.parameterOf('blurriness').track.isEmpty, isTrue);
    });

    test('every edit answers null on a lane it does not own', () {
      final effects = [blur(blurriness: 6)];
      const foreign = 'position';
      expect(
        effectsWithLaneKeyToggled(effects, laneId: foreign, frameIndex: 0),
        isNull,
      );
      expect(
        effectsWithLaneValueEdited(
          effects,
          laneId: foreign,
          frameIndex: 0,
          input: '3',
          scaleLinked: false,
        ),
        isNull,
      );
      expect(
        effectsWithLaneKeyToggled(
          effects,
          laneId: effectLaneId(const EffectId('gone'), 'blurriness'),
          frameIndex: 0,
        ),
        isNull,
        reason: 'a stale address must not edit the wrong effect',
      );
      expect(
        effectsWithLaneKeyToggled(
          effects,
          laneId: effectLaneId(const EffectId('e1'), 'hue'),
          frameIndex: 0,
        ),
        isNull,
        reason: 'a parameter from another kind is not this effect\'s',
      );
    });

    test("the key window's write gives an effect's keys a pick's sides "
        "alone: a path and a roving time are a position's", () {
      final laneId = effectLaneId(const EffectId('e1'), 'blurriness');
      var effects = [blur(blurriness: 6)];
      for (final frame in [0, 4, 8]) {
        effects = effectsWithLaneKeyToggled(
          effects,
          laneId: laneId,
          frameIndex: frame,
        )!;
      }
      final written = effectsWithLaneKeysWritten(
        effects,
        laneId: laneId,
        frames: {0, 4, 8},
        pick: const KeyTypePick(
          sides: KeySidesEdit.hold,
          path: KeyPathKind.bezier,
          roving: true,
        ),
      )!;
      for (final key in written.single.parameterOf('blurriness').track.keys.values) {
        expect(key.outgoing, KeyExit.hold);
        expect(key.path, KeyPath.straight);
        expect(key.roving, isFalse);
      }
    });

    test('an edit leaves the OTHER effects identical', () {
      final effects = [blur(blurriness: 6, id: 'a'), hue(id: 'b')];
      final edited = effectsWithLaneValueEdited(
        effects,
        laneId: effectLaneId(const EffectId('a'), 'blurriness'),
        frameIndex: 0,
        input: '3',
        scaleLinked: false,
      )!;
      expect(edited[1], same(effects[1]));
    });
  });

  group('the range move', () {
    String laneOf(String parameter) =>
        effectLaneId(const EffectId('e1'), parameter);

    List<LayerEffect> withKeys(Map<String, Map<int, double>> lanes) {
      var effects = [hue(id: 'e1')];
      for (final lane in lanes.entries) {
        for (final key in lane.value.entries) {
          effects = effectsWithLaneValueEdited(
            effectsWithLaneKeyToggled(
              effects,
              laneId: laneOf(lane.key),
              frameIndex: key.key,
            )!,
            laneId: laneOf(lane.key),
            frameIndex: key.key,
            input: '${key.value}',
            scaleLinked: false,
          )!;
        }
      }
      return effects;
    }

    test('shifts every ranged key of every spanned lane by one delta', () {
      final effects = withKeys({
        'hue': {2: 4, 3: 6},
        'saturation': {2: 1},
      });
      final moved = laneSpanKeysShifted(
        effects,
        laneIds: [laneOf('hue'), laneOf('saturation')],
        lensOf: effectLaneLens,
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 4,
        frameDelta: 5,
      )!;
      expect(moved.single.parameterOf('hue').track.keys.keys, [7, 8]);
      expect(moved.single.parameterOf('saturation').track.keys.keys, [7]);
    });

    test('a blocked landing vetoes the WHOLE move (all-or-nothing)', () {
      final effects = withKeys({
        'hue': {2: 4, 6: 9},
        'saturation': {2: 1},
      });
      expect(
        laneSpanKeysShifted(
          effects,
          laneIds: [laneOf('hue'), laneOf('saturation')],
          lensOf: effectLaneLens,
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 3,
          frameDelta: 4,
        ),
        isNull,
        reason: 'hue would land on its own unshifted key at 6',
      );
      expect(
        laneSpanKeysShifted(
          effects,
          laneIds: [laneOf('hue')],
          lensOf: effectLaneLens,
          rangeStartIndex: 2,
          rangeEndIndexExclusive: 3,
          frameDelta: -5,
        ),
        isNull,
        reason: 'a landing below frame 0 is blocked too',
      );
    });

    test('a lane with no ranged key rides along without blocking', () {
      final effects = withKeys({
        'hue': {2: 4},
      });
      final moved = laneSpanKeysShifted(
        effects,
        laneIds: [laneOf('hue'), laneOf('saturation')],
        lensOf: effectLaneLens,
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 3,
        frameDelta: 1,
      )!;
      expect(moved.single.parameterOf('hue').track.keys.keys, [3]);
    });

    test('the navigator reads a lane\'s keys, and a header its union', () {
      final effects = withKeys({
        'hue': {2: 4},
        'saturation': {8: 1},
      });
      expect(effectLaneKeyFrames(effects, laneOf('hue')), {2});
      expect(
        effectLaneKeyFrames(effects, effectGroupLaneId(const EffectId('e1'))),
        {2, 8},
      );
      expect(effectLaneKeyFrames(effects, 'position'), isEmpty);
    });
  });

  group('chain edits', () {
    test('add appends, remove drops, and both answer null on a miss', () {
      final one = effectsWithAdded(const [], blur(id: 'a'));
      expect(one, hasLength(1));
      final two = effectsWithAdded(one, hue(id: 'b'));
      expect(two.map((effect) => effect.id.value), ['a', 'b']);
      expect(
        effectsWithRemoved(two, const EffectId('a'))!.single.id.value,
        'b',
      );
      expect(effectsWithRemoved(two, const EffectId('zz')), isNull);
      expect(
        effectsWithEnabledToggled(two, const EffectId('b'))!.last.enabled,
        isFalse,
      );
      expect(effectsWithEnabledToggled(two, const EffectId('zz')), isNull);
    });
  });

  group('the group key', () {
    test('names the row AND the group, so two groups stay independent', () {
      const layerId = LayerId('l1');
      expect(
        laneGroupKey(layerId, transformGroupHeaderLane.laneId),
        isNot(laneGroupKey(layerId, effectGroupLaneId(const EffectId('e1')))),
      );
      expect(
        laneGroupKey(const LayerId('a'), 'transform-group'),
        isNot(laneGroupKey(const LayerId('b'), 'transform-group')),
      );
    });
  });

  group('the one value lookup every lane and key asks (F-101)', () {
    // ⛔THE WALK WAS WRITTEN THREE TIMES — a layer's chain, a track's chain
    // and the storyboard rail's — and each was the same find-the-id-then-
    // resolve. The value a lane SHOWS and a key FREEZES comes from one
    // function now, so a fourth surface cannot quietly answer differently.
    test('it resolves the named parameter, in the chain it is given', () {
      final effects = [blur(blurriness: 6), hue()];
      expect(
        effectParameterValueAt(effects, const EffectId('e1'), 'blurriness', 0),
        6,
      );
      expect(
        effectParameterValueAt(effects, const EffectId('e1'), 'blurriness', 999),
        6,
        reason: 'an unanimated parameter is the same at every frame',
      );
    });

    test('and it answers per FRAME once the parameter is animated', () {
      final keyed = effectsWithLaneKeyToggled(
        [blur(blurriness: 6)],
        laneId: effectLaneId(const EffectId('e1'), 'blurriness'),
        frameIndex: 4,
      )!;
      final animated = effectsWithLaneValueEdited(
        keyed,
        laneId: effectLaneId(const EffectId('e1'), 'blurriness'),
        frameIndex: 10,
        input: '12',
        scaleLinked: false,
      )!;
      expect(
        effectParameterValueAt(animated, const EffectId('e1'), 'blurriness', 4),
        6,
      );
      expect(
        effectParameterValueAt(animated, const EffectId('e1'), 'blurriness', 10),
        12,
      );
    });

    test('an id the chain does not hold answers 0 rather than throwing — a '
        'lane can outlive the effect it names', () {
      expect(
        effectParameterValueAt(
          [blur(blurriness: 6)],
          const EffectId('gone'),
          'blurriness',
          0,
        ),
        0,
      );
    });
  });
}

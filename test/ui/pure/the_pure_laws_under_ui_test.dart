import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/color/color_hex.dart';
import 'package:anicel/src/ui/text/byte_size_label.dart';
import 'package:anicel/src/ui/timeline/lane_span_in_order.dart';
import 'package:anicel/src/ui/timeline/lane_span_keys_shift.dart';

/// The pure laws under `ui/` that no test named — each replaced two or
/// three hand-written copies, and none of them needs a widget to check
/// (the audit's untested-file pass, 2026-09-05).
void main() {
  group('hex in one place', () {
    test('a colour prints as #RRGGBB, uppercase, alpha dropped', () {
      expect(colorHexOf(0xFF1A2B3C), '#1A2B3C');
      expect(
        colorHexOf(0x001A2B3C),
        '#1A2B3C',
        reason: 'alpha lives on the layer, not in the swatch',
      );
    });

    test('a dark colour keeps its leading zeroes', () {
      expect(colorHexOf(0xFF000000), '#000000');
      expect(colorHexOf(0xFF000102), '#000102');
    });

    test('the parse takes #RRGGBB, bare RRGGBB, and either case', () {
      expect(parseColorHex('#1a2b3c'), 0xFF1A2B3C);
      expect(parseColorHex('1A2B3C'), 0xFF1A2B3C);
      expect(parseColorHex('  #1A2B3C  '), 0xFF1A2B3C);
    });

    test('#RGB shorthand doubles each digit', () {
      expect(parseColorHex('#abc'), 0xFFAABBCC);
      expect(parseColorHex('f00'), 0xFFFF0000);
    });

    test('🚨a SIGNED string is not a colour — int.tryParse takes a sign, '
        'and OR-ing the sign bits gives something that is not a colour at '
        'all', () {
      expect(parseColorHex('-12345'), isNull);
      expect(parseColorHex('+12345'), isNull);
    });

    test('anything that is not six hex digits is null, not a guess', () {
      for (final text in ['', '#', 'gggggg', '#12345', '1234567', 'zz00ff']) {
        expect(parseColorHex(text), isNull, reason: 'text "$text"');
      }
    });

    test('the two directions round-trip', () {
      for (final argb in [0xFF000000, 0xFFFFFFFF, 0xFF1A2B3C, 0xFF0F0F0F]) {
        expect(parseColorHex(colorHexOf(argb)), argb);
      }
    });

    test('the channels come out in the order the status bar prints them', () {
      expect(colorChannels(0xFF1A2B3C), (r: 0x1A, g: 0x2B, b: 0x3C));
    });

    test('the channels go back, each CLAMPED to a byte', () {
      expect(colorFromChannels(r: 0x1A, g: 0x2B, b: 0x3C), 0xFF1A2B3C);
      expect(colorFromChannels(r: 999, g: -5, b: 300), 0xFFFF00FF);
    });
  });

  group('a byte count as a person reads it', () {
    test('megabytes are WHOLE — a decimal on 340 MB is noise', () {
      expect(byteSizeLabel(340 * 1024 * 1024), '340 MB');
      expect(byteSizeLabel((340.4 * 1024 * 1024).round()), '340 MB');
    });

    test('gigabytes carry ONE place — 1.2 against 1.8 is the decision', () {
      expect(byteSizeLabel((1.2 * 1024 * 1024 * 1024).round()), '1.2 GB');
      expect(byteSizeLabel((1.8 * 1024 * 1024 * 1024).round()), '1.8 GB');
    });

    test('the boundaries land on the bigger unit', () {
      expect(byteSizeLabel(1024 * 1024), '1 MB');
      expect(byteSizeLabel(1024 * 1024 * 1024), '1.0 GB');
    });

    test('anything under a megabyte is KB', () {
      expect(byteSizeLabel(0), '0 KB');
      expect(byteSizeLabel(2048), '2 KB');
      expect(byteSizeLabel(1024 * 1024 - 1), '1024 KB');
    });
  });

  group('the lane span a drag names', () {
    const order = ['a', 'b', 'c', 'd'];

    test('a forward drag is the inclusive run in DISPLAY order', () {
      expect(laneSpanInOrder(order, 'b', 'd'), ['b', 'c', 'd']);
    });

    test('a BACKWARD drag is the same run — display order, however the '
        'drag ran', () {
      expect(laneSpanInOrder(order, 'd', 'b'), ['b', 'c', 'd']);
    });

    test('anchor and head on the same lane is that lane alone', () {
      expect(laneSpanInOrder(order, 'c', 'c'), ['c']);
    });

    test('⛔an id OUTSIDE the order keeps only the ANCHOR — a span cannot '
        'be honestly named when one end is not on the list', () {
      expect(laneSpanInOrder(order, 'b', 'zzz'), ['b']);
      expect(laneSpanInOrder(order, 'zzz', 'b'), ['zzz']);
      expect(laneSpanInOrder(const [], 'b', 'c'), ['b']);
    });
  });

  group('lane keys shift ACROSS lanes, all or nothing', () {
    /// A toy track: lane id → the frames it has keys on.
    Map<String, Set<int>> track(Map<String, Set<int>> lanes) => {
      for (final entry in lanes.entries) entry.key: {...entry.value},
    };

    Set<int> keyFrames(Map<String, Set<int>> t, String laneId) =>
        t[laneId] ?? const {};

    /// The material: one lane's own shift, blocked when [blocked] names it.
    Map<String, Set<int>>? Function(
      Map<String, Set<int>> track, {
      required String laneId,
      required int rangeStartIndex,
      required int rangeEndIndexExclusive,
      required int frameDelta,
    })
    shifterBlocking(Set<String> blocked) =>
        (
          t, {
          required laneId,
          required rangeStartIndex,
          required rangeEndIndexExclusive,
          required frameDelta,
        }) {
          if (blocked.contains(laneId)) {
            return null;
          }
          return {
            ...t,
            laneId: {
              for (final frame in t[laneId] ?? const <int>{})
                if (frame >= rangeStartIndex && frame < rangeEndIndexExclusive)
                  frame + frameDelta
                else
                  frame,
            },
          };
        };

    Map<String, Set<int>>? shift({
      required Map<String, Set<int>> from,
      required List<String> laneIds,
      Set<String> blocked = const {},
      int delta = 2,
    }) => laneSpanKeysShifted<Map<String, Set<int>>>(
      from,
      laneIds: laneIds,
      rangeStartIndex: 0,
      rangeEndIndexExclusive: 5,
      frameDelta: delta,
      laneKeyFrames: keyFrames,
      laneKeysShifted: shifterBlocking(blocked),
    );

    test('every lane with a key in the range moves', () {
      final moved = shift(
        from: track({
          'x': {1},
          'y': {2},
        }),
        laneIds: const ['x', 'y'],
      );

      expect(moved, {
        'x': {3},
        'y': {4},
      });
    });

    test('a lane with NO key in the range rides along untouched', () {
      final moved = shift(
        from: track({
          'x': {1},
          'y': {90},
        }),
        laneIds: const ['x', 'y'],
      );

      expect(moved, {
        'x': {3},
        'y': {90},
      });
    });

    test('🚨a BLOCKED lane vetoes the whole move, not just its own', () {
      expect(
        shift(
          from: track({
            'x': {1},
            'y': {2},
          }),
          laneIds: const ['x', 'y'],
          blocked: const {'y'},
        ),
        isNull,
        reason:
            'all-or-nothing ACROSS lanes — a partial shift leaves the '
            'track saying two different things about one drag',
      );
    });

    test('a lane that is blocked but has NOTHING in the range does not '
        'veto — it was never asked', () {
      final moved = shift(
        from: track({
          'x': {1},
          'y': {90},
        }),
        laneIds: const ['x', 'y'],
        blocked: const {'y'},
      );

      expect(moved, isNotNull);
    });

    test('a zero delta is null', () {
      expect(
        shift(
          from: track({
            'x': {1},
          }),
          laneIds: const ['x'],
          delta: 0,
        ),
        isNull,
      );
    });

    test('nothing in range anywhere is null, not an unchanged track', () {
      expect(
        shift(
          from: track({
            'x': {90},
          }),
          laneIds: const ['x'],
        ),
        isNull,
      );
    });

    test('an empty lane list is null', () {
      expect(shift(from: track(const {}), laneIds: const []), isNull);
    });
  });
}

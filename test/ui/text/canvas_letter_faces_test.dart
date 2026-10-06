import 'dart:async';
import 'dart:typed_data';

import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool's faces): WHICH FACES LETTERS CAN BE SET IN NOW.
///
/// 🚨A face is handed to the engine when letters are first asked for in it
/// — a CJK font is tens of megabytes the engine never lets go of — so a
/// family is not on the device, on its way, or in the engine, and this is
/// what tells them apart and tells whoever measured in the old state.
void main() {
  late _Device device;
  late CanvasLetterFaces faces;
  late int told;
  void countTold() => told += 1;

  setUp(() {
    device = _Device();
    faces = CanvasLetterFaces(files: device.filesOf, register: device.register);
    CanvasLetterFaces.current = faces;
    told = 0;
    CanvasLetterFaces.changes.addListener(countTold);
  });
  tearDown(() {
    CanvasLetterFaces.changes.removeListener(countTold);
    CanvasLetterFaces.current = CanvasLetterFaces();
  });

  /// Lets every read and every hand-over that is under way come to its end.
  Future<void> arrive() => Future<void>.delayed(Duration.zero);

  group('the app\'s own faces', () {
    test('are every letter\'s to be set in, by their own names — and '
        'nothing is ever read for them', () async {
      expect(CanvasLetterFaces.isAppFace(null), isTrue);
      expect(CanvasLetterFaces.isAppFace(AppTypography.bundledFamily), isTrue);
      for (final family in AppTypography.bundledFallback) {
        expect(CanvasLetterFaces.isAppFace(family), isTrue, reason: family);
        expect(faces.engineFamilyOf(family), family);
        expect(faces.isOnItsWay(family), isFalse);
      }
      expect(CanvasLetterFaces.isAppFace('Probe Sans'), isFalse);
      expect(faces.engineFamilyOf(null), isNull);
      expect(faces.isOnItsWay(null), isFalse);
      expect(faces.whenHere([null, AppTypography.bundledFamily]), isNull);

      await arrive();

      expect(device.asked, isEmpty);
    });
  });

  group('a family this device does not hold', () {
    test('is set in the app\'s own face, is not on its way, and is not '
        'looked for', () async {
      expect(faces.holds('Probe Sans'), isFalse);
      expect(faces.engineFamilyOf('Probe Sans'), isNull);
      expect(faces.isOnItsWay('Probe Sans'), isFalse);
      expect(faces.whenHere(['Probe Sans']), isNull);

      await arrive();

      expect(device.asked, isEmpty);
      expect(told, 0);
    });
  });

  group('a family on this device', () {
    setUp(() {
      device.files['Probe Sans'] = [_bytes(1), _bytes(2)];
      device.files['Probe Serif'] = [_bytes(3)];
      faces.setOnDevice({'Probe Sans', 'Probe Serif'});
      told = 0;
    });

    test('🚨is not read until letters are asked for in it', () async {
      expect(faces.holds('Probe Sans'), isTrue);

      await arrive();

      expect(device.asked, isEmpty);
      expect(device.handed, isEmpty);
    });

    test('🚨asked for, it is sent for: on its way — the app\'s face until '
        'then — and read ONCE, whoever else asks meanwhile', () async {
      final before = faces.generation;

      expect(faces.engineFamilyOf('Probe Sans'), isNull);
      expect(faces.isOnItsWay('Probe Sans'), isTrue);
      expect(faces.engineFamilyOf('Probe Sans'), isNull);
      faces.sendFor('Probe Sans');
      expect(faces.generation, before, reason: 'nothing has changed yet');
      expect(told, 0);

      await arrive();

      expect(device.asked, ['Probe Sans']);
      expect(faces.isOnItsWay('Probe Sans'), isFalse);
      expect(faces.engineFamilyOf('Probe Sans'), isNotNull);
      expect(faces.generation, isNot(before));
      expect(told, 1);

      // And never again, once it is in the engine.
      faces.sendFor('Probe Sans');
      faces.isOnItsWay('Probe Sans');
      await arrive();
      expect(device.asked, ['Probe Sans']);
      expect(told, 1);
    });

    test('🚨what the engine calls it is itself an asking — whoever lays '
        'letters out causes their face to be read', () async {
      expect(faces.engineFamilyOf('Probe Serif'), isNull);

      await arrive();

      expect(device.asked, ['Probe Serif']);
      expect(faces.engineFamilyOf('Probe Serif'), isNotNull);
    });

    test('whether it is on its way is itself an asking', () async {
      expect(faces.isOnItsWay('Probe Serif'), isTrue);

      await arrive();

      expect(device.asked, ['Probe Serif']);
      expect(faces.engineFamilyOf('Probe Serif'), isNotNull);
    });

    test('🚨every file of it is handed over under ONE name, which is not '
        'the family\'s own — and another family under another', () async {
      faces
        ..sendFor('Probe Sans')
        ..sendFor('Probe Serif');
      await arrive();

      final sans = faces.engineFamilyOf('Probe Sans')!;
      final serif = faces.engineFamilyOf('Probe Serif')!;
      expect(sans, isNot('Probe Sans'));
      expect(sans, isNot(serif));
      expect(
        [
          for (final handed in device.handed)
            if (handed.engineFamily == sans) handed.bytes,
        ],
        [_bytes(1), _bytes(2)],
      );
      expect(
        [
          for (final handed in device.handed)
            if (handed.engineFamily == serif) handed.bytes,
        ],
        [_bytes(3)],
      );
    });

    group('whoever waits for faces', () {
      test('goes on at once when none is on its way', () async {
        expect(faces.whenHere(['Nobody\'s Face', null]), isNull);

        faces.sendFor('Probe Sans');
        await arrive();

        expect(faces.whenHere(['Probe Sans']), isNull);
      });

      test('🚨is held until the last of them is here — and the waiting is '
          'what sends for them', () async {
        device.gate = Completer<void>();
        var here = false;

        final wait = faces.whenHere(['Probe Sans', null, 'Probe Serif']);
        unawaited(wait!.then((_) => here = true));
        await arrive();

        expect(device.asked, unorderedEquals(['Probe Sans', 'Probe Serif']));
        expect(here, isFalse);
        expect(faces.engineFamilyOf('Probe Sans'), isNull);

        device.gate!.complete();
        await arrive();

        expect(here, isTrue);
        expect(faces.engineFamilyOf('Probe Sans'), isNotNull);
        expect(faces.engineFamilyOf('Probe Serif'), isNotNull);
      });
    });

    group('a family that cannot be had after all', () {
      test('🚨whose files are gone is a family this device does not hold: '
          'not on its way for ever, and not asked for again', () async {
        device.files['Probe Sans'] = [];

        faces.sendFor('Probe Sans');
        await arrive();

        expect(faces.holds('Probe Sans'), isFalse);
        expect(faces.isOnItsWay('Probe Sans'), isFalse);
        expect(faces.engineFamilyOf('Probe Sans'), isNull);
        expect(told, 1, reason: 'it was on its way, and is not');
        await arrive();
        expect(device.asked, ['Probe Sans']);
      });

      test('so is one the engine would not take', () async {
        device.refuses = StateError('not a font');

        faces.sendFor('Probe Sans');
        await arrive();

        expect(faces.holds('Probe Sans'), isFalse);
        expect(faces.engineFamilyOf('Probe Sans'), isNull);
        expect(faces.isOnItsWay('Probe Sans'), isFalse);
      });

      test('one the engine took PART of is not a family half-handed: it '
          'is not held either', () async {
        device.refusesAfter = 1;

        faces.sendFor('Probe Sans');
        await arrive();

        expect(device.handed, hasLength(1), reason: '⛔fixture: one was taken');
        expect(faces.holds('Probe Sans'), isFalse);
        expect(faces.engineFamilyOf('Probe Sans'), isNull);
      });

      test('and so is one whose files could not be read at all', () async {
        device.unreadable = true;

        faces.sendFor('Probe Sans');
        await arrive();

        expect(faces.holds('Probe Sans'), isFalse);
        expect(faces.isOnItsWay('Probe Sans'), isFalse);
      });
    });

    group('when the device is said to hold other families', () {
      test('🚨one that left is not drawn with from that moment, and that '
          'is told', () async {
        faces.sendFor('Probe Sans');
        await arrive();
        final before = faces.generation;
        told = 0;

        faces.setOnDevice({'Probe Serif'});

        expect(faces.holds('Probe Sans'), isFalse);
        expect(faces.engineFamilyOf('Probe Sans'), isNull);
        expect(faces.isOnItsWay('Probe Sans'), isFalse);
        expect(faces.generation, isNot(before));
        expect(told, 1);
      });

      test('the same families said again change nothing, and tell nobody', () {
        final before = faces.generation;

        faces.setOnDevice({'Probe Serif', 'Probe Sans'});

        expect(faces.generation, before);
        expect(told, 0);
      });

      test('one that came is held, and read when asked for', () async {
        device.files['Probe Mono'] = [_bytes(9)];

        faces.setOnDevice({'Probe Sans', 'Probe Serif', 'Probe Mono'});

        expect(told, 1);
        expect(faces.holds('Probe Mono'), isTrue);
        faces.sendFor('Probe Mono');
        await arrive();
        expect(faces.engineFamilyOf('Probe Mono'), isNotNull);
      });

      test('a family that left while it was on its way does not arrive', () async {
        device.gate = Completer<void>();
        faces.sendFor('Probe Sans');
        await arrive();

        faces.setOnDevice({'Probe Serif'});
        device.gate!.complete();
        await arrive();

        expect(faces.engineFamilyOf('Probe Sans'), isNull);
        expect(faces.isOnItsWay('Probe Sans'), isFalse);
      });
    });

    group('🚨a family whose FILES are others now', () {
      test('is no longer called by the name it had, and is read again — '
          'under a new one — when next asked for', () async {
        faces.sendFor('Probe Sans');
        await arrive();
        final first = faces.engineFamilyOf('Probe Sans')!;
        device.files['Probe Sans'] = [_bytes(7)];
        told = 0;

        faces.setOnDevice({'Probe Sans', 'Probe Serif'}, renewed: {'Probe Sans'});

        expect(told, 1);
        expect(faces.engineFamilyOf('Probe Sans'), isNull);
        expect(faces.isOnItsWay('Probe Sans'), isTrue);
        await arrive();
        final second = faces.engineFamilyOf('Probe Sans')!;
        expect(second, isNot(first));
        expect(
          [
            for (final handed in device.handed)
              if (handed.engineFamily == second) handed.bytes,
          ],
          [_bytes(7)],
          reason: 'the engine is not handed the new file under the old name, '
              'where it would JOIN the old face',
        );
      });

      test('what was being read when they changed is not taken for the '
          'family: it is read again', () async {
        device.gate = Completer<void>();
        faces.sendFor('Probe Sans');
        await arrive();

        device.files['Probe Sans'] = [_bytes(7)];
        faces.setOnDevice({'Probe Sans', 'Probe Serif'}, renewed: {'Probe Sans'});
        device.gate!.complete();
        device.gate = null;
        await arrive();

        expect(
          faces.engineFamilyOf('Probe Sans'),
          isNull,
          reason: 'the read that was under way came to nothing',
        );
        await arrive();
        final engine = faces.engineFamilyOf('Probe Sans')!;
        expect(
          [
            for (final handed in device.handed)
              if (handed.engineFamily == engine) handed.bytes,
          ],
          [_bytes(7)],
        );
      });
    });

    test('faces that are let go of read nothing more', () async {
      faces.dispose();

      faces.sendFor('Probe Sans');
      expect(faces.isOnItsWay('Probe Sans'), isFalse);
      await arrive();

      expect(device.asked, isEmpty);
    });
  });

  group('the faces of the run', () {
    test('🚨only what stands as the run\'s faces is told of — and standing '
        'others there is itself a change', () async {
      final other = _Device()..files['Probe Sans'] = [_bytes(1)];
      final aside = CanvasLetterFaces(
        files: other.filesOf,
        register: other.register,
      );

      aside
        ..setOnDevice({'Probe Sans'})
        ..sendFor('Probe Sans');
      await arrive();

      expect(aside.engineFamilyOf('Probe Sans'), isNotNull);
      expect(told, 0);

      CanvasLetterFaces.current = aside;

      expect(told, 1);
      expect(CanvasLetterFaces.current, same(aside));
    });

    test('no two faces ever stand at the same count: a layout kept under '
        'one is not taken for a layout under the next', () {
      final other = CanvasLetterFaces();

      expect(other.generation, isNot(faces.generation));
      final before = other.generation;
      other.setOnDevice({'Probe Sans'});
      expect(other.generation, isNot(before));
      expect(other.generation, isNot(faces.generation));
    });

    test('a name minted for one is never minted for another', () async {
      device.files['Probe Sans'] = [_bytes(1)];
      faces
        ..setOnDevice({'Probe Sans'})
        ..sendFor('Probe Sans');
      final other = _Device()..files['Probe Sans'] = [_bytes(1)];
      final aside = CanvasLetterFaces(
        files: other.filesOf,
        register: other.register,
      )
        ..setOnDevice({'Probe Sans'})
        ..sendFor('Probe Sans');
      await arrive();

      expect(
        aside.engineFamilyOf('Probe Sans'),
        isNot(faces.engineFamilyOf('Probe Sans')),
      );
    });
  });
}

Uint8List _bytes(int seed) => Uint8List.fromList([seed, seed, seed]);

/// A device's font files, and an engine that takes note of what it is
/// handed.
class _Device {
  final Map<String, List<Uint8List>> files = {};
  final List<String> asked = [];
  final List<({String engineFamily, Uint8List bytes})> handed = [];

  /// While set, a read does not come back.
  Completer<void>? gate;

  /// What the engine answers a hand-over with, in place of taking it.
  Error? refuses;

  /// How many files the engine takes before it refuses the rest.
  int? refusesAfter;

  /// Whether reading a family's files throws.
  bool unreadable = false;

  Future<List<Uint8List>> filesOf(String family) async {
    asked.add(family);
    await gate?.future;
    if (unreadable) {
      throw StateError('the disk is gone');
    }
    return files[family] ?? const [];
  }

  Future<void> register(Uint8List bytes, {required String engineFamily}) async {
    final refusal = refuses;
    if (refusal != null) {
      throw refusal;
    }
    final limit = refusesAfter;
    if (limit != null && handed.length >= limit) {
      throw StateError('no more');
    }
    handed.add((engineFamily: engineFamily, bytes: bytes));
  }
}

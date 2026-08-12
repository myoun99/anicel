import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/media_relink_matcher.dart';

/// RELINK-2. The rule is tested as a pure function because the failure it
/// exists to prevent — relinking `A1.png` to the wrong cut's `A1.png` —
/// cannot be demonstrated by a file system without building a production
/// drive to demonstrate it on.
void main() {
  group('a unique name is enough', () {
    test('one candidate matches', () {
      final plan = planMediaRelink(
        missingPaths: ['/old/take.wav'],
        candidatePaths: ['/new/audio/take.wav'],
      );
      expect(plan.matched, {'/old/take.wav': '/new/audio/take.wav'});
      expect(plan.unmatched, isEmpty);
    });

    test('no candidate leaves it alone', () {
      final plan = planMediaRelink(
        missingPaths: ['/old/take.wav'],
        candidatePaths: ['/new/audio/other.wav'],
      );
      expect(plan.matched, isEmpty);
      expect(plan.unmatched, ['/old/take.wav']);
    });
  });

  group('a repeated name is split by the tail', () {
    // The whole point: A1.png repeats in every cut folder.
    const candidates = [
      '/new/cuts/C-044/A1.png',
      '/new/cuts/C-045/A1.png',
      '/new/cuts/C-046/A1.png',
    ];

    test('the parent folder decides', () {
      final plan = planMediaRelink(
        missingPaths: ['/old/C-045/A1.png'],
        candidatePaths: candidates,
      );
      expect(plan.matched, {'/old/C-045/A1.png': '/new/cuts/C-045/A1.png'});
    });

    test('a name that matches many and a tail that matches none is skipped',
        () {
      // C-099 is not under the chosen folder at all. Picking any of the
      // three A1.png would be picking a different cut's drawing.
      final plan = planMediaRelink(
        missingPaths: ['/old/C-099/A1.png'],
        candidatePaths: candidates,
      );
      expect(plan.matched, isEmpty);
      expect(plan.unmatched, ['/old/C-099/A1.png']);
    });

    test('still ambiguous after every tail is skipped, never guessed', () {
      // Two candidates whose whole paths end identically — no suffix of the
      // original can separate them.
      final plan = planMediaRelink(
        missingPaths: ['/old/C-045/A1.png'],
        candidatePaths: [
          '/new/take1/C-045/A1.png',
          '/new/take2/C-045/A1.png',
        ],
      );
      expect(plan.matched, isEmpty);
      expect(plan.unmatched, ['/old/C-045/A1.png']);
    });

    test('several missing files split against the same candidate set', () {
      final plan = planMediaRelink(
        missingPaths: ['/old/C-044/A1.png', '/old/C-046/A1.png'],
        candidatePaths: candidates,
      );
      expect(plan.matched, {
        '/old/C-044/A1.png': '/new/cuts/C-044/A1.png',
        '/old/C-046/A1.png': '/new/cuts/C-046/A1.png',
      });
      expect(plan.unmatched, isEmpty);
    });
  });

  group('the extension has to survive', () {
    test('a different extension is not the same file', () {
      // A .psd beside a .png is a source, not a substitute — swapping them
      // would fail at decode time, far from here.
      final plan = planMediaRelink(
        missingPaths: ['/old/bg.png'],
        candidatePaths: ['/new/bg.psd'],
      );
      expect(plan.matched, isEmpty);
      expect(plan.unmatched, ['/old/bg.png']);
    });

    test('case does not make it a different extension', () {
      final plan = planMediaRelink(
        missingPaths: ['/old/bg.PNG'],
        candidatePaths: ['/new/bg.png'],
      );
      expect(plan.matched, {'/old/bg.PNG': '/new/bg.png'});
    });
  });

  group('two assets cannot claim one file', () {
    test('a collision drops BOTH rather than letting order decide', () {
      // Two different originals whose names both resolve to the same
      // candidate. Accepting the first would be arbitrary, and arbitrary is
      // exactly what this rule refuses.
      final plan = planMediaRelink(
        missingPaths: ['/a/shot.wav', '/b/shot.wav'],
        candidatePaths: ['/new/shot.wav'],
      );
      expect(plan.matched, isEmpty);
      expect(plan.unmatched, ['/a/shot.wav', '/b/shot.wav']);
    });

    test('a collision does not poison the others', () {
      final plan = planMediaRelink(
        missingPaths: ['/a/shot.wav', '/b/shot.wav', '/c/room.wav'],
        candidatePaths: ['/new/shot.wav', '/new/room.wav'],
      );
      expect(plan.matched, {'/c/room.wav': '/new/room.wav'});
      expect(plan.unmatched, ['/a/shot.wav', '/b/shot.wav']);
    });
  });

  group('spelling', () {
    test('backslashes match forward slashes on both sides', () {
      final plan = planMediaRelink(
        missingPaths: [r'C:\old\C-045\A1.png'],
        candidatePaths: [r'D:\new\C-044\A1.png', r'D:\new\C-045\A1.png'],
      );
      expect(plan.matched, {'C:/old/C-045/A1.png': 'D:/new/C-045/A1.png'});
    });

    test('a candidate with no file name is ignored rather than crashing', () {
      final plan = planMediaRelink(
        missingPaths: ['/old/take.wav'],
        candidatePaths: ['/new/', '/new/take.wav'],
      );
      expect(plan.matched, {'/old/take.wav': '/new/take.wav'});
    });

    test('unmatched comes back in a stable order', () {
      // The preview must read the same way twice.
      final plan = planMediaRelink(
        missingPaths: ['/z/b.png', '/z/a.png'],
        candidatePaths: const [],
      );
      expect(plan.unmatched, ['/z/a.png', '/z/b.png']);
    });
  });

  test('isEmpty says whether there is anything to apply', () {
    expect(
      planMediaRelink(
        missingPaths: ['/x/a.png'],
        candidatePaths: const [],
      ).isEmpty,
      isTrue,
    );
    expect(
      planMediaRelink(
        missingPaths: ['/x/a.png'],
        candidatePaths: ['/y/a.png'],
      ).isEmpty,
      isFalse,
    );
  });
}

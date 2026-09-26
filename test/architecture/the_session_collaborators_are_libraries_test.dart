// THE SESSION'S COLLABORATORS ARE LIBRARIES, AND THIS IS WHAT MAKES THAT
// TRUE.
//
// `EditorSessionManager` used to be one class in forty files: each
// collaborator was a `part of` the session library, held a `_session` field
// and reached into the host's PRIVATE names. A `part` splits a file, not a
// class — so nothing could be said about the coupling, because every name
// was in scope everywhere and the compiler had no opinion.
//
// G0 (round 8, 2026-09-06) made them libraries. Each one takes the ROLES it
// needs by constructor (`ProjectAccess`, `SelectionAccess`, `ChangeSink`,
// `FrameIds`, `TimelineAccess`) plus the siblings it names, and the compiler
// now enforces the boundary: a private field of one collaborator cannot be
// touched from another file at all.
//
// These three tests are what keep it that way. Without them the cheapest fix
// for any future coupling is the one that put us here — add a `part`, reach
// in, move on.
//
// It is an instrument, so here is what it looks like when it lies:
//   - it reads DIRECTIVE LINES textually, so a `part` written inside a block
//     comment counts -> a violation nobody can execute
//   - it counts `SessionInternals` members by the AST, so a member added in
//     a `part` of the roles file (there is none) would be invisible
//   - it says nothing about what a collaborator does with a role once it has
//     one: this is a boundary test, not a design test
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

const _host = 'lib/src/ui/editor_session_manager.dart';
const _sessionDir = 'lib/src/ui/session';
const _rolesFile = 'lib/src/ui/session/session_roles.dart';

/// The collaborators that are STILL parts of the session library, with the
/// reason each one could not leave in G0.
///
/// An entry that no longer matches anything FAILS: a ledger that keeps paid
/// debts on it stops being read. It is EMPTY as of G4-2 (2026-09-08), when
/// the composite tree found its owner and `editing_stack_map.dart` took its
/// roles by constructor like everything else — so the ledger now says what
/// it always meant to: the session library has no parts.
const _stillParts = <String, String>{};

/// The files under `session/` that name the session ON PURPOSE.
///
/// ⛔A COLLABORATOR may never be here. This is the one that is not a
/// collaborator: a UI wiring function that takes the session as an
/// argument, which is the composition root's job, not a collaborator's.
const _mayNameTheSession = <String, String>{
  'session_legend_callbacks.dart':
      'A free function that WIRES a session into the timeline legend. It '
      'takes the session as a parameter — it does not hold one.',
  'session_row_button_presses.dart':
      'The rail rows\' buttons WIRED to a session, built by the two hosts '
      'that draw rails (the timeline tab, the storyboard tab) and by the SE '
      'mixer their speaker opens, for the length of a press — the session '
      'never constructs it or keeps one.',
};

/// What `SessionInternals` still carries: the MEASURED remainder of the
/// coupling, after the roles took what they could name and the siblings took
/// what belonged to another collaborator.
///
/// ⛔This number only falls. It started at 117 when the interface was first
/// generated (G0-2, 2026-09-06), stood at 82 after the sibling promotion,
/// and reached 56 when G3's four clusters landed (the rows and their drags,
/// the cut/track surface, the media pool, the audio and SE rows); every
/// member left is either a host verb with no owner yet or one of the nine
/// edges that would close a construction CYCLE if injected — those are
/// named in the tool's REFUSED list. 51 → 49 (2026-09-16, ARCH-session-state's
/// first family): the onion skin's settings and layer set moved into
/// `OnionSkin`, the collaborator that plans with them, and the two getters
/// that handed them over left with them. 49 → 47 (2026-09-23, the second
/// family): the scrub's two flags moved into `FrameScrub`, which raises and
/// drops them, and `CutUnderPlayhead` — whose only read of the role was one
/// of them — now takes that flag instead of the role. 47 → 43 (2026-09-24,
/// the third family): the two opacity drag previews and the master bar's
/// resting value moved into `OpacityVerbs`, which writes all three — and
/// `OpacityVerbs`, whose only reads of the role were these, no longer takes
/// it at all. 43 → 39 (2026-09-25, the fourth and fifth families): the
/// block drag in flight moved into `DrawingBlockMoveDragVerbs`, which starts
/// and closes it; the selection-interaction flag became what it always stood
/// for — `RangeSelections`' own count of holds, which nothing had listened
/// to; and the SE solo set moved into `VisibilitySolo`, whose toggle is its
/// one writer — `VisibilitySolo`, whose only read of the role this was, no
/// longer takes it, and the playback rig takes the set by constructor.
/// 39 → 38 (2026-09-25, other-track-s-row-fx-and-mixer): the transform
/// switch's writer moved into `EffectsAndFx`, its one caller, which finds a
/// row the way every fx switch does — the host's copy asked the active
/// track alone, so another track's S row could not be switched. It was
/// `EffectsAndFx`'s only read of the role, so it no longer takes it.
/// 38 → 37 (2026-09-25, the sixth family): the transition row's own drag
/// preview channel went — its grips and moves publish on the one channel
/// the SE rows use, in their two forms (the cut's, the track's), so the
/// session holds no second one (transition-row-open-in-the-cut).
/// 37 → 36 (2026-09-26, the seventh family): the listenable of the row you
/// stand on moved into `Standing`, beside its one writer
/// (`publishCurrentRow`); the rails and the canvas read it there.
/// 36 → 35 (2026-09-26, the eighth family): the reveal tick moved into
/// `RangeSelections`, beside its one writer (`revealSelection`), which
/// releases it; the rails' hosts read it there.
const _sessionInternalsMembers = 35;

List<String> _dartFilesUnder(String dir) => [
  for (final f in Directory(dir).listSync().whereType<File>())
    if (f.path.endsWith('.dart')) f.uri.pathSegments.last,
];

void main() {
  test("the session's collaborators are libraries, not parts", () {
    final hostSource = File(_host).readAsStringSync();
    final parts = [
      for (final line in hostSource.split('\n'))
        if (line.startsWith("part '")) line.trim(),
    ];
    expect(
      parts.length,
      lessThanOrEqualTo(_stillParts.length),
      reason:
          'the session library grew a `part` back. What is there:\n'
          '${parts.join('\n')}',
    );

    final partOf = <String>[];
    for (final name in _dartFilesUnder(_sessionDir)) {
      final source = File('$_sessionDir/$name').readAsStringSync();
      if (source.split('\n').any((l) => l.startsWith('part of'))) {
        partOf.add(name);
      }
    }
    expect(
      partOf.toSet(),
      _stillParts.keys.toSet(),
      reason:
          'a file under $_sessionDir is `part of` the session and is not on '
          'the ledger (or a ledger entry is paid and should be deleted).',
    );
  });

  test('no collaborator imports the session', () {
    final offenders = <String>[];
    for (final name in _dartFilesUnder(_sessionDir)) {
      final source = File('$_sessionDir/$name').readAsStringSync();
      final namesTheHost = source
          .split('\n')
          .any((l) => l.contains('editor_session_manager.dart'));
      if (namesTheHost && !_mayNameTheSession.containsKey(name)) {
        offenders.add(name);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a collaborator imported `editor_session_manager.dart`. It takes '
          'the ROLES it needs by constructor instead — importing the host is '
          'how the private reach-in comes back.',
    );
    for (final allowed in _mayNameTheSession.keys) {
      expect(
        File('$_sessionDir/$allowed').existsSync(),
        isTrue,
        reason: '$allowed is on the ledger but no longer exists — delete it.',
      );
    }
  });

  test('SessionInternals only shrinks', () {
    final unit = parseString(
      content: File(_rolesFile).readAsStringSync(),
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    ).unit;
    final internals = unit.declarations
        .whereType<ClassDeclaration>()
        .where((c) => c.namePart.typeName.lexeme == 'SessionInternals')
        .toList();
    expect(
      internals,
      hasLength(1),
      reason: 'SessionInternals is the measured remainder — it has one home.',
    );
    final members = internals.single.body.members.length;

    expect(
      members,
      lessThanOrEqualTo(_sessionInternalsMembers),
      reason:
          'SessionInternals grew. ⛔Nothing is added to it: a host name a '
          'collaborator needs is either a ROLE, a SIBLING it takes by '
          'constructor, or code that moves INTO the collaborator.',
    );
    expect(
      _sessionInternalsMembers - members,
      lessThan(25),
      reason:
          'the SessionInternals ceiling is slack — lower it to $members so '
          'the ratchet keeps its bite',
    );
  });
}

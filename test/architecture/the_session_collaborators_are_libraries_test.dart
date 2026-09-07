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
/// debts on it stops being read.
const _stillParts = <String, String>{
  'editing_stack_map.dart':
      'It declares no class — it is a block of session members split out by '
      'file, so it has no `this` to hand roles to. It leaves when its '
      'members find an owner (G1).',
};

/// The files under `session/` that name the session ON PURPOSE.
///
/// ⛔A COLLABORATOR may never be here. These are the two that are not
/// collaborators: the part above (a part carries its parent's name by
/// definition) and a UI wiring function that takes the session as an
/// argument, which is the composition root's job, not a collaborator's.
const _mayNameTheSession = <String, String>{
  'editing_stack_map.dart': 'It is a `part of` the session library.',
  'session_legend_callbacks.dart':
      'A free function that WIRES a session into the timeline legend. It '
      'takes the session as a parameter — it does not hold one.',
};

/// What `SessionInternals` still carries: the MEASURED remainder of the
/// coupling, after the roles took what they could name and the siblings took
/// what belonged to another collaborator.
///
/// ⛔This number only falls. It started at 117 when the interface was first
/// generated (G0-2, 2026-09-06) and stands at 82 after the sibling
/// promotion; every member left is either a host verb with no owner yet
/// (G1's clusters) or one of the nine edges that would close a construction
/// CYCLE if injected — those are named in the tool's REFUSED list.
const _sessionInternalsMembers = 72;

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

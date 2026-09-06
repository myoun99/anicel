// ignore_for_file: avoid_print
// Drafts the role interfaces the EditorSessionManager collaborators need
// (round 8, 2026-09-06), from the map session_map.dart measures.
//
//   dart run tool/refactor/session_roles_gen.dart <repoRoot> <session_map.json> <outDir>
//
// For every host name a collaborator reads or calls, the host's own
// declaration is copied as an abstract member (a field becomes a getter,
// and a setter too when some part writes it). Names are sorted into
// roles by what they are FOR — project/history/commands/lookups,
// selection, change notification, frame-id minting, timeline/layer
// controllers — and what fits none of those lands in `SessionInternals`,
// the bucket later waves empty. The generator writes:
//   <outDir>/session_roles.draft.dart   — the interfaces
//   <outDir>/collaborator_roles.json    — which roles each collaborator
//                                          needs, by the names it uses
// It decides nothing on its own: the role table below IS the decision,
// and it is read by eye before the draft is copied into lib/.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

const _hostPath = 'lib/src/ui/editor_session_manager.dart';
const _hostClass = 'EditorSessionManager';

/// Name → role. Everything a collaborator touches and is not listed here
/// goes to SessionInternals, which is the list of what still has no home.
const roleOrder = [
  'ProjectAccess',
  'SelectionAccess',
  'ChangeSink',
  'FrameIds',
  'TimelineAccess',
];

const roleOf = <String, String>{
  // ProjectAccess: the document and the doors that change it.
  '_repository': 'ProjectAccess',
  '_historyManager': 'ProjectAccess',
  '_cutCommandCoordinator': 'ProjectAccess',
  '_layerById': 'ProjectAccess',
  '_trackById': 'ProjectAccess',
  'cutById': 'ProjectAccess',
  'trackOwningCut': 'ProjectAccess',
  'requireActiveCut': 'ProjectAccess',
  'activeCutOrNull': 'ProjectAccess',
  'activeCutId': 'ProjectAccess',
  'layers': 'ProjectAccess',
  '_rangeLayerById': 'ProjectAccess',
  '_commitLayerById': 'ProjectAccess',
  'trackSeGlobalLayerById': 'ProjectAccess',
  'isTrackSeLayerId': 'ProjectAccess',
  'isTrackTransitionLayerId': 'ProjectAccess',
  '_activeCutFrameCount': 'ProjectAccess',
  'activeCutGlobalStartFrame': 'ProjectAccess',
  '_refreshAfterCutCommand': 'ChangeSink',
  '_notifyChanged': 'ChangeSink',
  '_warmActiveCut': 'ChangeSink',
  '_refreshLiveAudioSchedule': 'ChangeSink',
  '_standsDownFromRetime': 'ChangeSink',
  '_nextFrameId': 'FrameIds',
  '_mintFrameId': 'FrameIds',
  '_frameSequence': 'FrameIds',
  '_timelineController': 'TimelineAccess',
  '_layerController': 'TimelineAccess',
  '_editingSession': 'TimelineAccess',
  'trackFrameAxis': 'TimelineAccess',
  '_axisForTrack': 'TimelineAccess',
  'exposureStateForLayer': 'TimelineAccess',
  'layerPoseAtFrame': 'TimelineAccess',
  'activeLayer': 'SelectionAccess',
  'activeLayerId': 'SelectionAccess',
  'selectedTrackId': 'SelectionAccess',
  'selectedFrame': 'SelectionAccess',
  'selectedRow': 'SelectionAccess',
  'currentFrameIndex': 'SelectionAccess',
  'frameRangeSelection': 'SelectionAccess',
  'trackFrameRangeSelection': 'SelectionAccess',
  'laneRangeSelection': 'SelectionAccess',
  'rowSelection': 'SelectionAccess',
  'activeTrack': 'SelectionAccess',
  'selectFrameIndex': 'SelectionAccess',
  'selectGlobalFrame': 'SelectionAccess',
  'clearAllSelections': 'SelectionAccess',
  'clearFrameRangeSelection': 'SelectionAccess',
  'clearRowSelection': 'SelectionAccess',
  'clearStoryboardCutSelection': 'SelectionAccess',
  'bandOrActiveRow': 'SelectionAccess',
  '_bandRowsForSelection': 'SelectionAccess',
  'bandNamesRowsThisPressWouldMiss': 'SelectionAccess',
  'editingGlobalFrame': 'SelectionAccess',
  '_gapGlobalFrame': 'SelectionAccess',
};

void main(List<String> args) {
  final root = args[0];
  final map =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  final outDir = Directory(args[2])..createSync(recursive: true);

  final parts = (map['parts'] as List).cast<Map<String, dynamic>>();
  final usedBy = <String, Set<String>>{};
  final writtenBy = <String, Set<String>>{};
  final namesOf = <String, Set<String>>{};
  for (final p in parts) {
    if (p['kind'] != 'collaborator') continue;
    final part = p['part'] as String;
    for (final m in (p['members'] as List).cast<Map<String, dynamic>>()) {
      for (final n in [
        ...(m['reads'] as List),
        ...(m['calls'] as List),
      ].cast<String>()) {
        usedBy.putIfAbsent(n, () => {}).add(part);
        namesOf.putIfAbsent(part, () => {}).add(n);
      }
      for (final n in (m['writes'] as List).cast<String>()) {
        writtenBy.putIfAbsent(n, () => {}).add(part);
        namesOf.putIfAbsent(part, () => {}).add(n);
      }
    }
  }

  final unit = parseString(
    content: File('$root/$_hostPath').readAsStringSync(),
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  final host = unit.declarations.whereType<ClassDeclaration>().firstWhere(
    (c) => c.namePart.typeName.lexeme == _hostClass,
  );
  final decl = <String, ClassMember>{};
  final fieldType = <String, String>{};
  for (final m in host.body.members) {
    if (m is MethodDeclaration) decl[m.name.lexeme] = m;
    if (m is FieldDeclaration) {
      for (final v in m.fields.variables) {
        decl[v.name.lexeme] = m;
        fieldType[v.name.lexeme] = m.fields.type?.toSource() ?? 'dynamic';
      }
    }
  }

  // Collaborator-typed host fields (late final _X _x = _X(this)) are
  // siblings, not roles: a collaborator that reads `_session._clipboard`
  // gets the sibling injected. Listed so the reader sees them.
  final siblings = <String>{};
  for (final e in fieldType.entries) {
    if (e.value.startsWith('_')) siblings.add(e.key);
  }

  final byRole = <String, List<String>>{};
  final unresolved = <String>[];
  for (final n in usedBy.keys.toList()..sort()) {
    if (!decl.containsKey(n)) {
      unresolved.add(n);
      continue;
    }
    final role = siblings.contains(n)
        ? 'Sibling'
        : (roleOf[n] ?? 'SessionInternals');
    byRole.putIfAbsent(role, () => []).add(n);
  }

  String memberSource(String n) {
    final m = decl[n]!;
    final public = n.startsWith('_') ? n.substring(1) : n;
    if (m is FieldDeclaration) {
      final t = fieldType[n]!;
      final s = StringBuffer('  $t get $public;');
      if (writtenBy.containsKey(n)) s.write('\n  set $public($t value);');
      return s.toString();
    }
    final md = m as MethodDeclaration;
    final ret = md.returnType?.toSource() ?? 'void';
    if (md.isGetter) return '  $ret get $public;';
    if (md.isSetter) return '  set $public${md.parameters!.toSource()};';
    final tp = md.typeParameters?.toSource() ?? '';
    return '  $ret $public$tp${md.parameters!.toSource()};';
  }

  final draft = StringBuffer()
    ..writeln(
      '// DRAFT — generated by tool/refactor/session_roles_gen.dart; read before use.',
    )
    ..writeln(
      '// Every member is a host member some collaborator reads or calls today.',
    )
    ..writeln();
  for (final role in [
    'ProjectAccess',
    'SelectionAccess',
    'ChangeSink',
    'FrameIds',
    'TimelineAccess',
    'SessionInternals',
  ]) {
    final names = byRole[role] ?? const [];
    draft.writeln('abstract interface class $role {');
    for (final n in names) {
      draft.writeln(
        '  // used by ${usedBy[n]!.length} part(s): ${(usedBy[n]!.toList()..sort()).join(', ')}',
      );
      draft.writeln(memberSource(n));
    }
    draft.writeln('}');
    draft.writeln();
  }
  draft.writeln(
    '// Siblings (collaborator fields read through the host): ${(byRole['Sibling'] ?? const []).join(', ')}',
  );
  draft.writeln(
    '// Names with no host declaration (extension/mixin members?): ${unresolved.join(', ')}',
  );
  File(
    '${outDir.path}/session_roles.draft.dart',
  ).writeAsStringSync(draft.toString());

  final perCollab = <String, Object?>{};
  for (final e in namesOf.entries) {
    final roles = <String>{};
    final sibs = <String>[];
    final internals = <String>[];
    for (final n in e.value) {
      if (siblings.contains(n)) {
        sibs.add(n);
      } else {
        final r = roleOf[n] ?? 'SessionInternals';
        roles.add(r);
        if (r == 'SessionInternals') internals.add(n);
      }
    }
    perCollab[e.key] = {
      'roles': roles.toList()..sort(),
      'siblings': sibs..sort(),
      'internals': internals..sort(),
      'names': e.value.toList()..sort(),
    };
  }
  File(
    '${outDir.path}/collaborator_roles.json',
  ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(perCollab));

  for (final role in byRole.keys.toList()..sort()) {
    print(
      '${role.padRight(18)} ${byRole[role]!.length.toString().padLeft(3)}  ${byRole[role]!.join(' ')}',
    );
  }
  print('unresolved: $unresolved');
}

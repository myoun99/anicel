// ignore_for_file: avoid_print
// G4-1 of the god-object decomposition (2026-09-08): the host is a FACADE,
// so it carries no forwarders. A member whose whole body is
// `=> _collaborator.x` / `=> _collaborator.x(...)` gives one verb two names
// — the host answering for an object it no longer owns — and the house rule
// is that the UI names the collaborator instead.
//
//   dart run tool/refactor/session_forwarders.dart <repoRoot> --list
//   dart run tool/refactor/session_forwarders.dart <repoRoot> --strip _camera
//
// ⛔WHAT IT REFUSES TO DELETE, and why each is NOT a forwarder:
//   - a member declared by one of the ROLE interfaces the host implements
//     (ProjectAccess/SelectionAccess/ChangeSink/FrameIds/TimelineAccess/
//     SessionInternals). The host implementing its own role is the host
//     doing its job, even when the body happens to be one line — and the
//     collaborator that asks for it must NOT name the one that answers it
//     (that edge would close a construction cycle: `late final X _x = X(…)`
//     with two objects naming each other is a stack overflow on first
//     touch, measured 2026-09-06).
//   - a member carrying a DECISION comment (🚨⛔★⚠️/"decided"), because
//     deleting it would delete the decision. Those are moved by hand, with
//     the comment carried verbatim to the collaborator.
// Both are printed as KEPT with the reason; everything else goes.
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

const _hostPath = 'lib/src/ui/editor_session_manager.dart';
const _rolesPath = 'lib/src/ui/session/session_roles.dart';
const _hostClass = 'EditorSessionManager';

CompilationUnit _parse(String path) => parseFile(
  path: path,
  featureSet: FeatureSet.latestLanguageVersion(),
  throwIfDiagnostics: false,
).unit;

/// The field a one-expression body delegates to and the name it calls
/// there, or null when the body is anything else (a real body, a literal,
/// a call on `this`). ⚠️The two names are not always equal —
/// `projectTimelineLayout() => _projectSettings.projectLayout()` — so the
/// call sites need the TARGET name, not the host's.
({String field, String member})? _delegateTarget(MethodDeclaration m) {
  final body = m.body;
  if (body is! ExpressionFunctionBody) return null;
  final e = body.expression;
  Expression? target;
  String? member;
  if (e is MethodInvocation) {
    target = e.target;
    member = e.methodName.name;
  } else if (e is PropertyAccess) {
    target = e.target;
    member = e.propertyName.name;
  } else if (e is PrefixedIdentifier) {
    target = e.prefix;
    member = e.identifier.name;
  } else if (e is AssignmentExpression) {
    final lhs = e.leftHandSide;
    if (lhs is PropertyAccess) {
      target = lhs.target;
      member = lhs.propertyName.name;
    } else if (lhs is PrefixedIdentifier) {
      target = lhs.prefix;
      member = lhs.identifier.name;
    }
  }
  if (target is! SimpleIdentifier || member == null) return null;
  return (field: target.name, member: member);
}

bool _isDecision(String text) =>
    text.contains('🚨') ||
    text.contains('⛔') ||
    text.contains('★') ||
    text.contains('⚠') ||
    text.contains('decided') ||
    text.contains('THE ');

/// The first token of the declaration PROPER — past every comment written
/// above it (doc comments are comment tokens in the stream, so they hang
/// off this one), but including `@override` and friends.
Token _declarationStart(MethodDeclaration m) => m.metadata.isNotEmpty
    ? m.metadata.first.beginToken
    : m.firstTokenAfterCommentAndMetadata;

/// Start offset of a member including the comments written above it.
int _startWithComments(MethodDeclaration m) {
  final anchor = _declarationStart(m);
  return anchor.precedingComments?.offset ?? anchor.offset;
}

String _leadingComments(MethodDeclaration m, String src) =>
    src.substring(_startWithComments(m), _declarationStart(m).offset);

void main(List<String> args) {
  final root = args.isEmpty ? '.' : args[0];
  final strip = args.contains('--strip')
      ? args[args.indexOf('--strip') + 1]
      : null;

  final roleMembers = <String, List<String>>{};
  for (final c in _parse(
    '$root/$_rolesPath',
  ).declarations.whereType<ClassDeclaration>()) {
    for (final m in c.body.members.whereType<MethodDeclaration>()) {
      (roleMembers[m.name.lexeme] ??= []).add(c.namePart.typeName.lexeme);
    }
  }

  final hostFile = File('$root/$_hostPath');
  final src = hostFile.readAsStringSync();
  final lineInfo = LineInfo.fromContent(src);
  final host = _parse(
    '$root/$_hostPath',
  ).declarations.whereType<ClassDeclaration>().firstWhere(
    (c) => c.namePart.typeName.lexeme == _hostClass,
  );

  final byField = <String, List<MethodDeclaration>>{};
  final targetName = <MethodDeclaration, String>{};
  for (final m in host.body.members.whereType<MethodDeclaration>()) {
    final to = _delegateTarget(m);
    if (to == null || !to.field.startsWith('_')) continue;
    (byField[to.field] ??= []).add(m);
    targetName[m] = to.member;
  }

  if (strip == null) {
    var total = 0;
    for (final field in byField.keys.toList()..sort()) {
      final members = byField[field]!;
      total += members.length;
      print('$field  (${members.length})');
      for (final m in members) {
        final roles = roleMembers[m.name.lexeme];
        final decision = _isDecision(_leadingComments(m, src));
        final renamed = targetName[m] != m.name.lexeme;
        print(
          '  L${lineInfo.getLocation(m.offset).lineNumber} ${m.name.lexeme}'
          '${renamed ? '  ->${targetName[m]}' : ''}'
          '${roles != null ? '  KEEP:role ${roles.join(",")}' : ''}'
          '${decision ? '  KEEP:decision-comment' : ''}'
          '${_leadingComments(m, src).trim().isEmpty ? '' : '  HASCOMMENT'}',
        );
      }
    }
    print('TOTAL $total');
    return;
  }

  final members = byField[strip];
  if (members == null) {
    stderr.writeln('no forwarders to $strip');
    exit(2);
  }
  final spans = <(int, int)>[];
  final deleted = <String>[];
  for (final m in members) {
    final roles = roleMembers[m.name.lexeme];
    if (roles != null) {
      print('KEPT ${m.name.lexeme}  role ${roles.join(",")}');
      continue;
    }
    if (_isDecision(_leadingComments(m, src))) {
      print('KEPT ${m.name.lexeme}  decision comment above it');
      continue;
    }
    // Back to the start of the line, or the member's own indent survives it.
    var start = _startWithComments(m);
    while (start > 0 && (src[start - 1] == ' ' || src[start - 1] == '\t')) {
      start -= 1;
    }
    spans.add((start, m.end));
    deleted.add(m.name.lexeme);
  }
  var out = src;
  for (final span in spans.reversed) {
    var end = span.$2;
    while (end < out.length && (out[end] == '\n' || out[end] == '\r')) {
      end += 1;
    }
    out = out.substring(0, span.$1) + out.substring(end);
  }
  hostFile.writeAsStringSync(out);
  print('deleted ${deleted.length}: ${deleted.join(" ")}');
}

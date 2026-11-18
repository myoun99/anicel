import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ci = '.github/workflows/ci.yml';
const _action = '.github/actions/test-shard/action.yml';

/// 🚨THE SHARDS READ THE RECORD THE SCOPE JOB FETCHED, AND LEAVE THE ONE IT
/// FETCHES NEXT TIME (card ci-shards-dealt-by-measured-seconds, 2026-11-17).
///
/// Three names tie it together across two files: the artifact the scope job
/// uploads and every shard job downloads, and the shards' own records the
/// scope job looks the last run up by. A shard asked for an artifact the
/// scope never made fails at the download — every shard of a bundle PR's
/// round red at once — and a record named past the scope's lookup is never
/// read again: the shards fall back to dealing by size, which looks exactly
/// like normal. So the landing's architecture run reads the names first.
void main() {
  final ci = File(_ci).readAsStringSync();
  final action = File(_action).readAsStringSync();

  test('every shard job reads the artifact the scope job uploads', () {
    final read = RegExp(r'times-artifact: (\S+)')
        .allMatches(ci)
        .map((m) => m[1]!)
        .toSet();
    expect(read, isNotEmpty, reason: '$_ci passes no record to its shards');
    final uploaded = RegExp(
      r'upload-artifact@\S+\s+with:\s+name: (\S+)\s+path: \$\{\{ runner\.temp '
      r'\}\}/shard-times/',
    ).firstMatch(ci);
    expect(uploaded, isNotNull, reason: 'the scope job uploads no record');
    expect(read, {uploaded![1]});
  });

  test('the scope job looks up the records the shards leave', () {
    final left = RegExp(r'name: (test-times-)\$\{\{ runner\.os \}\}-'
            r'\$\{\{ inputs\.index \}\}')
        .firstMatch(action);
    expect(left, isNotNull, reason: '$_action leaves no record');
    expect(ci, contains('name=${left![1]}\$os-0'), reason: 'the lookup');
    expect(ci, contains('-p "${left[1]}\$os-*"'), reason: 'the download');
    expect(
      ci,
      contains('for os in Linux Windows'),
      reason: 'runner.os spells the two OSes the shards run on this way',
    );
  });
}

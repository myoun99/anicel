import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🗣️play-auto-upload (유저 2026-10-31 「지금 빌드시 자동으로 올리는것도
/// 할수있나? 플레이스토어쪽?」): `tool/play_upload.sh` publishes a bundle on
/// the closed test. Only the control tower's round runs it, and a wrong step
/// reaches testers, so the real script is run here against a stand-in for
/// Google.
void main() {
  late HttpServer server;
  late Directory sandbox;
  late File key;
  late File bundle;
  late List<String> calls;
  late Map<String, String> bodies;
  late Map<String, String> queries;
  String? refuse;

  Future<ProcessResult> run(List<String> extra) => Process.run(
    'bash',
    ['tool/play_upload.sh', bundle.path, '1085', key.path, ...extra],
    environment: {
      'PLAY_API_ROOT': 'http://127.0.0.1:${server.port}',
      'PLAY_TOKEN_URL': 'http://127.0.0.1:${server.port}/token',
      'TMPDIR': Directory('${sandbox.path}/tmp').path.replaceAll(r'\', '/'),
    },
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('play_upload');
    await Directory('${sandbox.path}/tmp').create();
    final pem = await Process.run('bash', [
      '-c',
      'openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null',
    ]);
    key = File('${sandbox.path}/key.json')
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'type': 'service_account',
          'private_key': pem.stdout,
          'client_email': 'uploader@example.iam.gserviceaccount.com',
        }),
      );
    bundle = File('${sandbox.path}/bundle.aab')..writeAsStringSync('a bundle');
    calls = [];
    bodies = {};
    queries = {};
    refuse = null;
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      const app = '/androidpublisher/v3/applications/com.myoun.anicel';
      final raw = request.uri.path;
      final path = raw.startsWith(app) ? raw.substring(app.length) : raw;
      final call = '${request.method} $path';
      calls.add(call);
      bodies[call] = body;
      queries[call] = request.uri.query;
      final answer = request.response..headers.contentType = ContentType.json;
      if (call == refuse) {
        answer
          ..statusCode = 403
          ..write('{"error":{"message":"Play says no"}}');
      } else if (path == '/token') {
        answer.write('{"access_token": "a-token", "expires_in": 3600}');
      } else if (call == 'POST /edits') {
        answer.write('{\n  "id": "edit-1",\n  "expiryTimeSeconds": "9"\n}');
      } else {
        answer.write('{}');
      }
      await answer.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await sandbox.delete(recursive: true);
  });

  const opened = ['POST /token', 'POST /edits'];
  const upload = 'POST /upload/androidpublisher/v3/applications/com.myoun.anicel'
      '/edits/edit-1/bundles';
  const named = 'PUT /edits/edit-1/tracks/alpha';
  const validated = 'POST /edits/edit-1:validate';
  const committed = 'POST /edits/edit-1:commit';

  test('it uploads, names the release, validates, then publishes', () async {
    final done = await run([]);
    expect(done.exitCode, 0, reason: '${done.stderr}');
    expect(calls, [...opened, upload, named, validated, committed]);
    expect(bodies[upload], 'a bundle');
    expect(queries[upload], 'uploadType=media');
    final version = RegExp(r'^version: *([^+\s]+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())![1];
    expect(jsonDecode(bodies[named]!), {
      'track': 'alpha',
      'releases': [
        {
          'name': '1085 ($version)',
          'versionCodes': ['1085'],
          'status': 'completed',
        },
      ],
    });
  });

  test('--check validates and throws the edit away, publishing nothing',
      () async {
    final done = await run(['--check']);
    expect(done.exitCode, 0, reason: '${done.stderr}');
    expect(
      calls,
      [...opened, upload, named, validated, 'DELETE /edits/edit-1'],
    );
  });

  test('a refused step stops there, in Play\'s own words', () async {
    for (final step in [upload, named, validated, committed]) {
      calls.clear();
      refuse = step;
      final done = await run([]);
      expect(done.exitCode, 1, reason: step);
      expect(done.stderr, contains('Play says no'), reason: step);
      expect(calls.last, step);
    }
  });

  test('the key it writes out to sign with is gone afterwards', () async {
    await run([]);
    expect(Directory('${sandbox.path}/tmp').listSync(), isEmpty);
  });
}

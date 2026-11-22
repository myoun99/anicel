import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart' show codeOnly;
import 'dart_sources.dart';
import 'real_sockets.dart';

/// A TEST THAT TALKS TO A SERVER IS ANSWERED BY THAT SERVER, whatever
/// started the binding before it ([talkOverRealSockets]; card
/// the-wide-check-takes-five-hours, 2026-11-22).
void main() {
  // What a bundle does to a file that never starts the binding itself:
  // another file's `testWidgets` starts it, and with it the HTTP that
  // answers 400.
  TestWidgetsFlutterBinding.ensureInitialized();
  talkOverRealSockets();

  test('a request to the test\'s own server is answered by that server, '
      'though the binding has started', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('heard');
      await request.response.close();
    });
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final response = await (await client.get(
      InternetAddress.loopbackIPv4.address,
      server.port,
      '/',
    )).close();

    expect(response.statusCode, HttpStatus.ok);
    expect(await response.transform(utf8.decoder).join(), 'heard');
  });

  test('every test file that opens a socket says so first', () {
    final opens = RegExp(r'\bHttpServer\.bind\(|\bHttpClient\(');
    final silent = <String>[];
    for (final file in dartFilesUnder('test')) {
      if (!file.path.endsWith('_test.dart')) continue;
      final code = codeOnly(file.readAsStringSync());
      if (opens.hasMatch(code) && !code.contains('talkOverRealSockets();')) {
        silent.add(file.path.replaceAll(r'\', '/'));
      }
    }

    expect(
      silent,
      isEmpty,
      reason: 'in a bundle where another file started the binding, a file '
          'that talks to a server of its own is answered 400 — call '
          'talkOverRealSockets() first in its main',
    );
  });
}

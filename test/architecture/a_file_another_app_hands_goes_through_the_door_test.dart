import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/handed_files.dart';

import '../helpers/source_body.dart';

/// `open-door-android-share` (F-282-Q5, 유저 2026-10-09: 「추천대로. 최대한
/// 통일하고싶음」): what another app opens Anicel with (「다음으로 열기」) or
/// shares with it (「공유」) goes through the one door a drop goes through.
///
/// A CHANNEL HAS NO COMPILER (`one_channel_dialect_test`), so this is the
/// handover's type check: the activity takes the intents, says each file
/// as a pick says it, on [HandedFiles.channel], from the first frame on.
///
/// ⚠️A SOURCE PIN, because this suite runs no Android: it can say each part
/// is there; a share reaching a tab is the tablet's to show.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final source = File(
    'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt',
  ).readAsStringSync();

  /// The MainActivity element of the manifest, from its tag to its close.
  String activityElement() {
    final start = manifest.indexOf('android:name=".MainActivity"');
    expect(start, greaterThanOrEqualTo(0), reason: 'premise: it is declared');
    final end = manifest.indexOf('</activity>', start);
    expect(end, greaterThan(start), reason: 'premise: it closes');
    return manifest.substring(start, end);
  }

  /// The intent filter of [activity] that takes [action].
  String filterTaking(String activity, String action) {
    for (final filter in activity.split('<intent-filter>').skip(1)) {
      final body = filter.substring(0, filter.indexOf('</intent-filter>'));
      if (body.contains('<action android:name="$action"/>')) {
        return body;
      }
    }
    return fail('no filter takes $action');
  }

  test('the activity takes 「다음으로 열기」 and 「공유」 of every type, stands '
      'once, and reads no route out of a file', () {
    final activity = activityElement();
    final view = filterTaking(activity, 'android.intent.action.VIEW');
    final send = filterTaking(activity, 'android.intent.action.SEND');
    expect(
      send,
      contains('<action android:name="android.intent.action.SEND_MULTIPLE"/>'),
    );
    for (final filter in [view, send]) {
      expect(
        filter,
        contains('<category android:name="android.intent.category.DEFAULT"/>'),
        reason: 'an implicit intent reaches no activity without it',
      );
      expect(filter, contains('<data android:mimeType="*/*"/>'));
    }
    expect(
      activity,
      contains('android:launchMode="singleTask"'),
      reason: 'a file shared while Anicel runs opens in the running one',
    );
    expect(
      activity,
      matches(
        RegExp(
          r'android:name="flutter_deeplinking_enabled"\s+'
          'android:value="false"',
        ),
      ),
      reason: 'a VIEW\'s data is a file, not a route',
    );
  });

  test('the activity hands what a fresh start and a running app are given, '
      'from the first frame on, on the channel Dart hears', () {
    expect(
      source,
      contains(
        'private val handedFilesChannel = "${HandedFiles.channel.name}"',
      ),
    );
    expect(
      source,
      contains('private val openHanded = "${HandedFiles.openMethod}"'),
    );
    expect(
      sourceBodyOf(source, 'override fun configureFlutterEngine('),
      contains('handedFiles = MethodChannel('),
    );

    final created = sourceBodyOf(source, 'override fun onCreate(');
    final started = created.indexOf('super.onCreate(savedInstanceState)');
    expect(started, greaterThanOrEqualTo(0));
    expect(
      created.indexOf('hand(intent)'),
      greaterThan(started),
      reason: 'once the engine, and the channel, stand',
    );
    expect(created, contains('savedInstanceState != null'));
    expect(created, contains('Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY'));
    expect(
      sourceBodyOf(source, 'override fun onNewIntent('),
      contains('hand(intent)'),
    );

    final hand = sourceBodyOf(source, 'private fun hand(');
    for (final step in [
      'handsFiles(intent)',
      'documentUris(intent)',
      'pickedItem(it, isFolder = false)',
      'heldForTheFirstFrame',
      'invokeMethod(openHanded, items)',
    ]) {
      expect(hand, contains(step));
    }
    final hands = sourceBodyOf(source, 'private fun handsFiles(');
    for (final action in [
      'Intent.ACTION_VIEW',
      'Intent.ACTION_SEND',
      'Intent.ACTION_SEND_MULTIPLE',
    ]) {
      expect(hands, contains(action));
    }
    final firstFrame = sourceBodyOf(
      source,
      'override fun onFlutterUiDisplayed(',
    );
    expect(firstFrame, contains('heldForTheFirstFrame = null'));
    expect(firstFrame, contains('invokeMethod(openHanded, held)'));
  });

  test('a handed file is said by the code a pick says its files with', () {
    expect(
      sourceBodyOf(source, 'override fun onActivityResult('),
      contains('uris.mapNotNull { pickedItem(it, isFolder) }'),
    );
    final item = sourceBodyOf(source, 'private fun pickedItem(');
    for (final step in [
      'takePersistable(uri, writable = true)',
      'realPathFor(uri, isFolder)',
      'documentItem(uri)',
    ]) {
      expect(item, contains(step));
    }
    // What an app old enough to share a file: URI hands over is the path
    // it names — no picker answers with one, so this is the share's alone.
    final real = sourceBodyOf(source, 'private fun realPathFor(');
    expect(real, contains('uri.scheme == ContentResolver.SCHEME_FILE'));
    expect(real, contains('uri.path?.let { existingFile(it) }'));
  });
}

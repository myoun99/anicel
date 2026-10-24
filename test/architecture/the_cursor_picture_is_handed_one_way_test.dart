import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/drawing_cursor.dart';

import '../helpers/source_body.dart';

/// 🗣️I-54 (유저 2026-09-30): the pen 「os커서를 바꿈으로서 앱이랑 관계없이
/// 빠르게」 — and F-441, the bucket and the dropper with it. The engines of
/// macOS, Android and Linux take no picture for a cursor, so their runners
/// do, over [runnerCursorChannel] with the two calls Windows's engine takes.
///
/// A CHANNEL HAS NO COMPILER (`one_channel_dialect_test`), so this is the
/// picture's type check: every runner hears both calls, reads every key
/// Dart hands over, keeps what it made by name and wears it on the window
/// the engine wears its own cursors on.
///
/// ⚠️A SOURCE PIN, because this suite runs no runner: it can say each
/// runner answers; what the cursor looks like is the desktop's to show.
void main() {
  final channel = '"${runnerCursorChannel.name}"';
  const make = '"$runnerMakeCursor"';
  const wear = '"$runnerWearCursor"';
  const keys = ['buffer', 'width', 'height', 'hotX', 'hotY'];

  test('Dart hands over every key the runners read', () {
    final source = File('lib/src/ui/brush/drawing_cursor.dart')
        .readAsStringSync();
    // The map the picture is made with.
    final made = sourceBodyOf(source, 'door.channel.invokeMethod<String>(');
    for (final key in ['name', ...keys, 'scale']) {
      expect(made, contains("'$key':"), reason: key);
    }
  });

  test('the Mac makes the channel with its window, makes a cursor of the '
      'picture at the screen\'s points and wears it by name', () {
    final source = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    final cursors = sourceBodyOf(source, 'final class PictureCursors');
    expect(cursors, contains('name: $channel'));
    final handle = sourceBodyOf(cursors, 'private func handle(');
    expect(handle, contains('case $make:'));
    expect(handle, contains('case $wear:'));
    expect(handle, contains('cursor.set()'));
    final picture = sourceBodyOf(cursors, 'private static func cursor(');
    for (final key in [...keys, 'scale']) {
      expect(picture, contains('arguments["$key"]'), reason: key);
    }
    expect(
      sourceBodyOf(source, 'override func awakeFromNib()'),
      contains('PictureCursors('),
    );
  });

  test('Linux registers the channel with its view, builds it, and wears a '
      'cursor on the window the engine wears its own on', () {
    final source = File('linux/runner/picture_cursors.cc').readAsStringSync();
    expect(
      sourceBodyOf(source, 'void anicel_picture_cursors_register('),
      contains(channel),
    );
    final call = sourceBodyOf(source, 'void on_method_call(');
    expect(call, contains(make));
    expect(call, contains(wear));
    expect(call, contains('gdk_window_set_cursor(window, cursor);'));
    final picture = sourceBodyOf(source, 'GdkCursor* cursor_of(');
    for (final key in [...keys, 'scale']) {
      expect(picture, contains('"$key"'), reason: key);
    }
    expect(
      sourceBodyOf(source, 'GdkWindow* window_of('),
      contains('gtk_widget_get_toplevel'),
      reason: 'fl_view.cc wears the engine\'s cursors on the toplevel',
    );
    expect(
      sourceBodyOf(
        File('linux/runner/my_application.cc').readAsStringSync(),
        'static void my_application_activate(',
      ),
      contains('anicel_picture_cursors_register(view);'),
    );
    expect(
      File('linux/runner/CMakeLists.txt').readAsStringSync(),
      contains('"picture_cursors.cc"'),
    );
  });

  test('Android makes the channel with its engine and wears a picture as '
      'the Flutter view\'s pointer icon', () {
    final source = File(
      'android/app/src/main/kotlin/com/myoun/anicel/PictureCursors.kt',
    ).readAsStringSync();
    final cursors = sourceBodyOf(
      source,
      'internal fun FlutterActivity.wearPictureCursors(',
    );
    expect(cursors, contains(channel));
    expect(cursors, contains('call.method == $make'));
    expect(cursors, contains('call.method == $wear'));
    expect(cursors, contains('view.pointerIcon = icon'));
    for (final key in keys) {
      expect(cursors, contains('call.argument<'), reason: key);
      expect(cursors, contains('>("$key")'), reason: key);
    }
    expect(
      sourceBodyOf(
        File(
          'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt',
        ).readAsStringSync(),
        'override fun configureFlutterEngine(',
      ),
      contains('wearPictureCursors(flutterEngine)'),
    );
  });
}

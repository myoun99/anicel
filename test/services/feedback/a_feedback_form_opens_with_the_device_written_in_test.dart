import 'package:anicel/src/services/feedback/feedback_forms.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-139 (유저 2026-10-28): both forms open with the device, the OS, its
/// version and the build already answered. The numbers below are the
/// forms' own, read from the 「미리 채운 링크」 the user sent and from the
/// live text form's page on 2026-10-28.
void main() {
  const device = (
    model: 'Microsoft Corporation Surface Pro, 11th Edition',
    os: FeedbackOs.windows,
    osVersion: '11 25H2 (26200.6899)',
  );

  test('the text form: its id and the four answers, each on its entry', () {
    final link = FeedbackForm.text.prefilled(device, '1060 (a1b2c3d)');
    expect(link.host, 'docs.google.com');
    expect(
      link.path,
      '/forms/d/e/1FAIpQLSejoVJHbqvP2ElNpebsf135aiNmMWImiAUmxT5DAGg5fyKz8Q'
      '/viewform',
    );
    expect(link.queryParameters, {
      'usp': 'pp_url',
      'entry.2065979038': 'Microsoft Corporation Surface Pro, 11th Edition',
      'entry.1923349773': 'Windows',
      'entry.162816568': '11 25H2 (26200.6899)',
      'entry.1177841678': '1060 (a1b2c3d)',
    });
  });

  test('the file form: its own id, the same entries', () {
    final link = FeedbackForm.files.prefilled(device, 'dev');
    expect(
      link.path,
      '/forms/d/e/1FAIpQLSeQ5kCUA1tkl4Ob04AVtvZ7ZIGg66b4vcaExpdDcTnQLcQhgA'
      '/viewform',
    );
    expect(link.queryParameters['entry.1923349773'], 'Windows');
    expect(link.queryParameters['entry.1177841678'], 'dev');
  });

  test('the OS answers are the dropdown\'s words, letter for letter', () {
    // An answer that matches no choice is dropped by the form.
    expect([for (final os in FeedbackOs.values) os.choice], [
      'Windows',
      'macOS',
      'iPadOS',
      'iOS',
      'Android',
      'Linux',
    ]);
  });
}

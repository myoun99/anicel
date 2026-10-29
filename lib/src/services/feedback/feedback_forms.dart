/// The two Google Forms the 「의견 보내기」 row opens, and the link that
/// opens one with the sender's device already written in.
///
/// 🗣️I-139 (유저 2026-10-28): an anonymous text form and a form that takes
/// screenshots and videos — Google asks the sender of the second to sign
/// in, which is why there are two (I-139-Q1) — both opened in the browser
/// with the device, the OS, its version and the build filled in. The forms
/// are written in English alone (I-139-Q3), so nothing here is translated.
library;

/// The OS question's choices, spelled EXACTLY as the forms' dropdown spells
/// them: a filled-in answer that matches no choice is dropped by the form.
enum FeedbackOs {
  windows('Windows'),
  macOS('macOS'),
  iPadOS('iPadOS'),
  iOS('iOS'),
  android('Android'),
  linux('Linux');

  const FeedbackOs(this.choice);

  /// The dropdown's own words for it.
  final String choice;
}

/// What the forms are told about the device: its [model], its [os] and
/// that OS's [osVersion].
///
/// ⛔ONLY these. The places they are read from also hold the computer's
/// name, the user's name, the device's ID and its registered owner —
/// values that point at a person, which the forms never ask for.
typedef DeviceDescription = ({String model, FeedbackOs os, String osVersion});

enum FeedbackForm {
  /// Text only, no sign-in.
  text('1FAIpQLSejoVJHbqvP2ElNpebsf135aiNmMWImiAUmxT5DAGg5fyKz8Q'),

  /// With screenshots and videos; Google asks the sender to sign in.
  files('1FAIpQLSeQ5kCUA1tkl4Ob04AVtvZ7ZIGg66b4vcaExpdDcTnQLcQhgA');

  const FeedbackForm(this.publishedId);

  /// The `/forms/d/e/<id>` of the form's public link.
  final String publishedId;

  /// The form, opened with [device] and [build] already answered.
  Uri prefilled(DeviceDescription device, String build) => Uri.https(
    'docs.google.com',
    '/forms/d/e/$publishedId/viewform',
    {
      'usp': 'pp_url',
      'entry.$_deviceEntry': device.model,
      'entry.$_osEntry': device.os.choice,
      'entry.$_osVersionEntry': device.osVersion,
      'entry.$_buildEntry': build,
    },
  );
}

// The questions' entry numbers, from each form's own 「미리 채운 링크」. ONE
// set for both forms: the file form was made as a copy of the text form, and
// the two links the user sent (2026-10-28) carry the same four numbers.
const _deviceEntry = 2065979038;
const _osEntry = 1923349773;
const _osVersionEntry = 162816568;
const _buildEntry = 1177841678;

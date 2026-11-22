import 'app_strings.dart';

/// THE sentence a cloud wait shows, wherever it is drawn.
///
/// 🚨★★★ONE LAW, ONE PLACE (F-141). The top strip's open window and the
/// import window each wrote this out — the same templates, the same
/// `{sec}` substitution, in two files. Two spellings of one law drift, and
/// the one that drifts is the one nobody is looking at.
///
/// [waited] is how long the wait has gone on, and the line counts it to
/// the end — however long, whatever has or has not come.
/// 🪦🗣️NO 「NOTHING HAS ARRIVED」 (F-608, 유저 2026-11-23, a Galaxy Tab on
/// build 1098: 「그냥 도착안했다고 안뜨게하는게 젤 확실할거같은데. 이정도까지
/// 구분못할거면」). After ten seconds with no byte the app could see, the
/// line said none had come — and the file then opened on its own: a
/// provider can hold the bytes where the app cannot see them till they are
/// all there. The third time that sentence lied: F-141 (09-16, a wait on a
/// clock → on an arrival) and F-608 ① (11-17, on any arrival → on the last
/// one) each narrowed when it was said, and the 1098 build still said it.
/// The sentence, its ten seconds (`cloudWaitSaysNothingAfter`) and the
/// quiet it was read off went together.
///
/// 🗣️THE CLOUD IS NAMED ONLY WHILE THE DEVICE SAYS SO ([fromTheCloud] —
/// F-621-Q2, 유저 2026-11-19: 「투명하게만 하면되. 1번대로하자」): while
/// the file is not here yet — an iPad's provider holding the coordinated
/// read, a placeholder asked to come down — the line says it is coming
/// from the cloud, and while bytes come in that the app can see, that it
/// is reading the file. ↩️Every wait said the cloud, and a file on the
/// disk read for two seconds under 「クラウドから受信中」. ⚠️What the
/// device cannot tell reads as reading — a document an Android provider
/// pours in (from its network or its cache, the app cannot know), and a
/// file Drive on Windows calls here while it still comes down
/// (`readOpenedFile`'s 🚨): the line says what the device says, never a
/// guess.
String cloudWaitLine(Duration waited, {required bool fromTheCloud}) {
  final strings = AppText.strings;
  final template = fromTheCloud
      ? strings.openWaitingCloudTemplate
      : strings.openWaitingReadingTemplate;
  return template.replaceAll('{sec}', '${waited.inSeconds}');
}

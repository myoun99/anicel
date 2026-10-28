/// Which build of the app this is, as the release build stamped it
/// (`tool/release_build.sh`): the round's number and the commit it was cut
/// from — `1060 (a1b2c3d)`. A build nobody stamped (a run from the IDE, a
/// test) says `dev`.
///
/// 🗣️I-139-Q5 (유저 2026-10-28): the feedback forms' Build field carries
/// 「빌드 번호 + 커밋」, stamped one way for every release (「배포할때도 같은
/// 방식으로 통일하고싶음」) — and nothing built in Android Studio is ever
/// handed out (「안드로이드 스튜디오에서 빌드해서 줄 일은 없음」), so an
/// unstamped build needs no number of its own.
library;

/// The defines `tool/release_build.sh` passes, spelled again there;
/// `every_release_build_is_stamped_one_way_test.dart` reads both (and the
/// usage statistics' key, `aptabaseKeyDefine`, beside them).
const String buildNumberDefine = 'ANICEL_BUILD';
const String buildCommitDefine = 'ANICEL_COMMIT';

/// The round's number alone — empty in a build nobody stamped. The usage
/// statistics name the app's version by it (I-70).
const String buildNumber = String.fromEnvironment(buildNumberDefine);
const String _commit = String.fromEnvironment(buildCommitDefine);

/// This build's stamp — see [stampOf].
String get buildStamp => stampOf(number: buildNumber, commit: _commit);

/// `<number> (<commit>)`, or `dev` when no number was stamped.
String stampOf({required String number, required String commit}) =>
    number.isEmpty ? 'dev' : '$number ($commit)';

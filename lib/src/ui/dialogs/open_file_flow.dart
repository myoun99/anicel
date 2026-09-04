import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';

/// The seam tests drive instead of a native dialog.
typedef LooseFilePicker = Future<List<String>> Function();

/// 🚨★★★**EVERY PICKER SHOWS EVERY FILE, AND THE REFUSAL COMES AFTER.**
///
/// 유저 2026-08-29: 「임포트든 열기든 뭐든 픽커는 pdf만 표시한다던가. 특히
/// 윈도우 열기시 anicel이랑 tvp만 설정따라서 보이게 되있는데 그게아니라
/// 픽커는 **어떤플랫폼이든 어떤 확장자던 선택할수 있게**하고, 대응만
/// 지원안되는 확장자면 **그 때 해당 파일 지원안된다고 안내창** 띄우게」.
///
/// ⛔A type filter in the dialog looks like a courtesy and behaves like a
/// wall: the file the user came for is GREYED OUT and the dialog gives no
/// reason, so the app looks broken in the one moment it has nothing to say.
/// Refusing afterwards costs one dialog and can name the file and the
/// formats — the difference between「안 열려요」and「이건 여기서 못 엽니다」.
///
/// The notice goes through [showAppNotice] because F-10 (유저 2026-08-24)
/// says every refusal does: 「이런 경고문은 공통ui창 띄우는거 사용해서
/// 띄우도록」.
///
/// 🚨**PLURAL FROM THE START.** 유저 2026-08-29: 「복수선택열기도 제공할
/// 예정이니까 유념해줘 … 지원하지 않는 파일이 감지되었습니다. 라는 안내창으로
/// 두번째줄에 해당 파일들이라는 항목으로 접기 펼치기 가능하게 그 안에
/// 파일주소,이름들 표시」. One rejected file and forty are the same notice —
/// which is why this returns a LIST and the message never names one file.
///
/// ⚠️[supportedExtensions] is lower-case and without dots. An empty list
/// accepts anything, for a caller that judges the CONTENT rather than the

/// Tells the user which files were turned away, and why.
///
/// ⛔ONE NOTICE, TWO PICKERS. The folder-grant flow and the open flow each
/// refused the same way and each had to name the same window key; only one
/// of them said why the paths go in the disclosure rather than the
/// sentence.
///
/// ⚠️The paths go in [AppNoticeDetails], not the message: one refusal
/// reads the same as forty, and forty do not push the buttons off screen.
Future<void> noticeUnsupportedFiles(
  BuildContext context,
  List<String> refused,
  List<String> supportedExtensions,
) => showAppNotice(
  context,
  title: AppText.strings.unsupportedFileTitle,
  message: AppText.strings.unsupportedFileMessageTemplate.replaceAll(
    '{kinds}',
    supportedExtensions.map((extension) => '.$extension').join(', '),
  ),
  details: refused,
  windowKey: const ValueKey<String>('unsupported-file-notice'),
);

/// name.
Future<List<String>> openSupportedFiles(
  BuildContext context, {
  required List<String> supportedExtensions,
  bool allowMultiple = false,
  LooseFilePicker? picker,
}) async {
  // No type groups at all: that is what "show everything" is on every
  // platform, and it is the one call this app makes.
  final pick = picker ?? () => _pickLoose(allowMultiple: allowMultiple);
  final picked = await pick();
  if (picked.isEmpty || !context.mounted) {
    return const [];
  }
  final accepted = <String>[];
  final refused = <String>[];
  for (final path in picked) {
    (fileIsSupported(path, supportedExtensions) ? accepted : refused).add(path);
  }
  if (refused.isNotEmpty) {
    await noticeUnsupportedFiles(context, refused, supportedExtensions);
  }
  return accepted;
}

/// The single-file wording of [openSupportedFiles].
Future<String?> openSupportedFile(
  BuildContext context, {
  required List<String> supportedExtensions,
  LooseFilePicker? picker,
}) async {
  final accepted = await openSupportedFiles(
    context,
    supportedExtensions: supportedExtensions,
    picker: picker,
  );
  return accepted.isEmpty ? null : accepted.first;
}

Future<List<String>> _pickLoose({required bool allowMultiple}) async {
  if (allowMultiple) {
    final files = await openFiles(acceptedTypeGroups: const []);
    return [for (final file in files) file.path];
  }
  final file = await openFile(acceptedTypeGroups: const []);
  return file == null ? const [] : [file.path];
}

/// Whether [path]'s suffix is one of [supported] — the judgement the picker
/// used to make by hiding files.
bool fileIsSupported(String path, List<String> supported) {
  if (supported.isEmpty) {
    return true;
  }
  final name = fileNameOfPath(path);
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) {
    return false;
  }
  return supported.contains(name.substring(dot + 1).toLowerCase());
}

/// The last segment of [path], for either platform's separator — the same
/// normalise-then-split this repo already uses for asset paths.
String fileNameOfPath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

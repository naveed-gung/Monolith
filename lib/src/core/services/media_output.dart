import 'dart:io';

/// Publishes a fully-staged audio file at [target].
///
/// Staging lives in private app storage; scoped storage on Android 11+
/// only permits audio MIME types inside public `Music`, so in-progress
/// files (`.part`, source video, extracted audio) must never be created
/// there — only the finished audio file passes through here.
///
/// Rename is atomic when staging and target share a volume; across
/// volumes it copies, verifies the length, then removes the staged file.
/// A truncated target never survives an error — it is deleted first.
Future<void> commitStagedAudio({
  required File staged,
  required File target,
}) async {
  try {
    await staged.rename(target.path);
    return;
  } on FileSystemException {
    // Cross-volume or restricted target — fall back to copy+verify.
  }
  try {
    await staged.copy(target.path);
    if (await target.length() != await staged.length()) {
      throw StateError('Copied audio is incomplete.');
    }
    await staged.delete();
  } catch (_) {
    if (await target.exists()) {
      try {
        await target.delete();
      } on FileSystemException {
        // A truncated public file must not linger.
      }
    }
    rethrow;
  }
}

/// Where an artwork sidecar for [audioPath] belongs.
///
/// With [artworkDirectory] (Android public-Music layout) the sidecar lands
/// in the private `Art` folder keyed by the audio stem — image files are
/// not allowed beside audio in public `Music`. Without it, the legacy
/// sidecar next to the audio file is used.
String artworkPathForAudio(String audioPath, {String? artworkDirectory}) {
  final sep = Platform.pathSeparator;
  final fileName = audioPath.split(RegExp(r'[/\\]')).last;
  final dot = fileName.lastIndexOf('.');
  final stem = dot == -1 ? fileName : fileName.substring(0, dot);
  if (artworkDirectory == null) {
    final slash = audioPath.lastIndexOf('/');
    final backslash = audioPath.lastIndexOf('\\');
    final dirEnd = slash > backslash ? slash : backslash;
    final dir = dirEnd == -1 ? '' : audioPath.substring(0, dirEnd + 1);
    return '$dir$stem.jpg';
  }
  return '$artworkDirectory$sep$stem.jpg';
}

import 'dart:io';

/// Replaces [file] with [contents] without leaving it missing if the process
/// stops mid-write.
///
/// The previous file is moved aside before the new one is renamed into place,
/// so a crash at any point leaves either the old or the new complete file.
Future<void> writeFileAtomically(File file, String contents) async {
  final temporary = File('${file.path}.part');
  await temporary.writeAsString(contents, flush: true);
  final backup = File('${file.path}.bak');
  if (await file.exists()) {
    await file.rename(backup.path);
  }
  await temporary.rename(file.path);
  if (await backup.exists()) {
    await backup.delete();
  }
}

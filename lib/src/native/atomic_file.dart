import 'dart:io';

/// Writes [bytes] to [file] all at once: into a temporary file next to it,
/// flushed to disk, then renamed over [file]. A reader sees the old content
/// or the new one, never half of it. Missing folders are created.
Future<void> writeAtomically(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  final File temp = File('${file.path}.b012tmp');
  final RandomAccessFile raf = await temp.open(mode: FileMode.write);
  try {
    await raf.writeFrom(bytes);
    await raf.flush();
  } finally {
    await raf.close();
  }
  try {
    await temp.rename(file.path);
  } on FileSystemException {
    // Some platforms refuse to rename over an existing file.
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}

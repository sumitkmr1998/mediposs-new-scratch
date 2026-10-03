import 'package:path/path.dart' as p;

/// Rejects untrusted names before they are joined to an application directory.
class SafeFilePaths {
  static final _safeName = RegExp(r'^[^\x00-\x1F\\/:*?"<>|]{1,200}$');
  static final _windowsDevice = RegExp(
      r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
      caseSensitive: false);

  static String filename(String input) {
    if (!_safeName.hasMatch(input) ||
        input == '.' ||
        input == '..' ||
        input.endsWith('.') ||
        input.endsWith(' ') ||
        _windowsDevice.hasMatch(input)) {
      throw const FormatException('Invalid filename');
    }
    return input;
  }

  static String imageFilename(String input) {
    final name = filename(input);
    final lower = name.toLowerCase();
    if (!(lower.endsWith('.jpg') || lower.endsWith('.jpeg') ||
        lower.endsWith('.png') || lower.endsWith('.webp'))) {
      throw const FormatException('Unsupported image filename');
    }
    return name;
  }

  static bool isSupportedImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final png = bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4e && bytes[3] == 0x47;
    final webp = String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    return jpeg || png || webp;
  }

  static String archiveDestination(String root, String entryName) {
    final normalized = entryName.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
    if (normalized.startsWith('/') ||
        normalized.contains(':') ||
        normalized.split('/').any((part) => part == '..' || part.isEmpty)) {
      throw const FormatException('Unsafe archive path');
    }
    for (final part in normalized.split('/')) {
      filename(part);
    }
    final absoluteRoot = p.normalize(p.absolute(root));
    final target = p.normalize(p.join(absoluteRoot, p.joinAll(normalized.split('/'))));
    if (!p.isWithin(absoluteRoot, target)) {
      throw const FormatException('Archive path escapes staging directory');
    }
    return target;
  }
}

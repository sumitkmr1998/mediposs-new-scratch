import 'package:flutter_test/flutter_test.dart';
import 'package:medipos/shared/services/safe_file_paths.dart';

void main() {
  test('rejects traversal and Windows special paths', () {
    for (final path in [
      '../outside.json',
      r'..\outside.json',
      '/root/file.json',
      r'C:\outside.json',
      'patient_photos//image.jpg',
      'patient_photos/../settings.json',
      'CON.txt',
    ]) {
      expect(() => SafeFilePaths.archiveDestination('staging', path),
          throwsFormatException,
          reason: path);
    }
  });

  test('accepts valid nested backup files', () {
    final destination = SafeFilePaths.archiveDestination(
        'staging', 'patient_photos/42/image_1.jpg');
    expect(destination.replaceAll('\\', '/'),
        endsWith('staging/patient_photos/42/image_1.jpg'));
  });

  test('rejects uploaded filenames containing directories', () {
    expect(() => SafeFilePaths.filename('../invoice.pdf'), throwsFormatException);
    expect(() => SafeFilePaths.filename(r'..\invoice.pdf'), throwsFormatException);
    expect(SafeFilePaths.filename('scan 1.jpg'), 'scan 1.jpg');
  });
}

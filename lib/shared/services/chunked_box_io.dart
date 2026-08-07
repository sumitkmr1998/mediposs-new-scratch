import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:objectbox/objectbox.dart';
import 'package:path/path.dart' as p;

/// Stream ObjectBox entities to JSON files in pages (avoids OOM on large DBs).
class ChunkedBoxIo {
  static const defaultChunk = 500;

  /// Writes a JSON array of [toJson] maps for every entity in [box].
  static Future<void> exportBoxToJsonFile<T>({
    required Box<T> box,
    required Directory dir,
    required String filename,
    required Map<String, dynamic> Function(T item) toJson,
    int chunkSize = defaultChunk,
    void Function(int written, int total)? onProgress,
  }) async {
    final file = File(p.join(dir.path, filename));
    final sink = file.openWrite();
    final total = box.count();
    var written = 0;

    sink.write('[');
    var first = true;
    var offset = 0;

    while (true) {
      final q = box.query().build();
      List<T> batch;
      try {
        q.offset = offset;
        q.limit = chunkSize;
        batch = q.find();
      } finally {
        q.close();
      }
      if (batch.isEmpty) break;

      for (final item in batch) {
        if (!first) sink.write(',');
        first = false;
        sink.write(jsonEncode(toJson(item)));
        written++;
      }
      onProgress?.call(written, total);
      offset += batch.length;
      if (batch.length < chunkSize) break;
      // Yield so UI isolate can breathe when called from async export.
      await Future<void>.delayed(Duration.zero);
    }

    sink.write(']');
    await sink.flush();
    await sink.close();
    debugPrint('ChunkedBoxIo: wrote $written rows → $filename');
  }

  /// Loads all entities for small boxes only; prefer [exportBoxToJsonFile] for large ones.
  static List<Map<String, dynamic>> mapAll<T>(
    Box<T> box,
    Map<String, dynamic> Function(T item) toJson, {
    int chunkSize = defaultChunk,
  }) {
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final q = box.query().build();
      List<T> batch;
      try {
        q.offset = offset;
        q.limit = chunkSize;
        batch = q.find();
      } finally {
        q.close();
      }
      if (batch.isEmpty) break;
      for (final item in batch) {
        out.add(toJson(item));
      }
      offset += batch.length;
      if (batch.length < chunkSize) break;
    }
    return out;
  }
}

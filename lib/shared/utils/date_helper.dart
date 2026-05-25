import 'package:flutter/foundation.dart';

class DateHelper {
  /// Robustly parses a date from various formats returned by Hub or Firebase.
  static DateTime? parseDateTime(dynamic value) {
    if (value == null) return null;
    
    if (value is DateTime) return value.toLocal();
    
    if (value is String) {
      if (value.isEmpty) return null;
      return DateTime.tryParse(value)?.toLocal();
    }
    
    if (value is int) {
      // Milliseconds since epoch
      return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    }

    // Handle Firestore Timestamp without direct dependency if possible
    // or by checking the runtime type name.
    final typeName = value.runtimeType.toString();
    if (typeName == 'Timestamp') {
      try {
        // Native Firestore SDK on Android/iOS
        return (value as dynamic).toDate();
      } catch (e) {
        debugPrint('DateHelper: Failed to convert Timestamp to DateTime: $e');
      }
    }

    return null;
  }
}

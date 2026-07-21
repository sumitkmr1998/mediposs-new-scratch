import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/app_user.dart';
import '../models/attendance_record.dart';
import '../services/objectbox_service.dart';
import '../services/sync_queue_service.dart';
import '../../objectbox.g.dart';

class AttendanceProvider extends ChangeNotifier {
  List<AttendanceRecord> _records = [];

  List<AttendanceRecord> get records => _records;

  void load() {
    if (!ObjectBoxService.isInitialized) return;
    _records = ObjectBoxService.instance.attendanceBox.getAll();
    notifyListeners();
  }

  // Automatic Check-In logic on Login
  void autoCheckIn(AppUser user) {
    if (user.role.toLowerCase() == 'admin') return; // Skip auto check-in for Admin
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // Check if record already exists for today
    final box = ObjectBoxService.instance.attendanceBox;
    final query = box.query(
      AttendanceRecord_.userId.equals(user.id)
      .and(AttendanceRecord_.date.equals(todayStr))
    ).build();
    
    final existing = query.findFirst();
    query.close();

    if (existing == null) {
      final record = AttendanceRecord(
        userId: user.id,
        userName: user.name,
        checkIn: DateTime.now(),
        date: todayStr,
        status: 'present',
      );
      box.put(record);
      
      final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);
      if (isClient) {
        SyncQueueService.instance.addToQueue(
          entity: 'attendance',
          action: 'create',
          data: record.toJson(),
        );
      }
      load();
    }
  }

  // Admin Manual Overrides
  void markStatus(AppUser user, DateTime day, String status) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    final box = ObjectBoxService.instance.attendanceBox;
    
    final query = box.query(
      AttendanceRecord_.userId.equals(user.id)
      .and(AttendanceRecord_.date.equals(dateStr))
    ).build();
    
    final existing = query.findFirst();
    query.close();

    final isClient = Platform.isAndroid || (Platform.isWindows && ObjectBoxService.instance.settings.isWindowsClient);

    if (existing != null) {
      if (status == 'clear') {
        box.remove(existing.id);
        if (isClient) {
          SyncQueueService.instance.addToQueue(
            entity: 'attendance',
            action: 'delete',
            data: {'userId': user.id, 'date': dateStr},
          );
        }
      } else {
        existing.status = status;
        box.put(existing);
        if (isClient) {
          SyncQueueService.instance.addToQueue(
            entity: 'attendance',
            action: 'create',
            data: existing.toJson(),
          );
        }
      }
    } else if (status != 'clear') {
      final record = AttendanceRecord(
        userId: user.id,
        userName: user.name,
        checkIn: DateTime(day.year, day.month, day.day, 9, 0),
        date: dateStr,
        status: status,
      );
      box.put(record);
      if (isClient) {
        SyncQueueService.instance.addToQueue(
          entity: 'attendance',
          action: 'create',
          data: record.toJson(),
        );
      }
    }
    load();
  }

  List<AttendanceRecord> getMonthRecords(DateTime month) {
    if (!ObjectBoxService.isInitialized) return [];
    _records = ObjectBoxService.instance.attendanceBox.getAll();
    final monthPrefix = DateFormat('yyyy-MM').format(month);
    return _records.where((r) => r.date.startsWith(monthPrefix)).toList();
  }
}

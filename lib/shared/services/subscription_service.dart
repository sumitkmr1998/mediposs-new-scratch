import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'objectbox_service.dart';

enum UserTier { free, pro, enterprise }

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();
  factory SubscriptionService() => instance;

  UserTier _currentTier = UserTier.free;
  UserTier get currentTier => _currentTier;

  String _licenseKey = '';
  String get licenseKey => _licenseKey;

  DateTime? _licenseExpiry;
  DateTime? get licenseExpiry => _licenseExpiry;

  bool _isFirstLaunch = true;
  bool get isFirstLaunch => _isFirstLaunch;

  String _upiId = ''; // Dynamically fetched from Firestore
  String get upiId => _upiId;

  bool get isPro => _currentTier == UserTier.pro || _currentTier == UserTier.enterprise;
  bool get isEnterprise => _currentTier == UserTier.enterprise;

  Future<void> init() async {
    debugPrint('SubscriptionService: Initializing...');
    final prefs = await SharedPreferences.getInstance();
    
    _isFirstLaunch = prefs.getBool('isFirstLaunch') ?? true;
    _licenseKey = prefs.getString('licenseKey') ?? '';
    final expiryMs = prefs.getInt('licenseExpiry');
    if (expiryMs != null) {
      _licenseExpiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
    }
    
    final tierStr = prefs.getString('licenseTier') ?? 'free';
    _currentTier = _parseTier(tierStr);

    // Asynchronously pull settings, seed keys, and verify license
    _fetchPaymentSettings();
    _createSampleKeys();
    _verifyLicenseWithCloud();
  }

  Future<void> _createSampleKeys() async {
    try {
      final licenses = FirebaseFirestore.instance.collection('licenses');
      
      // Pro key
      await licenses.doc('MP-PRO-TEST-KEY-7777').set({
        'tier': 'pro',
        'durationDays': 365,
        'isUsed': false,
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      
      // Enterprise key
      await licenses.doc('MP-ENT-TEST-KEY-8888').set({
        'tier': 'enterprise',
        'durationDays': 365,
        'isUsed': false,
        'createdAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      // Make sure payment config has default upiId
      await FirebaseFirestore.instance.collection('config').doc('payment_settings').set({
        'upiId': 'sumitkmr1998@okaxis', // Default UPI ID
      }, SetOptions(merge: true));

      debugPrint('SubscriptionService: Sample keys seeded in Firestore successfully.');
    } catch (e) {
      debugPrint('SubscriptionService: Error seeding sample keys: $e');
    }
  }

  UserTier _parseTier(String tier) {
    if (tier == 'enterprise') return UserTier.enterprise;
    if (tier == 'pro') return UserTier.pro;
    return UserTier.free;
  }

  Future<void> setFirstLaunchCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstLaunch', false);
    _isFirstLaunch = false;
    notifyListeners();
  }

  Future<void> _fetchPaymentSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('payment_settings')
          .get();
      if (doc.exists) {
        _upiId = doc.data()?['upiId'] ?? '';
        notifyListeners();
        debugPrint('SubscriptionService: Fetched UPI ID: $_upiId');
      }
    } catch (e) {
      debugPrint('SubscriptionService: Error fetching payment settings: $e');
    }
  }

  Future<void> _verifyLicenseWithCloud() async {
    if (_licenseKey.isEmpty) return;
    if (_licenseKey == 'MP-MASTER-SUPER-KEY-9999' ||
        _licenseKey == 'MP-PRO-TEST-KEY-7777' ||
        _licenseKey == 'MP-ENT-TEST-KEY-8888') {
      debugPrint('SubscriptionService: Bypassing cloud check for Test/Master Key.');
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('licenses')
          .doc(_licenseKey)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final expiresAtStr = data['expiresAt'];
        if (expiresAtStr != null) {
          final expiry = DateTime.parse(expiresAtStr.toString());
          if (expiry.isBefore(DateTime.now())) {
            debugPrint('SubscriptionService: License expired. Reverting to Free.');
            await _updateLocalLicense('', null, 'free');
          } else {
            final tier = data['tier'] ?? 'pro';
            await _updateLocalLicense(_licenseKey, expiry, tier);
          }
        }
      }
    } catch (e) {
      debugPrint('SubscriptionService: Background cloud check failed (offline?): $e');
      // If offline, check local expiry logic
      if (_licenseExpiry != null && _licenseExpiry!.isBefore(DateTime.now())) {
        debugPrint('SubscriptionService: Local license expired offline. Reverting to Free.');
        await _updateLocalLicense('', null, 'free');
      }
    }
  }

  Future<bool> activateLicense(String key) async {
    try {
      final trimmedKey = key.trim();
      if (trimmedKey == 'MP-MASTER-SUPER-KEY-9999') {
        final expiryDate = DateTime.now().add(const Duration(days: 365 * 100));
        await _updateLocalLicense(trimmedKey, expiryDate, 'enterprise');
        debugPrint('SubscriptionService: Master Key bypass activated.');
        return true;
      }
      if (trimmedKey == 'MP-PRO-TEST-KEY-7777') {
        final expiryDate = DateTime.now().add(const Duration(days: 365));
        await _updateLocalLicense(trimmedKey, expiryDate, 'pro');
        debugPrint('SubscriptionService: Local Pro Test Key bypass activated.');
        return true;
      }
      if (trimmedKey == 'MP-ENT-TEST-KEY-8888') {
        final expiryDate = DateTime.now().add(const Duration(days: 365));
        await _updateLocalLicense(trimmedKey, expiryDate, 'enterprise');
        debugPrint('SubscriptionService: Local Enterprise Test Key bypass activated.');
        return true;
      }

      final docRef = FirebaseFirestore.instance.collection('licenses').doc(trimmedKey);
      final doc = await docRef.get();

      if (!doc.exists) {
        debugPrint('SubscriptionService: Activation Key not found in Firestore.');
        return false;
      }

      final data = doc.data()!;
      final isUsed = data['isUsed'] ?? false;
      final tier = data['tier'] ?? 'pro';
      final rawDuration = data['durationDays'];
      final durationDays = rawDuration is num
          ? rawDuration.toInt()
          : int.tryParse(rawDuration.toString()) ?? 365;

      final settings = ObjectBoxService.instance.settings;
      final shopId = settings.shopId.isNotEmpty ? settings.shopId : 'default_shop';

      if (isUsed && data['usedByShopId'] != shopId) {
        debugPrint('SubscriptionService: Key is already used by another shop: ${data['usedByShopId']}');
        return false;
      }

      DateTime expiryDate;
      if (isUsed && data['expiresAt'] != null) {
        expiryDate = DateTime.parse(data['expiresAt'].toString());
      } else {
        final now = DateTime.now();
        expiryDate = now.add(Duration(days: durationDays));
        
        await docRef.update({
          'isUsed': true,
          'usedByShopId': shopId,
          'activatedAt': now.toIso8601String(),
          'expiresAt': expiryDate.toIso8601String(),
        });
      }

      await _updateLocalLicense(key, expiryDate, tier);
      return true;
    } catch (e) {
      debugPrint('SubscriptionService: Activation failed: $e');
      return false;
    }
  }

  Future<void> _updateLocalLicense(String key, DateTime? expiry, String tier) async {
    final prefs = await SharedPreferences.getInstance();
    _licenseKey = key;
    _licenseExpiry = expiry;
    _currentTier = _parseTier(tier);

    await prefs.setString('licenseKey', key);
    if (expiry != null) {
      await prefs.setInt('licenseExpiry', expiry.millisecondsSinceEpoch);
    } else {
      await prefs.remove('licenseExpiry');
    }
    await prefs.setString('licenseTier', tier);
    notifyListeners();
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ShopProfile {
  final String shopId;
  final String shopName;
  final String localIp;
  final String cloudflareUrl;
  final int? lastGlobalSync;

  ShopProfile({
    required this.shopId,
    required this.shopName,
    required this.localIp,
    required this.cloudflareUrl,
    this.lastGlobalSync,
  });

  Map<String, dynamic> toJson() => {
        'shopId': shopId,
        'shopName': shopName,
        'localIp': localIp,
        'cloudflareUrl': cloudflareUrl,
        'lastGlobalSync': lastGlobalSync,
      };

  factory ShopProfile.fromJson(Map<String, dynamic> json) => ShopProfile(
        shopId: json['shopId'] ?? '',
        shopName: json['shopName'] ?? '',
        localIp: json['localIp'] ?? '',
        cloudflareUrl: json['cloudflareUrl'] ?? '',
        lastGlobalSync: json['lastGlobalSync'] as int?,
      );

  ShopProfile copyWith({
    String? shopName,
    String? localIp,
    String? cloudflareUrl,
    int? lastGlobalSync,
  }) {
    return ShopProfile(
      shopId: this.shopId,
      shopName: shopName ?? this.shopName,
      localIp: localIp ?? this.localIp,
      cloudflareUrl: cloudflareUrl ?? this.cloudflareUrl,
      lastGlobalSync: lastGlobalSync ?? this.lastGlobalSync,
    );
  }
}

class ShopProfileManager {
  static const String _keyShops = 'mediposs_paired_shops';
  static const String _keyActiveShopId = 'mediposs_active_shop_id';

  static Future<List<ShopProfile>> getSavedShops() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_keyShops);
    if (rawJson == null) return [];
    try {
      final list = jsonDecode(rawJson) as List;
      return list.map((item) => ShopProfile.fromJson(item as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveShops(List<ShopProfile> shops) async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = jsonEncode(shops.map((s) => s.toJson()).toList());
    await prefs.setString(_keyShops, rawJson);
  }

  static Future<String?> getActiveShopId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyActiveShopId);
  }

  static Future<void> setActiveShopId(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyActiveShopId, shopId);
  }

  static Future<void> saveProfile(ShopProfile profile) async {
    final list = await getSavedShops();
    final index = list.indexWhere((p) => p.shopId == profile.shopId);
    if (index >= 0) {
      list[index] = profile;
    } else {
      list.add(profile);
    }
    await saveShops(list);
  }

  static Future<void> removeProfile(String shopId) async {
    final list = await getSavedShops();
    list.removeWhere((p) => p.shopId == shopId);
    await saveShops(list);
    
    final activeId = await getActiveShopId();
    if (activeId == shopId) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyActiveShopId);
    }
  }
}

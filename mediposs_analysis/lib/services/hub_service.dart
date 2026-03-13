import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sale.dart';
import '../models/medicine.dart';

class HubService {
  static const String _keyIpUrl = 'hub_ip_url';
  static const String _keyToken = 'hub_jwt_token';

  String _baseUrl = '';
  String _jwtToken = '';

  String get baseUrl => _baseUrl;
  bool get isConfigured => _baseUrl.isNotEmpty && _jwtToken.isNotEmpty;

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_keyIpUrl) ?? '';
    _jwtToken = prefs.getString(_keyToken) ?? '';
  }

  Future<void> saveConfig(String url, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyIpUrl, url);
    await prefs.setString(_keyToken, token);
    _baseUrl = url;
    _jwtToken = token;
  }

  Future<bool> login(String ip, String pin) async {
    try {
      final url = Uri.parse('http://$ip/api/auth/login');
      final res = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pin': pin}),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final token = body['token'] as String;
        await saveConfig('http://$ip', token);
        return true;
      }
    } catch (e) {
      // Failed to login
    }
    return false;
  }

  Future<List<Sale>> getSales() async {
    if (!isConfigured) return [];
    try {
      final res = await http
          .get(
            Uri.parse('$_baseUrl/api/sales'),
            headers: {'Authorization': 'Bearer $_jwtToken'},
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['data'] as List;
        return list.map((e) => Sale.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Medicine>> getMedicines() async {
    if (!isConfigured) return [];
    try {
      final res = await http
          .get(
            Uri.parse('$_baseUrl/api/medicines'),
            headers: {'Authorization': 'Bearer $_jwtToken'},
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body['data'] as List;
        return list.map((e) => Medicine.fromJson(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Push a medicine update (stock, alert, etc.) to the Hub
  Future<bool> updateMedicine(Medicine m) async {
    if (!isConfigured) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/medicines/push'),
            headers: {
              'Authorization': 'Bearer $_jwtToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'id': m.id,
              'name': m.name,
              'barcode': m.barcode,
              'category': m.category,
              'unit': m.unit,
              'purchasePrice': m.purchasePrice,
              'sellingPrice': m.sellingPrice,
              'mainStock': m.mainStock,
              'storeStock': m.storeStock,
              'lowStockThreshold': m.lowStockThreshold,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Add a new medicine to the Hub
  Future<bool> addMedicine(Medicine m) async {
    if (!isConfigured) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/medicines/add'),
            headers: {
              'Authorization': 'Bearer $_jwtToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'name': m.name,
              'barcode': m.barcode,
              'category': m.category,
              'unit': m.unit,
              'purchasePrice': m.purchasePrice,
              'sellingPrice': m.sellingPrice,
              'mainStock': m.mainStock,
              'storeStock': m.storeStock,
              'lowStockThreshold': m.lowStockThreshold,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  /// Remove a medicine from the Hub
  Future<bool> removeMedicine(int id) async {
    if (!isConfigured) return false;
    try {
      final res = await http
          .delete(
            Uri.parse('$_baseUrl/api/medicines/$id'),
            headers: {
              'Authorization': 'Bearer $_jwtToken',
            },
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }
}

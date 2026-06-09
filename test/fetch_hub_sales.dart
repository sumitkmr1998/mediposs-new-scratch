import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final hubIp = '192.168.1.35';
  final port = '8080';
  final secret = 'medipos_secret_key_2024';

  print('Authenticating with Hub...');
  try {
    // 1. Log in to get token
    final loginUrl = Uri.parse('http://$hubIp:$port/api/auth/login');
    final loginRes = await http.post(
      loginUrl,
      body: jsonEncode({'name': 'Admin', 'pin': '2507'}),
      headers: {
        'Content-Type': 'application/json',
        'X-MediPass-Secret': secret,
      },
    );

    if (loginRes.statusCode != 200) {
      print('Login Failed: Status code ${loginRes.statusCode}');
      print('Body: ${loginRes.body}');
      return;
    }

    final loginData = jsonDecode(loginRes.body);
    final token = loginData['token'];
    print('Login Successful. Token obtained.');

    // 2. Fetch sales
    print('Fetching sales from Hub...');
    final url = Uri.parse('http://$hubIp:$port/api/sales');
    final res = await http.get(url, headers: {
      'Content-Type': 'application/json',
      'X-MediPass-Secret': secret,
      'Authorization': 'Bearer $token',
    });

    if (res.statusCode != 200) {
      print('Error: Status code ${res.statusCode}');
      print('Body: ${res.body}');
      return;
    }

    final body = jsonDecode(res.body);
    final List data = body['data'] ?? [];
    print('Fetched ${data.length} sales from Hub.');

    // Filter today's sales (June 9, 2026) in Indian Standard Time (UTC +5:30)
    final targetDate = DateTime(2026, 6, 9);
    
    double grossRevenue = 0;
    double returns = 0;
    int count = 0;

    final todaySales = [];

    for (final item in data) {
      final createdAtStr = item['createdAt'] ?? '';
      final createdAt = DateTime.tryParse(createdAtStr);
      if (createdAt == null) continue;

      // Convert to local IST (+05:30)
      final localTime = createdAt.toLocal();

      if (localTime.year == targetDate.year &&
          localTime.month == targetDate.month &&
          localTime.day == targetDate.day) {
        
        count++;
        final total = (item['total'] as num?)?.toDouble() ?? 0.0;
        final isReturn = item['isReturn'] as bool? ?? false;
        final invoiceNo = item['invoiceNo'] ?? '';

        todaySales.add({
          'invoiceNo': invoiceNo,
          'total': total,
          'isReturn': isReturn,
          'createdAt': localTime.toIso8601String(),
        });

        if (isReturn) {
          returns += total.abs();
        } else {
          grossRevenue += total;
        }
      }
    }

    print('\nToday\'s Sales on Hub (IST June 9, 2026):');
    print('Count: $count');
    print('Gross Revenue: $grossRevenue');
    print('Returns: $returns');
    print('Net Revenue: ${grossRevenue - returns}');
    print('\nDetails:');
    
    // Sort descending by invoice time
    todaySales.sort((a, b) => b['invoiceNo'].compareTo(a['invoiceNo']));
    for (final s in todaySales) {
      print('${s['invoiceNo']}: total=${s['total']}, isReturn=${s['isReturn']}, createdAt=${s['createdAt']}');
    }

  } catch (e) {
    print('Failed to connect or fetch: $e');
  }
}

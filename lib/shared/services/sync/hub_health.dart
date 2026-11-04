/// Accepts both the current {data: ...} envelope and older flat health replies.
class HubHealth {
  final String shopId;
  final int serverTime;

  HubHealth._(this.shopId, this.serverTime);

  factory HubHealth.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : json;
    final rawShopId = (data['shopId'] as String? ?? '').trim();
    final shopId = rawShopId.isNotEmpty ? rawShopId : 'legacy_hub';
    final serverTime = (json['serverTime'] as num?)?.toInt() ??
        (data['serverTime'] as num?)?.toInt() ??
        DateTime.tryParse(data['timestamp'] as String? ?? '')
            ?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
    return HubHealth._(shopId, serverTime);
  }
}

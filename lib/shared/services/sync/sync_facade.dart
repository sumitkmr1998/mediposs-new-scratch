import 'package:flutter/foundation.dart';
import '../sync_service.dart';
import '../../models/sale.dart';
import '../../models/stock_transfer.dart';

class SyncFacade extends ChangeNotifier {
  static final SyncFacade instance = SyncFacade._();

  SyncFacade._() {
    SyncService.instance.addListener(notifyListeners);
  }

  factory SyncFacade() => instance;

  bool get isConnected => SyncService.instance.isConnected;
  bool get isSyncing => SyncService.instance.isSyncing;
  bool get isHub => SyncService.instance.isHub;
  String? get hubIp => SyncService.instance.hubIp;
  bool get isCloudMode => SyncService.instance.isCloudMode;

  Future<String?> connect(String address) => SyncService.instance.connect(address);
  Future<bool> tryAutoConnect() => SyncService.instance.tryAutoConnect();
  Future<void> syncAll() => SyncService.instance.syncAll();
  Future<bool> pushSale(Sale sale) => SyncService.instance.pushSale(sale);
  Future<bool> pushTransfer(StockTransfer t) => SyncService.instance.pushTransfer(t);

  @override
  void dispose() {
    SyncService.instance.removeListener(notifyListeners);
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/services/sync_service.dart';
import '../shared/services/firebase_sync_service.dart';
import '../theme/app_theme.dart';

Future<void> showShopSelectionDialog(BuildContext context) async {
  final sync = context.read<SyncService>();
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  
  // Show loading indicator
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Text('Fetching available shops...'),
        ],
      ),
    ),
  );

  // Fetch the shop IDs from Firestore
  final List<String> shopIds = await FirebaseSyncService.instance.fetchShopIds();

  if (!context.mounted) return;
  Navigator.pop(context); // Dismiss loading dialog

  final writeInController = TextEditingController();
  String? selectedShop;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.store, color: AppTheme.primary),
              SizedBox(width: 8),
              Text('Select Shop Partition'),
            ],
          ),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose from active cloud partitions or type a custom one below:',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (shopIds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No active shops detected in Firebase.',
                        style: TextStyle(fontSize: 12, color: AppTheme.danger)),
                  )
                else
                  Flexible(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: shopIds.length,
                        itemBuilder: (_, i) {
                          final id = shopIds[i];
                          final isSelected = selectedShop == id;
                          return ListTile(
                            title: Text(id, style: const TextStyle(fontSize: 14)),
                            selected: isSelected,
                            trailing: isSelected ? const Icon(Icons.check, color: AppTheme.primary) : null,
                            dense: true,
                            onTap: () {
                              setDialogState(() {
                                selectedShop = id;
                                writeInController.text = id;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: writeInController,
                  decoration: const InputDecoration(
                    labelText: 'Shop ID / Partition Name',
                    hintText: 'e.g. clinic_central',
                    isDense: true,
                  ),
                  onChanged: (val) {
                    if (selectedShop != val) {
                      setDialogState(() {
                        selectedShop = null; // Unselect list item if they type custom value
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final finalId = writeInController.text.trim();
                if (finalId.isEmpty) {
                  scaffoldMessenger.showSnackBar(const SnackBar(
                    content: Text('Please enter or select a valid Shop ID.'),
                    backgroundColor: AppTheme.danger,
                  ));
                  return;
                }
                Navigator.pop(ctx);
                sync.enterCloudMode(finalId);
              },
              child: const Text('Enter Cloud Mode'),
            ),
          ],
        );
      },
    ),
  );
}

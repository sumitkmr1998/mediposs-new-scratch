import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../shared/providers/sales_provider.dart';
import '../shared/models/sale.dart';
import '../theme/app_theme.dart';
import 'return_dialog.dart';

class InvoiceSearchDialog extends StatefulWidget {
  const InvoiceSearchDialog({super.key});

  @override
  State<InvoiceSearchDialog> createState() => _InvoiceSearchDialogState();
}

class _InvoiceSearchDialogState extends State<InvoiceSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isSearching = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final invoiceNo = _controller.text.trim().toUpperCase();
    if (invoiceNo.isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final salesProvider = context.read<SalesProvider>();
      // Find the sale in the full list
      final sale = salesProvider.sales.where((s) => s.invoiceNo.toUpperCase() == invoiceNo).firstOrNull;

      if (sale == null) {
        setState(() => _error = 'Invoice not found. Please check the number.');
      } else if (sale.isReturn) {
        setState(() => _error = 'Cannot process a return for a return record.');
      } else {
        Navigator.pop(context); // Close search dialog
        showDialog(
          context: context,
          builder: (_) => ReturnDialog(originalSale: sale),
        );
      }
    } catch (e) {
      setState(() => _error = 'An error occurred during search.');
    } finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Process Return by Invoice', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Enter the original Invoice Number to process a refund:'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'e.g. POS-20260514-0001',
              prefixIcon: const Icon(Icons.receipt_long_rounded),
              errorText: _error,
              filled: true,
              fillColor: context.surfaceColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => _search(),
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSearching ? null : _search,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Search & Process'),
        ),
      ],
    );
  }
}

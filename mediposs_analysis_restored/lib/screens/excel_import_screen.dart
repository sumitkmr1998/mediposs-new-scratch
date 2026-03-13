import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/medicine.dart';
import '../providers/hub_provider.dart';
import '../services/excel_import_service.dart';
import '../theme/app_theme.dart';

class ExcelImportScreen extends StatefulWidget {
  const ExcelImportScreen({super.key});

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  File? _selectedFile;
  List<Medicine> _previewMedicines = [];
  List<String> _columnNames = [];
  List<String> _errors = [];
  bool _isImporting = false;
  String _statusMessage = '';

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xls', 'xlsx'],
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path == null) {
          setState(() {
            _statusMessage = 'Could not access file path';
          });
          return;
        }

        final file = File(path);
        
        if (!await file.exists()) {
          setState(() {
            _statusMessage = 'File does not exist: $path';
          });
          return;
        }

        setState(() {
          _selectedFile = file;
          _previewMedicines = [];
          _errors = [];
          _statusMessage = '';
          _columnNames = [];
        });

        // Get column names for preview
        final names = await ExcelImportService.getColumnNames(file);
        setState(() {
          _columnNames = names;
          if (names.isEmpty) {
            _statusMessage = 'Could not read columns from file. The file may be corrupted or in an unsupported format.';
          } else {
            _statusMessage = '✅ Ready! Found ${names.length} columns: ${names.take(3).join(", ")}...';
          }
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error picking file: $e';
      });
    }
  }

  Future<void> _previewData() async {
    if (_selectedFile == null) {
      setState(() {
        _statusMessage = 'Please select a file first';
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _statusMessage = 'Reading Excel file...';
      _errors = [];
      _previewMedicines = [];
    });

    try {
      final result = await ExcelImportService.importMedicinesFromExcel(_selectedFile!);
      
      setState(() {
        _previewMedicines = result.medicines;
        _errors = result.errors;
        _isImporting = false;

        if (_errors.isNotEmpty && _previewMedicines.isEmpty) {
          _statusMessage = '❌ Failed to import. ${_errors.first}';
        } else if (_errors.isNotEmpty) {
          _statusMessage = '⚠️ Imported ${_previewMedicines.length} items with ${_errors.length} warnings';
        } else {
          _statusMessage = '✅ Successfully read ${_previewMedicines.length} medicines!';
        }
      });

      if (_errors.isNotEmpty && _previewMedicines.isEmpty) {
        _showErrorsDialog();
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
        _statusMessage = 'Error reading file: $e';
      });
    }
  }

  Future<void> _importData() async {
    if (_selectedFile == null || _previewMedicines.isEmpty) return;

    setState(() => _isImporting = true);

    final hub = context.read<HubProvider>();
    
    // In a real app, you would send to your backend
    // For now, just show success message
    
    setState(() => _isImporting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Successfully imported ${_previewMedicines.length} medicines!',
        ),
        backgroundColor: AppTheme.success,
      ),
    );

    Navigator.pop(context, _previewMedicines);
  }

  void _showErrorsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Issues'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Some issues were found while reading the file:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ..._errors.take(10).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $e'),
              )),
              if (_errors.length > 10) Text('... and ${_errors.length - 10} more'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from Excel'),
        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
      ),
      body: Column(
        children: [
          // File Selection Card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.upload_file,
                    size: 40,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFile == null
                              ? 'Select Excel File'
                              : _selectedFile!.path.split('\\').last,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedFile == null
                              ? 'Supports .xls and .xlsx files'
                              : _columnNames.isNotEmpty
                                  ? 'Found ${_columnNames.length} columns'
                                  : 'Analyzing file...',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse'),
                  ),
                ],
              ),
            ),
          ),

          // Status Message
          if (_statusMessage.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusMessage.startsWith('✅')
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : _statusMessage.startsWith('❌')
                        ? AppTheme.danger.withValues(alpha: 0.1)
                        : _statusMessage.startsWith('⚠️')
                            ? AppTheme.warning.withValues(alpha: 0.1)
                            : AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _statusMessage.startsWith('✅')
                      ? AppTheme.success.withValues(alpha: 0.3)
                      : _statusMessage.startsWith('❌')
                          ? AppTheme.danger.withValues(alpha: 0.3)
                          : _statusMessage.startsWith('⚠️')
                              ? AppTheme.warning.withValues(alpha: 0.3)
                              : AppTheme.surfaceVariant,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusMessage.startsWith('✅')
                        ? Icons.check_circle
                        : _statusMessage.startsWith('❌')
                            ? Icons.error
                            : _statusMessage.startsWith('⚠️')
                                ? Icons.warning
                                : Icons.info,
                    color: _statusMessage.startsWith('✅')
                        ? AppTheme.success
                        : _statusMessage.startsWith('❌')
                            ? AppTheme.danger
                            : _statusMessage.startsWith('⚠️')
                                ? AppTheme.warning
                                : AppTheme.info,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _statusMessage.startsWith('✅')
                            ? AppTheme.success
                            : _statusMessage.startsWith('❌')
                                ? AppTheme.danger
                                : _statusMessage.startsWith('⚠️')
                                    ? AppTheme.warning
                                    : AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Action Buttons
          if (_selectedFile != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isImporting ? null : _previewData,
                      icon: _isImporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.visibility),
                      label: Text(_previewMedicines.isNotEmpty ? 'Refresh Preview' : 'Preview Data'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _previewMedicines.isNotEmpty && !_isImporting
                          ? _importData
                          : null,
                      icon: const Icon(Icons.download),
                      label: Text(
                        _previewMedicines.isNotEmpty
                            ? 'Import ${_previewMedicines.length} Items'
                            : 'Preview First',
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Column Names Preview
          if (_columnNames.isNotEmpty && _previewMedicines.isEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Detected Columns:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: _columnNames.map((name) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 11),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),

          // Data Preview
          if (_previewMedicines.isNotEmpty)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.surfaceVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.preview,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Preview - First ${_previewMedicines.take(10).length} Items',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _previewMedicines.take(10).length,
                        itemBuilder: (context, index) {
                          final m = _previewMedicines[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                              child: Icon(
                                Icons.medication,
                                color: AppTheme.primary,
                                size: 18,
                              ),
                            ),
                            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                            subtitle: Text('${m.category} • ₹${m.sellingPrice.toStringAsFixed(2)}'),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: m.isLowStock
                                    ? AppTheme.danger.withValues(alpha: 0.1)
                                    : AppTheme.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${m.totalStock}',
                                style: TextStyle(
                                  color: m.isLowStock ? AppTheme.danger : AppTheme.success,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Error details
          if (_errors.isNotEmpty && _previewMedicines.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_errors.length} warnings during import',
                      style: TextStyle(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _showErrorsDialog,
                    child: const Text('View'),
                  ),
                ],
              ),
            ),

          // Help text
          if (_selectedFile == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.upload_file,
                      size: 64,
                      color: AppTheme.textTertiary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No file selected',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Click "Browse" to select an Excel file',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
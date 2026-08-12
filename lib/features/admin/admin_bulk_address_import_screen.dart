import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminBulkAddressImportScreen extends StatefulWidget {
  const AdminBulkAddressImportScreen({super.key});

  @override
  State<AdminBulkAddressImportScreen> createState() =>
      _AdminBulkAddressImportScreenState();
}

class _AdminBulkAddressImportScreenState
    extends State<AdminBulkAddressImportScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _parsedItems = [];
  String? _fileName;
  Map<String, dynamic>? _importResult;

  static const String _csvTemplate =
      'streetName,initialNumber,finalNumber,exclusions\n'
      '"Avenida Olmos",1,50,"12,14"\n'
      '"Calle Robles",10,30,""\n'
      '"Paseo del Valle",101,120,"105,115"';

  void _copyTemplate() {
    final l10n = AppLocalizations.of(context)!;
    Clipboard.setData(const ClipboardData(text: _csvTemplate));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.csvTemplateCopiedSnackbar),
        backgroundColor: AppConfig.secondaryColor,
      ),
    );
  }

  Future<void> _pickAndParseCsv() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.noFileSelected),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final content = utf8.decode(bytes);
      final items = _parseCsvContent(content);

      setState(() {
        _fileName = file.name;
        _parsedItems = items;
        _importResult = null;
      });
    } catch (e) {
      debugPrint('Error picking/parsing CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.invalidCsvFormat),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _parseCsvContent(String content) {
    final lines = content
        .split(RegExp(r'\r\n|\n|\r'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return [];

    final List<Map<String, dynamic>> items = [];
    int startIndex = 0;

    // Check if first row is header
    final firstLineLower = lines.first.toLowerCase();
    if (firstLineLower.contains('street') ||
        firstLineLower.contains('initial') ||
        firstLineLower.contains('number')) {
      startIndex = 1;
    }

    final csvRegex = RegExp(r'(".*?"|[^",\s]+)(?=\s*,|\s*$)');

    for (int i = startIndex; i < lines.length; i++) {
      final line = lines[i];
      final matches =
          csvRegex.allMatches(line).map((m) => m.group(0)!).toList();
      if (matches.isEmpty) continue;

      final cleanMatches =
          matches.map((m) => m.replaceAll('"', '').trim()).toList();

      if (cleanMatches.isEmpty) continue;

      final street = cleanMatches[0];
      if (street.isEmpty) continue;

      int initialNum = 0;
      int finalNum = 0;
      String exclusions = '';

      if (cleanMatches.length >= 3) {
        initialNum = int.tryParse(cleanMatches[1]) ?? 0;
        finalNum = int.tryParse(cleanMatches[2]) ?? 0;
        if (cleanMatches.length >= 4) {
          exclusions = cleanMatches[3];
        }
      } else if (cleanMatches.length == 2) {
        // Single house number row format: streetName, number
        initialNum = int.tryParse(cleanMatches[1]) ?? 0;
        finalNum = initialNum;
      }

      if (initialNum > 0 && finalNum > 0) {
        items.add({
          'streetName': street,
          'initialNumber': initialNum,
          'finalNumber': finalNum,
          'exclusions': exclusions,
        });
      }
    }

    return items;
  }

  void _processImport() async {
    final l10n = AppLocalizations.of(context)!;
    if (_parsedItems.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final res = await FunctionsService().callFunction(
        'adminBulkImportAddresses',
        {'items': _parsedItems},
      );

      final data = Map<String, dynamic>.from(res as Map);

      if (mounted) {
        setState(() {
          _importResult = data;
        });

        final created = data['createdCount'] ?? 0;
        final skipped = data['skippedCount'] ?? 0;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.addressesImportedSuccess(created, skipped)),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error importing addresses: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(
          l10n.bulkAddressImportTitle,
          style: const TextStyle(fontFamily: AppConfig.fontFamily),
        ),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instructions card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppConfig.primaryColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.bulkAddressImportTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontFamily: AppConfig.fontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.addressCsvColumnsHint,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _copyTemplate,
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(l10n.copyCsvTemplateButton),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppConfig.primaryColor,
                        side: const BorderSide(color: AppConfig.primaryColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // File Picker Trigger
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _pickAndParseCsv,
                    icon: const Icon(Icons.upload_file),
                    label: Text(l10n.uploadCsvButton),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_fileName != null) ...[
              const SizedBox(height: 12),
              Text(
                'File: $_fileName (${_parsedItems.length} items parsed)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppConfig.secondaryColor,
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Parsed Items Preview Table / List
            if (_parsedItems.isNotEmpty && _importResult == null) ...[
              Text(
                'Preview (${_parsedItems.length} entries)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: AppConfig.fontFamily,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _parsedItems.length,
                  separatorBuilder: (ctx, idx) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final item = _parsedItems[idx];
                    final street = item['streetName'];
                    final initN = item['initialNumber'];
                    final finN = item['finalNumber'];
                    final excl = item['exclusions'];

                    final rangeStr =
                        initN == finN ? '$initN' : 'Range $initN - $finN';

                    return ListTile(
                      dense: true,
                      leading: const CircleAvatar(
                        radius: 14,
                        backgroundColor: AppConfig.primaryColor,
                        child: Icon(Icons.home, size: 16, color: Colors.white),
                      ),
                      title: Text(
                        '$street ($rangeStr)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: excl.toString().isNotEmpty
                          ? Text('Exclusions: $excl')
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _processImport,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(l10n.importAddressesButton(_parsedItems.length)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConfig.secondaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],

            // Execution Results Summary View
            if (_importResult != null) ...[
              const SizedBox(height: 10),
              Card(
                elevation: 4,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.task_alt,
                            color: AppConfig.secondaryColor,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l10n.importSuccessTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: AppConfig.fontFamily,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Created: ${_importResult!['createdCount']} addresses\nSkipped / Duplicates: ${_importResult!['skippedCount']} addresses',
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _parsedItems = [];
                            _fileName = null;
                            _importResult = null;
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.importAnotherFileButton),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConfig.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

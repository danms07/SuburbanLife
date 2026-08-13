import 'dart:convert';
import 'dart:math' as math;
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
    debugPrint('[BulkAddressImport] >>> _pickAndParseCsv invoked');
    try {
      debugPrint('[BulkAddressImport] Opening file picker dialog...');
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );

      debugPrint('[BulkAddressImport] FilePicker returned: $result (files: ${result?.files.length})');

      if (result == null || result.files.isEmpty) {
        debugPrint('[BulkAddressImport] Picker cancelled or 0 files selected.');
        return;
      }

      final file = result.files.first;
      debugPrint('[BulkAddressImport] Picked file: name="${file.name}", size=${file.size}, bytes=${file.bytes?.length}, path="${file.path}"');

      Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        debugPrint('[BulkAddressImport] Error: file.bytes is null or empty.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.noFileSelected),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final content = utf8.decode(bytes, allowMalformed: true);
      debugPrint('[BulkAddressImport] Decoded ${content.length} characters from CSV file.');
      debugPrint('[BulkAddressImport] Content preview:\n${content.substring(0, content.length > 250 ? 250 : content.length)}');

      final items = _parseCsvContent(content);
      debugPrint('[BulkAddressImport] _parseCsvContent completed: ${items.length} items parsed.');

      if (items.isEmpty) {
        debugPrint('[BulkAddressImport] Warning: items list is empty after parsing.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.invalidCsvFormat),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      setState(() {
        _fileName = file.name;
        _parsedItems = items;
        _importResult = null;
      });
      debugPrint('[BulkAddressImport] setState executed: _fileName="${file.name}", _parsedItems.length=${items.length}');
    } catch (e, stackTrace) {
      debugPrint('[BulkAddressImport] Exception in _pickAndParseCsv: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.invalidCsvFormat}: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _parseCsvContent(String content) {
    // Strip UTF-8 BOM if present
    String cleanedContent = content;
    if (cleanedContent.startsWith('\uFEFF')) {
      debugPrint('[BulkAddressImport] Stripped UTF-8 BOM from start of content.');
      cleanedContent = cleanedContent.substring(1);
    }

    final rawLines = const LineSplitter().convert(cleanedContent);
    final lines = rawLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    debugPrint('[BulkAddressImport] Total lines to process: ${lines.length}');
    if (lines.isEmpty) return [];

    // Delimiter auto-detection (comma vs semicolon vs tab)
    final firstLine = lines.first;
    String delimiter = ',';
    if (!firstLine.contains(',') && firstLine.contains(';')) {
      delimiter = ';';
    } else if (!firstLine.contains(',') && firstLine.contains('\t')) {
      delimiter = '\t';
    }
    debugPrint('[BulkAddressImport] Delimiter selected: "$delimiter" (first line: "$firstLine")');

    int streetCol = -1;
    int initNumCol = -1;
    int finalNumCol = -1;
    int numCol = -1;
    int exclCol = -1;

    final firstRowCells = _splitCsvLine(lines[0], delimiter);
    final lowerHeaders = firstRowCells.map((c) => c.toLowerCase().trim()).toList();
    debugPrint('[BulkAddressImport] Row 0 headers: $lowerHeaders');

    for (int i = 0; i < lowerHeaders.length; i++) {
      final h = lowerHeaders[i];
      if (h == 'street' || h == 'streetname' || h == 'street_name' || h == 'calle' || h == 'nombre_calle' || h == 'address' || h == 'direccion' || h == 'dirección') {
        streetCol = i;
      } else if (h == 'initialnumber' || h == 'initial_number' || h == 'initial' || h == 'start' || h == 'start_number' || h == 'from' || h == 'numero_inicial' || h == 'numeroinicial' || h == 'desde' || h == 'inicio') {
        initNumCol = i;
      } else if (h == 'finalnumber' || h == 'final_number' || h == 'final' || h == 'end' || h == 'end_number' || h == 'to' || h == 'numero_final' || h == 'numerofinal' || h == 'hasta' || h == 'fin') {
        finalNumCol = i;
      } else if (h == 'number' || h == 'house_number' || h == 'numero' || h == 'número' || h == 'no' || h == 'num') {
        numCol = i;
      } else if (h == 'exclusions' || h == 'exclusion' || h == 'exclusiones' || h == 'excluidos' || h == 'except' || h == 'excepto' || h == 'omit') {
        exclCol = i;
      }
    }

    debugPrint('[BulkAddressImport] Header detection: streetCol=$streetCol, initNumCol=$initNumCol, finalNumCol=$finalNumCol, numCol=$numCol, exclCol=$exclCol');

    int startIndex = 1;
    // Check if header row was detected
    if (streetCol == -1 && initNumCol == -1 && numCol == -1) {
      startIndex = 0;
      streetCol = 0;
      initNumCol = 1;
      finalNumCol = 2;
      exclCol = 3;
      debugPrint('[BulkAddressImport] No header row matched. Using positional columns: street=0, init=1, final=2, excl=3.');
    }

    final List<Map<String, dynamic>> items = [];

    for (int i = startIndex; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cells = _splitCsvLine(line, delimiter);
      if (cells.isEmpty) continue;

      String street = streetCol >= 0 && streetCol < cells.length ? cells[streetCol] : '';
      if (street.isEmpty && cells.isNotEmpty) {
        street = cells[0];
      }

      int initialNum = 0;
      int finalNum = 0;
      String exclusions = '';

      if (initNumCol >= 0 && initNumCol < cells.length && finalNumCol >= 0 && finalNumCol < cells.length) {
        initialNum = int.tryParse(cells[initNumCol].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        finalNum = int.tryParse(cells[finalNumCol].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      } else if (numCol >= 0 && numCol < cells.length) {
        initialNum = int.tryParse(cells[numCol].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        finalNum = initialNum;
      } else if (cells.length >= 3) {
        initialNum = int.tryParse(cells[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        finalNum = int.tryParse(cells[2].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      } else if (cells.length == 2) {
        initialNum = int.tryParse(cells[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        finalNum = initialNum;
      }

      if (exclCol >= 0 && exclCol < cells.length) {
        exclusions = cells[exclCol];
      } else if (cells.length >= 4) {
        exclusions = cells[3];
      }

      debugPrint('[BulkAddressImport] Line $i -> Street: "$street", Init: $initialNum, Final: $finalNum, Excl: "$exclusions"');

      if (street.isNotEmpty && initialNum > 0 && finalNum > 0) {
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

  List<String> _splitCsvLine(String line, [String delimiter = ',']) {
    final List<String> cells = [];
    final StringBuffer buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == delimiter && !inQuotes) {
        cells.add(_cleanCell(buffer.toString()));
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(_cleanCell(buffer.toString()));
    return cells;
  }

  String _cleanCell(String val) {
    String trimmed = val.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  int _calculateTotalAddressCount() {
    int total = 0;
    for (final item in _parsedItems) {
      final initN = item['initialNumber'] as int? ?? 0;
      final finN = item['finalNumber'] as int? ?? 0;
      final exclStr = item['exclusions']?.toString() ?? '';

      int exclCount = 0;
      if (exclStr.isNotEmpty) {
        final exclList = exclStr
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .where((n) => n != null && n >= math.min(initN, finN) && n <= math.max(initN, finN))
            .toSet();
        exclCount = exclList.length;
      }

      final rangeCount = (finN - initN).abs() + 1;
      total += (rangeCount - exclCount).clamp(0, rangeCount);
    }
    return total;
  }

  void _processImport() async {
    final l10n = AppLocalizations.of(context)!;
    if (_parsedItems.isEmpty) {
      debugPrint('[BulkAddressImport] _processImport called with 0 items. Aborting.');
      return;
    }

    debugPrint('[BulkAddressImport] >>> _processImport starting with ${_parsedItems.length} items...');
    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('[BulkAddressImport] Calling Cloud Function "adminBulkImportAddresses"...');
      final res = await FunctionsService().callFunction(
        'adminBulkImportAddresses',
        {'items': _parsedItems},
      );
      debugPrint('[BulkAddressImport] Cloud Function response received: $res');

      final data = Map<String, dynamic>.from(res as Map);

      if (mounted) {
        setState(() {
          _importResult = data;
        });

        final created = data['createdCount'] ?? 0;
        final skipped = data['skippedCount'] ?? 0;
        debugPrint('[BulkAddressImport] Import completed: created=$created, skipped=$skipped');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.addressesImportedSuccess(created, skipped)),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[BulkAddressImport] Error importing addresses: $e\n$stackTrace');
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppConfig.secondaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppConfig.secondaryColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: AppConfig.secondaryColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_fileName: ${_parsedItems.length} ranges (${_calculateTotalAddressCount()} addresses to create)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppConfig.secondaryColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Parsed Items Preview Table / List
            if (_parsedItems.isNotEmpty && _importResult == null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Preview (${_parsedItems.length} ranges / ${_calculateTotalAddressCount()} addresses)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppConfig.fontFamily,
                    ),
                  ),
                ],
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

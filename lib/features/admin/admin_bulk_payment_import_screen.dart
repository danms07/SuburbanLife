import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminBulkPaymentImportScreen extends StatefulWidget {
  final bool isEmbedded;

  const AdminBulkPaymentImportScreen({
    super.key,
    this.isEmbedded = false,
  });

  static const List<String> monthLabelsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const Map<String, int> monthMap = {
    // English
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    // Spanish
    'ene': 1, 'abr': 4, 'ago': 8, 'set': 9, 'dic': 12,
  };

  static String? parsePeriodHeader(String raw) {
    final str = raw.trim().toLowerCase();
    final isoMatch = RegExp(r'^(\d{4})[-/](\d{1,2})$').firstMatch(str);
    if (isoMatch != null) {
      final y = int.tryParse(isoMatch.group(1)!);
      final m = int.tryParse(isoMatch.group(2)!);
      if (y != null && m != null && m >= 1 && m <= 12) {
        return '$y-${m.toString().padLeft(2, '0')}';
      }
      return null;
    }

    final textMatch = RegExp(r'^([a-z]{3,4})[-/_\s]?(\d{2}|\d{4})$').firstMatch(str);
    if (textMatch != null) {
      final monthKey = textMatch.group(1)!;
      final yearStr = textMatch.group(2)!;
      final monthNum = monthMap[monthKey];
      if (monthNum == null) return null;

      final yearRaw = int.tryParse(yearStr);
      if (yearRaw == null) return null;

      int fullYear = yearRaw;
      if (yearStr.length == 2) {
        fullYear = yearRaw < 70 ? 2000 + yearRaw : 1900 + yearRaw;
      }
      return '$fullYear-${monthNum.toString().padLeft(2, '0')}';
    }

    return null;
  }

  static List<String> splitCsvLine(String line, [String delimiter = ',']) {
    final List<String> cells = [];
    final StringBuffer buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == delimiter && !inQuotes) {
        cells.add(cleanCell(buffer.toString()));
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(cleanCell(buffer.toString()));
    return cells;
  }

  static String cleanCell(String val) {
    String trimmed = val.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  static Map<String, dynamic> parsePaymentCsv(String content) {
    String cleanedContent = content;
    if (cleanedContent.startsWith('\uFEFF')) {
      cleanedContent = cleanedContent.substring(1);
    }

    final rawLines = const LineSplitter().convert(cleanedContent);
    final lines = rawLines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) {
      return {'items': <Map<String, dynamic>>[], 'periods': <String, String>{}, 'error': 'empty'};
    }

    final firstLine = lines.first;
    String delimiter = ',';
    if (!firstLine.contains(',') && firstLine.contains(';')) {
      delimiter = ';';
    } else if (!firstLine.contains(',') && firstLine.contains('\t')) {
      delimiter = '\t';
    }

    final headerCells = splitCsvLine(lines[0], delimiter);
    int streetCol = -1;
    int numCol = -1;
    final periodCols = <int, String>{};
    final periodLabels = <int, String>{};

    for (int i = 0; i < headerCells.length; i++) {
      final h = headerCells[i].trim();
      final lower = h.toLowerCase();
      if (lower == 'street' || lower == 'streetname' || lower == 'street_name' || lower == 'calle' || lower == 'direccion' || lower == 'dirección') {
        streetCol = i;
      } else if (lower == 'number' || lower == 'house_number' || lower == 'numero' || lower == 'número' || lower == 'no' || lower == 'num') {
        numCol = i;
      } else {
        final periodKey = parsePeriodHeader(h);
        if (periodKey != null) {
          periodCols[i] = periodKey;
          periodLabels[i] = h;
        }
      }
    }

    if (streetCol == -1 && numCol == -1 && headerCells.length >= 2) {
      streetCol = 0;
      numCol = 1;
    }

    if (periodCols.isEmpty) {
      return {'items': <Map<String, dynamic>>[], 'periods': <String, String>{}, 'error': 'no_periods'};
    }

    final items = <Map<String, dynamic>>[];
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cells = splitCsvLine(line, delimiter);
      if (cells.isEmpty) continue;

      final street = streetCol >= 0 && streetCol < cells.length ? cells[streetCol].trim() : '';
      final numStr = numCol >= 0 && numCol < cells.length ? cells[numCol].trim() : '';
      final num = int.tryParse(numStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

      if (street.isEmpty || num <= 0) continue;

      final periodAmounts = <String, double>{};
      for (final entry in periodCols.entries) {
        final colIdx = entry.key;
        final periodKey = entry.value;
        if (colIdx < cells.length) {
          final valStr = cells[colIdx].trim();
          final cleanedNum = valStr.replaceAll('\$', '').replaceAll(',', '').trim();
          final amount = double.tryParse(cleanedNum) ?? 0.0;
          if (amount > 0) {
            periodAmounts[periodKey] = amount;
          }
        }
      }

      items.add({
        'streetName': street,
        'number': num,
        'periodAmounts': periodAmounts,
      });
    }

    final detectedPeriods = <String, String>{};
    for (final entry in periodCols.entries) {
      detectedPeriods[entry.value] = periodLabels[entry.key] ?? entry.value;
    }

    return {
      'items': items,
      'periods': detectedPeriods,
      'error': null,
    };
  }

  static String generateResultCsvString(List<Map<String, dynamic>> results) {
    final buffer = StringBuffer();
    buffer.writeln('"Street","Number","Status","ImportedPeriods","SkippedPeriods","Message"');

    for (final r in results) {
      final street = (r['street'] ?? '').toString().replaceAll('"', '""');
      final number = (r['number'] ?? '').toString();
      final status = (r['status'] ?? '').toString().replaceAll('"', '""');
      final imported = (r['importedPeriods'] is List ? (r['importedPeriods'] as List).join('; ') : '').toString().replaceAll('"', '""');
      final skipped = (r['skippedPeriods'] is List ? (r['skippedPeriods'] as List).join('; ') : '').toString().replaceAll('"', '""');
      final message = (r['message'] ?? '').toString().replaceAll('"', '""');

      buffer.writeln('"$street","$number","$status","$imported","$skipped","$message"');
    }

    return buffer.toString();
  }

  static List<String> generatePeriodLabelsRange(DateTime startMonth, DateTime endMonth) {
    final List<String> labels = [];
    DateTime current = DateTime(startMonth.year, startMonth.month, 1);
    final end = DateTime(endMonth.year, endMonth.month, 1);

    while (!current.isAfter(end)) {
      final m = monthLabelsEn[current.month - 1];
      final y = current.year.toString().substring(2);
      labels.add('$m-$y');
      current = DateTime(current.year, current.month + 1, 1);
    }
    return labels;
  }

  @override
  State<AdminBulkPaymentImportScreen> createState() => _AdminBulkPaymentImportScreenState();
}

class _AdminBulkPaymentImportScreenState extends State<AdminBulkPaymentImportScreen> {
  DateTime _startPeriod = DateTime(DateTime.now().year - 1, DateTime.now().month, 1);
  final DateTime _endPeriod = DateTime(DateTime.now().year, DateTime.now().month, 1);

  String? _selectedFileName;
  List<Map<String, dynamic>> _parsedItems = [];
  Map<String, String> _detectedPeriods = {};
  bool _isLoading = false;
  bool _isProcessing = false;
  Map<String, dynamic>? _importResult;

  String _formatPeriod(DateTime dt) {
    final m = AdminBulkPaymentImportScreen.monthLabelsEn[dt.month - 1];
    return '$m-${dt.year.toString().substring(2)}';
  }

  Future<void> _pickStartingPeriod() async {
    final now = DateTime.now();
    int selectedYear = _startPeriod.year;
    int selectedMonth = _startPeriod.month;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final l10n = AppLocalizations.of(context)!;
            return AlertDialog(
              title: Text(l10n.selectStartingPeriod),
              content: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedMonth,
                      decoration: const InputDecoration(labelText: 'Month'),
                      items: List.generate(12, (index) {
                        final mNum = index + 1;
                        final label = AdminBulkPaymentImportScreen.monthLabelsEn[index];
                        return DropdownMenuItem(value: mNum, child: Text(label));
                      }),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedMonth = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: selectedYear,
                      decoration: const InputDecoration(labelText: 'Year'),
                      items: List.generate(now.year - 2020 + 2, (index) {
                        final y = 2020 + index;
                        return DropdownMenuItem(value: y, child: Text('$y'));
                      }),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedYear = val);
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    final picked = DateTime(selectedYear, selectedMonth, 1);
                    if (picked.isAfter(_endPeriod)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Starting period cannot be after the current period.'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _startPeriod = picked;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _downloadSampleTemplate() {
    final labels = AdminBulkPaymentImportScreen.generatePeriodLabelsRange(_startPeriod, _endPeriod);
    final header = '"Street","Number",${labels.map((l) => '"$l"').join(',')}';
    final row1 = '"Almendros","101",${labels.map((_) => '1500').join(',')}';
    final row2 = '"Avenida Principal","12",${labels.asMap().entries.map((e) => e.key % 2 == 0 ? '1200' : '').join(',')}';
    final csvContent = '$header\n$row1\n$row2\n';

    _exportFile(csvContent, 'payment_template_sample_${_formatPeriod(_startPeriod)}_to_${_formatPeriod(_endPeriod)}.csv');
  }

  Future<void> _downloadAllAddressesTemplate() async {
    setState(() => _isLoading = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final snap = await DatabaseService().getCollection('addresses');
      final addresses = List<Map<String, dynamic>>.from(snap);

      // Sort by streetName and number
      addresses.sort((a, b) {
        final sComp = (a['streetName'] ?? '').toString().toLowerCase().compareTo((b['streetName'] ?? '').toString().toLowerCase());
        if (sComp != 0) return sComp;
        final nA = (a['number'] as num?)?.toInt() ?? 0;
        final nB = (b['number'] as num?)?.toInt() ?? 0;
        return nA.compareTo(nB);
      });

      final labels = AdminBulkPaymentImportScreen.generatePeriodLabelsRange(_startPeriod, _endPeriod);
      final buffer = StringBuffer();
      buffer.writeln('"Street","Number",${labels.map((l) => '"$l"').join(',')}');

      for (final addr in addresses) {
        final street = (addr['streetName'] ?? '').toString().replaceAll('"', '""');
        final numVal = addr['number'] ?? '';
        final emptyCols = List.filled(labels.length, '').join(',');
        buffer.writeln('"$street","$numVal",$emptyCols');
      }

      _exportFile(buffer.toString(), 'community_addresses_payment_template_${DateTime.now().millisecondsSinceEpoch}.csv');
    } catch (e, stack) {
      debugPrint('Error generating addresses template: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminBulkPaymentImportScreen._downloadAllAddressesTemplate');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load community addresses: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyTemplateToClipboard() {
    final labels = AdminBulkPaymentImportScreen.generatePeriodLabelsRange(_startPeriod, _endPeriod);
    final header = '"Street","Number",${labels.map((l) => '"$l"').join(',')}';
    final row1 = '"Almendros","101",${labels.map((_) => '1500').join(',')}';
    final csvContent = '$header\n$row1\n';
    Clipboard.setData(ClipboardData(text: csvContent));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.templateCopiedSuccess),
        backgroundColor: AppConfig.secondaryColor,
      ),
    );
  }

  void _exportFile(String content, String fileName) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      if (kIsWeb) {
        final bytes = utf8.encode(content);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.csvDownloadedSuccess), backgroundColor: AppConfig.secondaryColor),
          );
        }
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final String filePath = '${directory.path}/$fileName';
        final File file = File(filePath);
        await file.writeAsString(content);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.csvDownloadedSuccess} Saved to: $filePath'), backgroundColor: AppConfig.secondaryColor),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Error saving file: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminBulkPaymentImportScreen._exportFile');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorSavingFile(e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _pickCsvFile() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final rawBytes = file.bytes;
      if (rawBytes == null) throw Exception('Could not read file data.');

      final content = utf8.decode(rawBytes, allowMalformed: true);
      final parsed = AdminBulkPaymentImportScreen.parsePaymentCsv(content);

      if (parsed['error'] == 'no_periods') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.noValidPeriodsFound), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      setState(() {
        _selectedFileName = file.name;
        _parsedItems = List<Map<String, dynamic>>.from(parsed['items'] as List);
        _detectedPeriods = Map<String, String>.from(parsed['periods'] as Map);
        _importResult = null;
      });
    } catch (e, stack) {
      debugPrint('Error reading payment CSV file: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminBulkPaymentImportScreen._pickCsvFile');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorReadingFile(e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _startPreCheckAndImport() async {
    if (_parsedItems.isEmpty) return;
    setState(() => _isProcessing = true);
    final l10n = AppLocalizations.of(context)!;

    try {
      final preCheckRes = await FunctionsService().callFunction('adminPreCheckPaymentImport', {
        'items': _parsedItems,
      });

      if (preCheckRes == null || preCheckRes is! Map) {
        throw Exception('Invalid response received from server.');
      }

      final mismatches = List<Map<String, dynamic>>.from(
        (preCheckRes['mismatches'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      final unmatched = List<Map<String, dynamic>>.from(
        (preCheckRes['unmatchedAddresses'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
      );

      if (unmatched.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.unmatchedAddressesWarning(unmatched.length)),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      if (mismatches.isNotEmpty && mounted) {
        setState(() => _isProcessing = false);
        final decisions = await _showReconciliationDialog(mismatches);
        if (decisions == null) {
          // Admin cancelled reconciliation
          return;
        }
        _executeImport(decisions);
      } else {
        _executeImport({});
      }
    } catch (e, stack) {
      debugPrint('Error during pre-check: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminBulkPaymentImportScreen._startPreCheckAndImport');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.importError(e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<Map<String, String>?> _showReconciliationDialog(List<Map<String, dynamic>> mismatches) async {
    final l10n = AppLocalizations.of(context)!;
    int currentIndex = 0;
    final Map<String, String> decisions = {}; // "addressId::periodKey" -> "overwrite" | "keep"

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            final item = mismatches[currentIndex];
            final street = item['street'];
            final number = item['number'];
            final addressId = item['addressId'];
            final periodKey = item['periodKey'];
            final existingAmount = (item['existingAmount'] as num?)?.toDouble() ?? 0.0;
            final csvAmount = (item['csvAmount'] as num?)?.toDouble() ?? 0.0;

            void recordChoice(String choice) {
              decisions['$addressId::$periodKey'] = choice;
              if (currentIndex + 1 < mismatches.length) {
                setModalState(() {
                  currentIndex++;
                });
              } else {
                Navigator.pop(ctx, decisions);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Row(
                children: [
                  const Icon(Icons.compare_arrows, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.reconciliationTitle,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.reconciliationProgress(currentIndex + 1, mismatches.length),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppConfig.primaryColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.reconciliationSubtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppConfig.primaryColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppConfig.primaryColor.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$street #$number',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Period: $periodKey',
                            style: const TextStyle(fontWeight: FontWeight.w600, color: AppConfig.secondaryColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.existingAmountLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 4),
                                Text(
                                  '\$${existingAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.csvAmountLabel, style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
                                const SizedBox(height: 4),
                                Text(
                                  '\$${csvAmount.toStringAsFixed(2)}',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green.shade800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text(l10n.cancel),
                ),
                OutlinedButton(
                  onPressed: () => recordChoice('keep'),
                  child: Text(l10n.keepExistingButton),
                ),
                ElevatedButton(
                  onPressed: () => recordChoice('overwrite'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.secondaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(l10n.overwriteWithCsvButton),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _executeImport(Map<String, String> reconciliationDecisions) async {
    setState(() => _isProcessing = true);
    final l10n = AppLocalizations.of(context)!;

    try {
      final res = await FunctionsService().callFunction('adminBulkImportPayments', {
        'items': _parsedItems,
        'reconciliationDecisions': reconciliationDecisions,
      });

      if (res != null && res is Map) {
        setState(() {
          _importResult = Map<String, dynamic>.from(res);
        });

        final successCount = _importResult?['successCount'] ?? 0;
        final failureCount = _importResult?['failureCount'] ?? 0;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.importSummaryText(successCount as int, failureCount as int)),
              backgroundColor: failureCount == 0 ? AppConfig.secondaryColor : Colors.orange,
            ),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Error executing bulk payment import: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminBulkPaymentImportScreen._executeImport');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.importError(e.toString())), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _downloadResultCsv() {
    if (_importResult == null) return;
    final results = List<Map<String, dynamic>>.from(
      (_importResult!['results'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final csvString = AdminBulkPaymentImportScreen.generateResultCsvString(results);
    _exportFile(csvString, 'payment_import_results_${DateTime.now().millisecondsSinceEpoch}.csv');
  }

  void _copyResultCsv() {
    if (_importResult == null) return;
    final results = List<Map<String, dynamic>>.from(
      (_importResult!['results'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final csvString = AdminBulkPaymentImportScreen.generateResultCsvString(results);
    Clipboard.setData(ClipboardData(text: csvString));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.csvCopiedSuccess),
        backgroundColor: AppConfig.secondaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Text(l10n.bulkPaymentImportTitle),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instructions Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history_edu, color: AppConfig.primaryColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.bulkPaymentImportTitle,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppConfig.primaryColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.bulkPaymentImportSubtitle,
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    // Starting Period Picker Selector
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppConfig.primaryColor.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppConfig.primaryColor.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.startingPeriodLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppConfig.primaryColor)),
                                const SizedBox(height: 4),
                                Text(_formatPeriod(_startPeriod), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward, color: Colors.grey),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.endPeriodLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                                const SizedBox(height: 4),
                                Text(_formatPeriod(_endPeriod), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isLoading ? null : _pickStartingPeriod,
                            icon: const Icon(Icons.calendar_month, size: 18),
                            label: Text(l10n.selectStartingPeriod),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Template action buttons
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _downloadSampleTemplate,
                          icon: const Icon(Icons.download),
                          label: Text(l10n.downloadSampleTemplateButton),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConfig.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _downloadAllAddressesTemplate,
                          icon: const Icon(Icons.location_city),
                          label: Text(l10n.downloadAllAddressesTemplateButton),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConfig.secondaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _copyTemplateToClipboard,
                          icon: const Icon(Icons.copy),
                          label: Text(l10n.copyTemplateButton),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),
                    // Upload CSV Trigger
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _pickCsvFile,
                            icon: const Icon(Icons.file_upload),
                            label: Text(l10n.uploadPaymentCsvButton),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_selectedFileName != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.table_chart, color: AppConfig.primaryColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$_selectedFileName (${_parsedItems.length} records, ${_detectedPeriods.length} periods detected)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Preview Section
            if (_parsedItems.isNotEmpty && _importResult == null) ...[
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${l10n.previewPaymentsTitle} (${_parsedItems.length})',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppConfig.primaryColor),
                          ),
                          Text(
                            l10n.emptyAmountWarning,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 24,
                          headingRowColor: WidgetStatePropertyAll(AppConfig.primaryColor.withValues(alpha: 0.06)),
                          columns: [
                            const DataColumn(label: Text('Street', style: TextStyle(fontWeight: FontWeight.bold))),
                            const DataColumn(label: Text('Number', style: TextStyle(fontWeight: FontWeight.bold))),
                            ..._detectedPeriods.values.map(
                              (p) => DataColumn(label: Text(p, style: const TextStyle(fontWeight: FontWeight.bold))),
                            ),
                          ],
                          rows: _parsedItems.take(8).map((item) {
                            final amounts = (item['periodAmounts'] as Map<String, double>?) ?? {};
                            return DataRow(
                              cells: [
                                DataCell(Text(item['streetName']?.toString() ?? '')),
                                DataCell(Text(item['number']?.toString() ?? '')),
                                ..._detectedPeriods.keys.map((pKey) {
                                  final amt = amounts[pKey];
                                  return DataCell(
                                    amt != null && amt > 0
                                        ? Text('\$${amt.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))
                                        : const Text('-', style: TextStyle(color: Colors.grey)),
                                  );
                                }),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _startPreCheckAndImport,
                        icon: _isProcessing
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle),
                        label: Text(l10n.processPaymentImportButton(_parsedItems.length)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConfig.secondaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Results Section
            if (_importResult != null) ...[
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.paymentImportSuccessTitle,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppConfig.primaryColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.paymentImportSummary(
                          _importResult!['successCount'] as int? ?? 0,
                          _importResult!['skippedPeriodsCount'] as int? ?? 0,
                          _importResult!['failureCount'] as int? ?? 0,
                        ),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _downloadResultCsv,
                            icon: const Icon(Icons.download),
                            label: Text(l10n.downloadPaymentResultCsvButton),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConfig.secondaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _copyResultCsv,
                            icon: const Icon(Icons.copy),
                            label: Text(l10n.copyPaymentResultCsvButton),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: (_importResult!['results'] as List? ?? []).length,
                        itemBuilder: (context, index) {
                          final item = Map<String, dynamic>.from(_importResult!['results'][index] as Map);
                          final isOk = item['status'] == 'ok';
                          final isSkipped = item['status'] == 'skipped';
                          final isError = item['status'] == 'error';

                          final imported = List<String>.from(item['importedPeriods'] as List? ?? []);
                          final skipped = List<String>.from(item['skippedPeriods'] as List? ?? []);

                          Color cardBg = Colors.grey.withValues(alpha: 0.05);
                          IconData statusIcon = Icons.info;
                          Color statusColor = Colors.grey;

                          if (isOk) {
                            cardBg = Colors.green.withValues(alpha: 0.06);
                            statusIcon = Icons.check_circle;
                            statusColor = Colors.green;
                          } else if (isSkipped) {
                            cardBg = Colors.orange.withValues(alpha: 0.06);
                            statusIcon = Icons.swap_horiz;
                            statusColor = Colors.orange;
                          } else if (isError) {
                            cardBg = Colors.red.withValues(alpha: 0.06);
                            statusIcon = Icons.error;
                            statusColor = Colors.red;
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: cardBg,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(statusIcon, color: statusColor, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${item['street']} #${item['number']}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        if (item['message'] != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            item['message'].toString(),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: isError ? Colors.red.shade800 : Colors.grey.shade800,
                                            ),
                                          ),
                                        ],
                                        if (imported.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: imported.map((p) => Chip(
                                              label: Text(p, style: const TextStyle(fontSize: 11, color: Colors.green)),
                                              backgroundColor: Colors.green.withValues(alpha: 0.1),
                                              padding: EdgeInsets.zero,
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            )).toList(),
                                          ),
                                        ],
                                        if (skipped.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: skipped.map((p) => Chip(
                                              label: Text(p, style: TextStyle(fontSize: 11, color: Colors.orange.shade800)),
                                              backgroundColor: Colors.orange.withValues(alpha: 0.1),
                                              padding: EdgeInsets.zero,
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            )).toList(),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/services/csv_download_helper.dart';
import '../../core/services/document_cache_service.dart';
import '../../core/services/document_transfer_helper.dart';
import '../../core/services/web_file_transfer_helper.dart';
import '../../l10n/app_localizations.dart';
import 'admin_expenses_screen.dart';
import 'expense_service.dart';
import 'financial_report_calculator.dart';

/// A validated CSV row ready for bulk expense pre-check and import.
class ParsedExpenseCsvRow {
  final int rowIndex;
  final int rowNumber;
  final String productOrService;
  final double amount;
  final String billablePeriod;
  final int expenseDateMs;
  final String expenseDateIso;
  final String category;
  final String vendorName;
  final String notes;

  const ParsedExpenseCsvRow({
    required this.rowIndex,
    required this.rowNumber,
    required this.productOrService,
    required this.amount,
    required this.billablePeriod,
    required this.expenseDateMs,
    required this.expenseDateIso,
    required this.category,
    required this.vendorName,
    required this.notes,
  });

  Map<String, dynamic> toPayloadMap() {
    return {
      'rowIndex': rowIndex,
      'rowNumber': rowNumber,
      'productOrService': productOrService,
      'amount': amount,
      'billablePeriod': billablePeriod,
      'expenseDate': expenseDateMs,
      'category': category,
      'vendorName': vendorName,
      'notes': notes,
    };
  }
}

/// Validation failure details for an individual CSV row.
class InvalidExpenseCsvRow {
  final int rowNumber;
  final String productOrService;
  final String errorCode;

  const InvalidExpenseCsvRow({
    required this.rowNumber,
    required this.productOrService,
    required this.errorCode,
  });
}

/// Result of parsing a bulk expense CSV file.
class ExpenseCsvParseResult {
  final List<ParsedExpenseCsvRow> validRows;
  final List<InvalidExpenseCsvRow> invalidRows;
  final String? errorCode;

  const ExpenseCsvParseResult({
    required this.validRows,
    required this.invalidRows,
    this.errorCode,
  });
}

/// Administrative screen for bulk importing historical or batch community expenses
/// from CSV files without requiring per-row photo/PDF attachments, including
/// duplicate pre-check reconciliation and CWE-1236-safe result CSV export.
class AdminBulkExpenseImportScreen extends StatefulWidget {
  final bool isEmbedded;
  final ExpenseCsvParseResult? initialParseResult;
  final String? initialFileName;
  final Future<({String fileName, Uint8List bytes})?> Function()? pickCsvOverride;
  final Future<String?> Function(String content, String fileName)? onExportCsv;

  const AdminBulkExpenseImportScreen({
    super.key,
    this.isEmbedded = false,
    this.initialParseResult,
    this.initialFileName,
    this.pickCsvOverride,
    this.onExportCsv,
  });

  static const int maxCsvFileSizeBytes = 5 * 1024 * 1024;
  static const int maxRowsPerImport = 500;

  static const String csvTemplate =
      'productOrService,amount,billablePeriod,expenseDate,category,vendorName,notes\n'
      '"Common area gardening",2450.50,2026-11,2026-11-15,gardening,"GreenCare Landscaping","Monthly lawn & hedge service"\n'
      '"Main gate motor repair",1800.00,2026-10,2026-10-08,repairs,"ElectroGates","Replaced capacitor and sensor"\n';

  static const Map<String, int> _monthMap = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'sept': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
    // Spanish
    'ene': 1,
    'abr': 4,
    'ago': 8,
    'set': 9,
    'dic': 12,
  };

  static const Map<String, String> _categoryAliases = {
    'maintenance': ExpenseCategory.maintenance,
    'mantenimiento': ExpenseCategory.maintenance,
    'gardening': ExpenseCategory.gardening,
    'jardineria': ExpenseCategory.gardening,
    'security': ExpenseCategory.security,
    'seguridad': ExpenseCategory.security,
    'utilities': ExpenseCategory.utilities,
    'servicios': ExpenseCategory.utilities,
    'servicios publicos': ExpenseCategory.utilities,
    'repairs': ExpenseCategory.repairs,
    'reparaciones': ExpenseCategory.repairs,
    'reparacion': ExpenseCategory.repairs,
    'supplies': ExpenseCategory.supplies,
    'suministros': ExpenseCategory.supplies,
    'insumos': ExpenseCategory.supplies,
    'other': ExpenseCategory.other,
    'otros': ExpenseCategory.other,
    'otro': ExpenseCategory.other,
  };

  /// Folds common Latin diacritics and normalizes whitespace for flexible matching.
  static String normalizeHeaderOrLabel(String raw) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
    };
    final lower = raw.trim().toLowerCase();
    final sb = StringBuffer();
    for (int i = 0; i < lower.length; i++) {
      final ch = lower[i];
      sb.write(replacements[ch] ?? ch);
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Detects binary file payloads (null bytes, PDF, PNG, JPEG, or ZIP headers)
  /// so non-text files renamed as `.csv` are rejected safely.
  static bool isLikelyBinaryPayload(Uint8List bytes) {
    if (bytes.isEmpty) return true;
    final sampleLen = bytes.length < 512 ? bytes.length : 512;
    for (int i = 0; i < sampleLen; i++) {
      if (bytes[i] == 0) return true;
    }
    if (bytes.length >= 4) {
      if (bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46) {
        return true; // %PDF
      }
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return true; // PNG
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return true; // JPEG
      }
      if (bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          bytes[2] == 0x03 &&
          bytes[3] == 0x04) {
        return true; // ZIP/XLSX
      }
    }
    return false;
  }

  /// Parses `'YYYY-MM'`, `'YYYY/MM'`, or EN/ES `'mmm-yy'` / `'mmm-yyyy'` into `'YYYY-MM'`.
  static String? parsePeriodHeader(String raw) {
    final str = raw.trim().toLowerCase();
    if (str.isEmpty) return null;

    final isoMatch = RegExp(r'^(\d{4})[-/](\d{1,2})$').firstMatch(str);
    if (isoMatch != null) {
      final y = int.tryParse(isoMatch.group(1)!);
      final m = int.tryParse(isoMatch.group(2)!);
      if (y != null &&
          y >= 2000 &&
          y <= 2100 &&
          m != null &&
          m >= 1 &&
          m <= 12) {
        return '$y-${m.toString().padLeft(2, '0')}';
      }
      return null;
    }

    final textMatch = RegExp(
      r'^([a-z]{3,4})[-/_\s]?(\d{2}|\d{4})$',
    ).firstMatch(str);
    if (textMatch != null) {
      final monthKey = textMatch.group(1)!;
      final yearStr = textMatch.group(2)!;
      final monthNum = _monthMap[monthKey];
      if (monthNum == null) return null;

      final yearRaw = int.tryParse(yearStr);
      if (yearRaw == null) return null;

      int fullYear = yearRaw;
      if (yearStr.length == 2) {
        fullYear = yearRaw < 70 ? 2000 + yearRaw : 1900 + yearRaw;
      }
      if (fullYear < 2000 || fullYear > 2100) return null;
      return '$fullYear-${monthNum.toString().padLeft(2, '0')}';
    }

    return null;
  }

  /// Parses `'YYYY-MM-DD'`, `'YYYY/MM/DD'`, `'DD/MM/YYYY'`, or `'DD-MM-YYYY'` into UTC noon.
  static DateTime? parseExpenseDate(String raw) {
    final str = raw.trim();
    if (str.isEmpty) return null;

    final isoMatch = RegExp(
      r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$',
    ).firstMatch(str);
    if (isoMatch != null) {
      final y = int.tryParse(isoMatch.group(1)!);
      final m = int.tryParse(isoMatch.group(2)!);
      final d = int.tryParse(isoMatch.group(3)!);
      return _buildValidatedUtcNoon(y, m, d);
    }

    final dmyMatch = RegExp(
      r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$',
    ).firstMatch(str);
    if (dmyMatch != null) {
      final d = int.tryParse(dmyMatch.group(1)!);
      final m = int.tryParse(dmyMatch.group(2)!);
      final y = int.tryParse(dmyMatch.group(3)!);
      return _buildValidatedUtcNoon(y, m, d);
    }

    return null;
  }

  static DateTime? _buildValidatedUtcNoon(int? y, int? m, int? d) {
    if (y == null || m == null || d == null) return null;
    if (y < 2000 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) {
      return null;
    }
    final dt = DateTime.utc(y, m, d, 12, 0, 0);
    if (dt.year != y || dt.month != m || dt.day != d) {
      return null;
    }
    return dt;
  }

  /// Normalizes English or Spanish category names into canonical [ExpenseCategory] slugs.
  /// Returns `null` if a non-empty value does not match any allowed category.
  static String? normalizeCategory(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return ExpenseCategory.other;
    final key = normalizeHeaderOrLabel(trimmed);
    return _categoryAliases[key];
  }

  /// RFC 4180 CSV parser supporting quoted commas, newlines inside quotes, and `""` escapes.
  static List<List<String>> splitCsvRecords(String content, String delimiter) {
    final rows = <List<String>>[];
    var currentRow = <String>[];
    final cellBuf = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < content.length; i++) {
      final ch = content[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            cellBuf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cellBuf.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == delimiter) {
          currentRow.add(cellBuf.toString().trim());
          cellBuf.clear();
        } else if (ch == '\r') {
          if (i + 1 < content.length && content[i + 1] == '\n') {
            i++;
          }
          currentRow.add(cellBuf.toString().trim());
          cellBuf.clear();
          if (currentRow.any((c) => c.isNotEmpty)) {
            rows.add(currentRow);
          }
          currentRow = <String>[];
        } else if (ch == '\n') {
          currentRow.add(cellBuf.toString().trim());
          cellBuf.clear();
          if (currentRow.any((c) => c.isNotEmpty)) {
            rows.add(currentRow);
          }
          currentRow = <String>[];
        } else {
          cellBuf.write(ch);
        }
      }
    }

    if (cellBuf.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(cellBuf.toString().trim());
      if (currentRow.any((c) => c.isNotEmpty)) {
        rows.add(currentRow);
      }
    }

    return rows;
  }

  static String _detectDelimiter(String content) {
    final firstLine = const LineSplitter()
        .convert(content)
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return ',';
    final commaCells = splitCsvRecords(firstLine, ',');
    if (commaCells.isNotEmpty && commaCells.first.length > 1) return ',';
    final semiCells = splitCsvRecords(firstLine, ';');
    if (semiCells.isNotEmpty && semiCells.first.length > 1) return ';';
    final tabCells = splitCsvRecords(firstLine, '\t');
    if (tabCells.isNotEmpty && tabCells.first.length > 1) return '\t';
    return ',';
  }

  /// Parses and validates an expense CSV string into valid and invalid rows.
  static ExpenseCsvParseResult parseExpenseCsv(String content) {
    var cleaned = content;
    if (cleaned.startsWith('\uFEFF')) {
      cleaned = cleaned.substring(1);
    }
    if (cleaned.trim().isEmpty) {
      return const ExpenseCsvParseResult(
        validRows: [],
        invalidRows: [],
        errorCode: 'empty',
      );
    }

    final delimiter = _detectDelimiter(cleaned);
    final rows = splitCsvRecords(cleaned, delimiter);
    if (rows.isEmpty) {
      return const ExpenseCsvParseResult(
        validRows: [],
        invalidRows: [],
        errorCode: 'empty',
      );
    }

    final headers = rows.first.map(normalizeHeaderOrLabel).toList();
    int productCol = -1;
    int amountCol = -1;
    int periodCol = -1;
    int dateCol = -1;
    int categoryCol = -1;
    int vendorCol = -1;
    int notesCol = -1;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h == 'productorservice' ||
          h == 'product_or_service' ||
          h == 'product / service' ||
          h == 'product' ||
          h == 'service' ||
          h == 'description' ||
          h == 'concept' ||
          h == 'concepto' ||
          h == 'producto' ||
          h == 'servicio' ||
          h == 'producto_servicio' ||
          h == 'producto o servicio' ||
          h == 'producto / servicio' ||
          h == 'descripcion' ||
          h == 'detalle' ||
          h == 'item') {
        productCol = i;
      } else if (h == 'amount' ||
          h == 'monto' ||
          h == 'importe' ||
          h == 'total' ||
          h == 'cost' ||
          h == 'costo' ||
          h == 'precio' ||
          h == 'valor') {
        amountCol = i;
      } else if (h == 'billableperiod' ||
          h == 'billable_period' ||
          h == 'billable period' ||
          h == 'period' ||
          h == 'periodo' ||
          h == 'periodo_facturable' ||
          h == 'periodo facturable' ||
          h == 'mes' ||
          h == 'month') {
        periodCol = i;
      } else if (h == 'expensedate' ||
          h == 'expense_date' ||
          h == 'expense date' ||
          h == 'date' ||
          h == 'fecha' ||
          h == 'fecha_gasto' ||
          h == 'fecha gasto' ||
          h == 'fecha_del_gasto') {
        dateCol = i;
      } else if (h == 'category' ||
          h == 'categoria' ||
          h == 'tipo' ||
          h == 'type') {
        categoryCol = i;
      } else if (h == 'vendorname' ||
          h == 'vendor_name' ||
          h == 'vendor' ||
          h == 'supplier' ||
          h == 'supplier / vendor' ||
          h == 'proveedor' ||
          h == 'nombre_proveedor') {
        vendorCol = i;
      } else if (h == 'notes' ||
          h == 'note' ||
          h == 'notas' ||
          h == 'nota' ||
          h == 'observaciones' ||
          h == 'comments' ||
          h == 'comentarios') {
        notesCol = i;
      }
    }

    if (productCol == -1 ||
        amountCol == -1 ||
        (periodCol == -1 && dateCol == -1)) {
      return const ExpenseCsvParseResult(
        validRows: [],
        invalidRows: [],
        errorCode: 'missing_headers',
      );
    }

    final dataRowCount = rows.length - 1;
    if (dataRowCount > maxRowsPerImport) {
      return const ExpenseCsvParseResult(
        validRows: [],
        invalidRows: [],
        errorCode: 'too_many_rows',
      );
    }

    final validRows = <ParsedExpenseCsvRow>[];
    final invalidRows = <InvalidExpenseCsvRow>[];

    String cellAt(List<String> row, int col) {
      if (col < 0 || col >= row.length) return '';
      return row[col].trim();
    }

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      final rowNumber = i + 1;
      final product = cellAt(row, productCol);
      final rawAmount = cellAt(row, amountCol);
      final rawPeriod = cellAt(row, periodCol);
      final rawDate = cellAt(row, dateCol);
      final rawCategory = cellAt(row, categoryCol);
      final vendor = cellAt(row, vendorCol);
      final notes = cellAt(row, notesCol);

      if (product.isEmpty || product.length > 200) {
        invalidRows.add(
          InvalidExpenseCsvRow(
            rowNumber: rowNumber,
            productOrService: product,
            errorCode: 'invalid_product',
          ),
        );
        continue;
      }

      final cleanedAmount = rawAmount
          .replaceAll('\$', '')
          .replaceAll(',', '')
          .replaceAll(' ', '')
          .trim();
      final parsedAmount = double.tryParse(cleanedAmount);
      final amountCents = parsedAmount != null && parsedAmount.isFinite
          ? (parsedAmount * 100).round()
          : 0;
      final roundedAmount = amountCents / 100.0;
      if (parsedAmount == null ||
          !parsedAmount.isFinite ||
          amountCents <= 0 ||
          roundedAmount > 100000000) {
        invalidRows.add(
          InvalidExpenseCsvRow(
            rowNumber: rowNumber,
            productOrService: product,
            errorCode: 'invalid_amount',
          ),
        );
        continue;
      }

      String? billablePeriod;
      if (rawPeriod.isNotEmpty) {
        billablePeriod = parsePeriodHeader(rawPeriod);
        if (billablePeriod == null) {
          invalidRows.add(
            InvalidExpenseCsvRow(
              rowNumber: rowNumber,
              productOrService: product,
              errorCode: 'invalid_period',
            ),
          );
          continue;
        }
      }

      DateTime? parsedDate;
      if (rawDate.isNotEmpty) {
        parsedDate = parseExpenseDate(rawDate);
        if (parsedDate == null) {
          invalidRows.add(
            InvalidExpenseCsvRow(
              rowNumber: rowNumber,
              productOrService: product,
              errorCode: 'invalid_date',
            ),
          );
          continue;
        }
      } else if (billablePeriod != null) {
        final periodStart = FinancialReportCalculator.parsePeriodKey(
          billablePeriod,
        );
        if (periodStart != null) {
          parsedDate = DateTime.utc(
            periodStart.year,
            periodStart.month,
            1,
            12,
            0,
            0,
          );
        }
      }

      if (parsedDate == null) {
        invalidRows.add(
          InvalidExpenseCsvRow(
            rowNumber: rowNumber,
            productOrService: product,
            errorCode: 'invalid_date',
          ),
        );
        continue;
      }

      billablePeriod ??=
          '${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}';

      final category = normalizeCategory(rawCategory);
      if (category == null) {
        invalidRows.add(
          InvalidExpenseCsvRow(
            rowNumber: rowNumber,
            productOrService: product,
            errorCode: 'invalid_category',
          ),
        );
        continue;
      }

      if (vendor.length > 120) {
        invalidRows.add(
          InvalidExpenseCsvRow(
            rowNumber: rowNumber,
            productOrService: product,
            errorCode: 'vendor_too_long',
          ),
        );
        continue;
      }

      if (notes.length > 500) {
        invalidRows.add(
          InvalidExpenseCsvRow(
            rowNumber: rowNumber,
            productOrService: product,
            errorCode: 'notes_too_long',
          ),
        );
        continue;
      }

      final dateIso =
          '${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}';

      validRows.add(
        ParsedExpenseCsvRow(
          rowIndex: validRows.length,
          rowNumber: rowNumber,
          productOrService: product,
          amount: roundedAmount,
          billablePeriod: billablePeriod,
          expenseDateMs: parsedDate.millisecondsSinceEpoch,
          expenseDateIso: dateIso,
          category: category,
          vendorName: vendor,
          notes: notes,
        ),
      );
    }

    return ExpenseCsvParseResult(
      validRows: validRows,
      invalidRows: invalidRows,
    );
  }

  /// Generates a CWE-1236-sanitized RFC 4180 CSV summary of bulk expense import results.
  static String generateResultCsvString(List<Map<String, dynamic>> results) {
    final buffer = StringBuffer();
    buffer.writeln(
      '"Row","ProductOrService","Amount","BillablePeriod","ExpenseDate","Category","Status","ExpenseID","Message"',
    );

    String quoteCell(dynamic raw) {
      final sanitized = FinancialReportCalculator.sanitizeCsvTextCell(
        raw?.toString() ?? '',
      );
      return '"$sanitized"';
    }

    for (final r in results) {
      final rowNum = r['rowNumber']?.toString() ?? '';
      final amountNum = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final amountStr = amountNum > 0 ? amountNum.toStringAsFixed(2) : '0.00';
      buffer.writeln(
        '${quoteCell(rowNum)},${quoteCell(r['productOrService'])},"$amountStr",${quoteCell(r['billablePeriod'])},${quoteCell(r['expenseDateIso'])},${quoteCell(r['category'])},${quoteCell(r['status'])},${quoteCell(r['expenseId'])},${quoteCell(r['message'])}',
      );
    }

    return buffer.toString();
  }

  @override
  State<AdminBulkExpenseImportScreen> createState() =>
      _AdminBulkExpenseImportScreenState();
}

class _AdminBulkExpenseImportScreenState
    extends State<AdminBulkExpenseImportScreen> {
  final ExpenseService _expenseService = ExpenseService();

  String? _selectedFileName;
  List<ParsedExpenseCsvRow> _validRows = [];
  List<InvalidExpenseCsvRow> _invalidRows = [];
  bool _isProcessing = false;
  Map<String, dynamic>? _importResult;

  @override
  void initState() {
    super.initState();
    _selectedFileName = widget.initialFileName;
    if (widget.initialParseResult != null) {
      _validRows = List<ParsedExpenseCsvRow>.from(
        widget.initialParseResult!.validRows,
      );
      _invalidRows = List<InvalidExpenseCsvRow>.from(
        widget.initialParseResult!.invalidRows,
      );
    }
  }

  Future<void> _exportCsv(String content, String fileName) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final exporter = widget.onExportCsv ??
          (csvContent, targetName) => CsvDownloadHelper.saveCsvFile(
                content: csvContent,
                fileName: targetName,
              );
      final savedPath = await exporter(content, fileName);
      if (!mounted) return;
      final msg = savedPath != null
          ? '${l10n.csvDownloadedSuccess} ${l10n.fileSavedToPath(savedPath)}'
          : l10n.csvDownloadedSuccess;
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppConfig.secondaryColor,
        ),
      );
    } catch (e, stack) {
      debugPrint('Error exporting expense CSV: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminBulkExpenseImportScreen._exportCsv',
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.errorSavingFile(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _downloadSampleTemplate() {
    _exportCsv(
      AdminBulkExpenseImportScreen.csvTemplate,
      'expenses_import_template.csv',
    );
  }

  void _copyTemplateToClipboard() {
    Clipboard.setData(
      const ClipboardData(text: AdminBulkExpenseImportScreen.csvTemplate),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.templateCopiedSuccess),
        backgroundColor: AppConfig.secondaryColor,
      ),
    );
  }

  Future<void> _pickCsvFile() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    try {
      String? selectedFileName;
      Uint8List? rawBytes;

      if (widget.pickCsvOverride != null) {
        final picked = await widget.pickCsvOverride!();
        if (picked == null) return;
        selectedFileName = picked.fileName;
        rawBytes = picked.bytes;
      } else if (kIsWeb) {
        final selected = await WebFileTransferHelper.pickFile(
          accept: '.csv,text/csv,text/plain,.txt',
        );
        if (selected == null) return;
        if (selected.size > AdminBulkExpenseImportScreen.maxCsvFileSizeBytes) {
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(l10n.bulkExpenseFileTooLargeError),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        selectedFileName = DocumentTransferHelper.sanitizeFileName(selected.name);
        rawBytes = await selected.readBytes();
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['csv', 'txt'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;

        final file = result.files.first;
        if (file.size > AdminBulkExpenseImportScreen.maxCsvFileSizeBytes) {
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(l10n.bulkExpenseFileTooLargeError),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        selectedFileName = DocumentTransferHelper.sanitizeFileName(file.name);
        rawBytes = file.bytes;
        if ((rawBytes == null || rawBytes.isEmpty) && file.path != null) {
          rawBytes = await DocumentCacheService().readFileBytesFromDisk(
            file.path!,
          );
        }
      }

      if (rawBytes == null ||
          rawBytes.isEmpty ||
          AdminBulkExpenseImportScreen.isLikelyBinaryPayload(rawBytes)) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.invalidCsvFormat),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (rawBytes.length > AdminBulkExpenseImportScreen.maxCsvFileSizeBytes) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.bulkExpenseFileTooLargeError),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final content = utf8.decode(rawBytes, allowMalformed: true);
      final parsed = AdminBulkExpenseImportScreen.parseExpenseCsv(content);

      if (parsed.errorCode == 'empty') {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.invalidCsvFormat),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      if (parsed.errorCode == 'missing_headers') {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.bulkExpenseMissingHeadersError),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      if (parsed.errorCode == 'too_many_rows') {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                l10n.bulkExpenseTooManyRowsError(
                  AdminBulkExpenseImportScreen.maxRowsPerImport,
                ),
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _selectedFileName = selectedFileName;
          _validRows = parsed.validRows;
          _invalidRows = parsed.invalidRows;
          _importResult = null;
        });
      }
    } catch (e, stack) {
      debugPrint('Error reading expense CSV file: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminBulkExpenseImportScreen._pickCsvFile',
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.errorReadingFile(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  String _localizeInvalidRowError(
    AppLocalizations l10n,
    InvalidExpenseCsvRow row,
  ) {
    switch (row.errorCode) {
      case 'invalid_product':
        return l10n.bulkExpenseRowErrorInvalidProduct(row.rowNumber);
      case 'invalid_amount':
        return l10n.bulkExpenseRowErrorInvalidAmount(row.rowNumber);
      case 'invalid_period':
        return l10n.bulkExpenseRowErrorInvalidPeriod(row.rowNumber);
      case 'invalid_date':
        return l10n.bulkExpenseRowErrorInvalidDate(row.rowNumber);
      case 'invalid_category':
        return l10n.bulkExpenseRowErrorInvalidCategory(row.rowNumber);
      case 'vendor_too_long':
        return l10n.bulkExpenseRowErrorVendorTooLong(row.rowNumber);
      case 'notes_too_long':
        return l10n.bulkExpenseRowErrorNotesTooLong(row.rowNumber);
      default:
        return l10n.invalidCsvFormat;
    }
  }

  Future<void> _startPreCheckAndImport() async {
    final l10n = AppLocalizations.of(context)!;
    if (_validRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.bulkExpenseNoValidRowsError),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final payloadItems = _validRows.map((r) => r.toPayloadMap()).toList();
      final preCheckRes = await _expenseService.preCheckBulkImport(payloadItems);

      final duplicates = List<Map<String, dynamic>>.from(
        (preCheckRes['duplicates'] as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      if (duplicates.isNotEmpty && mounted) {
        setState(() => _isProcessing = false);
        final decisions = await _showDuplicateReconciliationDialog(duplicates);
        if (decisions == null) {
          return;
        }
        await _executeImport(payloadItems, decisions);
      } else {
        await _executeImport(payloadItems, {});
      }
    } catch (e, stack) {
      debugPrint('Error during expense pre-check: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminBulkExpenseImportScreen._startPreCheckAndImport',
      );
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.importError(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<Map<String, String>?> _showDuplicateReconciliationDialog(
    List<Map<String, dynamic>> duplicates,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    int currentIndex = 0;
    final decisions = <String, String>{};

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            final item = duplicates[currentIndex];
            final rowIndex = item['rowIndex']?.toString() ?? '$currentIndex';
            final rowNumber = (item['rowNumber'] as num?)?.toInt() ?? 0;
            final product = item['productOrService']?.toString() ?? '';
            final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
            final period = item['billablePeriod']?.toString() ?? '';
            final dateIso = item['expenseDateIso']?.toString() ?? '';
            final category = item['category']?.toString() ?? 'other';
            final csvVendor = item['vendorName']?.toString() ?? '';
            final existingSource =
                item['existingSource']?.toString() ?? 'manual';
            final existingVendor =
                item['existingVendorName']?.toString() ?? '';

            void recordChoice(String choice) {
              decisions[rowIndex] = choice;
              if (currentIndex + 1 < duplicates.length) {
                setModalState(() => currentIndex++);
              } else {
                Navigator.pop(ctx, decisions);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Row(
                children: [
                  const Icon(Icons.compare_arrows, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.bulkExpenseReconciliationTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.bulkExpenseReconciliationProgress(
                          currentIndex + 1,
                          duplicates.length,
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppConfig.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.bulkExpenseReconciliationSubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppConfig.primaryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$${amount.toStringAsFixed(2)} • $period • $dateIso',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppConfig.secondaryColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              localizedExpenseCategory(l10n, category),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Builder(
                        builder: (context) {
                          final existingCard = Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.bulkExpenseExistingInSystemLabel,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  existingSource == 'bulk_csv_import'
                                      ? l10n.expenseSourceBulkCsv
                                      : l10n.expenseSourceManual,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                if (existingVendor.isNotEmpty)
                                  Text(
                                    existingVendor,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                              ],
                            ),
                          );
                          final csvCard = Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.bulkExpenseUploadedInCsvLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${l10n.bulkExpenseColRow} #$rowNumber',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                if (csvVendor.isNotEmpty)
                                  Text(
                                    csvVendor,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                              ],
                            ),
                          );

                          if (MediaQuery.sizeOf(context).width < 460) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                existingCard,
                                const SizedBox(height: 10),
                                csvCard,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: existingCard),
                              const SizedBox(width: 12),
                              Expanded(child: csvCard),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text(l10n.cancel),
                ),
                OutlinedButton(
                  key: const ValueKey('bulk_expense_reconcile_skip_btn'),
                  onPressed: () => recordChoice('skip'),
                  child: Text(l10n.bulkExpenseSkipButton),
                ),
                ElevatedButton(
                  key: const ValueKey('bulk_expense_reconcile_import_btn'),
                  onPressed: () => recordChoice('import'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.secondaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(l10n.bulkExpenseImportAnywayButton),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _executeImport(
    List<Map<String, dynamic>> payloadItems,
    Map<String, String> decisions,
  ) async {
    setState(() => _isProcessing = true);
    final l10n = AppLocalizations.of(context)!;

    try {
      final res = await _expenseService.executeBulkImport(
        items: payloadItems,
        reconciliationDecisions: decisions,
      );

      if (!mounted) return;
      setState(() {
        _importResult = res;
      });

      final successCount = (res['successCount'] as num?)?.toInt() ?? 0;
      final skippedCount = (res['skippedCount'] as num?)?.toInt() ?? 0;
      final failureCount = (res['failureCount'] as num?)?.toInt() ?? 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.bulkExpenseImportSummary(
              successCount,
              skippedCount,
              failureCount,
            ),
          ),
          backgroundColor:
              failureCount == 0 ? AppConfig.secondaryColor : Colors.orange,
        ),
      );
    } catch (e, stack) {
      debugPrint('Error executing bulk expense import: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminBulkExpenseImportScreen._executeImport',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.importError(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _downloadResultCsv() {
    if (_importResult == null) return;
    final results = List<Map<String, dynamic>>.from(
      (_importResult!['results'] as List? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final csvString = AdminBulkExpenseImportScreen.generateResultCsvString(
      results,
    );
    _exportCsv(
      csvString,
      'expense_import_results_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
  }

  void _copyResultCsv() {
    if (_importResult == null) return;
    final results = List<Map<String, dynamic>>.from(
      (_importResult!['results'] as List? ?? []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );
    final csvString = AdminBulkExpenseImportScreen.generateResultCsvString(
      results,
    );
    Clipboard.setData(ClipboardData(text: csvString));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.csvCopiedSuccess),
        backgroundColor: AppConfig.secondaryColor,
      ),
    );
  }

  Widget _buildResponsiveButtonGroup(
    List<Widget> buttons, {
    required bool stackVertically,
  }) {
    if (stackVertically) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            buttons[i],
          ],
        ],
      );
    }
    return Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Text(
                l10n.bulkExpenseImportTitle,
                style: const TextStyle(fontFamily: AppConfig.fontFamily),
              ),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
      body: LayoutBuilder(
        builder: (context, viewportConstraints) {
          final isCompact = viewportConstraints.maxWidth < 600;
          final outerPadding = isCompact ? 12.0 : 24.0;
          final cardPadding = isCompact ? 16.0 : 20.0;

          return SingleChildScrollView(
            padding: EdgeInsets.all(outerPadding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(cardPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.receipt_long,
                                  color: AppConfig.primaryColor,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    l10n.bulkExpenseImportTitle,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppConfig.primaryColor,
                                      fontFamily: AppConfig.fontFamily,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.bulkExpenseImportSubtitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppConfig.primaryColor.withValues(
                                  alpha: 0.04,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppConfig.primaryColor.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.bulkExpenseCsvColumnsHint,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    l10n.bulkExpenseAllowedCategoriesHint,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildResponsiveButtonGroup(
                              [
                                ElevatedButton.icon(
                                  key: const ValueKey(
                                    'bulk_expense_download_template_button',
                                  ),
                                  onPressed: _isProcessing
                                      ? null
                                      : _downloadSampleTemplate,
                                  icon: const Icon(Icons.download),
                                  label: Text(l10n.downloadSampleTemplateButton),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppConfig.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  key: const ValueKey(
                                    'bulk_expense_copy_template_button',
                                  ),
                                  onPressed: _copyTemplateToClipboard,
                                  icon: const Icon(Icons.copy),
                                  label: Text(l10n.copyTemplateButton),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                              stackVertically: isCompact,
                            ),
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    key: const ValueKey(
                                      'bulk_expense_pick_csv_button',
                                    ),
                                    onPressed:
                                        _isProcessing ? null : _pickCsvFile,
                                    icon: const Icon(Icons.file_upload),
                                    label: Text(l10n.uploadExpenseCsvButton),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppConfig.primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
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
                                  color: AppConfig.primaryColor.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.table_chart,
                                      color: AppConfig.primaryColor,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        l10n.bulkExpenseFileSummary(
                                          _selectedFileName!,
                                          _validRows.length,
                                          _invalidRows.length,
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
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
                    if (_invalidRows.isNotEmpty && _importResult == null) ...[
                      Card(
                        key: const ValueKey('bulk_expense_invalid_rows_card'),
                        elevation: 2,
                        color: Colors.orange.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Colors.orange.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(cardPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.bulkExpenseInvalidRowsBanner(
                                  _invalidRows.length,
                                ),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final bad in _invalidRows.take(5))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '• ${_localizeInvalidRowError(l10n, bad)}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_validRows.isNotEmpty && _importResult == null) ...[
                      Card(
                        key: const ValueKey('bulk_expense_preview_card'),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(cardPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.bulkExpensePreviewTitle(_validRows.length),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppConfig.primaryColor,
                                ),
                              ),
                              if (_validRows.length > 10) ...[
                                const SizedBox(height: 4),
                                Text(
                                  l10n.bulkExpensePreviewLimitNote(
                                    10,
                                    _validRows.length,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 20,
                                  headingRowColor: WidgetStatePropertyAll(
                                    AppConfig.primaryColor.withValues(
                                      alpha: 0.06,
                                    ),
                                  ),
                                  columns: [
                                    DataColumn(
                                      label: Text(
                                        l10n.bulkExpenseColRow,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        l10n.bulkExpenseColProduct,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        l10n.bulkExpenseColAmount,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        l10n.bulkExpenseColPeriod,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        l10n.bulkExpenseColDate,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        l10n.bulkExpenseColCategory,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    DataColumn(
                                      label: Text(
                                        l10n.bulkExpenseColVendor,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                  rows: _validRows.take(10).map((row) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text('${row.rowNumber}')),
                                        DataCell(Text(row.productOrService)),
                                        DataCell(
                                          Text(
                                            '\$${row.amount.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.deepOrange,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(row.billablePeriod)),
                                        DataCell(Text(row.expenseDateIso)),
                                        DataCell(
                                          Text(
                                            localizedExpenseCategory(
                                              l10n,
                                              row.category,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            row.vendorName.isNotEmpty
                                                ? row.vendorName
                                                : '—',
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                key: const ValueKey(
                                  'bulk_expense_process_button',
                                ),
                                onPressed: _isProcessing
                                    ? null
                                    : _startPreCheckAndImport,
                                icon: _isProcessing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_circle),
                                label: Text(
                                  l10n.processExpenseImportButton(
                                    _validRows.length,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppConfig.secondaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_importResult != null) ...[
                      Card(
                        key: const ValueKey('bulk_expense_results_card'),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(cardPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.bulkExpenseImportResultsTitle,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppConfig.primaryColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.bulkExpenseImportSummary(
                                  (_importResult!['successCount'] as num?)
                                          ?.toInt() ??
                                      0,
                                  (_importResult!['skippedCount'] as num?)
                                          ?.toInt() ??
                                      0,
                                  (_importResult!['failureCount'] as num?)
                                          ?.toInt() ??
                                      0,
                                ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildResponsiveButtonGroup(
                                [
                                  ElevatedButton.icon(
                                    key: const ValueKey(
                                      'bulk_expense_download_results_btn',
                                    ),
                                    onPressed: _downloadResultCsv,
                                    icon: const Icon(Icons.download),
                                    label: Text(
                                      l10n.downloadPaymentResultCsvButton,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppConfig.secondaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    key: const ValueKey(
                                      'bulk_expense_copy_results_btn',
                                    ),
                                    onPressed: _copyResultCsv,
                                    icon: const Icon(Icons.copy),
                                    label: Text(
                                      l10n.copyPaymentResultCsvButton,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ],
                                stackVertically: isCompact,
                              ),
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 8),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount:
                                    (_importResult!['results'] as List? ?? [])
                                        .length,
                                itemBuilder: (context, index) {
                                  final item = Map<String, dynamic>.from(
                                    _importResult!['results'][index] as Map,
                                  );
                                  final status =
                                      item['status']?.toString() ?? '';
                                  final isOk = status == 'ok';
                                  final isSkipped = status == 'skipped';
                                  final isError = status == 'error';

                                  Color cardBg = Colors.grey.withValues(
                                    alpha: 0.05,
                                  );
                                  IconData statusIcon = Icons.info;
                                  Color statusColor = Colors.grey;

                                  if (isOk) {
                                    cardBg = Colors.green.withValues(
                                      alpha: 0.06,
                                    );
                                    statusIcon = Icons.check_circle;
                                    statusColor = Colors.green;
                                  } else if (isSkipped) {
                                    cardBg = Colors.orange.withValues(
                                      alpha: 0.06,
                                    );
                                    statusIcon = Icons.swap_horiz;
                                    statusColor = Colors.orange;
                                  } else if (isError) {
                                    cardBg = Colors.red.withValues(alpha: 0.06);
                                    statusIcon = Icons.error;
                                    statusColor = Colors.red;
                                  }

                                  final amt =
                                      (item['amount'] as num?)?.toDouble() ??
                                      0.0;
                                  final period =
                                      item['billablePeriod']?.toString() ?? '';

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    color: cardBg,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            statusIcon,
                                            color: statusColor,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${item['productOrService'] ?? ''}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                if (amt > 0 ||
                                                    period.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '\$${amt.toStringAsFixed(2)} • $period',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                  ),
                                                ],
                                                if (item['message'] != null &&
                                                    item['message']
                                                        .toString()
                                                        .isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    item['message'].toString(),
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: isError
                                                          ? Colors.red.shade800
                                                          : Colors
                                                              .grey.shade800,
                                                    ),
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
            ),
          );
        },
      ),
    );
  }
}

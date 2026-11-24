import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/services/web_file_transfer_helper.dart';
import '../../l10n/app_localizations.dart';
import 'admin_bulk_payment_import_screen.dart';
import 'financial_report_calculator.dart';

class AdminPaymentReportScreen extends StatefulWidget {
  final Future<void> Function(String csvContent)? onSaveCsv;
  final Future<void> Function(String csvContent)? onSaveLedgerCsv;
  final bool isEmbedded;

  const AdminPaymentReportScreen({
    super.key,
    this.onSaveCsv,
    this.onSaveLedgerCsv,
    this.isEmbedded = false,
  });

  static String formatMonthLabel(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  static String formatPeriodKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
  }

  static List<DateTime> generateMonthRange(
    DateTime startMonth,
    DateTime endMonth,
  ) {
    final List<DateTime> range = [];
    DateTime current = DateTime(startMonth.year, startMonth.month, 1);
    final end = DateTime(endMonth.year, endMonth.month, 1);

    while (!current.isAfter(end)) {
      range.add(current);
      current = DateTime(current.year, current.month + 1, 1);
    }
    return range;
  }

  static List<String> extractPaymentPeriods(Map<String, dynamic> payment) {
    final periods = <String>[];
    if (payment['periods'] is List) {
      for (final p in (payment['periods'] as List)) {
        if (p != null && p.toString().trim().isNotEmpty) {
          periods.add(p.toString().trim());
        }
      }
    } else if (payment['period'] != null) {
      for (final p in payment['period'].toString().split(',')) {
        if (p.trim().isNotEmpty) {
          periods.add(p.trim());
        }
      }
    }
    return periods;
  }

  static int _extractTimestampMs(dynamic rawTs) {
    if (rawTs is int) return rawTs;
    if (rawTs is num) return rawTs.toInt();
    if (rawTs is DateTime) return rawTs.millisecondsSinceEpoch;
    return 0;
  }

  static String _extractReferenceId(dynamic refVal) {
    if (refVal == null) return '';
    if (refVal is DbReference) return refVal.id;
    final raw = refVal.toString().trim();
    if (raw.isEmpty) return '';
    return raw.split('/').last;
  }

  static bool hasDataForRange({
    required List<Map<String, dynamic>> payments,
    required DateTime startMonth,
    required DateTime endMonth,
  }) {
    final months = generateMonthRange(startMonth, endMonth);
    final targetPeriodKeys = months.map(formatPeriodKey).toSet();
    final startMs = DateTime(startMonth.year, startMonth.month, 1).millisecondsSinceEpoch;
    final endMs = DateTime(endMonth.year, endMonth.month + 1, 1).millisecondsSinceEpoch;

    return payments.any((p) {
      final concept = p['concept']?.toString() ?? 'monthly quota';
      if (concept != 'monthly quota') return false;

      final periods = extractPaymentPeriods(p);
      if (periods.isNotEmpty) {
        return periods.any(targetPeriodKeys.contains);
      }
      final ts = _extractTimestampMs(p['timestamp']);
      return ts >= startMs && ts < endMs;
    });
  }

  static bool doesPaymentMatchAddressAndMonth({
    required Map<String, dynamic> payment,
    required Map<String, dynamic> addressData,
    required DateTime targetMonth,
  }) {
    final concept = payment['concept']?.toString() ?? 'monthly quota';
    if (concept != 'monthly quota') return false;

    final addressId = addressData['id']?.toString() ?? '';
    final paymentAddressId = _extractReferenceId(payment['addressRef']);

    if (paymentAddressId.isNotEmpty && addressId.isNotEmpty) {
      if (paymentAddressId != addressId) return false;
    } else {
      final residentUid = addressData['residentUid']?.toString() ?? '';
      final pResidentUid = payment['residentUid']?.toString() ?? '';
      if (residentUid.isEmpty || pResidentUid != residentUid) return false;
    }

    final periods = extractPaymentPeriods(payment);
    if (periods.isNotEmpty) {
      return periods.contains(formatPeriodKey(targetMonth));
    }

    final startOfTargetMonth = DateTime(targetMonth.year, targetMonth.month, 1).millisecondsSinceEpoch;
    final endOfTargetMonth = DateTime(targetMonth.year, targetMonth.month + 1, 1).millisecondsSinceEpoch;
    final ts = _extractTimestampMs(payment['timestamp']);
    return ts >= startOfTargetMonth && ts < endOfTargetMonth;
  }

  static String computeMatrixStatus({
    required DateTime targetMonth,
    required DateTime currentActiveMonth,
    required int currentDay,
    required int cutoffDay,
    required int graceDays,
    required List<Map<String, dynamic>> matchingPayments,
  }) {
    final hasApproved = matchingPayments.any((p) => p['status'] == 'approved');
    final hasPending = matchingPayments.any((p) => p['status'] == 'pending');

    if (hasApproved) {
      return 'paid';
    } else if (hasPending) {
      return 'pending';
    } else {
      final graceThresholdDay = cutoffDay + graceDays;
      if (targetMonth.isBefore(currentActiveMonth)) {
        return 'past due';
      } else if (targetMonth.isAtSameMomentAs(currentActiveMonth)) {
        return currentDay <= graceThresholdDay ? 'pending' : 'past due';
      } else {
        return 'pending';
      }
    }
  }

  @override
  State<AdminPaymentReportScreen> createState() =>
      _AdminPaymentReportScreenState();
}

enum _ExportMode { bundle, matrixOnly, ledgerOnly }

class _AdminPaymentReportScreenState extends State<AdminPaymentReportScreen> {
  late DateTime _startMonth;
  late DateTime _endMonth;
  bool _isLoading = false;
  bool _isPublishing = false;

  late final Stream<Map<String, dynamic>?> _settingsStream;
  late final Stream<List<Map<String, dynamic>>> _paymentsStream;
  late final Stream<List<Map<String, dynamic>>> _expensesStream;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startMonth = DateTime(now.year, now.month - 5, 1);
    _endMonth = DateTime(now.year, now.month, 1);
    _settingsStream = DatabaseService().streamDocument('config', 'app_settings');
    _paymentsStream = DatabaseService().streamCollection('payments');
    _expensesStream = DatabaseService().streamCollection('expenses');
  }

  String _formatMonthLabel(DateTime dt) =>
      AdminPaymentReportScreen.formatMonthLabel(dt);

  List<DateTime> _generateMonthRange() =>
      AdminPaymentReportScreen.generateMonthRange(_startMonth, _endMonth);

  List<DateTime> _buildAvailableMonths(
    List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> expenses,
  ) {
    final now = DateTime.now();
    DateTime earliest = DateTime(now.year, now.month - 22, 1);
    DateTime latest = DateTime(now.year, now.month + 12, 1);

    void considerPeriod(String periodKey) {
      final parsed = FinancialReportCalculator.parsePeriodKey(periodKey);
      if (parsed == null) return;
      if (parsed.isBefore(earliest)) earliest = parsed;
      if (parsed.isAfter(latest)) latest = parsed;
    }

    for (final p in payments) {
      for (final pk in FinancialReportCalculator.extractValidPaymentPeriods(p)) {
        considerPeriod(pk);
      }
    }
    for (final e in expenses) {
      final bp = e['billablePeriod']?.toString() ?? '';
      considerPeriod(bp);
    }
    if (_startMonth.isBefore(earliest)) earliest = _startMonth;
    if (_endMonth.isAfter(latest)) latest = _endMonth;

    return AdminPaymentReportScreen.generateMonthRange(earliest, latest);
  }

  String _buildMatrixCsv({
    required List<Map<String, dynamic>> addresses,
    required List<Map<String, dynamic>> payments,
    required int cutoffDay,
    required int graceDays,
    required AppLocalizations l10n,
  }) {
    final months = _generateMonthRange();
    final headerCells = ['"Street name"', '"Street number"'];
    for (final m in months) {
      headerCells.add('"${_formatMonthLabel(m)}"');
    }

    final StringBuffer csvBuffer = StringBuffer();
    csvBuffer.writeln(headerCells.join(','));

    final now = DateTime.now();
    final currentActiveMonth = DateTime(now.year, now.month, 1);

    for (final addrData in addresses) {
      final streetName = FinancialReportCalculator.sanitizeCsvTextCell(
        addrData['streetName']?.toString() ?? '',
      );
      final streetNumber = FinancialReportCalculator.sanitizeCsvTextCell(
        addrData['number']?.toString() ?? '',
      );

      final rowCells = ['"$streetName"', '"$streetNumber"'];

      for (final targetMonth in months) {
        final matchingPayments = payments.where((p) {
          return AdminPaymentReportScreen.doesPaymentMatchAddressAndMonth(
            payment: p,
            addressData: addrData,
            targetMonth: targetMonth,
          );
        }).toList();

        final monthStatus = AdminPaymentReportScreen.computeMatrixStatus(
          targetMonth: targetMonth,
          currentActiveMonth: currentActiveMonth,
          currentDay: now.day,
          cutoffDay: cutoffDay,
          graceDays: graceDays,
          matchingPayments: matchingPayments,
        );

        String localizedStatusVal = monthStatus;
        if (monthStatus == 'paid') localizedStatusVal = l10n.statusPaid.toLowerCase();
        if (monthStatus == 'pending') localizedStatusVal = l10n.statusPending.toLowerCase();
        if (monthStatus == 'past due') localizedStatusVal = l10n.statusPastDue.toLowerCase();

        rowCells.add('"$localizedStatusVal"');
      }

      csvBuffer.writeln(rowCells.join(','));
    }

    return csvBuffer.toString();
  }

  Future<List<String>> _saveCsvOutputs(
    List<({String fileName, String content})> files,
  ) async {
    final savedPaths = <String>[];
    if (kIsWeb) {
      for (int i = 0; i < files.length; i++) {
        final entry = files[i];
        final bytes = Uint8List.fromList(utf8.encode(entry.content));
        WebFileTransferHelper.downloadBytes(
          bytes: bytes,
          fileName: entry.fileName,
          mimeType: 'text/csv;charset=utf-8',
        );
        if (i + 1 < files.length) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
      return savedPaths;
    }

    final directory = await getApplicationDocumentsDirectory();
    for (final entry in files) {
      final filePath = '${directory.path}/${entry.fileName}';
      final file = File(filePath);
      await file.writeAsString(entry.content);
      savedPaths.add(filePath);
    }
    return savedPaths;
  }

  Future<void> _exportReports(_ExportMode mode) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isLoading = true);

    try {
      int cutoffDay = 1;
      int graceDays = 10;
      double initialBalance = 0.0;
      String? initialBalancePeriod;
      String timeZone = 'America/Mexico_City';

      final cData = await DatabaseService().getDocument('config', 'app_settings');
      if (cData != null) {
        cutoffDay = cData['paymentCutoffDay'] ?? 1;
        graceDays = cData['gracePeriodDays'] ?? 10;
        initialBalance =
            (cData['initialBudgetBalance'] as num?)?.toDouble() ?? 0.0;
        final rawInitPeriod = cData['initialBalancePeriod']?.toString().trim();
        initialBalancePeriod =
            (rawInitPeriod != null && rawInitPeriod.isNotEmpty)
                ? rawInitPeriod
                : null;
        timeZone = cData['timeZone']?.toString() ?? 'America/Mexico_City';
      }

      final addresses = await DatabaseService().getCollection('addresses');
      addresses.sort((a, b) {
        final sA = a['streetName']?.toString() ?? '';
        final sB = b['streetName']?.toString() ?? '';
        final cmp = sA.compareTo(sB);
        if (cmp != 0) return cmp;
        final nA = a['number'] ?? 0;
        final nB = b['number'] ?? 0;
        if (nA is int && nB is int) return nA.compareTo(nB);
        return nA.toString().compareTo(nB.toString());
      });

      final payments = await DatabaseService().getCollection('payments');
      final expenses = await DatabaseService().getCollection('expenses');

      final ledger = FinancialReportCalculator.computeFinancialLedger(
        payments: payments,
        expenses: expenses,
        startMonth: _startMonth,
        endMonth: _endMonth,
        initialBudgetBalance: initialBalance,
        initialBalancePeriod: initialBalancePeriod,
        timeZone: timeZone,
      );

      final hasQuotaData = AdminPaymentReportScreen.hasDataForRange(
        payments: payments,
        startMonth: _startMonth,
        endMonth: _endMonth,
      );
      final hasLedgerData = ledger.rangeTotalIncomeCents > 0 ||
          ledger.expensesInRange.isNotEmpty ||
          ledger.initialBudgetBalanceCents != 0;

      final bool missingDataForMode = switch (mode) {
        _ExportMode.bundle => !hasQuotaData && !hasLedgerData,
        _ExportMode.matrixOnly => !hasQuotaData,
        _ExportMode.ledgerOnly => !hasLedgerData,
      };

      if (missingDataForMode) {
        if (mounted) {
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.noDataAlertTitle),
              content: Text(l10n.noDataAlertMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.ok),
                ),
              ],
            ),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      final startKey = AdminPaymentReportScreen.formatPeriodKey(_startMonth);
      final endKey = AdminPaymentReportScreen.formatPeriodKey(_endMonth);
      final ts = DateTime.now().millisecondsSinceEpoch;

      final matrixCsv = (mode == _ExportMode.bundle || mode == _ExportMode.matrixOnly)
          ? _buildMatrixCsv(
              addresses: addresses,
              payments: payments,
              cutoffDay: cutoffDay,
              graceDays: graceDays,
              l10n: l10n,
            )
          : null;

      final ledgerCsv = (mode == _ExportMode.bundle || mode == _ExportMode.ledgerOnly)
          ? FinancialReportCalculator.buildFinancialLedgerCsv(ledger)
          : null;

      final filesToSave = <({String fileName, String content})>[];

      if (matrixCsv != null) {
        if (widget.onSaveCsv != null) {
          await widget.onSaveCsv!(matrixCsv);
        } else {
          filesToSave.add((
            fileName: 'payment_status_matrix_${startKey}_to_${endKey}_$ts.csv',
            content: matrixCsv,
          ));
        }
      }

      if (ledgerCsv != null) {
        if (widget.onSaveLedgerCsv != null) {
          await widget.onSaveLedgerCsv!(ledgerCsv);
        } else if (widget.onSaveCsv == null) {
          // Only write to local disk/browser when no test callback overrides output
          filesToSave.add((
            fileName: 'financial_ledger_budget_${startKey}_to_${endKey}_$ts.csv',
            content: ledgerCsv,
          ));
        }
      }

      final savedPaths = filesToSave.isNotEmpty
          ? await _saveCsvOutputs(filesToSave)
          : const <String>[];

      if (mounted) {
        final msg = savedPaths.isEmpty
            ? l10n.reportSavedSuccess
            : '${l10n.reportSavedSuccess} ${savedPaths.join(', ')}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error downloading financial report: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminPaymentReportScreen._exportReports',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _publishSummaryToTransparency(
    FinancialLedgerResult ledger,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final defaultTitle = FinancialReportCalculator.formatTransparencyPeriodTitle(
      ledger.startPeriod,
      ledger.endPeriod,
    );

    final result = await showDialog<({String title, String visibility})>(
      context: context,
      builder: (_) => _PublishTransparencyDialog(initialTitle: defaultTitle),
    );

    if (result == null || result.title.isEmpty || !mounted) return;
    setState(() => _isPublishing = true);

    try {
      final docId = FinancialReportCalculator.buildTransparencyDocId(
        ledger.startPeriod,
        ledger.endPeriod,
      );
      final publishVersion = DateTime.now().millisecondsSinceEpoch;
      final enL10n = lookupAppLocalizations(const Locale('en'));
      final esL10n = lookupAppLocalizations(const Locale('es'));

      // Strictly aggregated Markdown summaries in ES & EN; never includes address payment status matrix.
      final Map<String, Map<String, String>> translations = {};
      for (final lang in const ['es', 'en']) {
        final md = FinancialReportCalculator.buildTransparencyMarkdownReport(
          title: result.title,
          ledger: ledger,
          languageCode: lang,
          useDescriptiveHeading: true,
        );
        translations[lang] = {
          'title': result.title,
          'fileName': '${docId}_${publishVersion}_$lang.md',
          'fileType': 'md',
          'fileBase64': base64Encode(utf8.encode(md)),
        };
      }

      await FunctionsService().callFunction('syncTransparencyDocument', {
        'docId': docId,
        'title': result.title,
        'fileType': 'md',
        'visibility': result.visibility,
        'category': 'financial',
        'categoryName': enL10n.docCategoryFinancial,
        'categoryLocalizedNames': {
          'en': enL10n.docCategoryFinancial,
          'es': esL10n.docCategoryFinancial,
        },
        'folderId': 'financial_reports',
        'folderName': enL10n.folderFinancialReports,
        'folderNameKey': 'financial_reports',
        'folderLocalizedNames': {
          'en': enL10n.folderFinancialReports,
          'es': esL10n.folderFinancialReports,
        },
        'translations': translations,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.publishTransparencySuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error publishing financial summary: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminPaymentReportScreen._publishSummaryToTransparency',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
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
                l10n.generateReportTitle,
                style: const TextStyle(fontFamily: AppConfig.fontFamily),
              ),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _settingsStream,
        builder: (context, settingsSnap) {
          final appSettings = settingsSnap.data ?? const <String, dynamic>{};
          final initialBalance =
              (appSettings['initialBudgetBalance'] as num?)?.toDouble() ?? 0.0;
          final rawInitPeriod =
              appSettings['initialBalancePeriod']?.toString().trim();
          final initialBalancePeriod =
              (rawInitPeriod != null && rawInitPeriod.isNotEmpty)
                  ? rawInitPeriod
                  : null;
          final timeZone =
              appSettings['timeZone']?.toString() ?? 'America/Mexico_City';

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _paymentsStream,
            builder: (context, paymentsSnap) {
              final payments = paymentsSnap.data ?? const <Map<String, dynamic>>[];

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _expensesStream,
                builder: (context, expensesSnap) {
                  final expenses =
                      expensesSnap.data ?? const <Map<String, dynamic>>[];
                  final availableMonths = _buildAvailableMonths(
                    payments,
                    expenses,
                  );

                  final ledger =
                      FinancialReportCalculator.computeFinancialLedger(
                    payments: payments,
                    expenses: expenses,
                    startMonth: _startMonth,
                    endMonth: _endMonth,
                    initialBudgetBalance: initialBalance,
                    initialBalancePeriod: initialBalancePeriod,
                    timeZone: timeZone,
                  );

                  final isCompact = MediaQuery.sizeOf(context).width < 600;

                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(isCompact ? 12.0 : 24.0),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(isCompact ? 16.0 : 24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Icon(
                                  Icons.table_chart,
                                  size: isCompact ? 44 : 52,
                                  color: AppConfig.primaryColor,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  l10n.generateReportTitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppConfig.primaryColor,
                                    fontFamily: AppConfig.fontFamily,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.financialReportSubtitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Live Financial Summary Preview Card (at top)
                                _buildFinancialPreviewCard(l10n, ledger),
                                const SizedBox(height: 20),

                                // Start & End Month Dropdowns
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final startDropdown =
                                        DropdownButtonFormField<DateTime>(
                                      key: ValueKey(
                                        'start_month_${_startMonth.millisecondsSinceEpoch}',
                                      ),
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: l10n.startMonthLabel,
                                        prefixIcon: const Icon(
                                          Icons.calendar_today,
                                          color: AppConfig.primaryColor,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      initialValue: availableMonths.any(
                                              (m) => m.isAtSameMomentAs(_startMonth))
                                          ? _startMonth
                                          : availableMonths.first,
                                      items: availableMonths.map((dt) {
                                        return DropdownMenuItem(
                                          value: dt,
                                          child: Text(
                                            _formatMonthLabel(dt),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            _startMonth = val;
                                            if (_startMonth.isAfter(_endMonth)) {
                                              _endMonth = _startMonth;
                                            }
                                          });
                                        }
                                      },
                                    );

                                    final endDropdown =
                                        DropdownButtonFormField<DateTime>(
                                      key: ValueKey(
                                        'end_month_${_startMonth.millisecondsSinceEpoch}_${_endMonth.millisecondsSinceEpoch}',
                                      ),
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: l10n.endMonthLabel,
                                        prefixIcon: const Icon(
                                          Icons.event,
                                          color: AppConfig.primaryColor,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      initialValue: availableMonths.any(
                                              (m) => m.isAtSameMomentAs(_endMonth))
                                          ? _endMonth
                                          : availableMonths.last,
                                      items: availableMonths
                                          .where(
                                            (dt) => !dt.isBefore(_startMonth),
                                          )
                                          .map((dt) {
                                        return DropdownMenuItem(
                                          value: dt,
                                          child: Text(
                                            _formatMonthLabel(dt),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _endMonth = val);
                                        }
                                      },
                                    );

                                    if (constraints.maxWidth >= 520) {
                                      return Row(
                                        children: [
                                          Expanded(child: startDropdown),
                                          const SizedBox(width: 14),
                                          Expanded(child: endDropdown),
                                        ],
                                      );
                                    }
                                    return Column(
                                      children: [
                                        startDropdown,
                                        const SizedBox(height: 16),
                                        endDropdown,
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),

                                // Download & Export Options (at the end)
                                ElevatedButton.icon(
                                  key: const ValueKey(
                                    'download_report_bundle_button',
                                  ),
                                  onPressed: _isLoading
                                      ? null
                                      : () => _exportReports(_ExportMode.bundle),
                                  icon: const Icon(Icons.download),
                                  label: _isLoading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          l10n.downloadReportBundleButton,
                                          textAlign: TextAlign.center,
                                        ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppConfig.secondaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Secondary Individual Exports & Publish
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final buttons = [
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'download_status_matrix_only_button',
                                        ),
                                        onPressed: _isLoading
                                            ? null
                                            : () => _exportReports(
                                                  _ExportMode.matrixOnly,
                                                ),
                                        icon: const Icon(
                                          Icons.table_chart_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          l10n.downloadStatusMatrixCsvButton,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'download_financial_ledger_only_button',
                                        ),
                                        onPressed: _isLoading
                                            ? null
                                            : () => _exportReports(
                                                  _ExportMode.ledgerOnly,
                                                ),
                                        icon: const Icon(
                                          Icons.receipt_long_outlined,
                                          size: 18,
                                        ),
                                        label: Text(
                                          l10n.downloadFinancialLedgerCsvButton,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'publish_transparency_report_button',
                                        ),
                                        onPressed: (_isLoading || _isPublishing)
                                            ? null
                                            : () =>
                                                _publishSummaryToTransparency(
                                                  ledger,
                                                ),
                                        icon: _isPublishing
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.public,
                                                size: 18,
                                              ),
                                        label: Text(
                                          l10n.publishToTransparencyButton,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'open_bulk_payment_import_button',
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const AdminBulkPaymentImportScreen(),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.history_edu,
                                          size: 18,
                                        ),
                                        label: Text(
                                          l10n.bulkPaymentImportMenu,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ];

                                    if (constraints.maxWidth < 520) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          for (var i = 0;
                                              i < buttons.length;
                                              i++) ...[
                                            if (i > 0)
                                              const SizedBox(height: 10),
                                            buttons[i],
                                          ],
                                        ],
                                      );
                                    }

                                    return Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: buttons,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFinancialPreviewCard(
    AppLocalizations l10n,
    FinancialLedgerResult ledger,
  ) {
    String fmt(double val) {
      final prefix = val < 0 ? '-\$' : '\$';
      return '$prefix${val.abs().toStringAsFixed(2)}';
    }

    return Container(
      key: const ValueKey('financial_summary_preview_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConfig.primaryColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppConfig.primaryColor.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppConfig.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.reportPreviewTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppConfig.primaryColor,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          _PreviewLine(
            label: l10n.openingBalancePreviewLabel,
            value: fmt(ledger.broughtForwardBalance),
          ),
          _PreviewLine(
            label: l10n.quotaIncomePreviewLabel,
            value: fmt(ledger.rangeQuotaIncome),
            valueColor: Colors.blue.shade700,
          ),
          _PreviewLine(
            label: l10n.sanctionIncomePreviewLabel,
            value: fmt(ledger.rangeSanctionIncome),
            valueColor: Colors.teal.shade700,
          ),
          _PreviewLine(
            label: l10n.expensesPreviewLabel,
            value: '-\$${ledger.rangeActiveExpenses.toStringAsFixed(2)}',
            valueColor: Colors.deepOrange.shade700,
          ),
          _PreviewLine(
            label: l10n.netPeriodBalancePreviewLabel,
            value: fmt(ledger.rangeNetBalance),
            valueColor: ledger.rangeNetBalance >= 0
                ? AppConfig.secondaryColor
                : AppConfig.dangerColor,
          ),
          const Divider(height: 16),
          _PreviewLine(
            label: l10n.accumulatedBudgetPreviewLabel,
            value: fmt(ledger.endingAccumulatedBudget),
            isTotal: true,
            valueColor: ledger.endingAccumulatedBudget >= 0
                ? AppConfig.secondaryColor
                : AppConfig.dangerColor,
          ),
        ],
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isTotal;

  const _PreviewLine({
    required this.label,
    required this.value,
    this.valueColor,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 14.5 : 13,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
                color: isTotal ? AppConfig.primaryColor : AppConfig.textColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 16 : 13.5,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppConfig.textColor,
              fontFamily: AppConfig.fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishTransparencyDialog extends StatefulWidget {
  final String initialTitle;

  const _PublishTransparencyDialog({required this.initialTitle});

  @override
  State<_PublishTransparencyDialog> createState() =>
      _PublishTransparencyDialogState();
}

class _PublishTransparencyDialogState
    extends State<_PublishTransparencyDialog> {
  late final TextEditingController _titleController;
  String _visibility = 'admin';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.publishTransparencyDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppConfig.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.privacy_tip_outlined,
                    size: 18,
                    color: AppConfig.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.publishTransparencyPrivacyNote,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('transparency_report_title_field'),
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l10n.publishTransparencyTitleLabel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('transparency_report_visibility_$_visibility'),
              initialValue: _visibility,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.publishTransparencyVisibilityLabel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'admin',
                  child: Text(l10n.visibilityAdminOnly),
                ),
                DropdownMenuItem(
                  value: 'all',
                  child: Text(l10n.visibilityAllResidents),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _visibility = val);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          key: const ValueKey('confirm_publish_transparency_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConfig.primaryColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final clean = _titleController.text.trim();
            if (clean.isEmpty) return;
            Navigator.of(context).pop((title: clean, visibility: _visibility));
          },
          child: Text(l10n.publishTransparencyButtonConfirm),
        ),
      ],
    );
  }
}

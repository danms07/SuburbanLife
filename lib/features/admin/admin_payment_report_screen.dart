import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import 'admin_bulk_payment_import_screen.dart';

class AdminPaymentReportScreen extends StatefulWidget {
  final Future<void> Function(String csvContent)? onSaveCsv;
  final bool isEmbedded;

  const AdminPaymentReportScreen({
    super.key,
    this.onSaveCsv,
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

  static List<DateTime> generateMonthRange(DateTime startMonth, DateTime endMonth) {
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
  State<AdminPaymentReportScreen> createState() => _AdminPaymentReportScreenState();
}

class _AdminPaymentReportScreenState extends State<AdminPaymentReportScreen> {
  late DateTime _startMonth;
  late DateTime _endMonth;
  bool _isLoading = false;

  final List<DateTime> _availableMonths = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default range: past 6 months to current month
    _startMonth = DateTime(now.year, now.month - 5, 1);
    _endMonth = DateTime(now.year, now.month, 1);

    // Populate dropdown options with last 24 months and next 2 months
    for (int i = -22; i <= 2; i++) {
      _availableMonths.add(DateTime(now.year, now.month + i, 1));
    }
    _availableMonths.sort((a, b) => a.compareTo(b));
  }

  String _formatMonthLabel(DateTime dt) => AdminPaymentReportScreen.formatMonthLabel(dt);

  List<DateTime> _generateMonthRange() =>
      AdminPaymentReportScreen.generateMonthRange(_startMonth, _endMonth);

  void _generateAndSaveReport() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Fetch global config constants
      int cutoffDay = 1;
      int graceDays = 10;
      final cData = await DatabaseService().getDocument('config', 'app_settings');
      if (cData != null) {
        cutoffDay = cData['paymentCutoffDay'] ?? 1;
        graceDays = cData['gracePeriodDays'] ?? 10;
      }

      // 2. Fetch all addresses
      final addresses = await DatabaseService().getCollection('addresses');

      // Sort logically
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

      // 3. Fetch all payments to evaluate locally
      final payments = await DatabaseService().getCollection('payments');

      final hasDataForPeriod = AdminPaymentReportScreen.hasDataForRange(
        payments: payments,
        startMonth: _startMonth,
        endMonth: _endMonth,
      );

      if (!hasDataForPeriod) {
        if (mounted) {
          showDialog(
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
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // 4. Generate Discrete Month Matrix Header
      final months = _generateMonthRange();
      final headerCells = ['"Street name"', '"Street number"'];
      for (final m in months) {
        headerCells.add('"${_formatMonthLabel(m)}"');
      }

      final StringBuffer csvBuffer = StringBuffer();
      csvBuffer.writeln(headerCells.join(','));

      final now = DateTime.now();
      final currentActiveMonth = DateTime(now.year, now.month, 1);

      // 5. Populate Address Matrix Rows
      for (final addrData in addresses) {
        final streetName = addrData['streetName']?.toString().replaceAll('"', '""') ?? '';
        final streetNumber = addrData['number']?.toString().replaceAll('"', '""') ?? '';

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

      final csvString = csvBuffer.toString();

      // 6. Trigger File Output Flow
      if (widget.onSaveCsv != null) {
        await widget.onSaveCsv!(csvString);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.reportSavedSuccess),
              backgroundColor: AppConfig.secondaryColor,
            ),
          );
        }
      } else if (kIsWeb) {
        final bytes = utf8.encode(csvString);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', 'payment_report_${DateTime.now().millisecondsSinceEpoch}.csv')
          ..click();
        html.Url.revokeObjectUrl(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.reportSavedSuccess), backgroundColor: AppConfig.secondaryColor),
          );
        }
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final String filePath = '${directory.path}/payment_report_${DateTime.now().millisecondsSinceEpoch}.csv';
        final File file = File(filePath);
        await file.writeAsString(csvString);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n.reportSavedSuccess} Saved to: $filePath'),
              backgroundColor: AppConfig.secondaryColor,
            ),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Error downloading payment report: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminPaymentReportScreen._downloadCsv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
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
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Text(l10n.generateReportTitle, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.table_chart, size: 60, color: AppConfig.primaryColor),
                const SizedBox(height: 16),
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
                const Text(
                  'Select custom month boundaries to compile property maintenance payments matrix.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.center,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminBulkPaymentImportScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history_edu, size: 18),
                    label: Text(l10n.bulkPaymentImportMenu),
                  ),
                ),
                const SizedBox(height: 24),

                // Start Month Dropdown
                DropdownButtonFormField<DateTime>(
                  key: ValueKey('start_month_${_startMonth.millisecondsSinceEpoch}'),
                  decoration: InputDecoration(
                    labelText: l10n.startMonthLabel,
                    prefixIcon: const Icon(Icons.calendar_today, color: AppConfig.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  initialValue: _availableMonths.any((m) => m.isAtSameMomentAs(_startMonth))
                      ? _startMonth
                      : _availableMonths.first,
                  items: _availableMonths.map((dt) {
                    return DropdownMenuItem(
                      value: dt,
                      child: Text(_formatMonthLabel(dt)),
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
                ),
                const SizedBox(height: 20),

                // End Month Dropdown
                DropdownButtonFormField<DateTime>(
                  key: ValueKey(
                    'end_month_${_startMonth.millisecondsSinceEpoch}_${_endMonth.millisecondsSinceEpoch}',
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.endMonthLabel,
                    prefixIcon: const Icon(Icons.event, color: AppConfig.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  initialValue: _availableMonths.any((m) => m.isAtSameMomentAs(_endMonth))
                      ? _endMonth
                      : _availableMonths.last,
                  items: _availableMonths.where((dt) => !dt.isBefore(_startMonth)).map((dt) {
                    return DropdownMenuItem(
                      value: dt,
                      child: Text(_formatMonthLabel(dt)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _endMonth = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 40),

                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _generateAndSaveReport,
                  icon: const Icon(Icons.download),
                  label: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(l10n.downloadReportMenu),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.secondaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

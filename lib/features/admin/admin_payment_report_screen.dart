import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import 'package:file_picker/file_picker.dart';
import 'package:universal_html/html.dart' as html;
import 'package:path_provider/path_provider.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';

class AdminPaymentReportScreen extends StatefulWidget {
  const AdminPaymentReportScreen({Key? key}) : super(key: key);

  @override
  _AdminPaymentReportScreenState createState() => _AdminPaymentReportScreenState();
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

  String _formatMonthLabel(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  List<DateTime> _generateMonthRange() {
    List<DateTime> range = [];
    DateTime current = DateTime(_startMonth.year, _startMonth.month, 1);
    final end = DateTime(_endMonth.year, _endMonth.month, 1);

    while (!current.isAfter(end)) {
      range.add(current);
      current = DateTime(current.year, current.month + 1, 1);
    }
    return range;
  }

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

      // Enforce checking if any payment record exists within the specified month boundaries
      final startOfEntireRange = DateTime(_startMonth.year, _startMonth.month, 1).millisecondsSinceEpoch;
      final endOfEntireRange = DateTime(_endMonth.year, _endMonth.month + 1, 1).millisecondsSinceEpoch;

      final hasDataForPeriod = payments.any((p) {
        final ts = p['timestamp'] ?? 0;
        return ts >= startOfEntireRange && ts < endOfEntireRange;
      });

      if (!hasDataForPeriod) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.noDataAlertTitle),
            content: Text(l10n.noDataAlertMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        setState(() { _isLoading = false; });
        return;
      }

      // 4. Generate Discrete Month Matrix Header
      final months = _generateMonthRange();
      final headerCells = ['"Street name"', '"Street number"'];
      for (var m in months) {
        headerCells.add('"${_formatMonthLabel(m)}"');
      }

      final StringBuffer csvBuffer = StringBuffer();
      csvBuffer.writeln(headerCells.join(','));

      final now = DateTime.now();
      final currentActiveMonth = DateTime(now.year, now.month, 1);
      final graceThresholdDay = cutoffDay + graceDays;

      // 5. Populate Address Matrix Rows
      for (var addrData in addresses) {
        final streetName = addrData['streetName']?.toString().replaceAll('"', '""') ?? '';
        final streetNumber = addrData['number']?.toString().replaceAll('"', '""') ?? '';
        final residentUid = addrData['residentUid']?.toString() ?? '';

        final rowCells = ['"$streetName"', '"$streetNumber"'];

        for (var targetMonth in months) {
          String monthStatus = 'past due';

          // Check payment records matching this user/address in this specific month/year bounds
          final startOfTargetMonth = DateTime(targetMonth.year, targetMonth.month, 1).millisecondsSinceEpoch;
          // Next month start is upper bound exclusive
          final endOfTargetMonth = DateTime(targetMonth.year, targetMonth.month + 1, 1).millisecondsSinceEpoch;

          final matchingPayments = payments.where((p) {
            final pResidentUid = p['residentUid']?.toString() ?? '';
            final ts = p['timestamp'] ?? 0;
            return pResidentUid == residentUid && ts >= startOfTargetMonth && ts < endOfTargetMonth;
          }).toList();

          final hasApproved = matchingPayments.any((p) => p['status'] == 'approved');
          final hasPending = matchingPayments.any((p) => p['status'] == 'pending');

          if (hasApproved) {
            monthStatus = 'paid';
          } else if (hasPending) {
            monthStatus = 'pending';
          } else {
            // Assess temporal grace bounds if no record exists
            if (targetMonth.isBefore(currentActiveMonth)) {
              monthStatus = 'past due';
            } else if (targetMonth.isAtSameMomentAs(currentActiveMonth)) {
              if (now.day <= graceThresholdDay) {
                monthStatus = 'pending';
              } else {
                monthStatus = 'past due';
              }
            } else {
              // Future month targets naturally pending
              monthStatus = 'pending';
            }
          }

          // Translate matrix state value cleanly
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
      if (kIsWeb) {
        final bytes = utf8.encode(csvString);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'payment_report_${DateTime.now().millisecondsSinceEpoch}.csv')
          ..click();
        html.Url.revokeObjectUrl(url);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.reportSavedSuccess), backgroundColor: AppConfig.secondaryColor),
        );
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final String filePath = '${directory.path}/payment_report_${DateTime.now().millisecondsSinceEpoch}.csv';
        final File file = File(filePath);
        await file.writeAsString(csvString);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.reportSavedSuccess} Saved to: $filePath'), backgroundColor: AppConfig.secondaryColor),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
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
                const SizedBox(height: 32),

                // Start Month Dropdown
                DropdownButtonFormField<DateTime>(
                  decoration: InputDecoration(
                    labelText: l10n.startMonthLabel,
                    prefixIcon: const Icon(Icons.calendar_today, color: AppConfig.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  value: _availableMonths.any((m) => m.isAtSameMomentAs(_startMonth)) ? _startMonth : _availableMonths.first,
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
                  decoration: InputDecoration(
                    labelText: l10n.endMonthLabel,
                    prefixIcon: const Icon(Icons.event, color: AppConfig.primaryColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  value: _availableMonths.any((m) => m.isAtSameMomentAs(_endMonth)) ? _endMonth : _availableMonths.last,
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
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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

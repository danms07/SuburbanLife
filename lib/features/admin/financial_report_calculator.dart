import 'dart:ui';

import '../../l10n/app_localizations.dart';
import 'expense_service.dart';

/// Monthly financial breakdown row for cashflow & running budget reporting.
class MonthlyLedgerRow {
  final String period;
  final int quotaIncomeCents;
  final int sanctionIncomeCents;
  final int activeExpensesCents;
  final int accumulatedBudgetCents;

  const MonthlyLedgerRow({
    required this.period,
    required this.quotaIncomeCents,
    required this.sanctionIncomeCents,
    required this.activeExpensesCents,
    required this.accumulatedBudgetCents,
  });

  int get totalIncomeCents => quotaIncomeCents + sanctionIncomeCents;
  int get netPeriodBalanceCents => totalIncomeCents - activeExpensesCents;

  double get quotaIncome => quotaIncomeCents / 100.0;
  double get sanctionIncome => sanctionIncomeCents / 100.0;
  double get totalIncome => totalIncomeCents / 100.0;
  double get activeExpenses => activeExpensesCents / 100.0;
  double get netPeriodBalance => netPeriodBalanceCents / 100.0;
  double get accumulatedBudget => accumulatedBudgetCents / 100.0;
}

/// Complete financial calculation result across a configured `[startMonth, endMonth]` range.
class FinancialLedgerResult {
  final String startPeriod;
  final String endPeriod;
  final int initialBudgetBalanceCents;
  final String? initialBalancePeriod;
  final int broughtForwardBalanceCents;
  final int rangeQuotaIncomeCents;
  final int rangeSanctionIncomeCents;
  final int rangeActiveExpensesCents;
  final int endingAccumulatedBudgetCents;
  final List<MonthlyLedgerRow> monthlyRows;
  final List<ExpenseRecord> expensesInRange;

  const FinancialLedgerResult({
    required this.startPeriod,
    required this.endPeriod,
    required this.initialBudgetBalanceCents,
    required this.initialBalancePeriod,
    required this.broughtForwardBalanceCents,
    required this.rangeQuotaIncomeCents,
    required this.rangeSanctionIncomeCents,
    required this.rangeActiveExpensesCents,
    required this.endingAccumulatedBudgetCents,
    required this.monthlyRows,
    required this.expensesInRange,
  });

  int get rangeTotalIncomeCents =>
      rangeQuotaIncomeCents + rangeSanctionIncomeCents;
  int get rangeNetBalanceCents =>
      rangeTotalIncomeCents - rangeActiveExpensesCents;

  double get initialBudgetBalance => initialBudgetBalanceCents / 100.0;
  double get broughtForwardBalance => broughtForwardBalanceCents / 100.0;
  double get rangeQuotaIncome => rangeQuotaIncomeCents / 100.0;
  double get rangeSanctionIncome => rangeSanctionIncomeCents / 100.0;
  double get rangeTotalIncome => rangeTotalIncomeCents / 100.0;
  double get rangeActiveExpenses => rangeActiveExpensesCents / 100.0;
  double get rangeNetBalance => rangeNetBalanceCents / 100.0;
  double get endingAccumulatedBudget => endingAccumulatedBudgetCents / 100.0;
}

/// Pure, deterministic accounting and CSV/Markdown report calculator.
///
/// Aggregates approved/paid maintenance quotas, approved/paid sanction fines,
/// active (non-voided) expenses, and configurable opening balances while
/// neutralizing CSV formula injection payloads and excluding address-level PII
/// from public summaries.
class FinancialReportCalculator {
  static final RegExp _periodRegex = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  /// Standard UTC offsets (hours) for community timezones supported in Admin Settings.
  static const Map<String, int> _timezoneStandardOffsetsHours = {
    'America/Mexico_City': -6,
    'America/Cancun': -5,
    'America/Tijuana': -8,
    'America/Hermosillo': -7,
    'UTC': 0,
  };

  /// Formats a [DateTime] into `'YYYY-MM'`.
  static String formatPeriodKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
  }

  /// Parses `'YYYY-MM'` into the first day of that month, or `null` if invalid.
  static DateTime? parsePeriodKey(String raw) {
    final clean = raw.trim();
    if (!_periodRegex.hasMatch(clean)) return null;
    final parts = clean.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return DateTime(year, month, 1);
  }

  /// Generates sequential `'YYYY-MM'` keys between [startPeriod] and [endPeriod] inclusive.
  static List<String> generatePeriodKeysRange(
    DateTime startMonth,
    DateTime endMonth,
  ) {
    final list = <String>[];
    var current = DateTime(startMonth.year, startMonth.month, 1);
    final end = DateTime(endMonth.year, endMonth.month, 1);
    while (!current.isAfter(end)) {
      list.add(formatPeriodKey(current));
      current = DateTime(current.year, current.month + 1, 1);
    }
    return list;
  }

  /// Resolves an epoch-ms / DateTime timestamp into a `'YYYY-MM'` period in [timeZone].
  static String resolvePeriodFromTimestamp(
    dynamic rawTs, {
    String timeZone = 'America/Mexico_City',
  }) {
    final ms = extractTimestampMs(rawTs);
    if (ms <= 0) return '';
    final offsetHours = _timezoneStandardOffsetsHours[timeZone];
    final DateTime dt = offsetHours != null
        ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
            .add(Duration(hours: offsetHours))
        : DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return formatPeriodKey(dt);
  }

  static int extractTimestampMs(dynamic rawTs) {
    if (rawTs is int) return rawTs;
    if (rawTs is num) return rawTs.toInt();
    if (rawTs is DateTime) return rawTs.millisecondsSinceEpoch;
    return 0;
  }

  /// Extracts normalized `'YYYY-MM'` period keys from a payment document.
  static List<String> extractValidPaymentPeriods(Map<String, dynamic> payment) {
    final result = <String>[];
    if (payment['periods'] is List) {
      for (final p in (payment['periods'] as List)) {
        final s = p?.toString().trim() ?? '';
        if (_periodRegex.hasMatch(s) && !result.contains(s)) {
          result.add(s);
        }
      }
    } else if (payment['period'] != null) {
      for (final p in payment['period'].toString().split(',')) {
        final s = p.trim();
        if (_periodRegex.hasMatch(s) && !result.contains(s)) {
          result.add(s);
        }
      }
    }
    result.sort();
    return result;
  }

  /// Neutralizes spreadsheet formula injection (CWE-1236) in untrusted text cells
  /// by prefixing a single quote before leading `=`, `+`, `-`, `@`, `\t`, or `\r`,
  /// and escapes double quotes per RFC 4180.
  static String sanitizeCsvTextCell(String rawValue) {
    var normalized = rawValue.replaceAll('\r\n', ' ').replaceAll('\n', ' ').replaceAll('\r', ' ');
    final trimmedStart = normalized.trimLeft();
    const formulaPrefixes = ['=', '+', '-', '@', '\t', '\r'];
    if ((normalized.isNotEmpty && formulaPrefixes.contains(normalized[0])) ||
        (trimmedStart.isNotEmpty && formulaPrefixes.contains(trimmedStart[0]))) {
      normalized = "'$normalized";
    }
    return normalized.replaceAll('"', '""');
  }

  static String _quoteCsvText(String rawValue) {
    return '"${sanitizeCsvTextCell(rawValue)}"';
  }

  static String _formatCents(int cents) {
    return (cents / 100.0).toStringAsFixed(2);
  }

  static String _formatDateIso(int millis) {
    if (millis <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// Computes complete monthly income, active expenses, brought-forward balance,
  /// and running accumulated budget across `[startMonth, endMonth]`.
  static FinancialLedgerResult computeFinancialLedger({
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> expenses,
    required DateTime startMonth,
    required DateTime endMonth,
    double initialBudgetBalance = 0.0,
    String? initialBalancePeriod,
    String timeZone = 'America/Mexico_City',
  }) {
    final startPeriod = formatPeriodKey(startMonth);
    final endPeriod = formatPeriodKey(endMonth);
    final cleanInitialPeriod = (initialBalancePeriod != null &&
            _periodRegex.hasMatch(initialBalancePeriod.trim()))
        ? initialBalancePeriod.trim()
        : null;

    final int initialCents =
        initialBudgetBalance.isFinite ? (initialBudgetBalance * 100).round() : 0;

    final quotaByPeriodCents = <String, int>{};
    final sanctionByPeriodCents = <String, int>{};
    final expensesByPeriodCents = <String, int>{};
    final allTrackedPeriods = <String>{
      startPeriod,
      endPeriod,
      ?cleanInitialPeriod,
    };

    // 1. Aggregate realized income (only approved or paid transactions)
    for (final payment in payments) {
      final status = (payment['status']?.toString() ?? '').trim().toLowerCase();
      if (status != 'approved' && status != 'paid') continue;

      final rawAmount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
      if (!rawAmount.isFinite || rawAmount <= 0) continue;
      final totalCents = (rawAmount * 100).round();
      if (totalCents <= 0) continue;

      final concept =
          (payment['concept']?.toString() ?? 'monthly quota').trim().toLowerCase();

      if (concept == 'sanction') {
        final sanctionPeriod = resolvePeriodFromTimestamp(
          payment['paymentDate'] ?? payment['approvalDate'] ?? payment['timestamp'],
          timeZone: timeZone,
        );
        if (_periodRegex.hasMatch(sanctionPeriod)) {
          sanctionByPeriodCents[sanctionPeriod] =
              (sanctionByPeriodCents[sanctionPeriod] ?? 0) + totalCents;
          allTrackedPeriods.add(sanctionPeriod);
        }
        continue;
      }

      if (concept == 'monthly quota') {
        var coveredPeriods = extractValidPaymentPeriods(payment);
        if (coveredPeriods.isEmpty) {
          final fallbackPeriod = resolvePeriodFromTimestamp(
            payment['paymentDate'] ?? payment['timestamp'],
            timeZone: timeZone,
          );
          if (_periodRegex.hasMatch(fallbackPeriod)) {
            coveredPeriods = [fallbackPeriod];
          }
        }
        if (coveredPeriods.isEmpty) continue;

        final count = coveredPeriods.length;
        final baseCents = totalCents ~/ count;
        final remainderCents = totalCents % count;

        for (int i = 0; i < count; i++) {
          final period = coveredPeriods[i];
          final share = i == count - 1 ? baseCents + remainderCents : baseCents;
          quotaByPeriodCents[period] =
              (quotaByPeriodCents[period] ?? 0) + share;
          allTrackedPeriods.add(period);
        }
      }
    }

    // 2. Aggregate expenses (only active expenses impact totals; voided stay in ledger for audit)
    final parsedExpenses = <ExpenseRecord>[];
    for (final rawExp in expenses) {
      final exp = ExpenseRecord.fromMap(rawExp);
      parsedExpenses.add(exp);
      if (!_periodRegex.hasMatch(exp.billablePeriod)) continue;
      allTrackedPeriods.add(exp.billablePeriod);

      if (exp.isActive && exp.amount.isFinite && exp.amount > 0) {
        final expCents = (exp.amount * 100).round();
        expensesByPeriodCents[exp.billablePeriod] =
            (expensesByPeriodCents[exp.billablePeriod] ?? 0) + expCents;
      }
    }

    // 3. Sort all observed periods to compute continuous accumulated running balance
    final sortedPeriods = allTrackedPeriods.toList()..sort();
    final earliestDt = parsePeriodKey(sortedPeriods.first) ?? startMonth;
    final latestDt = parsePeriodKey(sortedPeriods.last) ?? endMonth;
    final timeline = generatePeriodKeysRange(earliestDt, latestDt);

    int runningBalanceCents = cleanInitialPeriod == null ? initialCents : 0;
    int broughtForwardCents = runningBalanceCents;
    bool capturedBroughtForward = false;

    final monthlyRows = <MonthlyLedgerRow>[];
    int rangeQuotaCents = 0;
    int rangeSanctionCents = 0;
    int rangeExpensesCents = 0;

    for (final period in timeline) {
      if (cleanInitialPeriod != null && period == cleanInitialPeriod) {
        runningBalanceCents = initialCents;
      }

      if (period == startPeriod && !capturedBroughtForward) {
        broughtForwardCents = runningBalanceCents;
        capturedBroughtForward = true;
      }

      final bool countsInAccumulated =
          cleanInitialPeriod == null || period.compareTo(cleanInitialPeriod) >= 0;

      final qCents = quotaByPeriodCents[period] ?? 0;
      final sCents = sanctionByPeriodCents[period] ?? 0;
      final eCents = expensesByPeriodCents[period] ?? 0;

      if (countsInAccumulated) {
        runningBalanceCents += (qCents + sCents) - eCents;
      }

      if (period.compareTo(startPeriod) >= 0 &&
          period.compareTo(endPeriod) <= 0) {
        rangeQuotaCents += qCents;
        rangeSanctionCents += sCents;
        rangeExpensesCents += eCents;

        monthlyRows.add(
          MonthlyLedgerRow(
            period: period,
            quotaIncomeCents: qCents,
            sanctionIncomeCents: sCents,
            activeExpensesCents: eCents,
            accumulatedBudgetCents: runningBalanceCents,
          ),
        );
      }
    }

    final expensesInRange = parsedExpenses.where((e) {
      return e.billablePeriod.compareTo(startPeriod) >= 0 &&
          e.billablePeriod.compareTo(endPeriod) <= 0;
    }).toList()
      ..sort((a, b) {
        final periodCmp = a.billablePeriod.compareTo(b.billablePeriod);
        if (periodCmp != 0) return periodCmp;
        return a.expenseDateMs.compareTo(b.expenseDateMs);
      });

    final endingAccumulatedCents = monthlyRows.isNotEmpty
        ? monthlyRows.last.accumulatedBudgetCents
        : broughtForwardCents;

    return FinancialLedgerResult(
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      initialBudgetBalanceCents: initialCents,
      initialBalancePeriod: cleanInitialPeriod,
      broughtForwardBalanceCents: broughtForwardCents,
      rangeQuotaIncomeCents: rangeQuotaCents,
      rangeSanctionIncomeCents: rangeSanctionCents,
      rangeActiveExpensesCents: rangeExpensesCents,
      endingAccumulatedBudgetCents: endingAccumulatedCents,
      monthlyRows: monthlyRows,
      expensesInRange: expensesInRange,
    );
  }

  /// Serializes the admin Financial Ledger & Accumulated Budget CSV.
  /// Contains aggregated community inflows, monthly net/cumulative balances,
  /// and itemized expenses (never residential debt matrices or personal data).
  static String buildFinancialLedgerCsv(FinancialLedgerResult ledger) {
    final sb = StringBuffer();

    // Section 1: Summary
    sb.writeln('"SECTION","METRIC","VALUE"');
    sb.writeln('"SUMMARY","Report Period Range",${_quoteCsvText('${ledger.startPeriod} to ${ledger.endPeriod}')}');
    sb.writeln('"SUMMARY","Configured Initial Balance","${_formatCents(ledger.initialBudgetBalanceCents)}"');
    sb.writeln(
      '"SUMMARY","Initial Balance Effective Period",${_quoteCsvText(ledger.initialBalancePeriod ?? 'Prior to all records')}',
    );
    sb.writeln('"SUMMARY","Opening / Brought-Forward Balance","${_formatCents(ledger.broughtForwardBalanceCents)}"');
    sb.writeln('"SUMMARY","Range Maintenance Quotas Income","${_formatCents(ledger.rangeQuotaIncomeCents)}"');
    sb.writeln('"SUMMARY","Range Sanction Fines Income","${_formatCents(ledger.rangeSanctionIncomeCents)}"');
    sb.writeln('"SUMMARY","Range Total Income","${_formatCents(ledger.rangeTotalIncomeCents)}"');
    sb.writeln('"SUMMARY","Range Active Expenses","${_formatCents(ledger.rangeActiveExpensesCents)}"');
    sb.writeln('"SUMMARY","Range Net Balance","${_formatCents(ledger.rangeNetBalanceCents)}"');
    sb.writeln('"SUMMARY","Ending Accumulated Budget","${_formatCents(ledger.endingAccumulatedBudgetCents)}"');
    sb.writeln();

    // Section 2: Monthly Cashflow & Accumulated Budget
    sb.writeln(
      '"MONTHLY CASHFLOW","Period","Maintenance Quotas Income","Sanction Fines Income","Total Income","Active Expenses","Net Period Balance","Accumulated Budget"',
    );
    for (final row in ledger.monthlyRows) {
      sb.writeln(
        '"MONTHLY",${_quoteCsvText(row.period)},"${_formatCents(row.quotaIncomeCents)}","${_formatCents(row.sanctionIncomeCents)}","${_formatCents(row.totalIncomeCents)}","${_formatCents(row.activeExpensesCents)}","${_formatCents(row.netPeriodBalanceCents)}","${_formatCents(row.accumulatedBudgetCents)}"',
      );
    }
    sb.writeln();

    // Section 3: Itemized Expenses Ledger
    sb.writeln(
      '"EXPENSES LEDGER","Expense ID","Billable Period","Expense Date","Product / Service","Category","Vendor","Amount","Status","Void Reason","Recorded By","Product Evidence File","Receipt/Invoice File"',
    );
    for (final exp in ledger.expensesInRange) {
      final expCents = (exp.amount * 100).round();
      sb.writeln(
        '"EXPENSE",${_quoteCsvText(exp.id)},${_quoteCsvText(exp.billablePeriod)},${_quoteCsvText(_formatDateIso(exp.expenseDateMs))},${_quoteCsvText(exp.productOrService)},${_quoteCsvText(exp.category)},${_quoteCsvText(exp.vendorName)},"${_formatCents(expCents)}",${_quoteCsvText(exp.status)},${_quoteCsvText(exp.voidReason ?? '')},${_quoteCsvText(exp.createdByName)},${_quoteCsvText(exp.productEvidence.fileName)},${_quoteCsvText(exp.receiptEvidence.fileName)}',
      );
    }

    return sb.toString();
  }

  /// Formats the short card title representing a ledger's period span (e.g. `'2026-06 – 2026-11'` or `'2026-11'`).
  static String formatTransparencyPeriodTitle(
    String startPeriod,
    String endPeriod,
  ) {
    final start = startPeriod.trim();
    final end = endPeriod.trim();
    if (start.isEmpty) return end;
    if (end.isEmpty || start == end) return start;
    return '$start – $end';
  }

  /// Generates a deterministic Firestore document ID for a published Transparency period span.
  static String buildTransparencyDocId(String startPeriod, String endPeriod) {
    String sanitizeSegment(String raw) =>
        raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final start = sanitizeSegment(startPeriod);
    final end = sanitizeSegment(endPeriod);
    if (end.isEmpty || start == end) {
      return 'financial_summary_$start';
    }
    return 'financial_summary_${start}_to_$end';
  }

  static AppLocalizations _resolveReportLocalizations(String languageCode) {
    final code = languageCode.trim().toLowerCase() == 'es' ? 'es' : 'en';
    return lookupAppLocalizations(Locale(code));
  }

  /// Translates known [ExpenseCategory] slugs into the target language's localized label.
  static String localizeExpenseCategory(
    String rawCategory, {
    required String languageCode,
  }) {
    final l10n = _resolveReportLocalizations(languageCode);
    switch (rawCategory.trim().toLowerCase()) {
      case ExpenseCategory.maintenance:
        return l10n.expenseCategoryMaintenance;
      case ExpenseCategory.gardening:
        return l10n.expenseCategoryGardening;
      case ExpenseCategory.security:
        return l10n.expenseCategorySecurity;
      case ExpenseCategory.utilities:
        return l10n.expenseCategoryUtilities;
      case ExpenseCategory.repairs:
        return l10n.expenseCategoryRepairs;
      case ExpenseCategory.supplies:
        return l10n.expenseCategorySupplies;
      case ExpenseCategory.other:
        return l10n.expenseCategoryOther;
      default:
        return rawCategory;
    }
  }

  /// Generates a privacy-safe Markdown summary for optional Transparency publishing.
  /// Structurally excludes any address-level payment status matrix or resident PII.
  static String buildTransparencyMarkdownReport({
    required String title,
    required FinancialLedgerResult ledger,
    String languageCode = 'en',
    bool useDescriptiveHeading = false,
  }) {
    String cleanMd(String s) => s
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('|', '\\|')
        .trim();

    final l10n = _resolveReportLocalizations(languageCode);
    final cleanTitle = cleanMd(title);
    final headingText = useDescriptiveHeading
        ? cleanMd(l10n.transparencyReportHeading(cleanTitle))
        : cleanTitle;

    final sb = StringBuffer();
    sb.writeln('# $headingText');
    sb.writeln();
    sb.writeln(
      l10n.transparencyPeriodRangeLine(
        '`${ledger.startPeriod}`',
        '`${ledger.endPeriod}`',
      ),
    );
    sb.writeln();
    sb.writeln('## ${l10n.transparencySummarySection}');
    sb.writeln();
    sb.writeln(
      '| ${l10n.transparencyMetricHeader} | ${l10n.transparencyAmountHeader} |',
    );
    sb.writeln('| :--- | ---: |');
    sb.writeln(
      '| ${l10n.openingBalancePreviewLabel} | \$${_formatCents(ledger.broughtForwardBalanceCents)} |',
    );
    sb.writeln(
      '| ${l10n.quotaIncomePreviewLabel} | \$${_formatCents(ledger.rangeQuotaIncomeCents)} |',
    );
    sb.writeln(
      '| ${l10n.sanctionIncomePreviewLabel} | \$${_formatCents(ledger.rangeSanctionIncomeCents)} |',
    );
    sb.writeln(
      '| **${l10n.transparencyTotalIncomeLabel}** | **\$${_formatCents(ledger.rangeTotalIncomeCents)}** |',
    );
    sb.writeln(
      '| ${l10n.expensesPreviewLabel} | -\$${_formatCents(ledger.rangeActiveExpensesCents)} |',
    );
    sb.writeln(
      '| ${l10n.netPeriodBalancePreviewLabel} | \$${_formatCents(ledger.rangeNetBalanceCents)} |',
    );
    sb.writeln(
      '| **${l10n.accumulatedBudgetPreviewLabel}** | **\$${_formatCents(ledger.endingAccumulatedBudgetCents)}** |',
    );
    sb.writeln();
    sb.writeln('## ${l10n.transparencyMonthlyBreakdownSection}');
    sb.writeln();
    sb.writeln(
      '| ${l10n.transparencyColumnPeriod} | ${l10n.transparencyColumnQuotas} | ${l10n.transparencyColumnSanctions} | ${l10n.transparencyColumnTotalIncome} | ${l10n.transparencyColumnExpenses} | ${l10n.transparencyColumnNet} | ${l10n.transparencyColumnAccumulatedBudget} |',
    );
    sb.writeln('| :--- | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final row in ledger.monthlyRows) {
      sb.writeln(
        '| ${row.period} | \$${_formatCents(row.quotaIncomeCents)} | \$${_formatCents(row.sanctionIncomeCents)} | \$${_formatCents(row.totalIncomeCents)} | \$${_formatCents(row.activeExpensesCents)} | \$${_formatCents(row.netPeriodBalanceCents)} | \$${_formatCents(row.accumulatedBudgetCents)} |',
      );
    }

    final activeExpenses =
        ledger.expensesInRange.where((e) => e.isActive).toList();
    sb.writeln();
    sb.writeln('## ${l10n.transparencyActiveExpensesSection}');
    sb.writeln();
    if (activeExpenses.isEmpty) {
      sb.writeln('_${l10n.transparencyNoActiveExpenses}_');
    } else {
      sb.writeln(
        '| ${l10n.transparencyColumnPeriod} | ${l10n.transparencyColumnDate} | ${l10n.transparencyColumnProductService} | ${l10n.transparencyColumnCategory} | ${l10n.transparencyAmountHeader} |',
      );
      sb.writeln('| :--- | :--- | :--- | :--- | ---: |');
      for (final exp in activeExpenses) {
        final expCents = (exp.amount * 100).round();
        final localizedCategory = localizeExpenseCategory(
          exp.category,
          languageCode: languageCode,
        );
        sb.writeln(
          '| ${exp.billablePeriod} | ${_formatDateIso(exp.expenseDateMs)} | ${cleanMd(exp.productOrService)} | ${cleanMd(localizedCategory)} | \$${_formatCents(expCents)} |',
        );
      }
    }

    return sb.toString();
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/services/document_transfer_helper.dart';
import '../../core/services/temp_image_cleanup_service.dart';
import '../../core/widgets/rotatable_image_preview.dart';
import '../../l10n/app_localizations.dart';
import '../payments/payment_service.dart';
import 'admin_bulk_expense_import_screen.dart';
import 'expense_service.dart';
import 'financial_report_calculator.dart';

/// Administrative workspace for recording, filtering, inspecting, and soft-voiding
/// community expenses with mandatory product/service and receipt/invoice evidences.
class AdminExpensesScreen extends StatefulWidget {
  final bool isEmbedded;

  const AdminExpensesScreen({super.key, this.isEmbedded = false});

  @override
  State<AdminExpensesScreen> createState() => _AdminExpensesScreenState();
}

class _AdminExpensesScreenState extends State<AdminExpensesScreen> {
  final ExpenseService _expenseService = ExpenseService();

  String _selectedPeriodFilter = 'all';
  String _selectedStatusFilter = 'active';
  String _selectedCategoryFilter = 'all';

  late final Stream<List<ExpenseRecord>> _expensesStream;
  late final Stream<List<Map<String, dynamic>>> _paymentsStream;
  late final Stream<Map<String, dynamic>?> _settingsStream;

  @override
  void initState() {
    super.initState();
    _expensesStream = _expenseService.streamExpenses();
    _paymentsStream = DatabaseService().streamCollection('payments');
    _settingsStream = DatabaseService().streamDocument('config', 'app_settings');
  }

  void _openRecordExpenseModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RecordExpenseModal(),
    );
  }

  void _openBulkExpenseImport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AdminBulkExpenseImportScreen(),
      ),
    );
  }

  void _openExpenseDetail(ExpenseRecord expense) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminExpenseDetailScreen(expense: expense),
      ),
    );
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
                l10n.expensesTitle,
                style: const TextStyle(fontFamily: AppConfig.fontFamily),
              ),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add_expense_fab'),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart),
        label: Text(l10n.recordExpenseButton),
        onPressed: _openRecordExpenseModal,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _settingsStream,
        builder: (context, settingsSnap) {
          final appSettings = settingsSnap.data ?? const <String, dynamic>{};
          final initialBalance =
              (appSettings['initialBudgetBalance'] as num?)?.toDouble() ?? 0.0;
          final initialBalancePeriod =
              appSettings['initialBalancePeriod']?.toString();
          final timeZone =
              appSettings['timeZone']?.toString() ?? 'America/Mexico_City';

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _paymentsStream,
            builder: (context, paymentsSnap) {
              final payments = paymentsSnap.data ?? const <Map<String, dynamic>>[];

              return StreamBuilder<List<ExpenseRecord>>(
                stream: _expensesStream,
                builder: (context, expensesSnap) {
                  if (expensesSnap.hasError) {
                    return Center(
                      child: Text(l10n.errorPrefix(expensesSnap.error.toString())),
                    );
                  }
                  if (expensesSnap.connectionState == ConnectionState.waiting &&
                      !expensesSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allExpenses = expensesSnap.data ?? const <ExpenseRecord>[];
                  final rawExpenseMaps = allExpenses.map((e) => {
                        'id': e.id,
                        'productOrService': e.productOrService,
                        'amount': e.amount,
                        'billablePeriod': e.billablePeriod,
                        'expenseDate': e.expenseDateMs,
                        'category': e.category,
                        'vendorName': e.vendorName,
                        'notes': e.notes,
                        'status': e.status,
                      }).toList();

                  final now = DateTime.now();
                  final ledger = _computeLiveSummary(
                    payments: payments,
                    rawExpenses: rawExpenseMaps,
                    initialBalance: initialBalance,
                    initialBalancePeriod: initialBalancePeriod,
                    timeZone: timeZone,
                    now: now,
                  );

                  final periodOptions = _collectPeriodOptions(allExpenses, now);
                  final filteredExpenses = allExpenses.where((exp) {
                    if (_selectedStatusFilter != 'all' &&
                        exp.status != _selectedStatusFilter) {
                      return false;
                    }
                    if (_selectedPeriodFilter != 'all' &&
                        exp.billablePeriod != _selectedPeriodFilter) {
                      return false;
                    }
                    if (_selectedCategoryFilter != 'all' &&
                        exp.category != _selectedCategoryFilter) {
                      return false;
                    }
                    return true;
                  }).toList();

                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        children: [
                          _buildBudgetSummaryStrip(context, l10n, ledger),
                          _buildFilterBar(context, l10n, periodOptions),
                          const Divider(height: 1),
                          Expanded(
                            child: filteredExpenses.isEmpty
                                ? _buildEmptyState(l10n)
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      92,
                                    ),
                                    itemCount: filteredExpenses.length,
                                    itemBuilder: (context, index) {
                                      final exp = filteredExpenses[index];
                                      return _ExpenseSummaryCard(
                                        key: ValueKey('expense_card_${exp.id}'),
                                        expense: exp,
                                        onTap: () => _openExpenseDetail(exp),
                                      );
                                    },
                                  ),
                          ),
                        ],
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

  FinancialLedgerResult _computeLiveSummary({
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> rawExpenses,
    required double initialBalance,
    required String? initialBalancePeriod,
    required String timeZone,
    required DateTime now,
  }) {
    final allPeriodKeys = <String>{
      FinancialReportCalculator.formatPeriodKey(now),
      if (initialBalancePeriod != null &&
          FinancialReportCalculator.parsePeriodKey(initialBalancePeriod) !=
              null)
        initialBalancePeriod,
    };

    for (final p in payments) {
      for (final pk in FinancialReportCalculator.extractValidPaymentPeriods(p)) {
        allPeriodKeys.add(pk);
      }
      final fallback = FinancialReportCalculator.resolvePeriodFromTimestamp(
        p['paymentDate'] ?? p['timestamp'],
        timeZone: timeZone,
      );
      if (fallback.isNotEmpty) allPeriodKeys.add(fallback);
    }
    for (final e in rawExpenses) {
      final bp = e['billablePeriod']?.toString() ?? '';
      if (FinancialReportCalculator.parsePeriodKey(bp) != null) {
        allPeriodKeys.add(bp);
      }
    }

    final sorted = allPeriodKeys.toList()..sort();
    final startDt =
        FinancialReportCalculator.parsePeriodKey(sorted.first) ??
        DateTime(now.year, now.month, 1);
    final endDt =
        FinancialReportCalculator.parsePeriodKey(sorted.last) ??
        DateTime(now.year, now.month, 1);

    return FinancialReportCalculator.computeFinancialLedger(
      payments: payments,
      expenses: rawExpenses,
      startMonth: startDt,
      endMonth: endDt,
      initialBudgetBalance: initialBalance,
      initialBalancePeriod: initialBalancePeriod,
      timeZone: timeZone,
    );
  }

  List<String> _collectPeriodOptions(
    List<ExpenseRecord> expenses,
    DateTime now,
  ) {
    final periods = <String>{
      ...PaymentService().generateSelectablePeriods(
        DateTime(now.year - 1, now.month, 1),
        now,
        advanceMonths: 6,
      ),
      for (final exp in expenses)
        if (exp.billablePeriod.isNotEmpty) exp.billablePeriod,
    };
    final list = periods.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  Widget _buildBudgetSummaryStrip(
    BuildContext context,
    AppLocalizations l10n,
    FinancialLedgerResult ledger,
  ) {
    final totalAvailableIncome =
        ledger.initialBudgetBalance + ledger.rangeTotalIncome;
    final budgetPositive = ledger.endingAccumulatedBudget >= 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 680;
          final tiles = [
            _BudgetStatTile(
              key: const ValueKey('expenses_kpi_income'),
              label: l10n.financialSummaryIncomeLabel,
              amount: totalAvailableIncome,
              color: Colors.blue.shade700,
              icon: Icons.trending_up,
            ),
            _BudgetStatTile(
              key: const ValueKey('expenses_kpi_expenses'),
              label: l10n.financialSummaryExpensesLabel,
              amount: ledger.rangeActiveExpenses,
              color: Colors.deepOrange.shade700,
              icon: Icons.shopping_bag_outlined,
            ),
            _BudgetStatTile(
              key: const ValueKey('expenses_kpi_budget'),
              label: l10n.financialSummaryBudgetLabel,
              amount: ledger.endingAccumulatedBudget,
              color: budgetPositive
                  ? AppConfig.secondaryColor
                  : AppConfig.dangerColor,
              icon: Icons.account_balance_wallet_outlined,
            ),
          ];

          if (isWide) {
            return Row(
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 12),
                Expanded(child: tiles[1]),
                const SizedBox(width: 12),
                Expanded(child: tiles[2]),
              ],
            );
          }

          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: 10),
                  Expanded(child: tiles[1]),
                ],
              ),
              const SizedBox(height: 10),
              tiles[2],
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    AppLocalizations l10n,
    List<String> periodOptions,
  ) {
    final bulkImportButton = OutlinedButton.icon(
      key: const ValueKey('bulk_import_expenses_button'),
      onPressed: _openBulkExpenseImport,
      icon: const Icon(Icons.upload_file, size: 18),
      label: Text(l10n.bulkExpenseImportButton),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppConfig.primaryColor,
        side: const BorderSide(color: AppConfig.primaryColor),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );

    final statusChips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStatusChip('active', l10n.expenseStatusActive),
          const SizedBox(width: 8),
          _buildStatusChip('voided', l10n.expenseStatusVoided),
          const SizedBox(width: 8),
          _buildStatusChip('all', l10n.filterAll),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 560) {
                return Row(
                  children: [
                    Expanded(child: statusChips),
                    const SizedBox(width: 12),
                    bulkImportButton,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  statusChips,
                  const SizedBox(height: 8),
                  bulkImportButton,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final periodDropdown = DropdownButtonFormField<String>(
                key: ValueKey('expense_filter_period_$_selectedPeriodFilter'),
                initialValue: (_selectedPeriodFilter == 'all' ||
                        periodOptions.contains(_selectedPeriodFilter))
                    ? _selectedPeriodFilter
                    : 'all',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.expenseBillablePeriodLabel,
                  prefixIcon: const Icon(
                    Icons.calendar_month_outlined,
                    color: AppConfig.primaryColor,
                    size: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text(l10n.expenseFilterAllPeriods),
                  ),
                  for (final period in periodOptions)
                    DropdownMenuItem(
                      value: period,
                      child: Text(formatExpensePeriodLabel(context, period)),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedPeriodFilter = val);
                  }
                },
              );

              final categoryDropdown = DropdownButtonFormField<String>(
                key: ValueKey(
                  'expense_filter_category_$_selectedCategoryFilter',
                ),
                initialValue: _selectedCategoryFilter,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.expenseCategoryLabel,
                  prefixIcon: const Icon(
                    Icons.category_outlined,
                    color: AppConfig.primaryColor,
                    size: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text(l10n.expenseFilterAllCategories),
                  ),
                  for (final cat in ExpenseCategory.all)
                    DropdownMenuItem(
                      value: cat,
                      child: Text(localizedExpenseCategory(l10n, cat)),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedCategoryFilter = val);
                  }
                },
              );

              if (constraints.maxWidth >= 560) {
                return Row(
                  children: [
                    Expanded(child: periodDropdown),
                    const SizedBox(width: 12),
                    Expanded(child: categoryDropdown),
                  ],
                );
              }
              return Column(
                children: [
                  periodDropdown,
                  const SizedBox(height: 10),
                  categoryDropdown,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String keyVal, String label) {
    final selected = _selectedStatusFilter == keyVal;
    return FilterChip(
      selected: selected,
      label: Text(label),
      selectedColor: AppConfig.primaryColor.withValues(alpha: 0.16),
      checkmarkColor: AppConfig.primaryColor,
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? AppConfig.primaryColor : AppConfig.textColor,
      ),
      onSelected: (_) => setState(() => _selectedStatusFilter = keyVal),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              l10n.noExpensesFound,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontFamily: AppConfig.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats `'YYYY-MM'` into a localized readable month-year label (e.g., `Nov 2026`).
String formatExpensePeriodLabel(BuildContext context, String period) {
  final parsed = FinancialReportCalculator.parsePeriodKey(period);
  if (parsed == null) return period;
  final locale = Localizations.localeOf(context).languageCode;
  const enMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const esMonths = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];
  final label = locale.startsWith('es')
      ? esMonths[parsed.month - 1]
      : enMonths[parsed.month - 1];
  return '$label ${parsed.year} ($period)';
}

/// Maps normalized category slug to localized display label.
String localizedExpenseCategory(AppLocalizations l10n, String category) {
  switch (category.toLowerCase()) {
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
    default:
      return l10n.expenseCategoryOther;
  }
}

String _formatDateDisplay(int millis) {
  if (millis <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

class _BudgetStatTile extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _BudgetStatTile({
    super.key,
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final prefix = amount < 0 ? '-\$' : '\$';
    final absFormatted = amount.abs().toStringAsFixed(2);

    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$prefix$absFormatted',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontFamily: AppConfig.fontFamily,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontFamily: AppConfig.fontFamily,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseSummaryCard extends StatelessWidget {
  final ExpenseRecord expense;
  final VoidCallback onTap;

  const _ExpenseSummaryCard({
    super.key,
    required this.expense,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isVoided = expense.isVoided;
    final statusColor = isVoided ? AppConfig.dangerColor : AppConfig.secondaryColor;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isVoided
              ? AppConfig.dangerColor.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: (isVoided ? Colors.grey : AppConfig.primaryColor)
                    .withValues(alpha: 0.12),
                child: Icon(
                  Icons.receipt_long,
                  color: isVoided ? Colors.grey : AppConfig.primaryColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.productOrService,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        decoration:
                            isVoided ? TextDecoration.lineThrough : null,
                        color: isVoided ? Colors.grey.shade600 : AppConfig.textColor,
                        fontFamily: AppConfig.fontFamily,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MetaChip(
                          icon: Icons.calendar_month,
                          label: expense.billablePeriod,
                        ),
                        _MetaChip(
                          icon: Icons.category_outlined,
                          label: localizedExpenseCategory(l10n, expense.category),
                        ),
                        _MetaChip(
                          icon: Icons.event,
                          label: _formatDateDisplay(expense.expenseDateMs),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isVoided
                                ? l10n.expenseStatusVoided
                                : l10n.expenseStatusActive,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                        if (expense.isBulkImported)
                          _MetaChip(
                            icon: Icons.table_chart_outlined,
                            label: l10n.expenseBulkCsvChip,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '-\$${expense.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      decoration: isVoided ? TextDecoration.lineThrough : null,
                      color: isVoided
                          ? Colors.grey.shade500
                          : Colors.deepOrange.shade700,
                      fontFamily: AppConfig.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (expense.hasProductEvidence) ...[
                        const Icon(Icons.photo_camera_outlined,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                      ],
                      if (expense.hasReceiptEvidence) ...[
                        Icon(
                          expense.receiptEvidence.isImage
                              ? Icons.image_outlined
                              : Icons.picture_as_pdf_outlined,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (!expense.hasAnyEvidence) ...[
                        const Icon(Icons.table_chart_outlined,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                      ],
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: Colors.grey.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }
}

/// Detailed expense inspection screen displaying metadata, rotatable product photo,
/// rotatable or downloadable receipt/invoice evidence, and audit-safe voiding.
class AdminExpenseDetailScreen extends StatefulWidget {
  final ExpenseRecord expense;

  const AdminExpenseDetailScreen({super.key, required this.expense});

  @override
  State<AdminExpenseDetailScreen> createState() =>
      _AdminExpenseDetailScreenState();
}

class _AdminExpenseDetailScreenState extends State<AdminExpenseDetailScreen> {
  final ExpenseService _expenseService = ExpenseService();
  late ExpenseRecord _expense;
  bool _isVoiding = false;

  @override
  void initState() {
    super.initState();
    _expense = widget.expense;
  }

  Future<void> _promptVoidExpense() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmedReason = await showDialog<String>(
      context: context,
      builder: (_) => const _VoidExpenseDialog(),
    );

    if (confirmedReason == null || !mounted) return;
    setState(() => _isVoiding = true);

    try {
      await _expenseService.voidExpense(
        expenseId: _expense.id,
        voidReason: confirmedReason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.expenseVoidedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVoiding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(
          _expense.productOrService,
          style: const TextStyle(fontFamily: AppConfig.fontFamily),
        ),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 760;

          final metadataCard = _buildMetadataCard(context, l10n);
          final evidencesPanel = _buildEvidencesPanel(context, l10n);

          if (isWide) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(child: metadataCard),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 7,
                    child: SingleChildScrollView(child: evidencesPanel),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                metadataCard,
                const SizedBox(height: 16),
                evidencesPanel,
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetadataCard(BuildContext context, AppLocalizations l10n) {
    final isVoided = _expense.isVoided;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isVoided) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConfig.dangerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppConfig.dangerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.expenseVoidedBanner(_expense.voidReason ?? ''),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppConfig.dangerColor,
                      ),
                    ),
                    if ((_expense.voidedByName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${l10n.expenseVoidedByLabel}: ${_expense.voidedByName} (${_formatDateDisplay(_expense.voidedAtMs ?? 0)})',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(
              _expense.productOrService,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppConfig.primaryColor,
                fontFamily: AppConfig.fontFamily,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '\$${_expense.amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                decoration: isVoided ? TextDecoration.lineThrough : null,
                color: isVoided
                    ? Colors.grey.shade500
                    : Colors.deepOrange.shade700,
              ),
            ),
            const Divider(height: 24),
            _DetailRow(
              label: l10n.expenseBillablePeriodLabel,
              value: formatExpensePeriodLabel(context, _expense.billablePeriod),
            ),
            _DetailRow(
              label: l10n.expenseDateLabel,
              value: _formatDateDisplay(_expense.expenseDateMs),
            ),
            _DetailRow(
              label: l10n.expenseCategoryLabel,
              value: localizedExpenseCategory(l10n, _expense.category),
            ),
            if (_expense.vendorName.isNotEmpty)
              _DetailRow(
                label: l10n.expenseVendorLabel,
                value: _expense.vendorName,
              ),
            if (_expense.createdByName.isNotEmpty)
              _DetailRow(
                label: l10n.expenseRecordedByLabel,
                value: _expense.createdByName,
              ),
            if (_expense.isBulkImported)
              _DetailRow(
                label: l10n.expenseSourceLabel,
                value: l10n.expenseSourceBulkCsv,
              ),
            if (_expense.notes.isNotEmpty)
              _DetailRow(
                label: l10n.expenseNotesLabel,
                value: _expense.notes,
              ),
            if (_expense.isActive) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const ValueKey('void_expense_button'),
                onPressed: _isVoiding ? null : _promptVoidExpense,
                icon: _isVoiding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.block, color: AppConfig.dangerColor),
                label: Text(
                  l10n.expenseVoidButton,
                  style: const TextStyle(color: AppConfig.dangerColor),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppConfig.dangerColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEvidencesPanel(BuildContext context, AppLocalizations l10n) {
    final prodEv = _expense.productEvidence;
    final recEv = _expense.receiptEvidence;

    if (!_expense.hasAnyEvidence) {
      return Card(
        key: const ValueKey('expense_bulk_no_evidence_card'),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppConfig.primaryColor.withValues(alpha: 0.1),
                child: const Icon(
                  Icons.table_chart_outlined,
                  color: AppConfig.primaryColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.expenseBulkNoEvidenceTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppConfig.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.expenseBulkNoEvidenceBody,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prodEv.url.isNotEmpty) ...[
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.expenseProductEvidenceLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppConfig.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  RotatableImagePreview(
                    imageUrl: prodEv.url,
                    dialogTitle: l10n.expenseProductEvidenceLabel,
                    height: 220,
                    thumbnailKey: const ValueKey('expense_product_thumbnail'),
                    rotateButtonKey:
                        const ValueKey('expense_product_rotate_btn'),
                    fullscreenButtonKey:
                        const ValueKey('expense_product_fullscreen_btn'),
                  ),
                ],
              ),
            ),
          ),
          if (recEv.url.isNotEmpty) const SizedBox(height: 16),
        ],
        if (recEv.url.isNotEmpty)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.expenseReceiptEvidenceLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppConfig.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (recEv.isImage)
                    RotatableImagePreview(
                      imageUrl: recEv.url,
                      dialogTitle: l10n.expenseReceiptEvidenceLabel,
                      height: 220,
                      thumbnailKey: const ValueKey('expense_receipt_thumbnail'),
                      rotateButtonKey:
                          const ValueKey('expense_receipt_rotate_btn'),
                      fullscreenButtonKey:
                          const ValueKey('expense_receipt_fullscreen_btn'),
                    )
                  else
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      leading: const Icon(
                        Icons.picture_as_pdf,
                        color: Colors.redAccent,
                        size: 32,
                      ),
                      title: Text(
                        recEv.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        DocumentTransferHelper.formatFileSize(recEv.fileSize),
                      ),
                      trailing: ElevatedButton.icon(
                        key: const ValueKey('expense_receipt_download_btn'),
                        onPressed: () {
                          DocumentTransferHelper.openOrDownloadDocument(
                            context: context,
                            cacheId: 'expense_${_expense.id}_receipt',
                            url: recEv.url,
                            fileName: recEv.fileName,
                            title: l10n.expenseReceiptEvidenceLabel,
                          );
                        },
                        icon: const Icon(Icons.download, size: 18),
                        label: Text(l10n.downloadFacilityDocumentButton),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppConfig.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordExpenseModal extends StatefulWidget {
  const _RecordExpenseModal();

  @override
  State<_RecordExpenseModal> createState() => _RecordExpenseModalState();
}

class _RecordExpenseModalState extends State<_RecordExpenseModal> {
  final ExpenseService _expenseService = ExpenseService();
  final TextEditingController _productController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _vendorController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ValueNotifier<int> _evidenceRevision = ValueNotifier<int>(0);

  late String _billablePeriod;
  late final List<String> _candidatePeriods;
  DateTime _expenseDate = DateTime.now();
  String _category = ExpenseCategory.maintenance;
  PickedDocumentData? _productEvidence;
  PickedDocumentData? _receiptEvidence;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _billablePeriod = FinancialReportCalculator.formatPeriodKey(now);
    _candidatePeriods = PaymentService().generateSelectablePeriods(
      DateTime(now.year - 2, now.month, 1),
      now,
      advanceMonths: 12,
    ).reversed.toList();
  }

  @override
  void dispose() {
    unawaited(
      TempImageCleanupService.deleteTempXFile(_productEvidence?.tempCameraFile),
    );
    unawaited(
      TempImageCleanupService.deleteTempXFile(_receiptEvidence?.tempCameraFile),
    );
    _productController.dispose();
    _amountController.dispose();
    _vendorController.dispose();
    _notesController.dispose();
    _evidenceRevision.dispose();
    super.dispose();
  }

  Future<void> _selectExpenseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _expenseDate = picked);
    }
  }

  Future<void> _pickEvidenceFile({
    required bool isProductPhoto,
    required bool fromCamera,
  }) async {
    final Future<PickedDocumentData?> pickFuture;
    if (fromCamera) {
      pickFuture = DocumentTransferHelper.captureDocumentPhoto(context);
    } else if (isProductPhoto) {
      pickFuture = DocumentTransferHelper.pickAllowedImage(context);
    } else {
      pickFuture = DocumentTransferHelper.pickExpenseReceipt(context);
    }
    final picked = await pickFuture;
    if (picked == null) return;
    if (!mounted) {
      unawaited(TempImageCleanupService.deleteTempXFile(picked.tempCameraFile));
      return;
    }
    final previous = isProductPhoto
        ? _productEvidence?.tempCameraFile
        : _receiptEvidence?.tempCameraFile;
    setState(() {
      if (isProductPhoto) {
        _productEvidence = picked;
      } else {
        _receiptEvidence = picked;
      }
    });
    _evidenceRevision.value++;
    if (previous != null && previous.path != picked.tempCameraFile?.path) {
      unawaited(TempImageCleanupService.deleteTempXFile(previous));
    }
  }

  List<String> _getMissingFields(AppLocalizations l10n) {
    final missing = <String>[];
    if (_productController.text.trim().isEmpty) {
      missing.add(l10n.expenseMissingProductService);
    }
    final amt = double.tryParse(_amountController.text.trim());
    if (amt == null || !amt.isFinite || amt <= 0) {
      missing.add(l10n.expenseMissingAmount);
    }
    if (_billablePeriod.trim().isEmpty) {
      missing.add(l10n.expenseMissingPeriod);
    }
    if (_productEvidence == null) {
      missing.add(l10n.expenseMissingProductEvidence);
    }
    if (_receiptEvidence == null) {
      missing.add(l10n.expenseMissingReceiptEvidence);
    }
    return missing;
  }

  Future<void> _submitExpense() async {
    final l10n = AppLocalizations.of(context)!;
    final missing = _getMissingFields(l10n);
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.expenseMissingFieldsWarning),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final adminUid = AuthService().currentUser?.uid ?? '';
    if (adminUid.isEmpty) return;

    final productFile = _productEvidence!;
    final receiptFile = _receiptEvidence!;
    final amount = double.parse(_amountController.text.trim());

    setState(() => _isSaving = true);
    try {
      await _expenseService.recordExpense(
        adminUid: adminUid,
        productOrService: _productController.text.trim(),
        amount: amount,
        billablePeriod: _billablePeriod,
        expenseDate: _expenseDate,
        category: _category,
        productEvidenceFile: productFile,
        receiptEvidenceFile: receiptFile,
        vendorName: _vendorController.text.trim(),
        notes: _notesController.text.trim(),
      );
      // Ownership of temp files handled by ExpenseService.recordExpense
      _productEvidence = null;
      _receiptEvidence = null;

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.expenseRecordedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          margin: const EdgeInsets.only(top: 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.recordExpenseButton,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppConfig.primaryColor,
                          fontFamily: AppConfig.fontFamily,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 12),

                // Product / Service
                TextFormField(
                  key: const ValueKey('expense_product_field'),
                  controller: _productController,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: '${l10n.expenseProductServiceLabel} *',
                    hintText: l10n.expenseProductServiceHint,
                    prefixIcon: const Icon(
                      Icons.shopping_bag_outlined,
                      color: AppConfig.primaryColor,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),

                // Amount & Billable Period
                LayoutBuilder(
                  builder: (context, constraints) {
                    final amountField = TextFormField(
                      key: const ValueKey('expense_amount_field'),
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '${l10n.expenseAmountLabel} *',
                        prefixIcon: const Icon(
                          Icons.attach_money,
                          color: AppConfig.primaryColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );

                    final periodDropdown = DropdownButtonFormField<String>(
                      key: ValueKey('expense_period_dropdown_$_billablePeriod'),
                      initialValue: _candidatePeriods.contains(_billablePeriod)
                          ? _billablePeriod
                          : _candidatePeriods.first,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: '${l10n.expenseBillablePeriodLabel} *',
                        prefixIcon: const Icon(
                          Icons.calendar_month_outlined,
                          color: AppConfig.primaryColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: _candidatePeriods.map((period) {
                        return DropdownMenuItem(
                          value: period,
                          child: Text(
                            formatExpensePeriodLabel(context, period),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _billablePeriod = val);
                        }
                      },
                    );

                    if (constraints.maxWidth >= 500) {
                      return Row(
                        children: [
                          Expanded(flex: 2, child: amountField),
                          const SizedBox(width: 12),
                          Expanded(flex: 3, child: periodDropdown),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        amountField,
                        const SizedBox(height: 14),
                        periodDropdown,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),

                // Expense Date & Category
                LayoutBuilder(
                  builder: (context, constraints) {
                    final datePickerField = InkWell(
                      onTap: _selectExpenseDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: l10n.expenseDateLabel,
                          prefixIcon: const Icon(
                            Icons.event,
                            color: AppConfig.primaryColor,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          _formatDateDisplay(
                            _expenseDate.millisecondsSinceEpoch,
                          ),
                        ),
                      ),
                    );

                    final categoryField = DropdownButtonFormField<String>(
                      key: ValueKey('expense_category_dropdown_$_category'),
                      initialValue: _category,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.expenseCategoryLabel,
                        prefixIcon: const Icon(
                          Icons.category_outlined,
                          color: AppConfig.primaryColor,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: ExpenseCategory.all.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(localizedExpenseCategory(l10n, cat)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _category = val);
                        }
                      },
                    );

                    if (constraints.maxWidth >= 500) {
                      return Row(
                        children: [
                          Expanded(child: datePickerField),
                          const SizedBox(width: 12),
                          Expanded(child: categoryField),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        datePickerField,
                        const SizedBox(height: 14),
                        categoryField,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Product/Service Photo Evidence
                _EvidencePickerCard(
                  cardKey: const ValueKey('expense_product_evidence_card'),
                  title: '${l10n.expenseProductEvidenceLabel} *',
                  pickedData: _productEvidence,
                  cameraButtonKey:
                      const ValueKey('expense_product_camera_button'),
                  fileButtonKey: const ValueKey('expense_product_pick_button'),
                  cameraLabel: l10n.expenseTakePhotoButton,
                  fileLabel: l10n.expenseChoosePhotoButton,
                  onPickCamera: () => _pickEvidenceFile(
                    isProductPhoto: true,
                    fromCamera: true,
                  ),
                  onPickFile: () => _pickEvidenceFile(
                    isProductPhoto: true,
                    fromCamera: false,
                  ),
                ),
                const SizedBox(height: 14),

                // Receipt/Invoice Evidence (Photo or PDF)
                _EvidencePickerCard(
                  cardKey: const ValueKey('expense_receipt_evidence_card'),
                  title: '${l10n.expenseReceiptEvidenceLabel} *',
                  pickedData: _receiptEvidence,
                  cameraButtonKey:
                      const ValueKey('expense_receipt_camera_button'),
                  fileButtonKey: const ValueKey('expense_receipt_pick_button'),
                  cameraLabel: l10n.expenseTakePhotoButton,
                  fileLabel: l10n.expenseChooseFileOrPhotoButton,
                  onPickCamera: () => _pickEvidenceFile(
                    isProductPhoto: false,
                    fromCamera: true,
                  ),
                  onPickFile: () => _pickEvidenceFile(
                    isProductPhoto: false,
                    fromCamera: false,
                  ),
                ),
                const SizedBox(height: 14),

                // Optional Vendor & Notes
                TextFormField(
                  key: const ValueKey('expense_vendor_field'),
                  controller: _vendorController,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: l10n.expenseVendorLabel,
                    hintText: l10n.expenseVendorHint,
                    prefixIcon: const Icon(
                      Icons.storefront_outlined,
                      color: AppConfig.primaryColor,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('expense_notes_field'),
                  controller: _notesController,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: l10n.expenseNotesLabel,
                    hintText: l10n.expenseNotesHint,
                    prefixIcon: const Icon(
                      Icons.notes_outlined,
                      color: AppConfig.primaryColor,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),

                // Missing fields banner
                ListenableBuilder(
                  listenable: Listenable.merge([
                    _productController,
                    _amountController,
                    _evidenceRevision,
                  ]),
                  builder: (context, _) {
                    final missing = _getMissingFields(l10n);
                    if (missing.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in missing)
                            Text(
                              item,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.orange.shade900,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),

                ElevatedButton.icon(
                  key: const ValueKey('submit_expense_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isSaving ? null : _submitExpense,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(l10n.save),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EvidencePickerCard extends StatelessWidget {
  final Key cardKey;
  final String title;
  final PickedDocumentData? pickedData;
  final Key cameraButtonKey;
  final Key fileButtonKey;
  final String cameraLabel;
  final String fileLabel;
  final VoidCallback onPickCamera;
  final VoidCallback onPickFile;

  const _EvidencePickerCard({
    required this.cardKey,
    required this.title,
    required this.pickedData,
    required this.cameraButtonKey,
    required this.fileButtonKey,
    required this.cameraLabel,
    required this.fileLabel,
    required this.onPickCamera,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasFile = pickedData != null;
    final isImage = hasFile &&
        DocumentTransferHelper.imageExtensions
            .contains(pickedData!.extension.toLowerCase());

    return Container(
      key: cardKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasFile
            ? AppConfig.secondaryColor.withValues(alpha: 0.05)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasFile ? AppConfig.secondaryColor : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13.5,
              color: AppConfig.textColor,
            ),
          ),
          const SizedBox(height: 10),
          if (hasFile) ...[
            Row(
              children: [
                if (isImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      pickedData!.bytes,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf,
                      color: Colors.redAccent,
                      size: 30,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.expenseEvidenceSelected(pickedData!.sanitizedFileName),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DocumentTransferHelper.formatFileSize(
                          pickedData!.fileSize,
                        ),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: cameraButtonKey,
                onPressed: onPickCamera,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: Text(cameraLabel),
              ),
              OutlinedButton.icon(
                key: fileButtonKey,
                onPressed: onPickFile,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(fileLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoidExpenseDialog extends StatefulWidget {
  const _VoidExpenseDialog();

  @override
  State<_VoidExpenseDialog> createState() => _VoidExpenseDialogState();
}

class _VoidExpenseDialogState extends State<_VoidExpenseDialog> {
  final TextEditingController _reasonController = TextEditingController();
  String? _inlineError;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.expenseVoidDialogTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.expenseVoidAuditNotice,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('void_expense_reason_field'),
              controller: _reasonController,
              maxLines: 2,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.expenseVoidReasonLabel,
                hintText: l10n.expenseVoidReasonHint,
                errorText: _inlineError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
          key: const ValueKey('confirm_void_expense_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppConfig.dangerColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final text = _reasonController.text.trim();
            if (text.length < 3) {
              setState(() => _inlineError = l10n.expenseVoidReasonHint);
              return;
            }
            Navigator.of(context).pop(text);
          },
          child: Text(l10n.expenseVoidButton),
        ),
      ],
    );
  }
}

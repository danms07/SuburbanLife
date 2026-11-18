import 'package:flutter_test/flutter_test.dart';
import 'package:suburban_life/features/admin/financial_report_calculator.dart';

void main() {
  group('FinancialReportCalculator - Accounting & Cumulative Budget', () {
    test('allocates multi-period quota amounts in exact integer cents, includes approved sanctions, and ignores pending/rejected', () {
      final payments = [
        {
          'id': 'p_multi',
          'concept': 'monthly quota',
          'status': 'approved',
          'amount': 100.00,
          'periods': ['2026-09', '2026-10', '2026-11'],
        },
        {
          'id': 'p_pending',
          'concept': 'monthly quota',
          'status': 'pending',
          'amount': 500.00,
          'periods': ['2026-10'],
        },
        {
          'id': 'p_rejected',
          'concept': 'monthly quota',
          'status': 'rejected',
          'amount': 500.00,
          'periods': ['2026-11'],
        },
        {
          'id': 'p_sanction',
          'concept': 'sanction',
          'status': 'approved',
          'amount': 250.50,
          'periods': ['Sanction'],
          'paymentDate': DateTime.utc(2026, 10, 15, 18, 0).millisecondsSinceEpoch,
        },
      ];

      final expenses = [
        {
          'id': 'exp_1',
          'productOrService': 'Gardening service',
          'amount': 40.00,
          'billablePeriod': '2026-10',
          'expenseDate': DateTime.utc(2026, 10, 20).millisecondsSinceEpoch,
          'category': 'gardening',
          'status': 'active',
        },
        {
          'id': 'exp_voided',
          'productOrService': 'Duplicate invoice',
          'amount': 999.00,
          'billablePeriod': '2026-10',
          'expenseDate': DateTime.utc(2026, 10, 21).millisecondsSinceEpoch,
          'category': 'other',
          'status': 'voided',
          'voidReason': 'Entered twice',
        },
      ];

      final result = FinancialReportCalculator.computeFinancialLedger(
        payments: payments,
        expenses: expenses,
        startMonth: DateTime(2026, 10, 1),
        endMonth: DateTime(2026, 11, 1),
        initialBudgetBalance: 1000.00,
        timeZone: 'America/Mexico_City',
      );

      // 2026-09 had 33.33 quota income -> broughtForward = 1000.00 + 33.33 = 1033.33
      expect(result.broughtForwardBalanceCents, equals(103333));

      // Oct 2026: quota 33.33 + sanction 250.50 - active expense 40.00 = +243.83 -> 1277.16
      final octRow = result.monthlyRows[0];
      expect(octRow.period, equals('2026-10'));
      expect(octRow.quotaIncomeCents, equals(3333));
      expect(octRow.sanctionIncomeCents, equals(25050));
      expect(octRow.activeExpensesCents, equals(4000));
      expect(octRow.accumulatedBudgetCents, equals(127716));

      // Nov 2026: quota remainder 33.34 -> 1277.16 + 33.34 = 1310.50
      final novRow = result.monthlyRows[1];
      expect(novRow.period, equals('2026-11'));
      expect(novRow.quotaIncomeCents, equals(3334));
      expect(novRow.accumulatedBudgetCents, equals(131050));

      // Total quota across Sep+Oct+Nov == exact 100.00
      expect(
        3333 + result.rangeQuotaIncomeCents,
        equals(10000),
      );
      expect(result.endingAccumulatedBudgetCents, equals(131050));
    });

    test('respects initialBalancePeriod cutoff to avoid double-counting prior backfilled payments', () {
      final payments = [
        {
          'id': 'p_old',
          'concept': 'monthly quota',
          'status': 'approved',
          'amount': 800.00,
          'periods': ['2025-12'],
        },
        {
          'id': 'p_jan',
          'concept': 'monthly quota',
          'status': 'paid',
          'amount': 500.00,
          'periods': ['2026-01'],
        },
      ];
      final expenses = [
        {
          'id': 'exp_old',
          'productOrService': 'Old repair',
          'amount': 200.00,
          'billablePeriod': '2025-12',
          'status': 'active',
        },
        {
          'id': 'exp_jan',
          'productOrService': 'Gate lock',
          'amount': 150.00,
          'billablePeriod': '2026-01',
          'status': 'active',
        },
      ];

      final result = FinancialReportCalculator.computeFinancialLedger(
        payments: payments,
        expenses: expenses,
        startMonth: DateTime(2026, 1, 1),
        endMonth: DateTime(2026, 1, 1),
        initialBudgetBalance: 5000.00,
        initialBalancePeriod: '2026-01',
      );

      // Old 2025-12 entries do not alter the 2026-01 opening balance of 5000.00
      expect(result.broughtForwardBalanceCents, equals(500000));
      // Jan: 5000 + 500 - 150 = 5350.00
      expect(result.endingAccumulatedBudgetCents, equals(535000));
    });
  });

  group('FinancialReportCalculator - CSV Injection & Privacy Guardrails', () {
    test('neutralizes spreadsheet formula injection prefixes in CSV ledger output', () {
      expect(
        FinancialReportCalculator.sanitizeCsvTextCell('=CMD("calc")'),
        equals("'=CMD(\"\"calc\"\")"),
      );
      expect(
        FinancialReportCalculator.sanitizeCsvTextCell('+1+1'),
        equals("'+1+1"),
      );
      expect(
        FinancialReportCalculator.sanitizeCsvTextCell(' -2+3'),
        equals("' -2+3"),
      );
      expect(
        FinancialReportCalculator.sanitizeCsvTextCell('@SUM(A1:A2)'),
        equals("'@SUM(A1:A2)"),
      );

      final ledger = FinancialReportCalculator.computeFinancialLedger(
        payments: const [],
        expenses: [
          {
            'id': 'exp_inj',
            'productOrService': '=HYPERLINK("http://evil.test","Click")',
            'amount': 120.00,
            'billablePeriod': '2026-11',
            'expenseDate': DateTime.utc(2026, 11, 5).millisecondsSinceEpoch,
            'category': 'other',
            'vendorName': '+EvilVendor',
            'status': 'active',
            'createdByName': '@Admin',
            'productEvidence': {'fileName': 'p.jpg'},
            'receiptEvidence': {'fileName': 'r.pdf'},
          },
        ],
        startMonth: DateTime(2026, 11, 1),
        endMonth: DateTime(2026, 11, 1),
      );

      final csv = FinancialReportCalculator.buildFinancialLedgerCsv(ledger);
      expect(csv, contains("\"'=HYPERLINK"));
      expect(csv, contains("\"'+EvilVendor\""));
      expect(csv, contains("\"'@Admin\""));
    });

    test('Transparency Markdown report includes only aggregated totals & active expenses and never exposes address statuses', () {
      final payments = [
        {
          'id': 'p1',
          'concept': 'monthly quota',
          'status': 'approved',
          'amount': 1500.00,
          'periods': ['2026-11'],
          'streetName': 'Avenida Privada Secreta',
          'number': 999,
        },
      ];
      final expenses = [
        {
          'id': 'exp_active',
          'productOrService': 'Common pool pump service',
          'amount': 450.00,
          'billablePeriod': '2026-11',
          'expenseDate': DateTime.utc(2026, 11, 10).millisecondsSinceEpoch,
          'category': 'maintenance',
          'status': 'active',
        },
        {
          'id': 'exp_void',
          'productOrService': 'Mistaken entry should be hidden',
          'amount': 999.00,
          'billablePeriod': '2026-11',
          'expenseDate': DateTime.utc(2026, 11, 11).millisecondsSinceEpoch,
          'category': 'other',
          'status': 'voided',
          'voidReason': 'Mistake',
        },
      ];

      final ledger = FinancialReportCalculator.computeFinancialLedger(
        payments: payments,
        expenses: expenses,
        startMonth: DateTime(2026, 11, 1),
        endMonth: DateTime(2026, 11, 1),
      );

      final md = FinancialReportCalculator.buildTransparencyMarkdownReport(
        title: 'November 2026 Budget',
        ledger: ledger,
      );

      expect(md, contains('# November 2026 Budget'));
      expect(md, contains('\$1500.00'));
      expect(md, contains('\$450.00'));
      expect(md, contains('\$1050.00'));
      expect(md, contains('Common pool pump service'));
      expect(md, isNot(contains('Mistaken entry should be hidden')));
      expect(md, isNot(contains('Avenida Privada Secreta')));
      expect(md, isNot(contains('past due')));
    });
  });

  group('FinancialReportCalculator - Bilingual Transparency Helpers', () {
    test('formatTransparencyPeriodTitle and buildTransparencyDocId format single and multi-month spans deterministically', () {
      expect(
        FinancialReportCalculator.formatTransparencyPeriodTitle('2026-06', '2026-11'),
        equals('2026-06 – 2026-11'),
      );
      expect(
        FinancialReportCalculator.formatTransparencyPeriodTitle('2026-11', '2026-11'),
        equals('2026-11'),
      );

      expect(
        FinancialReportCalculator.buildTransparencyDocId('2026-06', '2026-11'),
        equals('financial_summary_2026-06_to_2026-11'),
      );
      expect(
        FinancialReportCalculator.buildTransparencyDocId('2026-11', '2026-11'),
        equals('financial_summary_2026-11'),
      );
    });

    test('localizeExpenseCategory translates all known slugs into English and Spanish and preserves unknown slugs', () {
      const slugs = [
        'maintenance',
        'gardening',
        'security',
        'utilities',
        'repairs',
        'supplies',
        'other',
      ];
      for (final slug in slugs) {
        final en = FinancialReportCalculator.localizeExpenseCategory(
          slug,
          languageCode: 'en',
        );
        final es = FinancialReportCalculator.localizeExpenseCategory(
          slug,
          languageCode: 'es',
        );
        expect(en, isNotEmpty);
        expect(es, isNotEmpty);
        expect(en.toLowerCase(), isNot(equals(slug == 'other' ? '' : '')));
      }

      expect(
        FinancialReportCalculator.localizeExpenseCategory('maintenance', languageCode: 'es'),
        equals('Mantenimiento'),
      );
      expect(
        FinancialReportCalculator.localizeExpenseCategory('maintenance', languageCode: 'en'),
        equals('Maintenance'),
      );
      expect(
        FinancialReportCalculator.localizeExpenseCategory('custom_category', languageCode: 'es'),
        equals('custom_category'),
      );
    });

    test('buildTransparencyMarkdownReport renders full Spanish & English documents with descriptive headings and zero PII', () {
      final ledger = FinancialReportCalculator.computeFinancialLedger(
        payments: [
          {
            'id': 'p1',
            'concept': 'monthly quota',
            'status': 'approved',
            'amount': 2000.00,
            'periods': ['2026-06', '2026-07'],
            'streetName': 'Privada Confidencial',
            'number': 12,
          },
        ],
        expenses: [
          {
            'id': 'exp_1',
            'productOrService': 'Guardhouse gate motor',
            'amount': 350.00,
            'billablePeriod': '2026-06',
            'expenseDate': DateTime.utc(2026, 6, 15).millisecondsSinceEpoch,
            'category': 'maintenance',
            'status': 'active',
          },
        ],
        startMonth: DateTime(2026, 6, 1),
        endMonth: DateTime(2026, 7, 1),
      );

      final periodTitle = FinancialReportCalculator.formatTransparencyPeriodTitle('2026-06', '2026-07');

      final esMd = FinancialReportCalculator.buildTransparencyMarkdownReport(
        title: periodTitle,
        ledger: ledger,
        languageCode: 'es',
        useDescriptiveHeading: true,
      );
      expect(esMd, contains('# Resumen Financiero — 2026-06 – 2026-07'));
      expect(esMd, contains('## Resumen'));
      expect(esMd, contains('## Desglose Mensual'));
      expect(esMd, contains('## Gastos Activos de la Comunidad'));
      expect(esMd, contains('| Mantenimiento |'));
      expect(esMd, contains('\$2000.00'));
      expect(esMd, contains('\$350.00'));
      expect(esMd, isNot(contains('Privada Confidencial')));

      final enMd = FinancialReportCalculator.buildTransparencyMarkdownReport(
        title: periodTitle,
        ledger: ledger,
        languageCode: 'en',
        useDescriptiveHeading: true,
      );
      expect(enMd, contains('# Financial Summary — 2026-06 – 2026-07'));
      expect(enMd, contains('## Summary'));
      expect(enMd, contains('## Monthly Breakdown'));
      expect(enMd, contains('## Active Community Expenses'));
      expect(enMd, contains('| Maintenance |'));
      expect(enMd, contains('\$2000.00'));
      expect(enMd, isNot(contains('Privada Confidencial')));
    });
  });
}

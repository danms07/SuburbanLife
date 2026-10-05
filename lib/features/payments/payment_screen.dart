import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import 'payment_service.dart';
import '../../l10n/app_localizations.dart';

class PaymentScreen extends StatefulWidget {
  final String currentUid;
  final String? initialConcept;
  final String? initialSanctionId;
  final double? initialAmount;

  const PaymentScreen({
    super.key,
    required this.currentUid,
    this.initialConcept,
    this.initialSanctionId,
    this.initialAmount,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final PaymentService _paymentService = PaymentService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _folioController = TextEditingController();
  final FocusNode _folioFocusNode = FocusNode();
  final FocusNode _amountFocusNode = FocusNode();

  late final Stream<Map<String, dynamic>?> _userStream;
  String? _cachedAddressId;
  Stream<Map<String, dynamic>?>? _addressStream;
  String? _cachedPaymentsAddressId;
  Stream<List<Map<String, dynamic>>>? _paymentsStream;
  String? _cachedSanctionsAddressId;
  Stream<List<Map<String, dynamic>>>? _sanctionsStream;

  String _selectedConcept = 'monthly quota';
  String? _selectedSanctionId;
  DateTime _paymentDate = DateTime.now();
  final Set<String> _selectedPeriods = <String>{};
  bool _payAdvancePeriods = false;
  XFile? _selectedReceiptImage;
  bool _isUploading = false;
  bool _hasPrefilledRejected = false;

  @override
  void initState() {
    super.initState();
    _userStream = DatabaseService().streamDocument('users', widget.currentUid);
    _selectedConcept = widget.initialConcept ?? 'monthly quota';
    _selectedSanctionId = widget.initialSanctionId;
    if (widget.initialAmount != null) {
      _amountController.text = widget.initialAmount!.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _folioController.dispose();
    _amountController.dispose();
    _folioFocusNode.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickReceiptImage() async {
    try {
      XFile? picked;
      try {
        picked = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 60,
        );
      } catch (_) {
        picked = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 60,
        );
      }
      if (picked != null && mounted) {
        setState(() {
          _selectedReceiptImage = picked;
        });
      }
    } catch (e) {
      debugPrint('Error picking receipt image: $e');
    }
  }

  Future<void> _selectPaymentDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _paymentDate = picked;
      });
    }
  }

  List<String> _getMissingFields(AppLocalizations l10n) {
    final missing = <String>[];
    if (_folioController.text.trim().isEmpty) {
      missing.add(l10n.missingFolio);
    }
    final parsedAmount = double.tryParse(_amountController.text.trim());
    if (parsedAmount == null || parsedAmount <= 0) {
      missing.add(l10n.missingAmount);
    }
    if (_selectedReceiptImage == null) {
      missing.add(l10n.missingReceipt);
    }
    if (_selectedConcept == 'monthly quota' && _selectedPeriods.isEmpty) {
      missing.add('• ${l10n.atLeastOnePeriodRequired}');
    }
    return missing;
  }

  Future<void> _submitPayment() async {
    final l10n = AppLocalizations.of(context)!;
    final missing = _getMissingFields(l10n);
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.missingPaymentFieldsWarning),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final amount = double.parse(_amountController.text.trim());
    setState(() {
      _isUploading = true;
    });

    try {
      final sortedPeriods = _selectedPeriods.toList()..sort();
      await _paymentService.uploadPaymentReceipt(
        widget.currentUid,
        sortedPeriods,
        amount,
        folio: _folioController.text.trim(),
        concept: _selectedConcept,
        paymentDate: _paymentDate,
        sanctionId: _selectedSanctionId,
        pickedFile: _selectedReceiptImage,
      );

      if (mounted) {
        setState(() {
          _folioController.clear();
          _amountController.clear();
          _selectedPeriods.clear();
          _selectedReceiptImage = null;
          _selectedSanctionId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.proofUploadedSuccess),
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
      if (mounted) {
        setState(() {
          _isUploading = false;
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
        title: Text(l10n.maintenancePayment, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _userStream,
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final userData = userSnap.data;
          final addressRef = userData?['addressRef'] as DbReference?;
          if (addressRef == null) {
            return Center(
              child: Text(
                l10n.noPendingPeriods,
                style: const TextStyle(fontSize: 16, color: Colors.grey, fontFamily: AppConfig.fontFamily),
              ),
            );
          }

          if (_cachedAddressId != addressRef.id) {
            _cachedAddressId = addressRef.id;
            _addressStream = DatabaseService().streamDocument('addresses', addressRef.id);
          }

          return StreamBuilder<Map<String, dynamic>?>(
            stream: _addressStream,
            builder: (context, addressSnap) {
              if (addressSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final addressData = addressSnap.data;
              if (addressData == null) {
                return Center(child: Text(l10n.addressDetailsNotFound));
              }

              final paymentStatus = addressData['paymentStatus'] as String? ?? 'restricted';
              final deliveryTimestamp = addressData['deliveryDate'] as DateTime?;

              if (_cachedPaymentsAddressId != addressRef.id) {
                _cachedPaymentsAddressId = addressRef.id;
                _paymentsStream = DatabaseService().streamCollection(
                  'payments',
                  filters: [QueryFilter('addressRef', FilterOperator.equal, addressRef)],
                );
              }

              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _paymentsStream,
                builder: (context, paymentsSnap) {
                  if (paymentsSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = paymentsSnap.data ?? [];

                  // Find latest rejected payment if any
                  Map<String, dynamic>? lastRejectedPayment;
                  if (docs.isNotEmpty) {
                    final sortedDocs = List<Map<String, dynamic>>.from(docs)
                      ..sort((a, b) => ((b['timestamp'] as num?) ?? 0).compareTo((a['timestamp'] as num?) ?? 0));
                    final latest = sortedDocs.first;
                    if (latest['status'] == 'rejected') {
                      lastRejectedPayment = latest;
                    }
                  }

                  // Auto pre-fill if rejected payment found and not yet prefilled
                  if (lastRejectedPayment != null && !_hasPrefilledRejected) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_hasPrefilledRejected) {
                        setState(() {
                          _hasPrefilledRejected = true;
                          if (_folioController.text.isEmpty && lastRejectedPayment?['folio'] != null) {
                            _folioController.text = lastRejectedPayment!['folio'].toString();
                          }
                          if (_amountController.text.isEmpty && lastRejectedPayment?['amount'] != null) {
                            _amountController.text = lastRejectedPayment!['amount'].toString();
                          }
                          if (lastRejectedPayment?['concept'] != null) {
                            _selectedConcept = lastRejectedPayment!['concept'].toString();
                          }
                          if (lastRejectedPayment?['sanctionId'] != null) {
                            _selectedSanctionId = lastRejectedPayment!['sanctionId'].toString();
                          }
                          if (lastRejectedPayment?['paymentDate'] != null) {
                            _paymentDate = DateTime.fromMillisecondsSinceEpoch(lastRejectedPayment!['paymentDate'] as int);
                          }
                          if (lastRejectedPayment?['periods'] is List) {
                            for (var p in (lastRejectedPayment!['periods'] as List)) {
                              if (p != null && p.toString().isNotEmpty) {
                                _selectedPeriods.add(p.toString());
                              }
                            }
                          }
                        });
                      }
                    });
                  }

                  // Build status lookup map across periods
                  final paymentsMap = <String, String>{};
                  for (var pData in docs) {
                    final concept = pData['concept'] as String? ?? 'monthly quota';
                    if (concept != 'monthly quota') continue;

                    final periodsList = <String>[];
                    if (pData['periods'] is List) {
                      for (var p in (pData['periods'] as List)) {
                        if (p != null && p.toString().trim().isNotEmpty) {
                          periodsList.add(p.toString().trim());
                        }
                      }
                    } else if (pData['period'] != null) {
                      final pStr = pData['period'].toString();
                      for (var p in pStr.split(',')) {
                        if (p.trim().isNotEmpty) periodsList.add(p.trim());
                      }
                    }

                    final status = pData['status'] as String?;
                    if (status != null) {
                      for (var period in periodsList) {
                        final existing = paymentsMap[period];
                        if (existing == null ||
                            status == 'approved' ||
                            (status == 'pending' && existing == 'rejected')) {
                          paymentsMap[period] = status;
                        }
                      }
                    }
                  }

                  final now = DateTime.now();
                  final allCandidatePeriods = _paymentService.generateSelectablePeriods(deliveryTimestamp, now, advanceMonths: 12);
                  final currentPeriodStr = "${now.year}-${now.month.toString().padLeft(2, '0')}";

                  // Partition candidate periods into due (past & current unpaid) and advance
                  final duePeriods = <String>[];
                  final advancePeriods = <String>[];

                  for (var period in allCandidatePeriods) {
                    final status = paymentsMap[period];
                    final isPastOrCurrent = period.compareTo(currentPeriodStr) <= 0;

                    if (isPastOrCurrent) {
                      if (status != 'approved') {
                        duePeriods.add(period);
                      }
                    } else {
                      advancePeriods.add(period);
                    }
                  }

                  // Auto-select first due period if none selected yet and concept is monthly quota
                  if (_selectedConcept == 'monthly quota' && _selectedPeriods.isEmpty && duePeriods.isNotEmpty) {
                    _selectedPeriods.add(duePeriods.first);
                  }

                  if (_cachedSanctionsAddressId != addressRef.id) {
                    _cachedSanctionsAddressId = addressRef.id;
                    _sanctionsStream = DatabaseService().streamCollection(
                      'sanctions',
                      filters: [QueryFilter('addressRef', FilterOperator.equal, addressRef)],
                    );
                  }

                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _sanctionsStream,
                    builder: (context, sanctionsSnap) {
                      final allSanctions = sanctionsSnap.data ?? [];
                      final activeSanctions = allSanctions.where((s) {
                        final st = s['status'] as String? ?? 'active';
                        return st == 'active' || st == 'pending_review';
                      }).toList();

                      return _buildPaymentUI(
                        context,
                        paymentStatus,
                        duePeriods,
                        advancePeriods,
                        paymentsMap,
                        currentPeriodStr,
                        lastRejectedPayment,
                        activeSanctions,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPaymentUI(
    BuildContext context,
    String paymentStatus,
    List<String> duePeriods,
    List<String> advancePeriods,
    Map<String, String> paymentsMap,
    String currentPeriodStr,
    Map<String, dynamic>? lastRejectedPayment,
    List<Map<String, dynamic>> activeSanctions,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Rejection Alert Banner at top
          if (lastRejectedPayment != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppConfig.dangerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppConfig.dangerColor.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppConfig.dangerColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.paymentRejectedBannerTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppConfig.dangerColor,
                            fontFamily: AppConfig.fontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.paymentRejectedBannerMsg(lastRejectedPayment['rejectionReason'] as String? ?? ''),
                    style: const TextStyle(fontSize: 14, fontFamily: AppConfig.fontFamily),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          Text(
            _selectedConcept == 'sanction' ? l10n.conceptSanction : l10n.monthlyQuota,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              fontFamily: AppConfig.fontFamily,
              color: AppConfig.primaryColor,
            ),
          ),
          const SizedBox(height: 16),

          // Status Banner Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: _getStatusColor(paymentStatus).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _getStatusColor(paymentStatus).withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_getStatusIcon(paymentStatus), color: _getStatusColor(paymentStatus), size: 22),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${l10n.currentStatus}: ${_getTranslatedStatus(l10n, paymentStatus).toUpperCase()}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppConfig.fontFamily,
                      color: _getStatusColor(paymentStatus),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Form Card
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Concept Selection
                  Text(
                    l10n.paymentConceptLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedConcept,
                    isExpanded: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.category_outlined, color: AppConfig.primaryColor),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'monthly quota',
                        child: Text(l10n.conceptMonthlyQuota),
                      ),
                      DropdownMenuItem(
                        value: 'sanction',
                        child: Text(l10n.conceptSanction),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedConcept = val;
                          if (val == 'sanction' && activeSanctions.isNotEmpty && _selectedSanctionId == null) {
                            _selectedSanctionId = activeSanctions.first['id']?.toString();
                            final amt = activeSanctions.first['amount'];
                            if (amt != null) {
                              _amountController.text = amt.toString();
                            }
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 20),

                  // If Sanction Concept selected, allow choosing which sanction
                  if (_selectedConcept == 'sanction') ...[
                    if (activeSanctions.isNotEmpty) ...[
                      Text(
                        l10n.sanctionsList,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedSanctionId ?? activeSanctions.first['id']?.toString(),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.gavel, color: AppConfig.primaryColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          isDense: true,
                        ),
                        items: activeSanctions.map((s) {
                          final sId = s['id']?.toString() ?? '';
                          final reason = s['reason']?.toString() ?? 'Sanction';
                          final amt = s['amount']?.toString() ?? '0';
                          return DropdownMenuItem(
                            value: sId,
                            child: Text(
                              '$reason (\$$amt MXN)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            final matching = activeSanctions.firstWhere(
                              (s) => s['id']?.toString() == val,
                              orElse: () => {},
                            );
                            setState(() {
                              _selectedSanctionId = val;
                              if (matching['amount'] != null) {
                                _amountController.text = matching['amount'].toString();
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],

                  // Folio (Receipt Number) Field
                  Text(
                    l10n.folioLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('folio_field'),
                    controller: _folioController,
                    focusNode: _folioFocusNode,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.receipt_long, color: AppConfig.primaryColor),
                      labelText: l10n.folioLabel,
                      hintText: l10n.folioHint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Payment Date Field
                  Text(
                    l10n.paymentDateLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _selectPaymentDate(context),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l10n.paymentDateLabel,
                        prefixIcon: const Icon(Icons.calendar_today, color: AppConfig.primaryColor),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                      child: Text(
                        "${_paymentDate.year}-${_paymentDate.month.toString().padLeft(2, '0')}-${_paymentDate.day.toString().padLeft(2, '0')}",
                        style: const TextStyle(fontSize: 15, fontFamily: AppConfig.fontFamily),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Payment Amount Field
                  Text(
                    l10n.paymentAmountLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('amount_field'),
                    controller: _amountController,
                    focusNode: _amountFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.attach_money, color: AppConfig.primaryColor),
                      labelText: l10n.paymentAmountLabel,
                      hintText: l10n.paymentAmountHint,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Periods Section (only for monthly quota)
                  if (_selectedConcept == 'monthly quota') ...[
                    if (duePeriods.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.dueMonthsSection,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: duePeriods.map((period) {
                          final isSelected = _selectedPeriods.contains(period);
                          final status = paymentsMap[period];
                          final isReviewing = status == 'pending';

                          return FilterChip(
                            selected: isSelected,
                            avatar: isReviewing
                                ? const Icon(Icons.hourglass_empty, size: 14, color: Colors.blue)
                                : null,
                            label: Text(_formatPeriod(period, locale)),
                            selectedColor: AppConfig.primaryColor.withValues(alpha: 0.2),
                            checkmarkColor: AppConfig.primaryColor,
                            labelStyle: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppConfig.primaryColor : Colors.black87,
                            ),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedPeriods.add(period);
                                } else {
                                  _selectedPeriods.remove(period);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Advance Periods Switch & List View
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l10n.payAdvancePeriodsSwitch,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: AppConfig.fontFamily),
                      ),
                      value: _payAdvancePeriods,
                      activeThumbColor: AppConfig.primaryColor,
                      onChanged: (val) {
                        setState(() {
                          _payAdvancePeriods = val;
                          if (!val) {
                            _selectedPeriods.removeWhere((p) => advancePeriods.contains(p));
                          }
                        });
                      },
                    ),

                    if (_payAdvancePeriods && advancePeriods.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.selectAdvancePeriods,
                        style: const TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: advancePeriods.length > 4 ? 220 : null,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView.separated(
                          shrinkWrap: advancePeriods.length <= 4,
                          physics: advancePeriods.length <= 4
                              ? const NeverScrollableScrollPhysics()
                              : const AlwaysScrollableScrollPhysics(),
                          itemCount: advancePeriods.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final period = advancePeriods[index];
                            final isSelected = _selectedPeriods.contains(period);
                            final status = paymentsMap[period];
                            final isPaid = status == 'approved';
                            final isReviewing = status == 'pending';

                            return CheckboxListTile(
                              title: Text(
                                _formatPeriod(period, locale),
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isPaid ? Colors.green.shade800 : Colors.black87,
                                  fontFamily: AppConfig.fontFamily,
                                ),
                              ),
                              subtitle: isPaid
                                  ? Text(l10n.statusPaid, style: TextStyle(color: Colors.green.shade700, fontSize: 12))
                                  : (isReviewing ? Text(l10n.statusPending, style: TextStyle(color: Colors.blue.shade700, fontSize: 12)) : null),
                              value: isSelected,
                              activeColor: AppConfig.primaryColor,
                              enabled: !isPaid,
                              onChanged: isPaid
                                  ? null
                                  : (bool? value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedPeriods.add(period);
                                        } else {
                                          _selectedPeriods.remove(period);
                                        }
                                      });
                                    },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],

                  // Receipt Photo Attachment Card
                  Text(
                    _selectedConcept == 'sanction' ? l10n.sanctionEvidencePhoto : l10n.paymentProofPhoto,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selectedReceiptImage != null ? AppConfig.primaryColor : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      color: _selectedReceiptImage != null ? AppConfig.primaryColor.withValues(alpha: 0.05) : Colors.grey.shade50,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _selectedReceiptImage != null ? Icons.check_circle : Icons.receipt_long_outlined,
                              color: _selectedReceiptImage != null ? AppConfig.primaryColor : Colors.grey.shade600,
                              size: 26,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedReceiptImage != null
                                        ? l10n.proofUploadedSuccess
                                        : l10n.missingReceipt.replaceAll('• ', ''),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: _selectedReceiptImage != null ? AppConfig.primaryColor : Colors.black87,
                                    ),
                                  ),
                                  if (_selectedReceiptImage != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _selectedReceiptImage!.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (_selectedReceiptImage != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                                tooltip: l10n.delete,
                                onPressed: () {
                                  setState(() {
                                    _selectedReceiptImage = null;
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt, size: 18),
                            label: Text(_selectedReceiptImage != null ? l10n.edit : l10n.takePhotoReceipt),
                            onPressed: _pickReceiptImage,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppConfig.primaryColor,
                              side: const BorderSide(color: AppConfig.primaryColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Missing Fields Warning Banner & Submit Button (reactive to text controllers without full rebuilds)
                  ListenableBuilder(
                    listenable: Listenable.merge([_folioController, _amountController]),
                    builder: (context, _) {
                      final currentMissingFields = _getMissingFields(l10n);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (currentMissingFields.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.shade400),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          l10n.missingPaymentFieldsWarning,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber.shade900,
                                            fontFamily: AppConfig.fontFamily,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...currentMissingFields.map(
                                    (field) => Padding(
                                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                                      child: Text(
                                        field,
                                        style: TextStyle(
                                          color: Colors.amber.shade900,
                                          fontSize: 13,
                                          fontFamily: AppConfig.fontFamily,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Submit Button
                          ElevatedButton.icon(
                            icon: _isUploading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            label: Text(l10n.submitPayment),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: AppConfig.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: (_isUploading || currentMissingFields.isNotEmpty) ? null : _submitPayment,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  Text(
                    l10n.receiptNotice,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                      fontFamily: AppConfig.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPeriod(String period, String locale) {
    try {
      final parts = period.split('-');
      if (parts.length != 2) return period;
      final year = parts[0];
      final month = parts[1];
      if (locale.startsWith('es')) {
        return '$month-$year';
      } else {
        return '$year-$month';
      }
    } catch (_) {
      return period;
    }
  }

  String _getTranslatedStatus(AppLocalizations l10n, String status) {
    switch (status) {
      case 'paid':
        return l10n.statusPaid;
      case 'pending':
        return l10n.statusPending;
      case 'reviewing':
        return l10n.statusReviewing;
      case 'restricted':
        return l10n.statusRestricted;
      default:
        return status.toUpperCase();
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'paid':
        return AppConfig.successColor;
      case 'pending':
        return AppConfig.warningColor;
      case 'reviewing':
        return AppConfig.infoColor;
      case 'restricted':
        return AppConfig.dangerColor;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'paid':
        return Icons.check_circle_outline;
      case 'pending':
        return Icons.warning_amber_rounded;
      case 'reviewing':
        return Icons.hourglass_empty;
      case 'restricted':
        return Icons.block;
      default:
        return Icons.info_outline;
    }
  }
}


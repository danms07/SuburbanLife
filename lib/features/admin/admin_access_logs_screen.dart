import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/widgets/interactive_image_dialog.dart';
import '../../l10n/app_localizations.dart';

class AdminAccessLogsScreen extends StatefulWidget {
  const AdminAccessLogsScreen({Key? key}) : super(key: key);

  @override
  State<AdminAccessLogsScreen> createState() => _AdminAccessLogsScreenState();
}

class _AdminAccessLogsScreenState extends State<AdminAccessLogsScreen> {
  String _selectedAddress = 'all';
  String _selectedVisitorType = 'all'; // 'all', 'visitor', 'supplier'
  String _dateFilterMode = 'all'; // 'all', 'today', 'this_week', 'this_month', 'custom'
  DateTimeRange? _customDateRange;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<String> _availableAddresses = [];
  bool _isLoadingAddresses = true;

  @override
  void initState() {
    super.initState();
    _fetchAddressOptions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _fetchAddressOptions() async {
    try {
      final addresses = await DatabaseService().getCollection('addresses');
      final Set<String> uniqueAddrs = {};

      for (var doc in addresses) {
        final street = doc['streetName']?.toString().trim();
        final number = doc['number']?.toString().trim();
        if (street != null && street.isNotEmpty) {
          final display = (number != null && number.isNotEmpty)
              ? '$street #$number'
              : street;
          uniqueAddrs.add(display);
        }
      }

      final list = uniqueAddrs.toList();
      list.sort((a, b) => a.compareTo(b));

      if (mounted) {
        setState(() {
          _availableAddresses = list;
          _isLoadingAddresses = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching address options: $e');
      if (mounted) {
        setState(() {
          _isLoadingAddresses = false;
        });
      }
    }
  }

  DateTime? _getFilterStartDate() {
    final now = DateTime.now();
    switch (_dateFilterMode) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'this_week':
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      case 'this_month':
        return DateTime(now.year, now.month, 1);
      case 'custom':
        return _customDateRange?.start != null
            ? DateTime(
                _customDateRange!.start.year,
                _customDateRange!.start.month,
                _customDateRange!.start.day,
              )
            : null;
      default:
        return null;
    }
  }

  DateTime? _getFilterEndDate() {
    final now = DateTime.now();
    switch (_dateFilterMode) {
      case 'today':
        return DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      case 'this_week':
        final endOfWeek = now.add(Duration(days: 7 - now.weekday));
        return DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59, 999);
      case 'this_month':
        final nextMonth = DateTime(now.year, now.month + 1, 1);
        return nextMonth.subtract(const Duration(milliseconds: 1));
      case 'custom':
        return _customDateRange?.end != null
            ? DateTime(
                _customDateRange!.end.year,
                _customDateRange!.end.month,
                _customDateRange!.end.day,
                23,
                59,
                59,
                999,
              )
            : null;
      default:
        return null;
    }
  }

  void _selectCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppConfig.primaryColor,
                  onPrimary: Colors.white,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _dateFilterMode = 'custom';
      });
    }
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '';
    DateTime dt;
    if (ts is DateTime) {
      dt = ts;
    } else if (ts is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is Map && ts['_seconds'] != null) {
      dt = DateTime.fromMillisecondsSinceEpoch((ts['_seconds'] as int) * 1000);
    } else {
      final parsed = DateTime.tryParse(ts.toString());
      if (parsed != null) {
        dt = parsed;
      } else {
        return ts.toString();
      }
    }

    final local = dt.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute';
  }

  DateTime? _parseDateTime(dynamic ts) {
    if (ts == null) return null;
    if (ts is DateTime) return ts;
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is Map && ts['_seconds'] != null) {
      return DateTime.fromMillisecondsSinceEpoch((ts['_seconds'] as int) * 1000);
    }
    return DateTime.tryParse(ts.toString());
  }

  bool _matchesFilter(Map<String, dynamic> log) {
    // 1. Address filter
    if (_selectedAddress != 'all') {
      final addrDisplay = log['addressDisplay']?.toString().trim() ?? '';
      final street = log['streetName']?.toString().trim() ?? '';
      final number = log['number']?.toString().trim() ?? '';
      final combined = number.isNotEmpty ? '$street #$number' : street;

      final matches = addrDisplay == _selectedAddress || combined == _selectedAddress;
      if (!matches) return false;
    }

    // 2. Visitor Type filter
    if (_selectedVisitorType != 'all') {
      final cat = (log['accessCategory']?.toString() ?? 'visitor').toLowerCase();
      if (_selectedVisitorType == 'supplier') {
        if (cat != 'supplier' && cat != 'provider') return false;
      } else if (_selectedVisitorType == 'visitor') {
        if (cat == 'supplier' || cat == 'provider') return false;
      }
    }

    // 3. Date range filter
    final startDate = _getFilterStartDate();
    final endDate = _getFilterEndDate();
    if (startDate != null || endDate != null) {
      final dt = _parseDateTime(log['timestamp']);
      if (dt != null) {
        final local = dt.toLocal();
        if (startDate != null && local.isBefore(startDate)) return false;
        if (endDate != null && local.isAfter(endDate)) return false;
      }
    }

    // 4. Search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      final guestName = (log['guestName'] ?? log['visitorName'] ?? '').toString().toLowerCase();
      final plates = (log['vehiclePlates'] ?? log['vehiclePlate'] ?? '').toString().toLowerCase();
      final address = (log['addressDisplay'] ?? '').toString().toLowerCase();
      final resident = (log['residentName'] ?? '').toString().toLowerCase();
      final guard = (log['guardName'] ?? '').toString().toLowerCase();
      final reason = (log['reason'] ?? '').toString().toLowerCase();

      final matchesSearch = guestName.contains(q) ||
          plates.contains(q) ||
          address.contains(q) ||
          resident.contains(q) ||
          guard.contains(q) ||
          reason.contains(q);

      if (!matchesSearch) return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accessLogsTitle),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Backend.db.streamCollection('access_logs'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _isLoadingAddresses) {
            return const Center(child: CircularProgressIndicator());
          }

          final allLogs = snapshot.data ?? [];
          // Sort descending by timestamp
          allLogs.sort((a, b) {
            final dtA = _parseDateTime(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final dtB = _parseDateTime(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
            return dtB.compareTo(dtA);
          });

          final filteredLogs = allLogs.where(_matchesFilter).toList();

          // Calculate KPI metrics
          final totalCount = filteredLogs.length;
          final allowedCount = filteredLogs.where((l) => l['status'] == 'allowed').length;
          final deniedCount = filteredLogs.where((l) => l['status'] == 'denied').length;
          final providerCount = filteredLogs.where((l) {
            final cat = (l['accessCategory']?.toString() ?? '').toLowerCase();
            return cat == 'supplier' || cat == 'provider';
          }).length;

          return Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Filter Section Card
                  _buildFilterCard(context, l10n, isDesktop),
                  const SizedBox(height: 16),

                  // KPI Summary Bar
                  _buildKpiSummaryBar(
                    l10n: l10n,
                    total: totalCount,
                    allowed: allowedCount,
                    denied: deniedCount,
                    providers: providerCount,
                    isDesktop: isDesktop,
                  ),
                  const SizedBox(height: 16),

                  // Access Logs List
                  if (filteredLogs.isEmpty)
                    _buildEmptyState(context, l10n)
                  else
                    ...filteredLogs.map((log) => _buildLogCard(context, l10n, log, isDesktop)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterCard(BuildContext context, AppLocalizations l10n, bool isDesktop) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchVisitorOrPlate,
                prefixIcon: const Icon(Icons.search, color: AppConfig.primaryColor),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
            ),
            const SizedBox(height: 14),

            // Dropdowns and Selectors Row
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Address Dropdown Filter
                Container(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 320 : double.infinity),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedAddress,
                      isExpanded: true,
                      icon: const Icon(Icons.location_on_outlined, color: AppConfig.primaryColor),
                      items: [
                        DropdownMenuItem<String>(
                          value: 'all',
                          child: Text(l10n.allAddresses, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        ..._availableAddresses.map((addr) {
                          return DropdownMenuItem<String>(
                            value: addr,
                            child: Text(addr),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedAddress = val;
                          });
                        }
                      },
                    ),
                  ),
                ),

                // Visitor Type Segmented Selector
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'all',
                      label: Text(l10n.allTypes),
                      icon: const Icon(Icons.groups_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: 'visitor',
                      label: Text(l10n.visitorTypeGuest),
                      icon: const Icon(Icons.person_outline, size: 16),
                    ),
                    ButtonSegment(
                      value: 'supplier',
                      label: Text(l10n.visitorTypeSupplier),
                      icon: const Icon(Icons.local_shipping_outlined, size: 16),
                    ),
                  ],
                  selected: {_selectedVisitorType},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _selectedVisitorType = newSelection.first;
                    });
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Date Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    '${l10n.filterByDate}: ',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  _buildDateChip(label: l10n.allDates, mode: 'all'),
                  const SizedBox(width: 6),
                  _buildDateChip(label: l10n.today, mode: 'today'),
                  const SizedBox(width: 6),
                  _buildDateChip(label: l10n.thisWeek, mode: 'this_week'),
                  const SizedBox(width: 6),
                  _buildDateChip(label: l10n.thisMonth, mode: 'this_month'),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.date_range, size: 16),
                    label: Text(
                      _dateFilterMode == 'custom' && _customDateRange != null
                          ? '${_formatTimestamp(_customDateRange!.start).split(' ')[0]} - ${_formatTimestamp(_customDateRange!.end).split(' ')[0]}'
                          : l10n.customDateRange,
                      style: TextStyle(
                        fontSize: 12,
                        color: _dateFilterMode == 'custom' ? Colors.white : Colors.black87,
                      ),
                    ),
                    backgroundColor: _dateFilterMode == 'custom'
                        ? AppConfig.primaryColor
                        : Colors.grey.shade100,
                    onPressed: _selectCustomDateRange,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip({required String label, required String mode}) {
    final isSelected = _dateFilterMode == mode;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSelected ? Colors.white : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: AppConfig.primaryColor,
      backgroundColor: Colors.grey.shade100,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _dateFilterMode = mode;
          });
        }
      },
    );
  }

  Widget _buildKpiSummaryBar({
    required AppLocalizations l10n,
    required int total,
    required int allowed,
    required int denied,
    required int providers,
    required bool isDesktop,
  }) {
    final cards = [
      _buildKpiCard(label: l10n.totalAccesses, count: total, color: Colors.blueGrey, icon: Icons.history),
      _buildKpiCard(label: l10n.allowedAccesses, count: allowed, color: Colors.green.shade700, icon: Icons.check_circle_outline),
      _buildKpiCard(label: l10n.deniedAccesses, count: denied, color: Colors.redAccent, icon: Icons.cancel_outlined),
      _buildKpiCard(label: l10n.providerAccesses, count: providers, color: Colors.orange.shade800, icon: Icons.local_shipping_outlined),
    ];

    if (isDesktop) {
      return Row(
        children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: c))).toList(),
      );
    } else {
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.2,
        children: cards,
      );
    }
  }

  Widget _buildKpiCard({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              foregroundColor: color,
              radius: 18,
              child: Icon(icon, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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

  Widget _buildLogCard(
    BuildContext context,
    AppLocalizations l10n,
    Map<String, dynamic> log,
    bool isDesktop,
  ) {
    final status = log['status']?.toString().toLowerCase() ?? 'allowed';
    final isAllowed = status == 'allowed';

    final cat = log['accessCategory']?.toString().toLowerCase() ?? 'visitor';
    final isSupplier = cat == 'supplier' || cat == 'provider';

    final guestName = (log['guestName'] ?? log['visitorName'] ?? 'Guest').toString();
    final timestampStr = _formatTimestamp(log['timestamp']);

    final addressDisplay = (log['addressDisplay'] ??
            ((log['streetName'] != null)
                ? '${log['streetName']} #${log['number'] ?? ''}'
                : ''))
        .toString()
        .trim();

    final residentName = log['residentName']?.toString().trim();
    final guardName = log['guardName']?.toString().trim();

    final vehicleType = log['vehicleType']?.toString();
    final vehiclePlates = log['vehiclePlates'] ?? log['vehiclePlate'];
    final passengers = log['passengers'] as int?;

    final idPhotoUrl = log['visitorIdPhotoUrl']?.toString().trim();
    final platePhotoUrl = log['visitorPlatePhotoUrl']?.toString().trim();
    final reason = log['reason']?.toString().trim();

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Badges & Timestamp
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isAllowed
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isAllowed ? Colors.green.shade600 : Colors.redAccent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isAllowed ? Icons.check_circle : Icons.cancel,
                            size: 14,
                            color: isAllowed ? Colors.green.shade700 : Colors.redAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isAllowed ? l10n.accessAllowed : l10n.accessDenied,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isAllowed ? Colors.green.shade800 : Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Visitor Category Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSupplier
                            ? Colors.orange.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSupplier ? Colors.orange.shade400 : Colors.blue.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSupplier ? Icons.local_shipping : Icons.person,
                            size: 14,
                            color: isSupplier ? Colors.orange.shade800 : Colors.blue.shade800,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSupplier ? l10n.visitorTypeSupplier : l10n.visitorTypeGuest,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSupplier ? Colors.orange.shade900 : Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Timestamp label
                Text(
                  timestampStr,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Main Details Row / Grid
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                // Visitor Name
                _buildInfoItem(
                  icon: Icons.person_outline,
                  label: l10n.cardGuestName,
                  value: guestName,
                ),

                // Destination Address
                if (addressDisplay.isNotEmpty)
                  _buildInfoItem(
                    icon: Icons.home_outlined,
                    label: l10n.destinationAddress,
                    value: addressDisplay,
                  ),

                // Host Resident
                if (residentName != null && residentName.isNotEmpty)
                  _buildInfoItem(
                    icon: Icons.account_circle_outlined,
                    label: l10n.invitedByResident,
                    value: residentName,
                  ),

                // Guard
                if (guardName != null && guardName.isNotEmpty)
                  _buildInfoItem(
                    icon: Icons.security,
                    label: l10n.verifiedByGuard,
                    value: guardName,
                  ),

                // Vehicle Details
                if (vehicleType != null && vehicleType != 'walking')
                  _buildInfoItem(
                    icon: Icons.directions_car_outlined,
                    label: l10n.vehicleDetails,
                    value: [
                      vehicleType.toUpperCase(),
                      if (vehiclePlates != null && vehiclePlates.toString().isNotEmpty)
                        '(${vehiclePlates.toString()})',
                      if (passengers != null && passengers > 0)
                        l10n.logPassengersCount(passengers),
                    ].join(' '),
                  ),
              ],
            ),

            // Reason / Notes
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isAllowed ? Colors.grey.shade50 : Colors.red.shade50.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isAllowed ? Colors.grey.shade200 : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notes,
                      size: 16,
                      color: isAllowed ? Colors.grey.shade700 : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${l10n.reasonOrNotes}: $reason',
                        style: TextStyle(
                          fontSize: 12,
                          color: isAllowed ? Colors.black87 : Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Photos Row
            if ((idPhotoUrl != null && idPhotoUrl.isNotEmpty) ||
                (platePhotoUrl != null && platePhotoUrl.isNotEmpty)) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (idPhotoUrl != null && idPhotoUrl.isNotEmpty)
                    _buildPhotoThumbnail(
                      context: context,
                      imageUrl: idPhotoUrl,
                      label: l10n.viewVisitorIdPhoto,
                      icon: Icons.badge_outlined,
                    ),
                  if (platePhotoUrl != null && platePhotoUrl.isNotEmpty)
                    _buildPhotoThumbnail(
                      context: context,
                      imageUrl: platePhotoUrl,
                      label: l10n.viewPlatePhoto,
                      icon: Icons.pin_outlined,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: AppConfig.primaryColor),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotoThumbnail({
    required BuildContext context,
    required String imageUrl,
    required String label,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () {
        showInteractiveImageDialog(
          context,
          imageUrl,
          title: label,
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppConfig.primaryColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppConfig.primaryColor,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.fullscreen, size: 14, color: AppConfig.primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noAccessLogsFound,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

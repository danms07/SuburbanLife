import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import 'admin_create_user_screen.dart';

class AdminUserManagementScreen extends StatefulWidget {
  final bool isEmbedded;

  const AdminUserManagementScreen({super.key, this.isEmbedded = false});

  @override
  State<AdminUserManagementScreen> createState() => _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  static const int _batchSize = 20;

  // Pagination & user list state
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _lastDocId;

  // In-memory address cache: addressId -> address doc map
  final Map<String, Map<String, dynamic>> _addressCache = {};

  // Search & Filter state
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String _searchQuery = '';
  String _selectedStreet = 'all';
  String _selectedRole = 'all';
  List<String> _availableStreets = [];

  @override
  void initState() {
    super.initState();
    _fetchStreetOptions();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Fetches unique street names from the addresses collection to populate the street filter.
  Future<void> _fetchStreetOptions() async {
    try {
      final addresses = await DatabaseService().getCollection('addresses');
      final Set<String> uniqueStreets = {};
      for (final addr in addresses) {
        final street = addr['streetName']?.toString().trim();
        if (street != null && street.isNotEmpty) {
          uniqueStreets.add(street);
        }
        final docId = addr['id']?.toString();
        if (docId != null) {
          _addressCache[docId] = addr;
        }
      }
      final sorted = uniqueStreets.toList()..sort((a, b) => a.compareTo(b));
      if (mounted) {
        setState(() {
          _availableStreets = sorted;
        });
      }
    } catch (e, stack) {
      debugPrint('Error fetching street options: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminUserManagementScreen._fetchStreetOptions');
    }
  }

  /// Fetches address documents for any users in the list that are not yet in `_addressCache`.
  Future<void> _fetchAddressesForUsers(List<Map<String, dynamic>> userDocs) async {
    final List<String> addressIdsToFetch = [];
    for (final doc in userDocs) {
      final ref = doc['addressRef'];
      if (ref is DbReference && !_addressCache.containsKey(ref.id)) {
        addressIdsToFetch.add(ref.id);
      }
    }

    if (addressIdsToFetch.isEmpty) return;

    await Future.wait(
      addressIdsToFetch.map((id) async {
        try {
          final addr = await DatabaseService().getDocument('addresses', id);
          if (addr != null) {
            _addressCache[id] = addr;
          }
        } catch (e) {
          debugPrint('Error resolving address $id: $e');
        }
      }),
    );
  }

  /// Checks if any search or filter criteria is actively applied.
  bool get _hasActiveFilter =>
      _searchQuery.isNotEmpty || _selectedStreet != 'all' || _selectedRole != 'all';

  /// Loads users from the database.
  /// When search or filters are active (`hasActiveFilter`), queries the entire database.
  /// When no filters are active, loads in batches of 20 with pagination support.
  Future<void> _loadUsers({bool isRefresh = false}) async {
    final hasFilter = _hasActiveFilter;

    setState(() {
      _isLoading = true;
      if (!isRefresh && !hasFilter) {
        _users = [];
      }
      _lastDocId = null;
      _hasMore = !hasFilter;
    });

    try {
      List<QueryFilter>? filters;
      if (_selectedRole != 'all') {
        filters = [QueryFilter('role', FilterOperator.equal, _selectedRole)];
      }

      // If filters or search are active, query without batch limit so all matches across the whole DB are inspected.
      // If browsing without filters, load the first batch of 20 users.
      final docs = await DatabaseService().getCollection(
        'users',
        filters: filters,
        sorts: filters == null ? [QuerySort('name', descending: false)] : null,
        limit: hasFilter ? null : _batchSize,
      );

      await _fetchAddressesForUsers(docs);

      List<Map<String, dynamic>> results = docs;
      if (hasFilter) {
        results = docs.where(_matchesFilter).toList()
          ..sort((a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase()));
      }

      if (mounted) {
        setState(() {
          _users = results;
          _hasMore = !hasFilter && docs.length == _batchSize;
          if (!hasFilter && docs.isNotEmpty) {
            _lastDocId = (docs.last['id'] ?? docs.last['uid'])?.toString();
          }
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading users: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminUserManagementScreen._loadUsers');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Queries the next batch of 20 users starting after `_lastDocId` (only in un-filtered pagination mode).
  Future<void> _loadMoreUsers() async {
    if (_hasActiveFilter || !_hasMore || _isLoadingMore || _isLoading || _lastDocId == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final docs = await DatabaseService().getCollection(
        'users',
        sorts: [QuerySort('name', descending: false)],
        limit: _batchSize,
        startAfter: _lastDocId,
      );

      await _fetchAddressesForUsers(docs);

      if (mounted) {
        setState(() {
          _users.addAll(docs);
          _hasMore = docs.length == _batchSize;
          if (docs.isNotEmpty) {
            _lastDocId = (docs.last['id'] ?? docs.last['uid'])?.toString();
          }
          _isLoadingMore = false;
        });
      }
    } catch (e, stack) {
      debugPrint('Error loading more users: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminUserManagementScreen._loadMoreUsers');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  /// Formats the address display string for a user document.
  String _getUserAddressDisplay(Map<String, dynamic> userDoc) {
    final addressRef = userDoc['addressRef'] as DbReference?;
    if (addressRef == null) return '';
    return _formatAddressDisplay(_addressCache[addressRef.id]);
  }

  /// Returns the street name for a user document (from cache or addressRef).
  String _getUserStreetName(Map<String, dynamic> userDoc) {
    final addressRef = userDoc['addressRef'] as DbReference?;
    if (addressRef == null) return '';
    final addr = _addressCache[addressRef.id];
    if (addr == null) return '';
    return addr['streetName']?.toString().trim() ?? '';
  }

  /// Returns the payment status of the user's bound address.
  String _getUserPaymentStatus(Map<String, dynamic> userDoc) {
    final addressRef = userDoc['addressRef'] as DbReference?;
    if (addressRef == null) return 'none';
    final addr = _addressCache[addressRef.id];
    if (addr == null) return 'none';
    return (addr['paymentStatus'] ?? 'pending').toString().toLowerCase();
  }

  /// Returns the delivery date of the user's bound address.
  DateTime? _getUserDeliveryDate(Map<String, dynamic> userDoc) {
    final addressRef = userDoc['addressRef'] as DbReference?;
    if (addressRef == null) return null;
    final addr = _addressCache[addressRef.id];
    if (addr == null) return null;
    final raw = addr['deliveryDate'];
    return raw is DateTime ? raw : null;
  }

  /// Determines if a user document matches all current filter criteria.
  bool _matchesFilter(Map<String, dynamic> doc) {
    // 1. Role filter
    if (_selectedRole != 'all') {
      final role = (doc['role'] ?? 'resident').toString().toLowerCase();
      if (role != _selectedRole.toLowerCase()) return false;
    }

    // 2. Street filter
    if (_selectedStreet != 'all') {
      final street = _getUserStreetName(doc);
      if (street != _selectedStreet) return false;
    }

    // 3. Search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final email = (doc['email'] ?? '').toString().toLowerCase();
      final addressDisplay = _getUserAddressDisplay(doc).toLowerCase();
      final street = _getUserStreetName(doc).toLowerCase();

      final matches = name.contains(q) ||
          email.contains(q) ||
          addressDisplay.contains(q) ||
          street.contains(q);

      if (!matches) return false;
    }

    return true;
  }

  void _onSearchChanged(String val) {
    setState(() {
      _searchQuery = val.trim();
    });
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        _loadUsers();
      }
    });
  }

  void _clearFilters() {
    _searchDebounceTimer?.cancel();
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedStreet = 'all';
      _selectedRole = 'all';
    });
    _loadUsers();
  }

  void _openUserDetail(Map<String, dynamic> doc) {
    final userId = (doc['id'] ?? doc['uid'] ?? '').toString();
    final addressRef = doc['addressRef'] as DbReference?;
    final cachedAddr = addressRef != null ? _addressCache[addressRef.id] : null;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminUserDetailScreen(
          userDoc: Map<String, dynamic>.from(doc),
          initialAddressDoc: cachedAddr != null ? Map<String, dynamic>.from(cachedAddr) : null,
          onUserUpdated: (updatedUser, updatedAddress) {
            if (!mounted) return;
            setState(() {
              final idx = _users.indexWhere((u) => (u['id'] ?? u['uid']) == userId);
              if (idx != -1) {
                _users[idx] = Map<String, dynamic>.from(updatedUser);
              }
              if (updatedAddress != null) {
                final addrId = (updatedAddress['id'] ?? addressRef?.id)?.toString();
                if (addrId != null && addrId.isNotEmpty) {
                  _addressCache[addrId] = Map<String, dynamic>.from(updatedAddress);
                }
              }
            });
          },
          onUserDeleted: () {
            if (!mounted) return;
            setState(() {
              _users.removeWhere((u) => (u['id'] ?? u['uid']) == userId);
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final hasActiveFilter = _hasActiveFilter;
    final displayedUsers = _users.where(_matchesFilter).toList();

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Text(l10n.manageUsersMenu, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
              elevation: 2,
              actions: [
                IconButton(
                  key: const ValueKey('manage_users_create_user_button'),
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: l10n.createUserMenu,
                  onPressed: () async {
                    final initialRole = (_selectedRole == 'guard' || _selectedRole == 'admin')
                        ? _selectedRole
                        : 'resident';
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminCreateUserScreen(initialRole: initialRole),
                      ),
                    );
                    if (mounted) {
                      _loadUsers(isRefresh: true);
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
                  onPressed: _isLoading ? null : () => _loadUsers(isRefresh: true),
                ),
              ],
            ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadUsers(isRefresh: true);
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.isEmbedded) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: ElevatedButton.icon(
                          key: const ValueKey('manage_users_create_user_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConfig.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: Text(
                            l10n.createUserMenu,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () async {
                            final initialRole = (_selectedRole == 'guard' || _selectedRole == 'admin')
                                ? _selectedRole
                                : 'resident';
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminCreateUserScreen(initialRole: initialRole),
                              ),
                            );
                            if (mounted) {
                              _loadUsers(isRefresh: true);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: AppConfig.primaryColor),
                        tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
                        onPressed: _isLoading ? null : () => _loadUsers(isRefresh: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                // 1. Search and Filter Section Card
                _buildFilterCard(context, l10n, isDesktop, hasActiveFilter),
                const SizedBox(height: 14),

                // 2. Count & Batch Information Summary Bar
                _buildBatchInfoBar(context, l10n, displayedUsers.length, hasActiveFilter),
                const SizedBox(height: 14),

                // 3. User Summary Cards or Empty / Loading States
                if (_isLoading && displayedUsers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(l10n.loadingUsers, style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  )
                else if (displayedUsers.isEmpty)
                  _buildEmptyState(context, l10n, hasActiveFilter)
                else ...[
                  ...displayedUsers.map((userDoc) => _buildUserSummaryCard(context, l10n, userDoc)),
                  const SizedBox(height: 8),

                  // 4. Batch Exploration Load More Footer
                  _buildLoadMoreFooter(context, l10n, hasActiveFilter, displayedUsers.length),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard(BuildContext context, AppLocalizations l10n, bool isDesktop, bool hasActiveFilter) {
    final roleOptions = <(String, String, IconData)>[
      ('all', l10n.allRoles, Icons.group_outlined),
      ('resident', l10n.roleResident, Icons.home_outlined),
      ('roommate', l10n.roleRoommate, Icons.person_outline),
      ('admin', l10n.roleAdmin, Icons.admin_panel_settings_outlined),
      ('guard', l10n.roleGuard, Icons.security),
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useCompactRoleChips = constraints.maxWidth < 680;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search Input Field
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.searchUsersPlaceholder,
                    prefixIcon: const Icon(Icons.search, color: AppConfig.primaryColor),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchDebounceTimer?.cancel();
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                              _loadUsers();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 12),

                // Dropdowns and Filters Area
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Street Filter Dropdown
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: isDesktop ? 300 : constraints.maxWidth,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedStreet,
                          isExpanded: true,
                          icon: const Icon(Icons.location_on_outlined, color: AppConfig.primaryColor),
                          items: [
                            DropdownMenuItem<String>(
                              value: 'all',
                              child: Text(
                                l10n.allStreets,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            ..._availableStreets.map((street) {
                              return DropdownMenuItem<String>(
                                value: street,
                                child: Text(street, style: const TextStyle(fontSize: 13)),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedStreet = val;
                              });
                              _loadUsers();
                            }
                          },
                        ),
                      ),
                    ),

                    // Role Filter: wrapping ChoiceChips on narrow screens, SegmentedButton on wide screens
                    if (useCompactRoleChips)
                      SizedBox(
                        width: constraints.maxWidth,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: roleOptions.map((option) {
                            final (value, label, icon) = option;
                            final isSelected = _selectedRole == value;
                            return ChoiceChip(
                              key: ValueKey('role_filter_chip_$value'),
                              showCheckmark: false,
                              avatar: Icon(
                                icon,
                                size: 16,
                                color: isSelected ? Colors.white : AppConfig.primaryColor,
                              ),
                              label: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : Colors.black87,
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppConfig.primaryColor,
                              backgroundColor: Colors.grey.shade100,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onSelected: (selected) {
                                if (selected && _selectedRole != value) {
                                  setState(() {
                                    _selectedRole = value;
                                  });
                                  _loadUsers();
                                }
                              },
                            );
                          }).toList(),
                        ),
                      )
                    else
                      SegmentedButton<String>(
                        segments: roleOptions
                            .map(
                              (option) => ButtonSegment<String>(
                                value: option.$1,
                                label: Text(option.$2),
                                icon: Icon(option.$3, size: 16),
                              ),
                            )
                            .toList(),
                        selected: {_selectedRole},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            _selectedRole = newSelection.first;
                          });
                          _loadUsers();
                        },
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),

                    // Clear Filters Action Button
                    if (hasActiveFilter)
                      TextButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.filter_alt_off, size: 16, color: Colors.redAccent),
                        label: Text(
                          l10n.clearFilters,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBatchInfoBar(BuildContext context, AppLocalizations l10n, int count, bool hasActiveFilter) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              hasActiveFilter
                  ? l10n.showingFilteredUsersCount(count)
                  : l10n.showingUsersCount(count, count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                hasActiveFilter
                    ? l10n.databaseSearchActive
                    : l10n.batchExplorationInfo(_batchSize),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n, bool hasActiveFilter) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_outlined, size: 54, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              l10n.noUsersFound,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
            if (hasActiveFilter) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: Text(l10n.clearFilters),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact user summary card without inline action buttons to prevent accidental misclicks.
  /// Tapping opens `AdminUserDetailScreen` for account and property management.
  Widget _buildUserSummaryCard(BuildContext context, AppLocalizations l10n, Map<String, dynamic> doc) {
    final userId = (doc['id'] ?? doc['uid'] ?? '').toString();
    final name = (doc['name'] ?? 'Unknown').toString();
    final email = (doc['email'] ?? '').toString();
    final role = (doc['role'] ?? 'resident').toString();
    final addressDisplay = _getUserAddressDisplay(doc);
    final paymentStatus = _getUserPaymentStatus(doc);
    final deliveryDate = _getUserDeliveryDate(doc);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('user_card_$userId'),
        onTap: () => _openUserDetail(doc),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Avatar, Name/Email, Role Badge
                    Row(
                      children: [
                        _buildRoleAvatar(context, role),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildRoleBadge(role, l10n),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),

                    // Address and Payment Standing Row
                    Row(
                      children: [
                        Icon(Icons.home_outlined, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            addressDisplay.isNotEmpty ? addressDisplay : l10n.noActiveAddressLinked,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: addressDisplay.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                              color: addressDisplay.isNotEmpty ? Colors.black87 : Colors.grey.shade500,
                            ),
                          ),
                        ),
                        if (paymentStatus != 'none')
                          _buildPaymentStandingBadge(l10n, paymentStatus),
                      ],
                    ),

                    if (doc['addressRef'] != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${l10n.deliveryDateLabel}: ${_formatDeliveryDate(deliveryDate, l10n)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: deliveryDate != null ? Colors.grey.shade700 : Colors.orange.shade800,
                                fontWeight: deliveryDate != null ? FontWeight.normal : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadMoreFooter(BuildContext context, AppLocalizations l10n, bool hasActiveFilter, int count) {
    if (hasActiveFilter) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(
            l10n.showingFilteredUsersCount(count),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    if (_isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(l10n.loadingMoreUsers, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: _loadMoreUsers,
            icon: const Icon(Icons.expand_more, size: 20),
            label: Text(l10n.loadMoreUsers(_users.length)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppConfig.primaryColor,
              side: const BorderSide(color: AppConfig.primaryColor),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      );
    }

    if (_users.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            l10n.allUsersLoaded(_users.length),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Dedicated detail screen for inspecting a single user's profile, property standing,
/// and administrative actions—preventing accidental misclicks in the directory list.
class AdminUserDetailScreen extends StatefulWidget {
  final Map<String, dynamic> userDoc;
  final Map<String, dynamic>? initialAddressDoc;
  final void Function(Map<String, dynamic> updatedUser, Map<String, dynamic>? updatedAddress)? onUserUpdated;
  final VoidCallback? onUserDeleted;

  const AdminUserDetailScreen({
    super.key,
    required this.userDoc,
    this.initialAddressDoc,
    this.onUserUpdated,
    this.onUserDeleted,
  });

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  late Map<String, dynamic> _userDoc;
  Map<String, dynamic>? _addressDoc;
  bool _isLoadingAddress = false;
  bool _isProcessing = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _userDoc = Map<String, dynamic>.from(widget.userDoc);
    _addressDoc = widget.initialAddressDoc != null
        ? Map<String, dynamic>.from(widget.initialAddressDoc!)
        : null;
    if (_addressDoc == null && _userDoc['addressRef'] is DbReference) {
      _loadAddress();
    }
  }

  Future<void> _loadAddress() async {
    final ref = _userDoc['addressRef'];
    if (ref is! DbReference) return;

    setState(() {
      _isLoadingAddress = true;
    });
    try {
      final addr = await DatabaseService().getDocument('addresses', ref.id);
      if (mounted) {
        setState(() {
          _addressDoc = addr;
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user detail address: $e');
      if (mounted) {
        setState(() {
          _isLoadingAddress = false;
        });
      }
    }
  }

  String get _userId => (_userDoc['id'] ?? _userDoc['uid'] ?? '').toString();

  Future<void> _editAddressDeliveryDate(BuildContext context, String addressId) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final rawDelivery = _addressDoc?['deliveryDate'];
    final currentDelivery = rawDelivery is DateTime ? rawDelivery : null;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDelivery ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await DatabaseService().updateDocument('addresses', addressId, {
        'deliveryDate': picked,
      });

      final updatedAddr = Map<String, dynamic>.from(_addressDoc ?? {'id': addressId});
      updatedAddr['deliveryDate'] = picked;

      if (mounted) {
        setState(() {
          _addressDoc = updatedAddr;
        });
        widget.onUserUpdated?.call(_userDoc, _addressDoc);
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.deliveryDateUpdatedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error updating delivery date: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminUserDetailScreen._editAddressDeliveryDate');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.deliveryDateUpdatedError(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _toggleAdminRole(BuildContext context, bool currentIsAdmin) async {
    final l10n = AppLocalizations.of(context)!;
    final targetUid = _userId;
    final currentAdminUid = Backend.auth.currentUser?.uid;

    if (targetUid == currentAdminUid && currentIsAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.cannotDeleteSelfAdminError),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isProcessing = true;
    });

    try {
      final newRole = currentIsAdmin ? 'resident' : 'admin';
      await FunctionsService().callFunction('setCustomUserClaims', {
        'uid': targetUid,
        'claims': {
          'admin': !currentIsAdmin,
          'resident': true,
        },
      });

      await DatabaseService().updateDocument('users', targetUid, {
        'role': newRole,
      });

      if (mounted) {
        setState(() {
          _userDoc['role'] = newRole;
        });
        widget.onUserUpdated?.call(_userDoc, _addressDoc);
        messenger.showSnackBar(
          SnackBar(
            content: Text(currentIsAdmin ? l10n.userRevokedSuccess : l10n.userPromotedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error updating role: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminUserDetailScreen._toggleAdminRole');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _changePassword(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final targetUid = _userId;
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.changePasswordTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.passwordComplexityHelper,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: l10n.newPasswordLabel,
                helperText: l10n.passwordComplexityHelper,
                border: const OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConfig.primaryColor, foregroundColor: Colors.white),
            onPressed: () async {
              final pwd = controller.text.trim();
              if (!PasswordValidator.isValid(pwd)) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.passwordMinLengthValidation)),
                );
                return;
              }
              Navigator.pop(dialogContext);
              setState(() {
                _isProcessing = true;
              });
              try {
                await FunctionsService().callFunction('adminUpdatePassword', {
                  'uid': targetUid,
                  'newPassword': pwd,
                });
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.passwordUpdatedSuccess), backgroundColor: AppConfig.secondaryColor),
                  );
                }
              } catch (e, stack) {
                debugPrint('Error updating password: $e');
                Backend.crashlytics.recordError(e, stack, reason: 'AdminUserDetailScreen._changePassword');
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _isProcessing = false;
                  });
                }
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _unbindUserAddress(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.resignAddressLabel),
        content: Text(l10n.resignConfirmText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.ok, style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });
    try {
      await FunctionsService().callFunction('unbindAddress', {
        'uid': _userId,
      });
      if (mounted) {
        setState(() {
          _userDoc['addressRef'] = null;
          _addressDoc = null;
        });
        widget.onUserUpdated?.call(_userDoc, null);
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.addressUnlinkedSuccess),
            backgroundColor: AppConfig.successColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error unbinding address: $e');
      Backend.crashlytics.recordError(
        e,
        stack,
        reason: 'AdminUserDetailScreen._unbindUserAddress',
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.errorPrefix(e.toString())),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _deleteUserAccount(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final targetUid = _userId;
    final currentAdminUid = Backend.auth.currentUser?.uid;

    if (targetUid == currentAdminUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.cannotDeleteSelfAdminError),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteUserConfirmTitle),
        content: Text(l10n.deleteUserConfirmText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() {
                _isProcessing = true;
                _isDeleting = true;
              });

              try {
                await FunctionsService().callFunction('adminDeleteUser', {
                  'uid': targetUid,
                });

                widget.onUserDeleted?.call();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(l10n.deleteUserSuccess),
                    backgroundColor: AppConfig.secondaryColor,
                  ),
                );
                if (mounted) {
                  navigator.pop();
                }
              } catch (e, stack) {
                debugPrint('Error deleting user account: $e');
                Backend.crashlytics.recordError(
                  e,
                  stack,
                  reason: 'AdminUserDetailScreen._deleteUserAccount',
                );
                if (mounted) {
                  setState(() {
                    _isProcessing = false;
                    _isDeleting = false;
                  });
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.errorPrefix(e.toString())),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = (_userDoc['name'] ?? 'Unknown').toString();
    final email = (_userDoc['email'] ?? '').toString();
    final role = (_userDoc['role'] ?? 'resident').toString();
    final isAdmin = role == 'admin';
    final isGuard = role == 'guard';
    final addressRef = _userDoc['addressRef'] as DbReference?;
    final hasAddress = addressRef != null;

    final addressDisplay = hasAddress ? _formatAddressDisplay(_addressDoc) : '';
    final paymentStatus = (hasAddress && _addressDoc != null)
        ? (_addressDoc!['paymentStatus'] ?? 'pending').toString().toLowerCase()
        : 'none';
    final rawDelivery = _addressDoc?['deliveryDate'];
    final DateTime? deliveryDate = rawDelivery is DateTime ? rawDelivery : null;

    Widget buildProfileAndPropertyCard() {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. User Identity Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildRoleAvatar(context, role, radius: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppConfig.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildRoleBadge(role, l10n),
                ],
              ),
              const SizedBox(height: 22),
              const Divider(height: 1),
              const SizedBox(height: 20),

              // 2. Linked Property & Payment Standing
              Text(
                l10n.selectAddressLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 10),
              if (_isLoadingAddress)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppConfig.cardBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.home_outlined,
                            size: 20,
                            color: hasAddress ? AppConfig.primaryColor : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              addressDisplay.isNotEmpty ? addressDisplay : l10n.noActiveAddressLinked,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: addressDisplay.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                                color: addressDisplay.isNotEmpty ? AppConfig.textColor : Colors.grey.shade600,
                              ),
                            ),
                          ),
                          if (paymentStatus != 'none')
                            _buildPaymentStandingBadge(l10n, paymentStatus),
                        ],
                      ),
                      if (hasAddress) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${l10n.deliveryDateLabel}: ${_formatDeliveryDate(deliveryDate, l10n)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: deliveryDate != null ? Colors.grey.shade800 : Colors.orange.shade800,
                                  fontWeight: deliveryDate != null ? FontWeight.w500 : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    Widget buildActionsCard() {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Standard Account & Property Actions
              Text(
                l10n.userActionsSectionTitle,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppConfig.primaryColor,
                ),
              ),
              const SizedBox(height: 14),

              OutlinedButton.icon(
                key: const ValueKey('user_detail_change_password_button'),
                onPressed: _isProcessing ? null : () => _changePassword(context),
                icon: const Icon(Icons.lock_reset, size: 18),
                label: Text(l10n.changePasswordTitle),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size.fromHeight(46),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),

              if (!isGuard) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('user_detail_toggle_admin_button'),
                  onPressed: _isProcessing ? null : () => _toggleAdminRole(context, isAdmin),
                  icon: Icon(isAdmin ? Icons.shield_outlined : Icons.security, size: 18),
                  label: Text(isAdmin ? l10n.revokeAdminButton : l10n.promoteAdminButton),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(46),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    foregroundColor: isAdmin ? Colors.orange.shade800 : AppConfig.primaryColor,
                    side: BorderSide(
                      color: isAdmin
                          ? Colors.orange.shade400
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],

              if (hasAddress) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('user_detail_edit_delivery_date_button'),
                  onPressed: _isProcessing
                      ? null
                      : () => _editAddressDeliveryDate(context, addressRef.id),
                  icon: const Icon(Icons.edit_calendar, size: 18),
                  label: Text(
                    deliveryDate != null ? l10n.editDeliveryDateButton : l10n.setDeliveryDateButton,
                  ),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(46),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 20),

              // 2. Isolated Sensitive / Destructive Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.userDangerZoneSectionTitle,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (hasAddress) ...[
                      OutlinedButton.icon(
                        key: const ValueKey('user_detail_unbind_address_button'),
                        onPressed: _isProcessing ? null : () => _unbindUserAddress(context),
                        icon: const Icon(Icons.link_off, size: 18),
                        label: Text(l10n.resignAddressLabel),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          minimumSize: const Size.fromHeight(46),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ElevatedButton.icon(
                      key: const ValueKey('user_detail_delete_user_button'),
                      onPressed: (_isProcessing || _isDeleting)
                          ? null
                          : () => _deleteUserAccount(context),
                      icon: _isDeleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.delete_forever, size: 18),
                      label: Text(l10n.deleteUserButton),
                      style: ElevatedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size.fromHeight(46),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

    return Scaffold(
      backgroundColor: AppConfig.backgroundColor,
      appBar: AppBar(
        title: Text(l10n.userManagementMenu, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: buildProfileAndPropertyCard(),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 2,
                              child: buildActionsCard(),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildProfileAndPropertyCard(),
                            const SizedBox(height: 16),
                            buildActionsCard(),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _formatAddressDisplay(Map<String, dynamic>? addr) {
  if (addr == null) return '';
  final street = addr['streetName']?.toString().trim() ?? '';
  final number = addr['number']?.toString().trim() ?? '';
  if (number.isNotEmpty && number != '0') {
    return '$street #$number';
  }
  return street;
}

String _formatDeliveryDate(DateTime? date, AppLocalizations l10n) {
  if (date == null) return l10n.deliveryDateNotSet;
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

Widget _buildRoleAvatar(BuildContext context, String role, {double radius = 20}) {
  final isAdmin = role == 'admin';
  final isGuard = role == 'guard';
  return CircleAvatar(
    radius: radius,
    backgroundColor: isAdmin
        ? Colors.amber.shade100
        : isGuard
            ? Colors.blue.shade100
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
    child: Icon(
      isAdmin
          ? Icons.admin_panel_settings
          : isGuard
              ? Icons.security
              : Icons.person,
      size: radius * 1.15,
      color: isAdmin
          ? Colors.amber.shade900
          : isGuard
              ? Colors.blue.shade900
              : AppConfig.primaryColor,
    ),
  );
}

Widget _buildRoleBadge(String role, AppLocalizations l10n) {
  final isAdmin = role == 'admin';
  final isGuard = role == 'guard';

  String roleTag = role.toUpperCase();
  if (role == 'resident') roleTag = l10n.roleResident.toUpperCase();
  if (role == 'roommate') roleTag = l10n.roleRoommate.toUpperCase();
  if (role == 'admin') roleTag = l10n.roleAdmin.toUpperCase();
  if (role == 'guard') roleTag = l10n.roleGuard.toUpperCase();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: isAdmin
          ? Colors.amber.shade50
          : (isGuard ? Colors.blue.shade50 : Colors.teal.shade50),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isAdmin
            ? Colors.amber.shade400
            : (isGuard ? Colors.blue.shade300 : Colors.teal.shade300),
      ),
    ),
    child: Text(
      roleTag,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: isAdmin
            ? Colors.amber.shade900
            : (isGuard ? Colors.blue.shade900 : Colors.teal.shade900),
      ),
    ),
  );
}

Widget _buildPaymentStandingBadge(AppLocalizations l10n, String status) {
  Color bg;
  Color fg;
  String label;

  switch (status) {
    case 'paid':
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
      label = l10n.statusPaid;
      break;
    case 'restricted':
      bg = Colors.red.shade50;
      fg = Colors.red.shade800;
      label = l10n.statusRestricted;
      break;
    case 'reviewing':
      bg = Colors.amber.shade50;
      fg = Colors.amber.shade900;
      label = l10n.statusReviewing;
      break;
    default:
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade800;
      label = l10n.statusPending;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: fg.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
    ),
  );
}

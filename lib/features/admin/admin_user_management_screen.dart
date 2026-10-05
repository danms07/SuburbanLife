import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../payments/payment_service.dart';

class AdminUserManagementScreen extends StatefulWidget {
  const AdminUserManagementScreen({super.key});

  @override
  State<AdminUserManagementScreen> createState() => _AdminUserManagementScreenState();
}

class _AdminUserManagementScreenState extends State<AdminUserManagementScreen> {
  static const int _batchSize = 20;

  bool _isProcessing = false;
  String? _processingDeleteUid;

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
        sorts: [QuerySort('name', descending: false)],
        limit: hasFilter ? null : _batchSize,
      );

      await _fetchAddressesForUsers(docs);

      List<Map<String, dynamic>> results = docs;
      if (hasFilter) {
        results = docs.where(_matchesFilter).toList();
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
    final addr = _addressCache[addressRef.id];
    if (addr == null) return '';
    final street = addr['streetName']?.toString().trim() ?? '';
    final number = addr['number']?.toString().trim() ?? '';
    if (number.isNotEmpty && number != '0') {
      return '$street #$number';
    }
    return street;
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
    return addr['deliveryDate'] as DateTime?;
  }

  /// Opens a DatePicker dialog to update the delivery date for an address.
  Future<void> _editAddressDeliveryDate(BuildContext context, String addressId) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final currentAddr = _addressCache[addressId];
    final currentDelivery = currentAddr?['deliveryDate'] as DateTime?;

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDelivery ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        _isProcessing = true;
      });

      try {
        await DatabaseService().updateDocument('addresses', addressId, {
          'deliveryDate': picked,
        });
        final newStatus = await PaymentService().recalculatePaymentStatusForAddress(addressId);
        if (currentAddr != null) {
          currentAddr['deliveryDate'] = picked;
          currentAddr['paymentStatus'] = newStatus;
        }
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(l10n.deliveryDateUpdatedSuccess),
              backgroundColor: AppConfig.secondaryColor,
            ),
          );
        }
      } catch (e, stack) {
        debugPrint('Error updating delivery date: $e');
        Backend.crashlytics.recordError(e, stack, reason: 'AdminUserManagementScreen._editAddressDeliveryDate');
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

  void _deleteUserAccount(BuildContext context, String targetUid, String targetName) {
    final l10n = AppLocalizations.of(context)!;
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
                _processingDeleteUid = targetUid;
              });

              try {
                await FunctionsService().callFunction('adminDeleteUser', {
                  'uid': targetUid,
                });

                if (mounted) {
                  setState(() {
                    _users.removeWhere((u) => (u['id'] ?? u['uid']) == targetUid);
                  });
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.deleteUserSuccess),
                      backgroundColor: AppConfig.secondaryColor,
                    ),
                  );
                }
              } catch (e, stack) {
                debugPrint('Error deleting user account: $e');
                Backend.crashlytics.recordError(
                  e,
                  stack,
                  reason: 'AdminUserManagementScreen._deleteUserAccount',
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
                    _processingDeleteUid = null;
                  });
                }
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _toggleAdminRole(BuildContext context, String targetUid, bool currentIsAdmin) async {
    final l10n = AppLocalizations.of(context)!;
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
          final idx = _users.indexWhere((u) => (u['id'] ?? u['uid']) == targetUid);
          if (idx != -1) {
            _users[idx]['role'] = newRole;
          }
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(currentIsAdmin ? l10n.userRevokedSuccess : l10n.userPromotedSuccess),
            backgroundColor: AppConfig.secondaryColor,
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Error updating role: $e');
      Backend.crashlytics.recordError(e, stack, reason: 'AdminUserManagementScreen.toggleAdminRole');
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

  void _changePassword(BuildContext context, String targetUid) {
    final l10n = AppLocalizations.of(context)!;
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
              setState(() { _isProcessing = true; });
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
                Backend.crashlytics.recordError(e, stack, reason: 'AdminUserManagementScreen.updatePassword');
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.errorPrefix(e.toString())), backgroundColor: Colors.redAccent),
                  );
                }
              } finally {
                if (mounted) setState(() { _isProcessing = false; });
              }
            },
            child: Text(l10n.save),
          ),
        ],
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
      appBar: AppBar(
        title: Text(l10n.manageUsersMenu, style: const TextStyle(fontFamily: AppConfig.fontFamily)),
        backgroundColor: AppConfig.primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
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
                // 1. Search and Filter Section Card
                _buildFilterCard(context, l10n, isDesktop, hasActiveFilter),
                const SizedBox(height: 14),

                // 2. Count & Batch Information Summary Bar
                _buildBatchInfoBar(context, l10n, displayedUsers.length, hasActiveFilter),
                const SizedBox(height: 14),

                // 3. User Cards or Empty / Loading States
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
                  ...displayedUsers.map((userDoc) => _buildUserCard(context, l10n, userDoc)),
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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

            // Dropdowns and Filters Row
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Street Filter Dropdown
                Container(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 300 : double.infinity),
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

                // Role Segmented Button
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'all',
                        label: Text(l10n.allRoles),
                        icon: const Icon(Icons.group_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'resident',
                        label: Text(l10n.roleResident),
                        icon: const Icon(Icons.home_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'roommate',
                        label: Text(l10n.roleRoommate),
                        icon: const Icon(Icons.person_outline, size: 16),
                      ),
                      ButtonSegment(
                        value: 'admin',
                        label: Text(l10n.roleAdmin),
                        icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'guard',
                        label: Text(l10n.roleGuard),
                        icon: const Icon(Icons.security, size: 16),
                      ),
                    ],
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
        ),
      ),
    );
  }

  Widget _buildBatchInfoBar(BuildContext context, AppLocalizations l10n, int count, bool hasActiveFilter) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

  Widget _buildUserCard(BuildContext context, AppLocalizations l10n, Map<String, dynamic> doc) {
    final userId = (doc['id'] ?? doc['uid'] ?? '').toString();
    final name = doc['name'] ?? 'Unknown';
    final email = doc['email'] ?? '';
    final role = doc['role'] ?? 'resident';
    final isAdmin = role == 'admin';

    // Translate Role Tag
    String roleTag = role.toUpperCase();
    if (role == 'resident') roleTag = l10n.roleResident.toUpperCase();
    if (role == 'roommate') roleTag = l10n.roleRoommate.toUpperCase();
    if (role == 'admin') roleTag = l10n.roleAdmin.toUpperCase();
    if (role == 'guard') roleTag = l10n.roleGuard.toUpperCase();

    final isDeletingThisUser = _processingDeleteUid == userId;
    final addressDisplay = _getUserAddressDisplay(doc);
    final paymentStatus = _getUserPaymentStatus(doc);
    final deliveryDate = _getUserDeliveryDate(doc);

    return Card(
      key: ValueKey('user_card_$userId'),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Top Row: Avatar, Name/Email, Role Badge
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isAdmin
                      ? Colors.amber.shade100
                      : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  child: Icon(
                    isAdmin ? Icons.admin_panel_settings : Icons.person,
                    color: isAdmin ? Colors.amber.shade900 : AppConfig.primaryColor,
                  ),
                ),
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
                // Role Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isAdmin
                        ? Colors.amber.shade50
                        : (role == 'guard' ? Colors.blue.shade50 : Colors.teal.shade50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isAdmin
                          ? Colors.amber.shade400
                          : (role == 'guard' ? Colors.blue.shade300 : Colors.teal.shade300),
                    ),
                  ),
                  child: Text(
                    roleTag,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isAdmin
                          ? Colors.amber.shade900
                          : (role == 'guard' ? Colors.blue.shade900 : Colors.teal.shade900),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                  _buildPaymentBadge(context, l10n, paymentStatus),
              ],
            ),

            if (doc['addressRef'] != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    '${l10n.deliveryDateLabel}: ${_formatDeliveryDate(deliveryDate, l10n)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: deliveryDate != null ? Colors.grey.shade700 : Colors.orange.shade800,
                      fontWeight: deliveryDate != null ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            // Action Buttons Row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Change Password Button
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _changePassword(context, userId),
                  icon: const Icon(Icons.lock_reset, size: 16),
                  label: Text(l10n.changePasswordTitle, style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                // Make/Remove Admin Role
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _toggleAdminRole(context, userId, isAdmin),
                  icon: Icon(isAdmin ? Icons.shield_outlined : Icons.security, size: 16),
                  label: Text(
                    isAdmin ? l10n.revokeAdminButton : l10n.promoteAdminButton,
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: isAdmin ? Colors.orange.shade800 : AppConfig.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                // Edit / Set Delivery Date
                if (doc['addressRef'] != null)
                  OutlinedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () => _editAddressDeliveryDate(context, (doc['addressRef'] as DbReference).id),
                    icon: const Icon(Icons.edit_calendar, size: 16),
                    label: Text(
                      deliveryDate != null ? l10n.editDeliveryDateButton : l10n.setDeliveryDateButton,
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),

                // Force Unbind Address (if linked)
                if (doc['addressRef'] != null)
                  OutlinedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () async {
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
                            if (confirmed == true) {
                              setState(() {
                                _isProcessing = true;
                              });
                              try {
                                await FunctionsService().callFunction('unbindAddress', {
                                  'uid': userId,
                                });
                                if (mounted) {
                                  setState(() {
                                    final idx = _users.indexWhere((u) => (u['id'] ?? u['uid']) == userId);
                                    if (idx != -1) {
                                      _users[idx]['addressRef'] = null;
                                    }
                                  });
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
                                  reason: 'AdminUserManagementScreen.unbindAddress',
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
                          },
                    icon: const Icon(Icons.link_off, size: 16),
                    label: Text(l10n.resignAddressLabel, style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),

                // Delete User Account Button
                ElevatedButton.icon(
                  onPressed: (_isProcessing || isDeletingThisUser)
                      ? null
                      : () => _deleteUserAccount(context, userId, name),
                  icon: isDeletingThisUser
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.delete_forever, size: 16),
                  label: Text(l10n.deleteUserButton, style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentBadge(BuildContext context, AppLocalizations l10n, String status) {
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

  String _formatDeliveryDate(DateTime? date, AppLocalizations l10n) {
    if (date == null) return l10n.deliveryDateNotSet;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
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

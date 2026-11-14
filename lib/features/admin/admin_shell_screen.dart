import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../announcements/announcements_screen.dart';
import '../auth/admin_resident_approval_screen.dart';
import '../qr_access/qr_generator_screen.dart';
import '../sanctions/admin_sanctions_screen.dart';
import '../transparency/transparency_screen.dart';
import 'admin_access_logs_screen.dart';
import 'admin_booking_approval_screen.dart';
import 'admin_bulk_address_import_screen.dart';
import 'admin_bulk_user_import_screen.dart';
import 'admin_create_user_screen.dart';
import 'admin_facilities_screen.dart';
import 'admin_payment_approval_screen.dart';
import 'admin_payment_report_screen.dart';
import 'admin_bulk_payment_import_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_upload_payment_screen.dart';
import 'admin_user_management_screen.dart';

/// Enumerates all navigable views inside the Admin Panel workspace shell.
enum AdminSection {
  overview,

  // User Management
  approveResidents,
  createUser,
  bulkUserImport,
  userDirectory,

  // Residential Management
  manageFacilities,
  reviewBookings,
  accessLogs,
  bulkAddressImport,
  sanctions,

  // Finance
  reviewPayments,
  uploadPayment,
  downloadPaymentReport,
  importPaymentHistory,

  // Transparency & Community
  announcements,
  transparencyDocs,
  // TODO(feature): Polls / community surveys (uncomment when screen is implemented)
  // polls,

  // General Settings
  generalSettings,
}

class _AdminNavItem {
  final AdminSection section;
  final String label;
  final IconData icon;
  final int badgeCount;

  const _AdminNavItem({
    required this.section,
    required this.label,
    required this.icon,
    this.badgeCount = 0,
  });
}

class _AdminNavGroup {
  final String id;
  final String title;
  final IconData icon;
  final List<_AdminNavItem> items;

  const _AdminNavGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.items,
  });

  int get totalBadgeCount =>
      items.fold<int>(0, (sum, item) => sum + item.badgeCount);
}

/// Adaptive NavDrawer workspace shell for system administrators.
///
/// Renders a persistent left navigation sidebar on wide/desktop viewports
/// (`>= 900px`) and collapses into a modal hamburger `Drawer` on mobile/narrow
/// viewports (`< 900px`).
class AdminShellScreen extends StatefulWidget {
  final String appTitle;
  final bool isAdmin;
  final bool isResident;
  final VoidCallback onSwitchToResidentView;
  final Future<void> Function() onResignAdminRole;
  final VoidCallback onLogout;

  const AdminShellScreen({
    super.key,
    required this.appTitle,
    required this.isAdmin,
    required this.isResident,
    required this.onSwitchToResidentView,
    required this.onResignAdminRole,
    required this.onLogout,
  });

  static const double desktopBreakpoint = 900.0;

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  AdminSection _selectedSection = AdminSection.overview;
  final Set<String> _expandedGroups = <String>{};
  int _programmaticExpandGeneration = 0;
  bool _openCreateAnnouncementOnMount = false;
  bool _scanOnExitEnabled = false;
  bool _mobilePendingApprovalsExpanded = false;
  bool _mobileCommunityStatsExpanded = false;

  // Real-time badge & KPI counts
  int _pendingClaimsCount = 0;
  int _pendingPaymentsCount = 0;
  int _pendingBookingsCount = 0;
  int _currentlyInsideCount = 0;
  int _activeSanctionsCount = 0;

  StreamSubscription<List<Map<String, dynamic>>>? _claimsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _paymentsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _bookingsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _insideLogsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _sanctionsSub;
  StreamSubscription<Map<String, dynamic>?>? _appSettingsSub;

  @override
  void initState() {
    super.initState();
    _initBadgeStreams();
  }

  void _initBadgeStreams() {
    final db = DatabaseService();

    _appSettingsSub = db.streamDocument('config', 'app_settings').listen(
      (doc) {
        if (mounted) {
          setState(() {
            _scanOnExitEnabled = doc?['scanOnExitEnabled'] == true;
          });
        }
      },
      onError: (Object e) {
        debugPrint('Error streaming config/app_settings: $e');
      },
    );

    _claimsSub = db.streamCollection('ownership_claims').listen(
      (docs) {
        if (mounted) {
          setState(() {
            _pendingClaimsCount = docs.length;
          });
        }
      },
      onError: (Object e) {
        debugPrint('Error streaming ownership_claims count: $e');
      },
    );

    _paymentsSub = db
        .streamCollection(
          'payments',
          filters: [QueryFilter('status', FilterOperator.equal, 'pending')],
        )
        .listen(
          (docs) {
            if (mounted) {
              setState(() {
                _pendingPaymentsCount = docs.length;
              });
            }
          },
          onError: (Object e) {
            debugPrint('Error streaming pending payments count: $e');
          },
        );

    _bookingsSub = db
        .streamCollection(
          'bookings',
          filters: [
            QueryFilter('status', FilterOperator.equal, 'pending review'),
          ],
        )
        .listen(
          (docs) {
            if (mounted) {
              setState(() {
                _pendingBookingsCount = docs.length;
              });
            }
          },
          onError: (Object e) {
            debugPrint('Error streaming pending bookings count: $e');
          },
        );

    _insideLogsSub = db
        .streamCollection(
          'access_logs',
          filters: [QueryFilter('isInside', FilterOperator.equal, true)],
        )
        .listen(
          (docs) {
            if (mounted) {
              setState(() {
                _currentlyInsideCount = docs.length;
              });
            }
          },
          onError: (Object e) {
            debugPrint('Error streaming currently inside count: $e');
          },
        );

    _sanctionsSub = db
        .streamCollection(
          'sanctions',
          filters: [QueryFilter('status', FilterOperator.equal, 'active')],
        )
        .listen(
          (docs) {
            if (mounted) {
              setState(() {
                _activeSanctionsCount = docs.length;
              });
            }
          },
          onError: (Object e) {
            debugPrint('Error streaming active sanctions count: $e');
          },
        );
  }

  @override
  void dispose() {
    _claimsSub?.cancel();
    _paymentsSub?.cancel();
    _bookingsSub?.cancel();
    _insideLogsSub?.cancel();
    _sanctionsSub?.cancel();
    _appSettingsSub?.cancel();
    super.dispose();
  }

  List<_AdminNavGroup> _buildGroups(AppLocalizations l10n) {
    return [
      _AdminNavGroup(
        id: 'user_management',
        title: l10n.adminGroupUserManagement,
        icon: Icons.manage_accounts,
        items: [
          _AdminNavItem(
            section: AdminSection.approveResidents,
            label: l10n.approveResidentsMenu,
            icon: Icons.verified_user,
            badgeCount: _pendingClaimsCount,
          ),
          _AdminNavItem(
            section: AdminSection.createUser,
            label: l10n.createUserMenu,
            icon: Icons.person_add_alt_1,
          ),
          _AdminNavItem(
            section: AdminSection.bulkUserImport,
            label: l10n.bulkUserImportMenu,
            icon: Icons.group_add,
          ),
          _AdminNavItem(
            section: AdminSection.userDirectory,
            label: l10n.manageUsersMenu,
            icon: Icons.people_alt,
          ),
        ],
      ),
      _AdminNavGroup(
        id: 'residential_management',
        title: l10n.adminGroupResidentialManagement,
        icon: Icons.apartment,
        items: [
          _AdminNavItem(
            section: AdminSection.manageFacilities,
            label: l10n.manageFacilitiesMenu,
            icon: Icons.category,
          ),
          _AdminNavItem(
            section: AdminSection.reviewBookings,
            label: l10n.reviewBookingsMenu,
            icon: Icons.event_available,
            badgeCount: _pendingBookingsCount,
          ),
          _AdminNavItem(
            section: AdminSection.accessLogs,
            label: l10n.accessLogsMenu,
            icon: Icons.history,
          ),
          _AdminNavItem(
            section: AdminSection.bulkAddressImport,
            label: l10n.bulkAddressImportMenu,
            icon: Icons.domain_add,
          ),
          _AdminNavItem(
            section: AdminSection.sanctions,
            label: l10n.adminSanctionsTitle,
            icon: Icons.gavel,
          ),
        ],
      ),
      _AdminNavGroup(
        id: 'finance',
        title: l10n.adminGroupFinance,
        icon: Icons.account_balance_wallet,
        items: [
          _AdminNavItem(
            section: AdminSection.reviewPayments,
            label: l10n.reviewPaymentsMenu,
            icon: Icons.payments,
            badgeCount: _pendingPaymentsCount,
          ),
          _AdminNavItem(
            section: AdminSection.uploadPayment,
            label: l10n.uploadPaymentOnBehalfMenu,
            icon: Icons.upload_file,
          ),
          _AdminNavItem(
            section: AdminSection.downloadPaymentReport,
            label: l10n.downloadReportMenu,
            icon: Icons.table_chart,
          ),
          _AdminNavItem(
            section: AdminSection.importPaymentHistory,
            label: l10n.bulkPaymentImportMenu,
            icon: Icons.history_edu,
          ),
        ],
      ),
      _AdminNavGroup(
        id: 'transparency_community',
        title: l10n.adminGroupTransparencyCommunity,
        icon: Icons.forum,
        items: [
          _AdminNavItem(
            section: AdminSection.announcements,
            label: l10n.manageAnnouncements,
            icon: Icons.announcement,
          ),
          _AdminNavItem(
            section: AdminSection.transparencyDocs,
            label: l10n.manageTransparencyDocs,
            icon: Icons.description,
          ),
          // TODO(feature): Polls / community surveys (AdminSection.polls)
          // Reserved menu slot — keep hidden until feature is implemented.
        ],
      ),
      _AdminNavGroup(
        id: 'general_settings',
        title: l10n.adminGroupGeneralSettings,
        icon: Icons.settings,
        items: [
          _AdminNavItem(
            section: AdminSection.generalSettings,
            label: l10n.adminSettingsMenu,
            icon: Icons.tune,
          ),
        ],
      ),
    ];
  }

  String? _findGroupIdForSection(
    AdminSection section,
    List<_AdminNavGroup> groups,
  ) {
    for (final group in groups) {
      if (group.items.any((item) => item.section == section)) {
        return group.id;
      }
    }
    return null;
  }

  void _selectSection(
    AdminSection section, {
    required List<_AdminNavGroup> groups,
    bool closeDrawer = false,
    bool expandParentGroup = false,
    bool openCreateAnnouncement = false,
  }) {
    if (closeDrawer && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    final parentGroupId = _findGroupIdForSection(section, groups);
    setState(() {
      _selectedSection = section;
      _openCreateAnnouncementOnMount = openCreateAnnouncement;
      if (expandParentGroup &&
          parentGroupId != null &&
          !_expandedGroups.contains(parentGroupId)) {
        _expandedGroups.add(parentGroupId);
        _programmaticExpandGeneration++;
      }
    });
  }

  String _resolveSectionTitle(
    AdminSection section,
    AppLocalizations l10n,
    List<_AdminNavGroup> groups,
  ) {
    if (section == AdminSection.overview) {
      return '${widget.appTitle} (Admin)';
    }
    for (final group in groups) {
      for (final item in group.items) {
        if (item.section == section) {
          return item.label;
        }
      }
    }
    return '${widget.appTitle} (Admin)';
  }

  void _confirmResignAdmin(BuildContext context, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.resignAdminRole),
        content: Text(l10n.resignAdminConfirm),
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
              await widget.onResignAdminRole();
            },
            child: Text(l10n.resignAdminRole),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groups = _buildGroups(l10n);
    final activeTitle = _resolveSectionTitle(_selectedSection, l10n, groups);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop =
            constraints.maxWidth >= AdminShellScreen.desktopBreakpoint;

        final activeContent = _buildActiveSectionWidget(
          groups,
          l10n,
          isMobile: !isDesktop,
        );

        // Allow TransparencyScreen to manage its own nested folder PopScope without interference
        final shouldInterceptBack =
            _selectedSection != AdminSection.overview &&
            _selectedSection != AdminSection.transparencyDocs;

        return PopScope(
          canPop: !shouldInterceptBack,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            setState(() {
              _selectedSection = AdminSection.overview;
            });
          },
          child: Scaffold(
            backgroundColor: AppConfig.backgroundColor,
            appBar: AppBar(
              backgroundColor: AppConfig.primaryColor,
              foregroundColor: Colors.white,
              title: _selectedSection == AdminSection.overview
                  ? Text(
                      activeTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: AppConfig.brandingFontFamily,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          activeTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: AppConfig.fontFamily,
                          ),
                        ),
                        Text(
                          '${widget.appTitle} (Admin)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontFamily: AppConfig.brandingFontFamily,
                          ),
                        ),
                      ],
                    ),
              actions: [
                if (widget.isAdmin && widget.isResident) ...[
                  IconButton(
                    icon: const Icon(Icons.waving_hand),
                    tooltip: l10n.resignAdminRole,
                    onPressed: () => _confirmResignAdmin(context, l10n),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person),
                    tooltip: l10n.switchToResidentViewTooltip,
                    onPressed: widget.onSwitchToResidentView,
                  ),
                ],
              ],
            ),
            drawer: isDesktop
                ? null
                : Drawer(
                    key: const ValueKey('admin_mobile_drawer'),
                    child: _buildNavigationMenu(
                      context: context,
                      l10n: l10n,
                      groups: groups,
                      isMobileDrawer: true,
                    ),
                  ),
            floatingActionButton: _selectedSection == AdminSection.overview
                ? FloatingActionButton.extended(
                    key: const ValueKey('admin_overview_generate_qr_fab'),
                    backgroundColor: AppConfig.primaryColor,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.qr_code),
                    label: Text(l10n.generateQr),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const QrGeneratorScreen(),
                        ),
                      );
                    },
                  )
                : null,
            body: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        key: const ValueKey('admin_desktop_sidebar'),
                        width: 290,
                        child: Material(
                          color: Colors.white,
                          child: _buildNavigationMenu(
                            context: context,
                            l10n: l10n,
                            groups: groups,
                            isMobileDrawer: false,
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                      Expanded(child: activeContent),
                    ],
                  )
                : activeContent,
          ),
        );
      },
    );
  }

  Widget _buildNavigationMenu({
    required BuildContext context,
    required AppLocalizations l10n,
    required List<_AdminNavGroup> groups,
    required bool isMobileDrawer,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isOverviewSelected = _selectedSection == AdminSection.overview;

    return Column(
      children: [
        if (isMobileDrawer)
          DrawerHeader(
            margin: EdgeInsets.zero,
            decoration: const BoxDecoration(color: AppConfig.primaryColor),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    AppConfig.appLogoAsset,
                    height: 68,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.adminPanelTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppConfig.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            children: [
              // Overview Home Destination
              _buildLeafNavTile(
                context: context,
                key: const ValueKey('admin_nav_overview'),
                icon: Icons.dashboard_rounded,
                label: l10n.adminOverviewMenu,
                isSelected: isOverviewSelected,
                badgeCount: 0,
                onTap: () => _selectSection(
                  AdminSection.overview,
                  groups: groups,
                  closeDrawer: isMobileDrawer,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1),
              ),

              // Collapsible Category Groups
              for (final group in groups)
                _buildCollapsibleGroup(
                  context: context,
                  group: group,
                  groups: groups,
                  isMobileDrawer: isMobileDrawer,
                  primaryColor: primaryColor,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            child: ListTile(
              key: const ValueKey('admin_nav_logout'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              leading: Icon(
                Icons.logout,
                size: 22,
                color: Colors.grey[700],
              ),
              title: Text(
                l10n.logout,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: AppConfig.textColor,
                  fontFamily: AppConfig.fontFamily,
                ),
              ),
              onTap: () {
                if (isMobileDrawer && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
                widget.onLogout();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsibleGroup({
    required BuildContext context,
    required _AdminNavGroup group,
    required List<_AdminNavGroup> groups,
    required bool isMobileDrawer,
    required Color primaryColor,
  }) {
    if (group.items.length == 1) {
      final singleItem = group.items.first;
      return _buildLeafNavTile(
        context: context,
        key: ValueKey('admin_nav_${singleItem.section.name}'),
        icon: group.icon,
        label: group.title,
        isSelected: _selectedSection == singleItem.section,
        badgeCount: singleItem.badgeCount,
        badgeKey: ValueKey('admin_item_badge_${singleItem.section.name}'),
        matchCategoryTypography: true,
        onTap: () => _selectSection(
          singleItem.section,
          groups: groups,
          closeDrawer: isMobileDrawer,
        ),
      );
    }

    final isExpanded = _expandedGroups.contains(group.id);
    final hasActiveChild = group.items.any(
      (item) => item.section == _selectedSection,
    );
    final showRollupBadge = !isExpanded && group.totalBadgeCount > 0;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey(
          'admin_group_${group.id}_$_programmaticExpandGeneration',
        ),
        initiallyExpanded: isExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.only(left: 12, bottom: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        leading: Badge(
          key: ValueKey('admin_group_badge_${group.id}'),
          isLabelVisible: showRollupBadge,
          label: Text(group.totalBadgeCount.toString()),
          child: Icon(
            group.icon,
            color: hasActiveChild ? AppConfig.primaryColor : Colors.grey[700],
          ),
        ),
        title: Text(
          group.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: hasActiveChild ? FontWeight.bold : FontWeight.w600,
            color: hasActiveChild ? AppConfig.primaryColor : AppConfig.textColor,
            fontFamily: AppConfig.fontFamily,
          ),
        ),
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedGroups.add(group.id);
            } else {
              _expandedGroups.remove(group.id);
            }
          });
        },
        children: [
          for (final item in group.items)
            _buildLeafNavTile(
              context: context,
              key: ValueKey('admin_nav_${item.section.name}'),
              icon: item.icon,
              label: item.label,
              isSelected: _selectedSection == item.section,
              badgeCount: item.badgeCount,
              badgeKey: ValueKey('admin_item_badge_${item.section.name}'),
              compact: true,
              onTap: () => _selectSection(
                item.section,
                groups: groups,
                closeDrawer: isMobileDrawer,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeafNavTile({
    required BuildContext context,
    required Key key,
    required IconData icon,
    required String label,
    required bool isSelected,
    required int badgeCount,
    required VoidCallback onTap,
    Key? badgeKey,
    bool compact = false,
    bool matchCategoryTypography = false,
  }) {
    final primarySchemeColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? primarySchemeColor.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          key: key,
          dense: compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: compact
              ? const VisualDensity(vertical: -1)
              : VisualDensity.standard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: Icon(
            icon,
            size: compact ? 20 : (matchCategoryTypography ? 24 : 22),
            color: isSelected ? AppConfig.primaryColor : Colors.grey[700],
          ),
          title: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 13.5 : (matchCategoryTypography ? 14 : 14.5),
              fontWeight: isSelected
                  ? FontWeight.bold
                  : (matchCategoryTypography ? FontWeight.w600 : FontWeight.w500),
              color: isSelected ? AppConfig.primaryColor : AppConfig.textColor,
              fontFamily: AppConfig.fontFamily,
            ),
          ),
          trailing: badgeCount > 0
              ? Badge(
                  key: badgeKey,
                  label: Text(badgeCount.toString()),
                )
              : null,
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildActiveSectionWidget(
    List<_AdminNavGroup> groups,
    AppLocalizations l10n, {
    required bool isMobile,
  }) {
    switch (_selectedSection) {
      case AdminSection.overview:
        return _buildOverviewDashboard(groups, l10n, isMobile: isMobile);
      case AdminSection.approveResidents:
        return const AdminResidentApprovalScreen(isEmbedded: true);
      case AdminSection.createUser:
        return const AdminCreateUserScreen(isEmbedded: true);
      case AdminSection.bulkUserImport:
        return const AdminBulkUserImportScreen(isEmbedded: true);
      case AdminSection.userDirectory:
        return const AdminUserManagementScreen(isEmbedded: true);
      case AdminSection.manageFacilities:
        return const AdminFacilitiesScreen(isEmbedded: true);
      case AdminSection.reviewBookings:
        return const AdminBookingApprovalScreen(isEmbedded: true);
      case AdminSection.accessLogs:
        return const AdminAccessLogsScreen(isEmbedded: true);
      case AdminSection.bulkAddressImport:
        return const AdminBulkAddressImportScreen(isEmbedded: true);
      case AdminSection.sanctions:
        return const AdminSanctionsScreen(isEmbedded: true);
      case AdminSection.reviewPayments:
        return const AdminPaymentApprovalScreen(isEmbedded: true);
      case AdminSection.uploadPayment:
        return const AdminUploadPaymentScreen(isEmbedded: true);
      case AdminSection.downloadPaymentReport:
        return const AdminPaymentReportScreen(isEmbedded: true);
      case AdminSection.importPaymentHistory:
        return const AdminBulkPaymentImportScreen(isEmbedded: true);
      case AdminSection.announcements:
        return AnnouncementsScreen(
          isEmbedded: true,
          autoOpenCreateDialog: _openCreateAnnouncementOnMount,
          onCreateDialogOpened: () {
            if (mounted && _openCreateAnnouncementOnMount) {
              setState(() {
                _openCreateAnnouncementOnMount = false;
              });
            }
          },
        );
      case AdminSection.transparencyDocs:
        return const TransparencyScreen(isAdminView: true, isEmbedded: true);
      case AdminSection.generalSettings:
        return const AdminSettingsScreen(isEmbedded: true);
    }
  }

  Widget _buildOverviewDashboard(
    List<_AdminNavGroup> groups,
    AppLocalizations l10n, {
    required bool isMobile,
  }) {
    final int totalPendingApprovals =
        _pendingClaimsCount + _pendingPaymentsCount + _pendingBookingsCount;

    final pendingApprovalsContent = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 680;
        final cards = [
          _buildPendingActionCard(
            context: context,
            key: const ValueKey('overview_card_approve_residents'),
            title: l10n.approveResidentsMenu,
            subtitle: l10n.adminPendingItemsCount(_pendingClaimsCount),
            icon: Icons.verified_user,
            accentColor: Colors.deepPurple,
            count: _pendingClaimsCount,
            onTap: () => _selectSection(
              AdminSection.approveResidents,
              groups: groups,
              expandParentGroup: true,
            ),
          ),
          _buildPendingActionCard(
            context: context,
            key: const ValueKey('overview_card_review_payments'),
            title: l10n.reviewPaymentsMenu,
            subtitle: l10n.adminPendingItemsCount(_pendingPaymentsCount),
            icon: Icons.payments,
            accentColor: Colors.blue.shade700,
            count: _pendingPaymentsCount,
            onTap: () => _selectSection(
              AdminSection.reviewPayments,
              groups: groups,
              expandParentGroup: true,
            ),
          ),
          _buildPendingActionCard(
            context: context,
            key: const ValueKey('overview_card_review_bookings'),
            title: l10n.reviewBookingsMenu,
            subtitle: l10n.adminPendingItemsCount(_pendingBookingsCount),
            icon: Icons.event_available,
            accentColor: Colors.teal.shade700,
            count: _pendingBookingsCount,
            onTap: () => _selectSection(
              AdminSection.reviewBookings,
              groups: groups,
              expandParentGroup: true,
            ),
          ),
        ];

        if (isWide) {
          return Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 14),
              Expanded(child: cards[1]),
              const SizedBox(width: 14),
              Expanded(child: cards[2]),
            ],
          );
        }
        return Column(
          children: [
            cards[0],
            const SizedBox(height: 10),
            cards[1],
            const SizedBox(height: 10),
            cards[2],
          ],
        );
      },
    );

    final communityStatsContent = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 520;
        final statCards = <Widget>[
          if (_scanOnExitEnabled)
            _buildStatCard(
              context: context,
              key: const ValueKey('overview_stat_currently_inside'),
              label: l10n.adminVisitorsCurrentlyInsideStat,
              value: _currentlyInsideCount.toString(),
              icon: Icons.sensor_door_outlined,
              color: Colors.teal.shade700,
              onTap: () => _selectSection(
                AdminSection.accessLogs,
                groups: groups,
                expandParentGroup: true,
              ),
            ),
          _buildStatCard(
            context: context,
            key: const ValueKey('overview_stat_active_sanctions'),
            label: l10n.adminActiveSanctionsStat,
            value: _activeSanctionsCount.toString(),
            icon: Icons.gavel,
            color: Colors.deepOrange,
            onTap: () => _selectSection(
              AdminSection.sanctions,
              groups: groups,
              expandParentGroup: true,
            ),
          ),
        ];

        if (statCards.length == 1) {
          return statCards.first;
        }

        if (isWide) {
          return Row(
            children: [
              Expanded(child: statCards[0]),
              const SizedBox(width: 14),
              Expanded(child: statCards[1]),
            ],
          );
        }
        return Column(
          children: [
            statCards[0],
            const SizedBox(height: 10),
            statCards[1],
          ],
        );
      },
    );

    final shortcutCards = <Widget>[
      _buildShortcutCard(
        key: const ValueKey('overview_shortcut_create_user'),
        label: l10n.createUserMenu,
        icon: Icons.person_add_alt_1,
        onTap: () => _selectSection(
          AdminSection.createUser,
          groups: groups,
          expandParentGroup: true,
        ),
      ),
      _buildShortcutCard(
        key: const ValueKey('overview_shortcut_user_directory'),
        label: l10n.adminShortcutUserDirectory,
        icon: Icons.people_alt,
        onTap: () => _selectSection(
          AdminSection.userDirectory,
          groups: groups,
          expandParentGroup: true,
        ),
      ),
      _buildShortcutCard(
        key: const ValueKey('overview_shortcut_create_announcement'),
        label: l10n.createAnnouncement,
        icon: Icons.campaign,
        onTap: () => _selectSection(
          AdminSection.announcements,
          groups: groups,
          expandParentGroup: true,
          openCreateAnnouncement: true,
        ),
      ),
      _buildShortcutCard(
        key: const ValueKey('overview_shortcut_upload_payment'),
        label: l10n.uploadPaymentOnBehalfMenu,
        icon: Icons.upload_file,
        onTap: () => _selectSection(
          AdminSection.uploadPayment,
          groups: groups,
          expandParentGroup: true,
        ),
      ),
      _buildShortcutCard(
        key: const ValueKey('overview_shortcut_download_report'),
        label: l10n.downloadReportMenu,
        icon: Icons.table_chart,
        onTap: () => _selectSection(
          AdminSection.downloadPaymentReport,
          groups: groups,
          expandParentGroup: true,
        ),
      ),
      _buildShortcutCard(
        key: const ValueKey('overview_shortcut_settings'),
        label: l10n.adminShortcutSettings,
        icon: Icons.settings,
        onTap: () => _selectSection(
          AdminSection.generalSettings,
          groups: groups,
          expandParentGroup: true,
        ),
      ),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isMobile) ...[
                _buildMobileCollapsibleSection(
                  context: context,
                  sectionKey: const ValueKey('mobile_section_pending_approvals'),
                  title: l10n.adminPendingReviewsSection,
                  icon: Icons.pending_actions_rounded,
                  isExpanded: _mobilePendingApprovalsExpanded,
                  badgeCount: totalPendingApprovals,
                  badgeKey: const ValueKey('mobile_badge_pending_approvals'),
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _mobilePendingApprovalsExpanded = expanded;
                    });
                  },
                  child: pendingApprovalsContent,
                ),
                const SizedBox(height: 12),
                _buildMobileCollapsibleSection(
                  context: context,
                  sectionKey: const ValueKey('mobile_section_community_stats'),
                  title: l10n.adminCommunityStatsSection,
                  icon: Icons.insights_rounded,
                  isExpanded: _mobileCommunityStatsExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _mobileCommunityStatsExpanded = expanded;
                    });
                  },
                  child: communityStatsContent,
                ),
                const SizedBox(height: 24),
              ] else ...[
                // Section 1: Pending Approvals (Desktop static section)
                Text(
                  l10n.adminPendingReviewsSection,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppConfig.textColor,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
                const SizedBox(height: 12),
                pendingApprovalsContent,
                const SizedBox(height: 28),

                // Section 2: Live Community Status (Desktop static section)
                Text(
                  l10n.adminCommunityStatsSection,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppConfig.textColor,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
                const SizedBox(height: 12),
                communityStatsContent,
                const SizedBox(height: 28),
              ],

              // Section 3: Shortcut Cards
              Text(
                l10n.adminQuickAccessSection,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppConfig.textColor,
                  fontFamily: AppConfig.fontFamily,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final int columns = constraints.maxWidth >= 760
                      ? 3
                      : (constraints.maxWidth >= 480 ? 2 : 1);

                  if (columns == 1) {
                    return Column(
                      children: [
                        for (int i = 0; i < shortcutCards.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          shortcutCards[i],
                        ],
                      ],
                    );
                  }

                  final List<Widget> rows = [];
                  for (int i = 0; i < shortcutCards.length; i += columns) {
                    if (rows.isNotEmpty) {
                      rows.add(const SizedBox(height: 12));
                    }
                    final List<Widget> rowChildren = [];
                    for (int c = 0; c < columns; c++) {
                      if (c > 0) {
                        rowChildren.add(const SizedBox(width: 14));
                      }
                      final int idx = i + c;
                      rowChildren.add(
                        Expanded(
                          child: idx < shortcutCards.length
                              ? shortcutCards[idx]
                              : const SizedBox.shrink(),
                        ),
                      );
                    }
                    rows.add(
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: rowChildren,
                        ),
                      ),
                    );
                  }

                  return Column(children: rows);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCollapsibleSection({
    required BuildContext context,
    required Key sectionKey,
    required String title,
    required IconData icon,
    required bool isExpanded,
    required ValueChanged<bool> onExpansionChanged,
    required Widget child,
    int badgeCount = 0,
    Key? badgeKey,
  }) {
    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: sectionKey,
          initiallyExpanded: isExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
          leading: Badge(
            key: badgeKey,
            isLabelVisible: !isExpanded && badgeCount > 0,
            label: Text(badgeCount.toString()),
            child: Icon(icon, color: AppConfig.primaryColor, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.bold,
              color: AppConfig.textColor,
              fontFamily: AppConfig.fontFamily,
            ),
          ),
          iconColor: AppConfig.primaryColor,
          collapsedIconColor: Colors.grey[700],
          onExpansionChanged: onExpansionChanged,
          children: [child],
        ),
      ),
    );
  }

  Widget _buildShortcutCard({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      key: key,
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppConfig.primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppConfig.primaryColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppConfig.textColor,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 20, color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingActionCard({
    required BuildContext context,
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required int count,
    required VoidCallback onTap,
  }) {
    final hasPending = count > 0;

    return Card(
      key: key,
      elevation: hasPending ? 3 : 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: hasPending
              ? accentColor.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.2),
          width: hasPending ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Badge(
                  isLabelVisible: hasPending,
                  label: Text(count.toString()),
                  child: Icon(icon, color: accentColor, size: 26),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppConfig.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            hasPending ? FontWeight.w600 : FontWeight.normal,
                        color: hasPending ? accentColor : Colors.grey[600],
                        fontFamily: AppConfig.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 15,
                color: Colors.grey[500],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required BuildContext context,
    required Key key,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      key: key,
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontFamily: AppConfig.fontFamily,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontFamily: AppConfig.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }
}

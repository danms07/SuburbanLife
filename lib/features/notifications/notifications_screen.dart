import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/backend/backend.dart';
import '../../core/config/app_config.dart';
import '../../core/services/notification_router.dart';
import '../../l10n/app_localizations.dart';

({IconData icon, Color color}) _categoryVisual(
  NotificationCategory? category,
  ColorScheme colorScheme,
) {
  switch (category) {
    case NotificationCategory.reviews:
      return (icon: Icons.verified_outlined, color: AppConfig.successColor);
    case NotificationCategory.sanctions:
      return (icon: Icons.gavel_rounded, color: AppConfig.dangerColor);
    case NotificationCategory.qrAccess:
      return (icon: Icons.qr_code_2_rounded, color: AppConfig.infoColor);
    case NotificationCategory.roommates:
      return (icon: Icons.group_outlined, color: colorScheme.primary);
    case NotificationCategory.transparency:
      return (icon: Icons.description_outlined, color: Colors.teal);
    case NotificationCategory.announcements:
      return (icon: Icons.campaign_outlined, color: AppConfig.warningColor);
    case NotificationCategory.adminReviews:
      return (icon: Icons.pending_actions_rounded, color: Colors.deepPurple);
    case null:
      return (icon: Icons.notifications_outlined, color: colorScheme.primary);
  }
}

/// Live-updating bell button backed by `/notifications/{uid}` unread count in RTDB.
class NotificationBellButton extends StatelessWidget {
  final String uid;
  final VoidCallback onPressed;
  final Color iconColor;
  final String? tooltip;

  const NotificationBellButton({
    super.key,
    required this.uid,
    required this.onPressed,
    this.iconColor = Colors.white,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<int>(
      stream: Backend.notifications.watchUnreadCount(uid),
      initialData: 0,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        final badgeText = unreadCount > 99 ? '99+' : '$unreadCount';

        return Semantics(
          button: true,
          label: l10n.notificationsUnreadBadgeSemantics(unreadCount),
          child: IconButton(
            key: const Key('notification_bell_button'),
            tooltip: tooltip ?? l10n.notificationsInboxTitle,
            onPressed: onPressed,
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              backgroundColor: colorScheme.error,
              textColor: colorScheme.onError,
              label: Text(
                badgeText,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: Icon(
                unreadCount > 0
                    ? Icons.notifications_active
                    : Icons.notifications_outlined,
                color: iconColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Interactive cross-platform foreground notification banner rendered on top of
/// the active workspace when `inAppBannerEnabled` is active.
class InAppNotificationBanner extends StatelessWidget {
  final AppNotification notification;
  final String languageCode;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const InAppNotificationBanner({
    super.key,
    required this.notification,
    required this.languageCode,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final visual = _categoryVisual(notification.category, colorScheme);
    final title = notification.localizedTitle(languageCode);
    final body = notification.localizedBody(languageCode);

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Dismissible(
              key: ValueKey('in_app_banner_${notification.id}'),
              direction: DismissDirection.up,
              onDismissed: (_) => onDismiss(),
              child: Material(
                key: const Key('in_app_notification_banner'),
                elevation: 8,
                shadowColor: colorScheme.shadow.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14),
                color: colorScheme.surface,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: visual.color.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: visual.color.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(visual.icon, color: visual.color, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (title.isNotEmpty)
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    fontFamily: AppConfig.fontFamily,
                                  ),
                                ),
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                    fontFamily: AppConfig.fontFamily,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              key: const Key('in_app_banner_dismiss_button'),
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              padding: EdgeInsets.zero,
                              iconSize: 18,
                              tooltip: l10n.notificationBannerDismissTooltip,
                              onPressed: onDismiss,
                              icon: const Icon(Icons.close),
                            ),
                            TextButton(
                              key: const Key('in_app_banner_view_button'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: const Size(0, 28),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: onTap,
                              child: Text(l10n.notificationBannerViewButton),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full notification inbox backed by RTDB `/notifications/{uid}` with filter,
/// mark-as-read, delete, clear-all, deep-link routing, and preference controls.
class NotificationsScreen extends StatefulWidget {
  final String uid;
  final bool isAdmin;
  final bool isResident;
  final bool isAdminWorkspace;
  final AdminSectionCallback? onOpenAdminSection;
  final void Function(AppNotification notification)? onNotificationTap;
  final bool openPreferencesInitially;

  const NotificationsScreen({
    super.key,
    required this.uid,
    this.isAdmin = false,
    this.isResident = true,
    this.isAdminWorkspace = false,
    this.onOpenAdminSection,
    this.onNotificationTap,
    this.openPreferencesInitially = false,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _showUnreadOnly = false;
  PushPermissionStatus _permissionStatus = PushPermissionStatus.authorized;
  bool _permissionPromptDismissed = false;

  @override
  void initState() {
    super.initState();
    _loadPermissionStatus();
    if (widget.openPreferencesInitially) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPreferencesSheet();
      });
    }
  }

  Future<void> _loadPermissionStatus() async {
    final status = await Backend.notifications.getPermissionStatus();
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
    });
  }

  Future<void> _requestPermissionFromInbox() async {
    final lang = Localizations.localeOf(context).languageCode;
    final status = await Backend.notifications.requestPermissionAndRegister(
      uid: widget.uid,
      languageCode: lang,
    );
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
    });
  }

  Future<void> _openPreferencesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => NotificationPreferencesSheet(
        uid: widget.uid,
        isAdmin: widget.isAdmin,
      ),
    );
    await _loadPermissionStatus();
  }

  Future<void> _handleClearAll(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.notificationsClearConfirmTitle),
        content: Text(l10n.notificationsClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            key: const Key('confirm_clear_notifications_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.notificationsClearAll),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await Backend.notifications.clearAllNotifications(widget.uid);
    }
  }

  Future<void> _handleNotificationTap(AppNotification item) async {
    if (!item.isRead) {
      await Backend.notifications.markAsRead(widget.uid, item.id);
    }
    if (!mounted) return;

    if (widget.onNotificationTap != null) {
      widget.onNotificationTap!(item);
      return;
    }

    final safeRoute = sanitizeNotificationRoute(item.targetRoute);
    if (safeRoute == 'notifications') return;
    if (safeRoute == 'home') {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    final adminSection = NotificationRouter.adminSectionForRoute(safeRoute);
    if (adminSection != null) {
      if (widget.isAdmin && widget.onOpenAdminSection != null) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        widget.onOpenAdminSection!(adminSection);
      }
      return;
    }

    await NotificationRouter.navigate(
      context: context,
      uid: widget.uid,
      rawRoute: safeRoute,
      isAdmin: widget.isAdmin,
      isResident: widget.isResident,
      isAdminWorkspace: widget.isAdminWorkspace,
      onOpenAdminSection: (section) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        widget.onOpenAdminSection?.call(section);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final colorScheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat.yMMMd(locale).add_jm();

    return StreamBuilder<List<AppNotification>>(
      stream: Backend.notifications.watchNotifications(widget.uid),
      builder: (context, snapshot) {
        final allItems = snapshot.data ?? const <AppNotification>[];
        final unreadCount = allItems.where((n) => !n.isRead).length;
        final visibleItems = _showUnreadOnly
            ? allItems.where((n) => !n.isRead).toList()
            : allItems;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.notificationsInboxTitle),
            actions: [
              if (unreadCount > 0)
                IconButton(
                  key: const Key('mark_all_read_button'),
                  tooltip: l10n.notificationsMarkAllRead,
                  icon: const Icon(Icons.done_all),
                  onPressed: () => Backend.notifications.markAllAsRead(widget.uid),
                ),
              IconButton(
                key: const Key('notification_preferences_button'),
                tooltip: l10n.notificationsPreferencesTooltip,
                icon: const Icon(Icons.tune),
                onPressed: _openPreferencesSheet,
              ),
              if (allItems.isNotEmpty)
                IconButton(
                  key: const Key('clear_all_notifications_button'),
                  tooltip: l10n.notificationsClearAll,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () => _handleClearAll(l10n),
                ),
            ],
          ),
          body: Column(
            children: [
              if (!_permissionPromptDismissed &&
                  _permissionStatus == PushPermissionStatus.notDetermined)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Material(
                    key: const Key('inbox_push_opt_in_banner'),
                    color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.notificationPermissionNotDetermined,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextButton(
                                  key: const Key('inbox_enable_push_button'),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: const Size(0, 30),
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                  ),
                                  onPressed: _requestPermissionFromInbox,
                                  child: Text(l10n.notificationEnablePermissionButton),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.notificationBannerDismissTooltip,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() {
                                _permissionPromptDismissed = true;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    ChoiceChip(
                      key: const Key('filter_all_notifications'),
                      label: Text('${l10n.notificationsAllFilter} (${allItems.length})'),
                      selected: !_showUnreadOnly,
                      onSelected: (_) => setState(() => _showUnreadOnly = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: const Key('filter_unread_notifications'),
                      label: Text('${l10n.notificationsUnreadFilter} ($unreadCount)'),
                      selected: _showUnreadOnly,
                      onSelected: (_) => setState(() => _showUnreadOnly = true),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : visibleItems.isEmpty
                        ? _buildEmptyState(l10n, colorScheme)
                        : Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 820),
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: visibleItems.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = visibleItems[index];
                                  return _buildNotificationCard(
                                    item: item,
                                    locale: locale,
                                    dateFmt: dateFmt,
                                    colorScheme: colorScheme,
                                    l10n: l10n,
                                  );
                                },
                              ),
                            ),
                          ),
              ),
              Container(
                width: double.infinity,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.notificationsRetentionNotice,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: AppConfig.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, ColorScheme colorScheme) {
    final isFilteredEmpty = _showUnreadOnly;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFilteredEmpty ? Icons.mark_email_read_outlined : Icons.notifications_none,
              size: 64,
              color: colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              isFilteredEmpty
                  ? l10n.notificationsNoUnreadTitle
                  : l10n.notificationsEmptyTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: AppConfig.fontFamily,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isFilteredEmpty
                  ? l10n.notificationsNoUnreadSubtitle
                  : l10n.notificationsEmptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                fontFamily: AppConfig.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard({
    required AppNotification item,
    required String locale,
    required DateFormat dateFmt,
    required ColorScheme colorScheme,
    required AppLocalizations l10n,
  }) {
    final visual = _categoryVisual(item.category, colorScheme);
    final title = item.localizedTitle(locale);
    final body = item.localizedBody(locale);

    return Dismissible(
      key: ValueKey('notif_dismiss_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: colorScheme.onError),
      ),
      onDismissed: (_) => Backend.notifications.deleteNotification(widget.uid, item.id),
      child: Card(
        key: Key('notification_card_${item.id}'),
        margin: EdgeInsets.zero,
        elevation: item.isRead ? 0 : 1.5,
        color: item.isRead
            ? colorScheme.surface
            : colorScheme.primary.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: item.isRead
                ? colorScheme.outlineVariant.withValues(alpha: 0.6)
                : visual.color.withValues(alpha: 0.45),
            width: item.isRead ? 1 : 1.3,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _handleNotificationTap(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: visual.color.withValues(alpha: 0.14),
                  child: Icon(visual.icon, color: visual.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (!item.isRead)
                            Container(
                              key: Key('unread_dot_${item.id}'),
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: visual.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: item.isRead ? FontWeight.w600 : FontWeight.bold,
                                fontFamily: AppConfig.fontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: AppConfig.fontFamily,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        dateFmt.format(item.createdAt),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          fontFamily: AppConfig.fontFamily,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('delete_notification_${item.id}'),
                  tooltip: l10n.notificationsDeleteTooltip,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () =>
                      Backend.notifications.deleteNotification(widget.uid, item.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Interactive sheet for OS permission requests, master push toggle,
/// foreground in-app banner toggle, and per-category push preferences.
class NotificationPreferencesSheet extends StatefulWidget {
  final String uid;
  final bool isAdmin;

  const NotificationPreferencesSheet({
    super.key,
    required this.uid,
    required this.isAdmin,
  });

  @override
  State<NotificationPreferencesSheet> createState() =>
      _NotificationPreferencesSheetState();
}

class _NotificationPreferencesSheetState extends State<NotificationPreferencesSheet>
    with WidgetsBindingObserver {
  PushPermissionStatus _permissionStatus = PushPermissionStatus.notDetermined;
  bool _loadingPermission = true;
  bool _requestingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissionStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatus();
    }
  }

  Future<void> _refreshPermissionStatus() async {
    final status = await Backend.notifications.getPermissionStatus();
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
      _loadingPermission = false;
    });
  }

  Future<void> _requestPermission() async {
    setState(() => _requestingPermission = true);
    final lang = Localizations.localeOf(context).languageCode;
    final status = await Backend.notifications.requestPermissionAndRegister(
      uid: widget.uid,
      languageCode: lang,
    );
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
      _requestingPermission = false;
    });
  }

  Future<void> _togglePushEnabled(bool enabled) async {
    final lang = Localizations.localeOf(context).languageCode;
    if (enabled && _permissionStatus == PushPermissionStatus.notDetermined) {
      await _requestPermission();
      return;
    }
    await Backend.notifications.setPushEnabled(
      widget.uid,
      enabled,
      languageCode: lang,
    );
  }

  ({String title, String subtitle}) _categoryStrings(
    NotificationCategory category,
    AppLocalizations l10n,
  ) {
    switch (category) {
      case NotificationCategory.reviews:
        return (
          title: l10n.notificationCatReviewsTitle,
          subtitle: l10n.notificationCatReviewsDesc,
        );
      case NotificationCategory.sanctions:
        return (
          title: l10n.notificationCatSanctionsTitle,
          subtitle: l10n.notificationCatSanctionsDesc,
        );
      case NotificationCategory.qrAccess:
        return (
          title: l10n.notificationCatQrAccessTitle,
          subtitle: l10n.notificationCatQrAccessDesc,
        );
      case NotificationCategory.roommates:
        return (
          title: l10n.notificationCatRoommatesTitle,
          subtitle: l10n.notificationCatRoommatesDesc,
        );
      case NotificationCategory.transparency:
        return (
          title: l10n.notificationCatTransparencyTitle,
          subtitle: l10n.notificationCatTransparencyDesc,
        );
      case NotificationCategory.announcements:
        return (
          title: l10n.notificationCatAnnouncementsTitle,
          subtitle: l10n.notificationCatAnnouncementsDesc,
        );
      case NotificationCategory.adminReviews:
        return (
          title: l10n.notificationCatAdminReviewsTitle,
          subtitle: l10n.notificationCatAdminReviewsDesc,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final categories = NotificationCategory.values
        .where((c) => widget.isAdmin || c != NotificationCategory.adminReviews)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return StreamBuilder<UserNotificationSettings>(
          stream: Backend.notifications.watchSettings(widget.uid),
          initialData: const UserNotificationSettings(),
          builder: (context, snapshot) {
            final settings = snapshot.data ?? const UserNotificationSettings();

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.tune, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.notificationPreferencesTitle,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          fontFamily: AppConfig.fontFamily,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.notificationPermissionSectionTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
                const SizedBox(height: 8),
                _buildPermissionCard(l10n, colorScheme),
                const SizedBox(height: 16),
                SwitchListTile(
                  key: const Key('switch_push_enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.notificationMasterPushTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.notificationMasterPushSubtitle),
                  value: settings.pushEnabled,
                  onChanged: _togglePushEnabled,
                ),
                const Divider(),
                SwitchListTile(
                  key: const Key('switch_in_app_banner'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.notificationInAppBannerTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.notificationInAppBannerSubtitle),
                  value: settings.inAppBannerEnabled,
                  onChanged: (val) =>
                      Backend.notifications.setInAppBannerEnabled(widget.uid, val),
                ),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  l10n.notificationCategoriesSectionTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.notificationCategoriesSectionSubtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                ...categories.map((cat) {
                  final copy = _categoryStrings(cat, l10n);
                  final visual = _categoryVisual(cat, colorScheme);
                  return SwitchListTile(
                    key: Key('switch_category_${cat.key}'),
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(visual.icon, color: visual.color),
                    title: Text(copy.title),
                    subtitle: Text(copy.subtitle),
                    value: settings.isCategoryEnabled(cat),
                    onChanged: settings.pushEnabled
                        ? (val) => Backend.notifications
                            .setCategoryEnabled(widget.uid, cat, val)
                        : null,
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPermissionCard(AppLocalizations l10n, ColorScheme colorScheme) {
    if (_loadingPermission) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    }

    late final Color tintColor;
    late final IconData icon;
    late final String message;
    String? secondaryNote;
    bool showEnableButton = false;

    switch (_permissionStatus) {
      case PushPermissionStatus.authorized:
      case PushPermissionStatus.provisional:
        tintColor = AppConfig.successColor;
        icon = Icons.check_circle_outline;
        message = l10n.notificationPermissionAuthorized;
      case PushPermissionStatus.denied:
        tintColor = AppConfig.warningColor;
        icon = Icons.notifications_off_outlined;
        message = l10n.notificationPermissionDenied;
        secondaryNote = l10n.notificationSystemSettingsHint;
      case PushPermissionStatus.notDetermined:
        tintColor = colorScheme.primary;
        icon = Icons.notifications_active_outlined;
        message = l10n.notificationPermissionNotDetermined;
        showEnableButton = true;
      case PushPermissionStatus.unsupported:
        tintColor = colorScheme.onSurfaceVariant;
        icon = Icons.info_outline;
        message = l10n.notificationPermissionUnsupported;
    }

    return Container(
      key: Key('permission_status_card_${_permissionStatus.name}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tintColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tintColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    fontFamily: AppConfig.fontFamily,
                  ),
                ),
              ),
            ],
          ),
          if (secondaryNote != null) ...[
            const SizedBox(height: 8),
            Text(
              secondaryNote,
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (showEnableButton) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('enable_push_permission_button'),
                onPressed: _requestingPermission ? null : _requestPermission,
                icon: _requestingPermission
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active),
                label: Text(l10n.notificationEnablePermissionButton),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

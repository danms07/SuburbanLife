import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:suburban_life/core/config/app_config.dart';
import 'package:suburban_life/core/services/app_update_service.dart';
import 'package:suburban_life/l10n/app_localizations.dart';

/// Shared subtle caption widget displaying the active application version
/// sourced from the bundled `web/version.json` manifest.
class AppVersionLabel extends StatefulWidget {
  final TextStyle? style;
  final TextAlign textAlign;

  const AppVersionLabel({
    super.key,
    this.style,
    this.textAlign = TextAlign.center,
  });

  static const String versionAssetPath = 'web/version.json';
  static String? _cachedVersion;
  static Future<String?>? _inFlightLoad;

  /// Returns the cached version string if already resolved from [rootBundle].
  static String? get cachedVersion => _cachedVersion;

  /// Loads and parses `version+build_number` from [bundle] (defaulting to [rootBundle]).
  static Future<String?> loadVersion({AssetBundle? bundle}) {
    final effectiveBundle = bundle ?? rootBundle;
    final useRootCache = identical(effectiveBundle, rootBundle);
    if (useRootCache && _cachedVersion != null) {
      return Future<String?>.value(_cachedVersion);
    }

    Future<String?> readFromBundle() async {
      try {
        final rawJson = await effectiveBundle.loadString(versionAssetPath);
        final parsed = AppUpdateService.parseVersionPayload(rawJson);
        if (useRootCache && parsed != null) {
          _cachedVersion = parsed;
        }
        return parsed;
      } catch (e) {
        debugPrint('[AppVersionLabel] Failed to read $versionAssetPath: $e');
        return null;
      }
    }

    if (useRootCache) {
      return _inFlightLoad ??= readFromBundle().whenComplete(() {
        _inFlightLoad = null;
      });
    }
    return readFromBundle();
  }

  /// Clears the cached version string so tests can verify cold-load behavior.
  @visibleForTesting
  static void resetCacheForTesting() {
    _cachedVersion = null;
    _inFlightLoad = null;
  }

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  AssetBundle? _boundBundle;
  String? _version;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bundle = DefaultAssetBundle.of(context);
    if (identical(bundle, _boundBundle)) return;
    _boundBundle = bundle;

    if (identical(bundle, rootBundle) && AppVersionLabel.cachedVersion != null) {
      _version = AppVersionLabel.cachedVersion;
      return;
    }

    _resolveVersion(bundle);
  }

  Future<void> _resolveVersion(AssetBundle bundle) async {
    final resolved = await AppVersionLabel.loadVersion(bundle: bundle);
    if (!mounted || !identical(_boundBundle, bundle)) return;
    setState(() {
      _version = resolved;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final version = _version;
    if (l10n == null || version == null || version.isEmpty) {
      return const SizedBox.shrink();
    }

    final effectiveStyle =
        widget.style ??
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
          fontFamily: AppConfig.fontFamily,
        );

    return Text(
      l10n.appVersionLabel(version),
      textAlign: widget.textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: effectiveStyle,
    );
  }
}

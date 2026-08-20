import 'package:flutter/material.dart';
import '../../../core/config/app_config.dart';

class BreadcrumbItem {
  final String id; // 'root' or folderId
  final String name;

  const BreadcrumbItem({required this.id, required this.name});
}

class FileExplorerBreadcrumb extends StatelessWidget {
  final List<BreadcrumbItem> items;
  final ValueChanged<BreadcrumbItem> onItemTap;

  const FileExplorerBreadcrumb({
    Key? key,
    required this.items,
    required this.onItemTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Colors.grey.shade500,
                  ),
                ),
              InkWell(
                onTap: () => onItemTap(items[i]),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i == 0)
                        const Padding(
                          padding: EdgeInsets.only(right: 4.0),
                          child: Icon(
                            Icons.home_outlined,
                            size: 16,
                            color: AppConfig.primaryColor,
                          ),
                        ),
                      Text(
                        items[i].name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: (i == items.length - 1)
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: (i == items.length - 1)
                              ? AppConfig.textColor
                              : AppConfig.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

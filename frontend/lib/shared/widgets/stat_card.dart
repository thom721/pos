import 'package:flutter/material.dart';
import 'package:pos_connect/core/responsive.dart';
import 'package:pos_connect/core/theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = context.isSmallPhone;
    final pad = isSmall ? 12.0 : 16.0;
    final iconSize = isSmall ? 36.0 : 44.0;
    final iconInner = isSmall ? 18.0 : 22.0;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Row(
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: iconInner),
            ),
            SizedBox(width: isSmall ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: isSmall ? 10 : 12,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: color,
                            fontSize: isSmall ? 10 : 11,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}

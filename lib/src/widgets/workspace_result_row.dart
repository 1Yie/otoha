import 'package:flutter/material.dart';

import '../app/theme.dart';

class WorkspaceResultRow extends StatelessWidget {
  const WorkspaceResultRow({
    required this.actionKey,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.isLoading,
    required this.onTap,
    this.trailing,
    this.selected = false,
    this.loadingOverlayKey,
    super.key,
  });

  final Key actionKey;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool selected;
  final bool isLoading;
  final Key? loadingOverlayKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppMetrics.radius),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  leading,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (trailing case final trailing?) ...<Widget>[
                    const SizedBox(width: 12),
                    trailing,
                  ],
                ],
              ),
            ),
            if (selected)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x1AB6F26D)),
                ),
              ),
            if (isLoading)
              Positioned.fill(
                key: loadingOverlayKey,
                child: const ColoredBox(
                  color: Color(0x99000000),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: actionKey,
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(AppMetrics.radius),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

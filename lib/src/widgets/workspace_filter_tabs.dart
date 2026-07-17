import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';

class WorkspaceFilterTabOption<T> {
  const WorkspaceFilterTabOption({
    required this.value,
    required this.label,
    required this.tabKey,
  });

  final T value;
  final String label;
  final Key tabKey;
}

class WorkspaceFilterTabs<T> extends StatefulWidget {
  const WorkspaceFilterTabs({
    required this.options,
    required this.selectedValue,
    required this.reduceMotion,
    required this.onSelected,
    required this.scrollLeftKey,
    required this.scrollRightKey,
    required this.scrollLeftTooltip,
    required this.scrollRightTooltip,
    super.key,
  });

  final List<WorkspaceFilterTabOption<T>> options;
  final T? selectedValue;
  final bool reduceMotion;
  final ValueChanged<T> onSelected;
  final Key scrollLeftKey;
  final Key scrollRightKey;
  final String scrollLeftTooltip;
  final String scrollRightTooltip;

  @override
  State<WorkspaceFilterTabs<T>> createState() => _WorkspaceFilterTabsState<T>();
}

class _WorkspaceFilterTabsState<T> extends State<WorkspaceFilterTabs<T>> {
  late final ScrollController _scrollController;
  final Map<T, GlobalKey> _optionKeys = <T, GlobalKey>{};
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_updateScrollActions);
    _afterLayout();
  }

  @override
  void didUpdateWidget(covariant WorkspaceFilterTabs<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _afterLayout(
      ensureSelectionVisible: oldWidget.selectedValue != widget.selectedValue,
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollActions);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollBy(double direction) {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final target = (position.pixels + direction * 280)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if (widget.reduceMotion) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _afterLayout({bool ensureSelectionVisible = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _updateScrollActions();
      if (!ensureSelectionVisible || widget.selectedValue == null) {
        return;
      }
      final selectedContext = _optionKeys[widget.selectedValue]?.currentContext;
      if (selectedContext != null) {
        Scrollable.ensureVisible(
          selectedContext,
          alignment: 0.5,
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _updateScrollActions() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final canScrollLeft = position.pixels > 0.5;
    final canScrollRight = position.pixels < position.maxScrollExtent - 0.5;
    if (canScrollLeft == _canScrollLeft && canScrollRight == _canScrollRight) {
      return;
    }
    setState(() {
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _afterLayout();
          return false;
        },
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  colors: <Color>[
                    _canScrollLeft ? Colors.transparent : Colors.white,
                    Colors.white,
                    Colors.white,
                    _canScrollRight ? Colors.transparent : Colors.white,
                  ],
                  stops: const <double>[0, 0.06, 0.86, 1],
                ).createShader(bounds),
                child: ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(2, 0, 80, 0),
                  itemCount: widget.options.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final option = widget.options[index];
                    return _WorkspaceFilterTab(
                      key: _optionKeys.putIfAbsent(
                        option.value,
                        () => GlobalKey(),
                      ),
                      tabKey: option.tabKey,
                      label: option.label,
                      selected: widget.selectedValue == option.value,
                      reduceMotion: widget.reduceMotion,
                      onTap: widget.selectedValue == option.value
                          ? null
                          : () => widget.onSelected(option.value),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _FilterScrollButton(
                    key: widget.scrollLeftKey,
                    tooltip: widget.scrollLeftTooltip,
                    enabled: _canScrollLeft,
                    icon: Icons.chevron_left_rounded,
                    onPressed: () => _scrollBy(-1),
                  ),
                  _FilterScrollButton(
                    key: widget.scrollRightKey,
                    tooltip: widget.scrollRightTooltip,
                    enabled: _canScrollRight,
                    icon: Icons.chevron_right_rounded,
                    onPressed: () => _scrollBy(1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterScrollButton extends StatelessWidget {
  const _FilterScrollButton({
    required this.tooltip,
    required this.enabled,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final bool enabled;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        iconSize: 22,
        color: OtohaColors.text,
        disabledColor: OtohaColors.mutedText.withValues(alpha: 0.4),
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
      ),
    );
  }
}

class _WorkspaceFilterTab extends StatelessWidget {
  const _WorkspaceFilterTab({
    required this.tabKey,
    required this.label,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
    super.key,
  });

  final Key tabKey;
  final String label;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const tabRadius = BorderRadius.all(Radius.circular(22));
    return ClipRRect(
      borderRadius: tabRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AnimatedContainer(
          key: tabKey,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.linear,
          constraints: const BoxConstraints(minWidth: 64),
          decoration: BoxDecoration(
            color: selected
                ? OtohaColors.text.withValues(alpha: 0.92)
                : OtohaColors.surfaceRaised.withValues(alpha: 0.62),
            borderRadius: tabRadius,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.linear,
                    style: TextStyle(
                      color: selected ? OtohaColors.canvas : OtohaColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    child: Text(label, maxLines: 1),
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

import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '/src/shared/widgets/toast_helper.dart';
import 'package:go_router/go_router.dart';
import '/src/core/navigation/navigation.dart';
import '/src/core/navigation/sub_navigation_notifier.dart';
import '/src/core/theme/desktop_semantic_colors.dart';
import '/src/core/utils/logger.dart';
import '/src/features/auth/application/auth_service.dart';
import '/src/features/misskey/application/misskey_notifier.dart';
import '/src/features/misskey/application/misskey_notifications_notifier.dart';
import '/src/features/misskey/application/misskey_streaming_service.dart';
import '/src/shared/widgets/error_state.dart';
import 'pages/misskey_aiscript_console_page.dart';
import 'pages/misskey_announcements_page.dart';
import 'pages/misskey_antennas_page.dart';
import 'pages/misskey_channels_page.dart';
import 'pages/misskey_explore_page.dart';
import 'pages/misskey_follow_requests_page.dart';
import 'pages/misskey_notes_page.dart';
import 'pages/misskey_post_page.dart';
import 'pages/misskey_timeline_page.dart';
import 'widgets/avatar_menu_card.dart';
import '/src/shared/widgets/circle_icon_button.dart';
import '/src/shared/widgets/cyani_loading_indicator.dart';
import 'widgets/timeline_selector_sheet.dart';

class MisskeyPage extends ConsumerStatefulWidget {
  const MisskeyPage({super.key});

  @override
  ConsumerState<MisskeyPage> createState() => _MisskeyPageState();
}

class _MisskeyPageState extends ConsumerState<MisskeyPage>
    with WidgetsBindingObserver {
  String _timelineType = 'Global';
  bool _isToastVisible = false;
  StreamSubscription<bool>? _toastSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 监听 Toast 可见性变化
    _toastSubscription = ref
        .read(misskeyStreamingServiceProvider.notifier)
        .toastVisibilityStream
        .listen((visible) {
      if (mounted) {
        setState(() => _isToastVisible = visible);
      }
    });
  }

  @override
  void dispose() {
    _toastSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      logger.info('MisskeyPage: App resumed, triggering background refresh');
      _triggerBackgroundRefresh();
    }
  }

  void _triggerBackgroundRefresh() {
    try {
      final index = ref.read(misskeySubIndexProvider);
      if (index == 0) {
        ref.read(misskeyTimelineProvider(_timelineType).notifier).refresh();
      }
      ref.read(misskeyNotificationsProvider.notifier).refresh();
    } catch (e) {
      logger.warning('MisskeyPage: Background refresh failed: $e');
    }
  }

  void _triggerRefreshIfNecessary(int index) {
    if (index == 0) {
      try {
        ref.read(misskeyTimelineProvider(_timelineType).notifier).refresh();
      } catch (e) {
        logger.warning('MisskeyPage: Manual refresh failed: $e');
      }
    }
  }

  void _onTimelineTypeChanged(String timelineType) {
    if (timelineType == _timelineType) return;
    setState(() => _timelineType = timelineType);
    ref.read(misskeyTimelineProvider(timelineType).notifier).refresh();
  }

  final List<String> _titles = [
    'misskey_page_timeline'.tr(),
    'misskey_page_clips'.tr(),
    'misskey_page_antennas'.tr(),
    'misskey_page_channels'.tr(),
    'misskey_page_explore'.tr(),
    'misskey_page_follow_requests'.tr(),
    'misskey_page_announcements'.tr(),
    'misskey_page_aiscript_console'.tr(),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedAccountAsync = ref.watch(selectedMisskeyAccountProvider);
    final selectedIndex = ref.watch(misskeySubIndexProvider);
    final desktopColors = context.desktopSemanticColors;
    final isTimelineSelected = selectedIndex == 0;

    final pages = [
      MisskeyTimelinePage(
        key: const ValueKey('timeline'),
        timelineType: _timelineType,
      ),
      const MisskeyNotesPage(key: ValueKey('notes')),
      const MisskeyAntennasPage(key: ValueKey('antennas')),
      const MisskeyChannelsPage(key: ValueKey('channels')),
      const MisskeyExplorePage(key: ValueKey('explore')),
      const MisskeyFollowRequestsPage(key: ValueKey('follow_requests')),
      const MisskeyAnnouncementsPage(key: ValueKey('announcements')),
      const MisskeyAiScriptConsolePage(key: ValueKey('aiscript_console')),
    ];

    ref.listen(misskeySubIndexProvider, (previous, next) {
      if (next == 0 && previous != 0) {
        logger.info('MisskeyPage: Returned to timeline, triggering refresh');
        _triggerRefreshIfNecessary(next);
      }
    });

    return Scaffold(
      floatingActionButton: selectedIndex == 0
          ? FloatingActionButton(
              heroTag: 'misskey_fab',
              onPressed: () => _handlePostAction(context),
              child: const Icon(Icons.edit),
            )
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              backgroundColor: isTimelineSelected
                  ? desktopColors.timelineBackground
                  : desktopColors.contentBackground,
              leading: CircleIconButton(
                icon: Icons.menu,
                onPressed: () => ref
                    .read(navigationControllerProvider.notifier)
                    .openDrawer(),
              ),
              title: selectedIndex == 0
                  ? _TimelineIconBar(
                      timelineType: _timelineType,
                      onTimelineTypeChanged: _onTimelineTypeChanged,
                    )
                  : Text(_titles[selectedIndex]),
              titleSpacing: 4,
              centerTitle: false,
              floating: true,
              pinned: true,
              snap: true,
              actions: [
                if (_isToastVisible)
                  CircleIconButton(
                    icon: Icons.refresh,
                    tooltip: 'stream_refresh'.tr(),
                    onPressed: () {
                      ref
                          .read(misskeyStreamingServiceProvider.notifier)
                          .dismissToastAndReconnect();
                    },
                  ),
                // 用户头像按钮
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () {
                      _showAvatarMenu(context);
                    },
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      backgroundImage: selectedAccountAsync.value?.avatarUrl != null
                          ? NetworkImage(selectedAccountAsync.value!.avatarUrl!)
                          : null,
                      child: selectedAccountAsync.value?.avatarUrl == null
                          ? Icon(
                              Icons.person,
                              size: 18,
                              color: Theme.of(context).colorScheme.onSurface,
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ];
        },
        body: selectedAccountAsync.when(
          data: (account) {
            if (account == null) return _buildNoAccountState(context);
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                final isIncoming = child.key == pages[selectedIndex].key;
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: animation.drive(
                      Tween<Offset>(
                        begin: isIncoming
                            ? const Offset(0, 0.05)
                            : const Offset(0, -0.05),
                        end: Offset.zero,
                      ).chain(CurveTween(curve: Curves.easeOutCubic)),
                    ),
                    child: ExcludeSemantics(
                      excluding: !animation.isCompleted,
                      child: child,
                    ),
                  ),
                );
              },
              child: pages[selectedIndex],
            );
          },
          loading: () => const Center(child: CyaniLoadingIndicator()),
          error: (err, stack) => ErrorState(message: err.toString()),
        ),
      ),
    );
  }

  Future<void> _handlePostAction(BuildContext context) async {
    final authState = ref.read(authServiceProvider);
    final hasMisskeyAccount = authState.maybeWhen(
      data: (accounts) => accounts.any((a) => a.platform == 'misskey'),
      orElse: () => false,
    );

    if (hasMisskeyAccount) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => const MisskeyPostPage(),
      );
    } else {
      if (mounted) {
        if (!context.mounted) return;
        showToast(title: 'misskey_page_please_login'.tr(), type: ToastificationType.warning);
      }
    }
  }

  void _showAvatarMenu(BuildContext context) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    // 头像在 AppBar actions 区域的右侧，估算位置
    final avatarCenter = Offset(
      size.width - 24,
      MediaQuery.of(context).padding.top + 28,
    );

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => _AnimatedAvatarMenu(
        cardTop: avatarCenter.dy + 16,
        cardRight: size.width - avatarCenter.dx + 8,
        onDismiss: () => overlayEntry.remove(),
      ),
    );
    overlay.insert(overlayEntry);
  }

  Widget _buildNoAccountState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'misskey_page_no_account_title'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'misskey_page_no_account_subtitle'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.go('/profile'),
              icon: const Icon(Icons.login),
              label: Text('misskey_page_login_now'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineIconBar extends ConsumerWidget {
  const _TimelineIconBar({
    required this.timelineType,
    required this.onTimelineTypeChanged,
  });

  final String timelineType;
  final ValueChanged<String> onTimelineTypeChanged;

  IconData _getIcon(String type) {
    return switch (type) {
      'Home' => Icons.home_rounded,
      'Local' => Icons.language_rounded,
      'Social' => Icons.group_rounded,
      _ => Icons.public_rounded,
    };
  }

  Color _getIconColor(String type, ColorScheme colorScheme) {
    return switch (type) {
      'Home' => colorScheme.primary,
      'Local' => colorScheme.tertiary,
      'Social' => colorScheme.primaryContainer,
      _ => colorScheme.secondary,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final onlineColor = colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            TimelineSelectorSheet.show(
              context,
              currentType: timelineType,
              onTypeSelected: onTimelineTypeChanged,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getIcon(timelineType),
                  color: _getIconColor(timelineType, colorScheme),
                  size: 18,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        ref
            .watch(misskeyOnlineUsersProvider)
            .when(
              data: (count) {
                final suffix = switch (context.locale.languageCode) {
                  'zh' => '人在线',
                  'ja' => '人オンライン',
                  _ => ' online',
                };
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PulsingOnlineDot(color: onlineColor),
                    const SizedBox(width: 6),
                    RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodyMedium,
                        children: [
                          TextSpan(
                            text: count.toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: onlineColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: suffix,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (error, stack) => const SizedBox.shrink(),
            ),
      ],
    );
  }
}

class _PulsingOnlineDot extends StatefulWidget {
  const _PulsingOnlineDot({required this.color});

  final Color color;

  @override
  State<_PulsingOnlineDot> createState() => _PulsingOnlineDotState();
}

class _PulsingOnlineDotState extends State<_PulsingOnlineDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer expanding ripple ring
            Transform.scale(
              scale: 1.0 + (_controller.value * 1.5),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withAlpha(((1.0 - _controller.value) * 160).round()),
                ),
              ),
            ),
            // Inner solid dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withAlpha(120),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 带弹出/收起动画的头像菜单 Overlay 组件
class _AnimatedAvatarMenu extends StatefulWidget {
  final double cardTop;
  final double cardRight;
  final VoidCallback onDismiss;

  const _AnimatedAvatarMenu({
    required this.cardTop,
    required this.cardRight,
    required this.onDismiss,
  });

  @override
  State<_AnimatedAvatarMenu> createState() => _AnimatedAvatarMenuState();
}

class _AnimatedAvatarMenuState extends State<_AnimatedAvatarMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _controller.forward();
  }

  void _close() {
    if (_isClosing) return;
    _isClosing = true;
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 半透明遮罩（带淡入/淡出）
        FadeTransition(
          opacity: _fadeAnim,
          child: GestureDetector(
            onTap: _close,
            child: Container(color: Colors.black54),
          ),
        ),
        // 卡片（带缩放 + 淡入/淡出，从右上方展开）
        Positioned(
          top: widget.cardTop,
          right: widget.cardRight,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnim.value,
                alignment: Alignment.topRight,
                child: child,
              );
            },
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () {},
                child: AvatarMenuCard(onDismiss: _close),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

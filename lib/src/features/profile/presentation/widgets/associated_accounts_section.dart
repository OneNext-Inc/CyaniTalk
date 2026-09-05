import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:Nyachi/src/features/auth/application/auth_service.dart';
import 'package:Nyachi/src/features/auth/domain/account.dart';
import 'package:Nyachi/src/features/auth/presentation/pages/raw_data_viewer_page.dart';
import 'package:Nyachi/src/features/auth/presentation/widgets/add_account_dialog.dart';
import 'package:Nyachi/src/features/auth/presentation/widgets/misskey_permissions_sheet.dart';
import 'package:Nyachi/src/core/services/streaming/streaming_service_interface.dart';
import 'package:Nyachi/src/features/misskey/application/misskey_streaming_service.dart';
import 'package:Nyachi/src/shared/widgets/adaptive_sheet.dart';
import 'package:Nyachi/src/shared/widgets/cyani_loading_indicator.dart';
import 'package:Nyachi/src/shared/widgets/error_state.dart';
import 'package:Nyachi/src/features/profile/presentation/widgets/user_details_view.dart';

/// 统一登录管理器组件 — 卡片制账户管理
///
/// 布局：
/// - 顶部「主用户」卡片（AnimatedSwitcher 渐显渐隐切换）
/// - 下方「其他账户」可排序列表（仅容器内拖拽排序）
/// - 每张卡片右侧：原始数据 / API 权限 / 删除（图标按钮）
/// - 点击其他账户 → 设为主用户（伴随渐显渐隐动画）
class AssociatedAccountsSection extends ConsumerStatefulWidget {
  final bool showRemoveButton;

  const AssociatedAccountsSection({super.key, this.showRemoveButton = true});

  @override
  ConsumerState<AssociatedAccountsSection> createState() =>
      _AssociatedAccountsSectionState();
}

class _AssociatedAccountsSectionState
    extends ConsumerState<AssociatedAccountsSection> {
  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(authServiceProvider);
    final selectedMisskey =
        ref.watch(selectedMisskeyAccountProvider).asData?.value;

    return accountsAsync.when(
      data: (accounts) {
        if (accounts.isEmpty) {
          return _buildEmptyState(context);
        }

        final primaryAccount = selectedMisskey ?? accounts.first;
        final secondaryAccounts =
            accounts.where((a) => a.id != primaryAccount.id).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionLabel(
                context,
                'accounts_primary_label'.tr(),
                icon: Icons.star_rounded,
              ),
              const SizedBox(height: 8),
              // AnimatedSwitcher 实现主用户渐显渐隐切换
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _buildPrimaryCard(
                  context,
                  primaryAccount,
                  key: ValueKey(primaryAccount.id),
                ),
              ),
              if (secondaryAccounts.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildSectionLabel(
                  context,
                  'accounts_other_label'.tr(
                    namedArgs: {'count': '${secondaryAccounts.length}'},
                  ),
                  icon: Icons.people_outline,
                ),
                const SizedBox(height: 8),
                _buildSecondaryList(context, secondaryAccounts, primaryAccount),
              ],
              const SizedBox(height: 12),
              _buildAddAccountButton(context),
              const SizedBox(height: 16),
              _buildResetInfoBar(context),
            ],
          ),
        );
      },
      loading: () => const Center(child: CyaniLoadingIndicator()),
      error: (err, stack) => ErrorState(message: err.toString()),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.account_circle_outlined,
            size: 80,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'accounts_no_linked'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddAccountDialog(context),
            icon: const Icon(Icons.add),
            label: Text('accounts_add_account'.tr()),
          ),
        ],
      ),
    );
  }

  // ── Section label ────────────────────────────────────────────────────

  Widget _buildSectionLabel(
    BuildContext context,
    String text, {
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
        ],
        Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ── Primary card (含操作按钮) ────────────────────────────────────────

  Widget _buildPrimaryCard(
    BuildContext context,
    Account account, {
    Key? key,
  }) {
    final theme = Theme.of(context);

    return Container(
      key: key,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withAlpha(120),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: _buildCardContent(
        context,
        account,
        isPrimary: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconButton(
              context,
              icon: Icons.code,
              tooltip: 'accounts_view_raw_data'.tr(),
              onPressed: () => _openRawData(context, account),
            ),
            _iconButton(
              context,
              icon: Icons.key,
              tooltip: 'accounts_view_permissions'.tr(),
              onPressed: () => MisskeyPermissionsSheet.show(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Secondary list (仅容器内 ReorderableListView) ───────────────────

  Widget _buildSecondaryList(
    BuildContext context,
    List<Account> secondaryAccounts,
    Account primaryAccount,
  ) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(vertical: 4),
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 4,
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            child: child,
          );
        },
        itemCount: secondaryAccounts.length,
        onReorderItem: (oldIndex, newIndex) async {
          final ids = secondaryAccounts.map((a) => a.id).toList();
          final item = ids.removeAt(oldIndex);
          ids.insert(newIndex, item);
          final allIds = [primaryAccount.id, ...ids];
          await ref
              .read(authServiceProvider.notifier)
              .reorderAccounts(allIds);
        },
        itemBuilder: (context, index) {
          final account = secondaryAccounts[index];
          return Padding(
            key: ValueKey('secondary_${account.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: LongPressDraggable<Account>(
              data: account,
              feedback: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: _buildCardContent(context, account, isPrimary: false),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: _buildCardContent(context, account, isPrimary: false),
              ),
              child: _buildSecondaryItem(context, account, index),
            ),
          );
        },
      ),
    );
  }

  // ── 单个二级账户行（点击 → 设为主用户；含拖拽手柄 + 操作按钮）─────

  Widget _buildSecondaryItem(
    BuildContext context,
    Account account,
    int index,
  ) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _switchAccount(context, account),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // 拖拽手柄（左侧）
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.drag_handle,
                    size: 20,
                    color:
                        theme.colorScheme.onSurfaceVariant.withAlpha(150),
                  ),
                ),
              ),
              // 头像
              CircleAvatar(
                radius: 18,
                backgroundImage: account.avatarUrl != null
                    ? NetworkImage(account.avatarUrl!)
                    : null,
                child: account.avatarUrl == null
                    ? Text(
                        account.username?[0].toUpperCase() ?? '?',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // 名称 & 主机（占据剩余空间）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (account.name != null && account.name!.isNotEmpty)
                          ? account.name!
                          : (account.username ?? 'Unknown'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${account.username} · ${account.host}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 操作按钮（右侧，紧凑排列）
              _iconButton(
                context,
                icon: Icons.code,
                tooltip: 'accounts_view_raw_data'.tr(),
                onPressed: () => _openRawData(context, account),
              ),
              const SizedBox(width: 2),
              _iconButton(
                context,
                icon: Icons.key,
                tooltip: 'accounts_view_permissions'.tr(),
                onPressed: () => MisskeyPermissionsSheet.show(context),
              ),
              if (widget.showRemoveButton) ...[
                const SizedBox(width: 2),
                _iconButton(
                  context,
                  icon: Icons.delete_outline,
                  tooltip: 'accounts_remove_button'.tr(),
                  color: theme.colorScheme.error,
                  onPressed: () => _confirmDelete(context, account),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── 通用卡片内容 ────────────────────────────────────────────────────

  Widget _buildCardContent(
    BuildContext context,
    Account account, {
    required bool isPrimary,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final displayName = (account.name != null && account.name!.isNotEmpty)
        ? account.name!
        : (account.username ?? 'Unknown');
    final secondaryName =
        account.username != null ? '@${account.username}' : '';

    return Row(
      children: [
        CircleAvatar(
          radius: isPrimary ? 26 : 22,
          backgroundImage: account.avatarUrl != null
              ? NetworkImage(account.avatarUrl!)
              : null,
          child: account.avatarUrl == null
              ? Text(
                  account.username?[0].toUpperCase() ?? '?',
                  style: TextStyle(
                    fontSize: isPrimary ? 18 : 16,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isPrimary ? 16 : 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isPrimary) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'accounts_primary_badge'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$secondaryName · ${account.host}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  // ── 通用图标操作按钮 ────────────────────────────────────────────────

  Widget _iconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final theme = Theme.of(context);
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 18,
        color: color ?? theme.colorScheme.onSurfaceVariant.withAlpha(180),
      ),
      tooltip: tooltip,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  // ── 打开原始数据 ────────────────────────────────────────────────────

  void _openRawData(BuildContext context, Account account) {
    if (_isDesktop) {
      showAdaptiveSheet(
        context: context,
        sideSheetWidth: 420,
        builder: (context) => _RawDataSideSheetContent(account: account),
      );
    } else {
      RawDataViewerPage.open(context, account);
    }
  }

  // ── 删除确认（主用户和二级用户均需要）─────────────────────────────

  void _confirmDelete(BuildContext context, Account account) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('accounts_remove_title'.tr()),
        content: Text(
          'accounts_remove_confirm'.tr(
            namedArgs: {'username': account.username ?? 'Unknown'},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('accounts_remove_cancel'.tr()),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(authServiceProvider.notifier)
                  .removeAccount(account.id);
            },
            child: Text(
              'accounts_remove_confirm_button'.tr(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 添加账户按钮 ────────────────────────────────────────────────────

  Widget _buildAddAccountButton(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showAddAccountDialog(context),
        icon: const Icon(Icons.add, size: 18),
        label: Text('accounts_add_account'.tr()),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(120),
          ),
        ),
      ),
    );
  }

  // ── 添加账户 ────────────────────────────────────────────────────────

  void _showAddAccountDialog(BuildContext context) {
    AddAccountBottomSheet.show(context);
  }

  // ── 重置应用提示栏 ──────────────────────────────────────────────────

  Widget _buildResetInfoBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
                children: [
                  TextSpan(text: 'accounts_reset_info_prefix'.tr()),
                  TextSpan(
                    text: 'accounts_reset_info_link'.tr(),
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                    // 点击跳转到缓存设置页面（含"重置此应用"功能）
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        // 通过 go_router 导航到缓存设置页
                        Navigator.of(context).popUntil((route) => false);
                        Navigator.of(context).pushNamed('/settings/cache');
                      },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 切换账户（含弹窗 + 流抑制）─────────────────────────────────────

  Future<void> _switchAccount(BuildContext context, Account account) async {
    final streamingNotifier =
        ref.read(misskeyStreamingServiceProvider.notifier);

    // 1. 显示切换弹窗
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccountSwitchingDialog(account: account),
    );

    // 2. 抑制实时流 toast
    streamingNotifier.setSuppressToast(true);

    // 3. 执行账户切换
    await ref
        .read(authServiceProvider.notifier)
        .setPrimaryAccount(account);

    // 4. 等待新连接建立（监听 status stream）
    final completer = Completer<void>();
    late StreamSubscription<StreamingStatus> sub;
    sub = streamingNotifier.statusStream.listen((status) {
      if (status == StreamingStatus.connected && !completer.isCompleted) {
        completer.complete();
        sub.cancel();
      }
    });

    // 超时保护：最多等待 10 秒
    Future.delayed(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete();
        sub.cancel();
      }
    });

    await completer.future;

    // 5. 关闭切换弹窗
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

// ── 切换账户弹窗 ────────────────────────────────────────────────────────

class _AccountSwitchingDialog extends StatelessWidget {
  final Account account;

  const _AccountSwitchingDialog({required this.account});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = (account.name != null && account.name!.isNotEmpty)
        ? account.name!
        : (account.username ?? 'Unknown');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // M3E 加载动效 + 新账户头像
            Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 80,
                  height: 80,
                  child: CyaniLoadingIndicator(),
                ),
                CircleAvatar(
                  radius: 24,
                  backgroundImage: account.avatarUrl != null
                      ? NetworkImage(account.avatarUrl!)
                      : null,
                  child: account.avatarUrl == null
                      ? Text(
                          account.username?[0].toUpperCase() ?? '?',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'accounts_switching_to'.tr(
                namedArgs: {'username': displayName},
              ),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'accounts_switching_syncing'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 桌面端 Side Sheet 内容 ──────────────────────────────────────────────

class _RawDataSideSheetContent extends ConsumerWidget {
  final Account account;

  const _RawDataSideSheetContent({required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detailsAsync = ref.watch(userDetailsProvider(account));
    final displayName = (account.name != null && account.name!.isNotEmpty)
        ? account.name!
        : (account.username ?? 'Unknown');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'accounts_raw_data_title'.tr(
                    namedArgs: {'username': displayName},
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: detailsAsync.when(
            data: (data) {
              final jsonString =
                  const JsonEncoder.withIndent('  ').convert(data);
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    jsonString,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'JetBrainsMono',
                      height: 1.5,
                    ),
                  ),
                ),
              );
            },
            loading: () => const Center(child: CyaniLoadingIndicator()),
            error: (err, _) =>
                Center(child: ErrorState(message: err.toString())),
          ),
        ),
      ],
    );
  }
}

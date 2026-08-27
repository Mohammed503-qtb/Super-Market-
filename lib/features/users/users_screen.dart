import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/providers/auth_provider.dart';
import '../../application/service_locator.dart';
import '../../data/database/app_database.dart';
import '../shared/widgets.dart';

/// شاشة إدارة المستخدمين والصلاحيات
/// --------------------------------
/// تحتوي على تبويبين:
///  1) المستخدمون: قائمة بكل المستخدمين مع البحث، إضافة/تعديل/حذف،
///     عرض اسم الدور والحالة وآخر دخول وتاريخ الإنشاء.
///  2) الأدوار والصلاحيات: قائمة بالأدوار، الضغط على دور يفتح نافذة
///     لإدارة صلاحياته مجمّعة حسب الوحدة (Module).
///
/// صلاحيات التحكم: users.view (دخول الشاشة)، users.create، users.edit،
/// users.delete. الأدوار النظامية (isSystemRole = true) لا يمكن تعديل
/// صلاحياتها لكن تُعرض فقط.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // شريط التبويبات مدمج أعلى الشاشة (بدون AppBar منفصل لكل تبويب).
          Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 1,
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              tabAlignment: TabAlignment.center,
              labelColor: AppColors.primary,
              indicatorColor: AppColors.primary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(
                  icon: Icon(Icons.people_outline, size: 20),
                  text: 'المستخدمون',
                ),
                Tab(
                  icon: Icon(Icons.shield_outlined, size: 20),
                  text: 'الأدوار والصلاحيات',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _UsersTab(),
                _RolesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  تبويب المستخدمين
// ============================================================================

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  // ===== Controllers =====
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ===== Data =====
  final List<User> _users = [];
  final Map<int, Role> _rolesMap = {};

  // ===== حالة الواجهة =====
  bool _isLoading = true;
  String _searchQuery = '';

  // ===== الصلاحيات =====
  bool _canCreate = false;
  bool _canEdit = false;
  bool _canDelete = false;

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _refresh();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _initPermissions() {
    final auth = context.read<AuthProvider>();
    _canCreate = auth.hasPermission(PermissionCodes.usersCreate);
    _canEdit = auth.hasPermission(PermissionCodes.usersEdit);
    _canDelete = auth.hasPermission(PermissionCodes.usersDelete);
  }

  // =====================
  // تحميل البيانات
  // =====================

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final db = ServiceLocator.database;
      final results = await Future.wait([
        db.userDao.getAll(),
        db.roleDao.getAll(),
      ]);
      final users = results[0] as List<User>;
      final roles = results[1] as List<Role>;

      _rolesMap
        ..clear()
        ..addEntries(roles.map((r) => MapEntry(r.id, r)));

      // فلترة حسب البحث (اسم المستخدم أو الاسم المعروض)
      final q = _searchQuery.trim().toLowerCase();
      _users
        ..clear()
        ..addAll(q.isEmpty
            ? users
            : users.where((u) {
                return u.username.toLowerCase().contains(q) ||
                    u.displayName.toLowerCase().contains(q);
              }).toList());
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'فشل تحميل المستخدمين: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: AppConstants.searchDebounceMs),
      () {
        _searchQuery = _searchController.text;
        _refresh();
      },
    );
  }

  // =====================
  // إحصائيات
  // =====================

  int get _activeCount => _users.where((u) => u.isActive).length;
  int get _rolesCount => _rolesMap.length;

  // =====================
  // حماية الحذف: لا يمكن حذف نفسك أو آخر مدير
  // =====================

  /// المديرون = المستخدمون الذين يملكون صلاحية users.delete عبر دورهم.
  /// نعتبر "آخر مدير" عقبة أمام الحذف حتى لا يبقى النظام بلا صلاحية إدارة.
  Future<int> _countAdmins() async {
    final db = ServiceLocator.database;
    final all = await db.userDao.getAll();
    int count = 0;
    for (final u in all) {
      final perms = await db.userDao.getPermissionsForUser(u.id);
      if (perms.any((p) => p.code == PermissionCodes.usersDelete)) {
        count++;
      }
    }
    return count;
  }

  // =====================
  // فتح النماذج
  // =====================

  Future<void> _openUserForm({User? user}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserFormDialog(
        user: user,
        roles: _rolesMap.values.toList(),
      ),
    );
    if (result == true) {
      await _refresh();
    }
  }

  Future<void> _openResetPassword(User user) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResetPasswordDialog(user: user),
    );
    if (result == true) {
      if (mounted) {
        showSuccessSnackBar(
            context, 'تم إعادة تعيين كلمة مرور "${user.username}"');
      }
    }
  }

  // =====================
  // حذف المستخدم
  // =====================

  Future<void> _confirmDelete(User user) async {
    final currentUserId = context.read<AuthProvider>().currentUser!.id;

    // 1) لا يمكن حذف نفسك
    if (user.id == currentUserId) {
      showErrorSnackBar(context, 'لا يمكنك حذف حسابك أثناء استخدامه');
      return;
    }

    // 2) التحقق من كونه آخر مدير
    try {
      final db = ServiceLocator.database;
      final perms = await db.userDao.getPermissionsForUser(user.id);
      final isAdmin = perms.any((p) => p.code == PermissionCodes.usersDelete);
      if (isAdmin) {
        final adminCount = await _countAdmins();
        if (adminCount <= 1) {
          if (!mounted) return;
          showErrorSnackBar(
            context,
            'لا يمكن حذف آخر مستخدم يملك صلاحية إدارة المستخدمين',
          );
          return;
        }
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل التحقق من الصلاحيات: $e');
      return;
    }

    if (!mounted) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'حذف المستخدم',
      message: 'هل أنت متأكد من حذف المستخدم "${user.displayName}" '
          '(${user.username})؟ لا يمكن التراجع عن هذا الإجراء.',
      confirmText: 'حذف',
      isDanger: true,
    );
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      await ServiceLocator.database.userDao.deleteUser(user.id);
      if (mounted) {
        showSuccessSnackBar(context, 'تم حذف المستخدم بنجاح');
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل الحذف: $e');
    }
  }

  // =====================
  // البناء
  // =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openUserForm(),
              icon: const Icon(Icons.person_add),
              label: const Text('مستخدم جديد'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildSearchAndStats()),
            if (_isLoading && _users.isEmpty)
              const SliverFillRemaining(
                child: LoadingIndicator(message: 'جارٍ تحميل المستخدمين...'),
              )
            else if (_users.isEmpty)
              SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.people_outline,
                  message: _searchQuery.isNotEmpty
                      ? 'لا يوجد مستخدمون مطابقون لبحثك'
                      : 'لا يوجد مستخدمون بعد',
                  actionLabel: _canCreate ? 'إضافة مستخدم' : null,
                  onAction: _canCreate ? () => _openUserForm() : null,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                sliver: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (wide) {
                      return SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 460,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.05,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _UserCard(
                            user: _users[i],
                            role: _rolesMap[_users[i].roleId],
                            isSelf: _users[i].id ==
                                context.read<AuthProvider>().currentUser!.id,
                            canEdit: _canEdit,
                            canDelete: _canDelete,
                            onTap: () => _openUserForm(user: _users[i]),
                            onEdit: () => _openUserForm(user: _users[i]),
                            onResetPassword: () =>
                                _openResetPassword(_users[i]),
                            onDelete: () => _confirmDelete(_users[i]),
                          ),
                          childCount: _users.length,
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _UserTile(
                          user: _users[i],
                          role: _rolesMap[_users[i].roleId],
                          isSelf: _users[i].id ==
                              context.read<AuthProvider>().currentUser!.id,
                          canEdit: _canEdit,
                          canDelete: _canDelete,
                          onTap: () => _openUserForm(user: _users[i]),
                          onEdit: () => _openUserForm(user: _users[i]),
                          onResetPassword: () => _openResetPassword(_users[i]),
                          onDelete: () => _confirmDelete(_users[i]),
                        ),
                        childCount: _users.length,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          // StatCards
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                StatCard(
                  title: 'إجمالي المستخدمين',
                  value: _users.length.toString(),
                  icon: Icons.people_alt_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                StatCard(
                  title: 'المستخدمون النشطون',
                  value: _activeCount.toString(),
                  icon: Icons.verified_user_outlined,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                StatCard(
                  title: 'إجمالي الأدوار',
                  value: _rolesCount.toString(),
                  icon: Icons.shield_outlined,
                  color: AppColors.accent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SearchField(
            controller: _searchController,
            hintText: 'بحث باسم المستخدم أو الاسم المعروض...',
            onChanged: _onSearchChanged,
            onClear: () {
              _searchQuery = '';
              _refresh();
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  بطاقة المستخدم (عريض)
// ============================================================================

class _UserCard extends StatelessWidget {
  final User user;
  final Role? role;
  final bool isSelf;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.role,
    required this.isSelf,
    required this.canEdit,
    required this.canDelete,
    required this.onTap,
    required this.onEdit,
    required this.onResetPassword,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initials(user.displayName);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الصف العلوي: الأفتار + الاسم + شارة الحالة
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: (role?.isSystemRole ?? false)
                        ? AppColors.accent.withValues(alpha: 0.15)
                        : AppColors.primary.withValues(alpha: 0.15),
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: (role?.isSystemRole ?? false)
                            ? AppColors.accent
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.displayName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSelf) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.info.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'أنت',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.info,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${user.username}',
                          style: TextStyle(
                            color: AppColors.textSecondaryLight,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _ActiveBadge(active: user.isActive),
                ],
              ),
              const Divider(height: 20),
              // الدور
              InfoRow(
                label: 'الدور',
                value: role?.name ?? '—',
                icon: Icons.shield_outlined,
                valueColor: (role?.isSystemRole ?? false)
                    ? AppColors.accent
                    : AppColors.primary,
              ),
              // آخر دخول
              InfoRow(
                label: 'آخر دخول',
                value: user.lastLoginAt == null
                    ? 'لم يسجل دخول'
                    : FormatUtils.formatDateTime(user.lastLoginAt!),
                icon: Icons.access_time,
              ),
              // تاريخ الإنشاء
              InfoRow(
                label: 'أُنشئ في',
                value: FormatUtils.formatDate(user.createdAt),
                icon: Icons.event_outlined,
              ),
              const Spacer(),
              // أزرار الإجراءات
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canEdit)
                    IconButton(
                      tooltip: 'تعديل',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      color: AppColors.primary,
                      onPressed: onEdit,
                    ),
                  if (canEdit)
                    IconButton(
                      tooltip: 'إعادة تعيين كلمة المرور',
                      icon: const Icon(Icons.password_outlined, size: 20),
                      color: AppColors.secondary,
                      onPressed: onResetPassword,
                    ),
                  if (canDelete && !isSelf)
                    IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: AppColors.error,
                      onPressed: onDelete,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  عنصر قائمة المستخدم (هاتف)
// ============================================================================

class _UserTile extends StatelessWidget {
  final User user;
  final Role? role;
  final bool isSelf;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;

  const _UserTile({
    required this.user,
    required this.role,
    required this.isSelf,
    required this.canEdit,
    required this.canDelete,
    required this.onTap,
    required this.onEdit,
    required this.onResetPassword,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initials(user.displayName);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: (role?.isSystemRole ?? false)
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  initials,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (role?.isSystemRole ?? false)
                        ? AppColors.accent
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          const Text(
                            '(أنت)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.info,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${user.username} • ${role?.name ?? '—'}',
                      style: TextStyle(
                        color: AppColors.textSecondaryLight,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.lastLoginAt == null
                          ? 'آخر دخول: لم يسجل دخول'
                          : 'آخر دخول: ${FormatUtils.formatDateTime(user.lastLoginAt!)}',
                      style: TextStyle(
                        color: AppColors.textSecondaryLight,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ActiveBadge(active: user.isActive),
              if (canEdit || (canDelete && !isSelf)) ...[
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  tooltip: 'إجراءات',
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'reset':
                        onResetPassword();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (canEdit)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('تعديل'),
                        ]),
                      ),
                    if (canEdit)
                      const PopupMenuItem(
                        value: 'reset',
                        child: Row(children: [
                          Icon(Icons.password_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('إعادة تعيين كلمة المرور'),
                        ]),
                      ),
                    if (canDelete && !isSelf)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: AppColors.error),
                          SizedBox(width: 8),
                          Text('حذف', style: TextStyle(color: AppColors.error)),
                        ]),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  final bool active;
  const _ActiveBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.textSecondaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        active ? 'نشط' : 'معطّل',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '؟';
  if (parts.length == 1) {
    return parts.first.substring(0, parts.first.length.clamp(1, 2));
  }
  return '${parts.first[0]}${parts[1][0]}';
}

// ============================================================================
//  تبويب الأدوار
// ============================================================================

class _RolesTab extends StatefulWidget {
  const _RolesTab();

  @override
  State<_RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends State<_RolesTab> {
  // ===== Data =====
  final List<Role> _roles = [];
  final Map<int, int> _userCountByRole = {};
  final Map<int, int> _permCountByRole = {};

  bool _isLoading = true;
  // تحديث صلاحيات الأدوار يحتاج صلاحية users.edit
  late final bool _canEditPermissions;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _canEditPermissions = auth.hasPermission(PermissionCodes.usersEdit);
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final db = ServiceLocator.database;
      final roles = await db.roleDao.getAll();
      final users = await db.userDao.getAll();
      _roles
        ..clear()
        ..addAll(roles);
      _userCountByRole
        ..clear()
        ..addEntries(
          roles.map((r) =>
              MapEntry(r.id, users.where((u) => u.roleId == r.id).length)),
        );

      // احصاء الصلاحيات لكل دور
      _permCountByRole.clear();
      for (final r in roles) {
        final perms = await db.userDao.getPermissionsForRole(r.id);
        _permCountByRole[r.id] = perms.length;
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل الأدوار: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openRolePermissions(Role role) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RolePermissionsDialog(
        role: role,
        canEdit: _canEditPermissions && !role.isSystemRole,
      ),
    );
    if (result == true) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            if (_isLoading && _roles.isEmpty)
              const SliverFillRemaining(
                child: LoadingIndicator(message: 'جارٍ تحميل الأدوار...'),
              )
            else if (_roles.isEmpty)
              const SliverFillRemaining(
                child: EmptyState(
                  icon: Icons.shield_outlined,
                  message: 'لا توجد أدوار بعد',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                sliver: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    if (wide) {
                      return SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 480,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.6,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _RoleCard(
                            role: _roles[i],
                            userCount: _userCountByRole[_roles[i].id] ?? 0,
                            permCount: _permCountByRole[_roles[i].id] ?? 0,
                            onTap: () => _openRolePermissions(_roles[i]),
                          ),
                          childCount: _roles.length,
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _RoleTile(
                          role: _roles[i],
                          userCount: _userCountByRole[_roles[i].id] ?? 0,
                          permCount: _permCountByRole[_roles[i].id] ?? 0,
                          onTap: () => _openRolePermissions(_roles[i]),
                        ),
                        childCount: _roles.length,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إدارة الأدوار والصلاحيات',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'اضغط على أي دور لعرض وإدارة صلاحياته. الأدوار النظامية معروضة فقط '
            'ولا يمكن تعديل صلاحياتها.',
            style: TextStyle(
              color: AppColors.textSecondaryLight,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  بطاقة / عنصر قائمة الدور
// ============================================================================

class _RoleCard extends StatelessWidget {
  final Role role;
  final int userCount;
  final int permCount;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.userCount,
    required this.permCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = role.isSystemRole ? AppColors.accent : AppColors.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.shield, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          role.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (role.description != null &&
                            role.description!.isNotEmpty)
                          Text(
                            role.description!,
                            style: TextStyle(
                              color: AppColors.textSecondaryLight,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (role.isSystemRole)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Text(
                        'نظامي',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      icon: Icons.people_outline,
                      label: 'مستخدمون',
                      value: userCount.toString(),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                      icon: Icons.check_circle_outline,
                      label: 'صلاحيات',
                      value: permCount.toString(),
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.manage_accounts, size: 18),
                  label: const Text('إدارة الصلاحيات'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final Role role;
  final int userCount;
  final int permCount;
  final VoidCallback onTap;

  const _RoleTile({
    required this.role,
    required this.userCount,
    required this.permCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = role.isSystemRole ? AppColors.accent : AppColors.primary;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.shield, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            role.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (role.isSystemRole) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'نظامي',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$userCount مستخدم • $permCount صلاحية',
                      style: TextStyle(
                        color: AppColors.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: AppColors.textSecondaryLight),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textSecondaryLight,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
//  نموذج إضافة/تعديل المستخدم
// ============================================================================

class _UserFormDialog extends StatefulWidget {
  final User? user; // null = إنشاء
  final List<Role> roles;

  const _UserFormDialog({this.user, required this.roles});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _passwordCtrl;

  late int _selectedRoleId;
  late bool _isActive;
  bool _saving = false;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _usernameCtrl = TextEditingController(text: u?.username ?? '');
    _displayNameCtrl = TextEditingController(text: u?.displayName ?? '');
    _passwordCtrl = TextEditingController();

    // اختيار الدور الافتراضي
    if (u != null) {
      _selectedRoleId = u.roleId;
    } else if (widget.roles.isNotEmpty) {
      // افتراضياً نختار أول دور غير نظامي إن وُجد، وإلا الأول
      final nonSystem = widget.roles.where((r) => !r.isSystemRole).toList();
      _selectedRoleId =
          nonSystem.isNotEmpty ? nonSystem.first.id : widget.roles.first.id;
    } else {
      _selectedRoleId = 0; // لا توجد أدوار — التحقق سيصدر رسالة
    }
    if (widget.roles.isNotEmpty &&
        !widget.roles.any((r) => r.id == _selectedRoleId)) {
      _selectedRoleId = widget.roles.first.id;
    }

    _isActive = u?.isActive ?? true;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // التحقق من اختيار دور
    if (!widget.roles.any((r) => r.id == _selectedRoleId)) {
      showErrorSnackBar(context, 'يرجى اختيار دور');
      return;
    }

    setState(() => _saving = true);
    try {
      final db = ServiceLocator.database;

      // التحقق من تفرّد اسم المستخدم (في الإضافة أو عند تغييره في التعديل)
      final existing =
          await db.userDao.findByUsername(_usernameCtrl.text.trim());
      final isSelfEdit =
          _isEdit && existing != null && existing.id == widget.user!.id;
      if (existing != null && !isSelfEdit) {
        if (mounted) {
          showErrorSnackBar(
              context, 'اسم المستخدم مستخدم بالفعل، اختر اسماً آخر');
        }
        return;
      }

      if (_isEdit) {
        final u = widget.user!;
        final updated = u.copyWith(
          username: _usernameCtrl.text.trim(),
          displayName: _displayNameCtrl.text.trim(),
          roleId: _selectedRoleId,
          isActive: _isActive,
          updatedAt: DateTime.now(),
        );
        await db.userDao.updateUser(updated);
      } else {
        final companion = UsersCompanion.insert(
          username: _usernameCtrl.text.trim(),
          displayName: _displayNameCtrl.text.trim(),
          passwordHash: PasswordHasher.hash(_passwordCtrl.text),
          roleId: _selectedRoleId,
          isActive: Value(_isActive),
        );
        await db.userDao.insertUser(companion);
      }

      if (mounted) {
        showSuccessSnackBar(
          context,
          _isEdit ? 'تم تحديث المستخدم بنجاح' : 'تم إنشاء المستخدم بنجاح',
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل الحفظ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width >= 700 ? 600 : double.infinity,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // الترويسة
                  Row(
                    children: [
                      Icon(
                        _isEdit ? Icons.edit : Icons.person_add,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isEdit ? 'تعديل مستخدم' : 'إضافة مستخدم',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const Divider(),
                  // الحقول
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم *',
                      hintText: 'أحرف إنجليزية وأرقام (3 أحرف على الأقل)',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.none,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9_.]')),
                    ],
                    validator: (v) => Validators.username(v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الاسم المعروض *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        Validators.required(v, fieldName: 'الاسم المعروض'),
                  ),
                  const SizedBox(height: 12),
                  // كلمة المرور (إنشاء فقط)
                  if (!_isEdit) ...[
                    TextFormField(
                      controller: _passwordCtrl,
                      decoration: const InputDecoration(
                        labelText: 'كلمة المرور *',
                        hintText: '4 أحرف على الأقل',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      validator: (v) => Validators.password(v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // الدور
                  DropdownButtonFormField<int>(
                    value: widget.roles.any((r) => r.id == _selectedRoleId)
                        ? _selectedRoleId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'الدور *',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                    items: widget.roles.map((r) {
                      return DropdownMenuItem(
                        value: r.id,
                        child: Row(
                          children: [
                            Text(r.name),
                            if (r.isSystemRole) ...[
                              const SizedBox(width: 6),
                              const Text(
                                '(نظامي)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() => _selectedRoleId = v);
                            }
                          },
                    validator: (v) => v == null ? 'يرجى اختيار دور' : null,
                  ),
                  const SizedBox(height: 12),
                  // الحالة
                  SwitchListTile(
                    value: _isActive,
                    onChanged:
                        _saving ? null : (v) => setState(() => _isActive = v),
                    title: const Text('الحساب نشط'),
                    subtitle: Text(
                      _isActive
                          ? 'يمكن للمستخدم تسجيل الدخول'
                          : 'المستخدم معطّل ولا يمكنه الدخول',
                    ),
                    secondary: Icon(
                      _isActive ? Icons.check_circle : Icons.block,
                      color: _isActive ? AppColors.success : AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // الأزرار
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('إلغاء'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isEdit ? 'حفظ' : 'إنشاء'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  إعادة تعيين كلمة المرور
// ============================================================================

class _ResetPasswordDialog extends StatefulWidget {
  final User user;
  const _ResetPasswordDialog({required this.user});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _saving = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final db = ServiceLocator.database;
      final updated = widget.user.copyWith(
        passwordHash: PasswordHasher.hash(_passwordCtrl.text),
        updatedAt: DateTime.now(),
      );
      await db.userDao.updateUser(updated);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل إعادة التعيين: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.password, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text('إعادة تعيين كلمة المرور')),
        ],
      ),
      content: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: width >= 700 ? 480 : double.infinity),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'سيتم تغيير كلمة مرور المستخدم "${widget.user.displayName}" '
                  '(${widget.user.username}).',
                  style: TextStyle(
                      color: AppColors.textSecondaryLight, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور الجديدة *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  obscureText: !_showPassword,
                  validator: (v) => Validators.password(v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmCtrl,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور *',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: !_showPassword,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'تأكيد كلمة المرور مطلوب';
                    }
                    if (v != _passwordCtrl.text) {
                      return 'كلمتا المرور غير متطابقتين';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check),
          label: const Text('حفظ'),
        ),
      ],
    );
  }
}

// ============================================================================
//  إدارة صلاحيات الدور
// ============================================================================

class _RolePermissionsDialog extends StatefulWidget {
  final Role role;
  final bool canEdit;

  const _RolePermissionsDialog({
    required this.role,
    required this.canEdit,
  });

  @override
  State<_RolePermissionsDialog> createState() => _RolePermissionsDialogState();
}

class _RolePermissionsDialogState extends State<_RolePermissionsDialog> {
  bool _loading = true;
  bool _saving = false;
  final List<Permission> _allPermissions = [];
  final Set<int> _selectedIds = {};

  /// ترتيب الوحدات وأسماؤها العربية
  static const _moduleOrder = <String>[
    'sales',
    'purchase',
    'inventory',
    'customers',
    'suppliers',
    'cashbox',
    'reports',
    'users',
    'settings',
    'backup',
  ];

  static const _moduleLabelsAr = <String, String>{
    'sales': 'المبيعات',
    'purchase': 'المشتريات',
    'inventory': 'المخزون',
    'customers': 'العملاء',
    'suppliers': 'الموردون',
    'cashbox': 'الصندوق',
    'reports': 'التقارير',
    'users': 'المستخدمون',
    'settings': 'الإعدادات',
    'backup': 'النسخ الاحتياطي',
  };

  static const _moduleIcons = <String, IconData>{
    'sales': Icons.point_of_sale_outlined,
    'purchase': Icons.shopping_cart_outlined,
    'inventory': Icons.inventory_2_outlined,
    'customers': Icons.people_alt_outlined,
    'suppliers': Icons.local_shipping_outlined,
    'cashbox': Icons.account_balance_wallet_outlined,
    'reports': Icons.assessment_outlined,
    'users': Icons.manage_accounts_outlined,
    'settings': Icons.settings_outlined,
    'backup': Icons.backup_outlined,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final db = ServiceLocator.database;
      final allPerms = await db.roleDao.getAllPermissions();
      final rolePerms = await db.userDao.getPermissionsForRole(widget.role.id);
      _allPermissions
        ..clear()
        ..addAll(allPerms);
      _selectedIds
        ..clear()
        ..addAll(rolePerms.map((p) => p.id));
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل تحميل الصلاحيات: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ServiceLocator.database.userDao
          .setRolePermissions(widget.role.id, _selectedIds.toList());
      if (mounted) {
        showSuccessSnackBar(
            context, 'تم تحديث صلاحيات دور "${widget.role.name}"');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'فشل الحفظ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleModule(String module, bool selectAll) {
    setState(() {
      final modulePerms = _allPermissions.where((p) => p.module == module);
      if (selectAll) {
        _selectedIds.addAll(modulePerms.map((p) => p.id));
      } else {
        _selectedIds.removeAll(modulePerms.map((p) => p.id));
      }
    });
  }

  void _togglePermission(int id, bool value) {
    setState(() {
      if (value) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  /// وحدات موجودة فعلاً في قائمة الصلاحيات (محفوظة بترتيب _moduleOrder)
  List<String> get _modulesInUse {
    final present = _allPermissions.map((p) => p.module).toSet();
    return [
      ..._moduleOrder.where((m) => present.contains(m)),
      ...present.difference(_moduleOrder.toSet()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width >= 900 ? 900 : double.infinity,
          maxHeight: height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الترويسة
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (widget.role.isSystemRole
                              ? AppColors.accent
                              : AppColors.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.shield,
                      color: widget.role.isSystemRole
                          ? AppColors.accent
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.role.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.role.description != null &&
                            widget.role.description!.isNotEmpty)
                          Text(
                            widget.role.description!,
                            style: TextStyle(
                              color: AppColors.textSecondaryLight,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              // تنبيه الأدوار النظامية
              if (widget.role.isSystemRole)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.08),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.accent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'هذا دور نظامي ولا يمكن تعديل صلاحياته. '
                          'العرض فقط.',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 20),
              // المحتوى
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: LoadingIndicator(message: 'جارٍ تحميل الصلاحيات...'),
                )
              else
                Expanded(
                  child: ListView(
                    children: _modulesInUse.map((module) {
                      return _buildModuleSection(module);
                    }).toList(),
                  ),
                ),
              // الأزرار
              if (!_loading) ...[
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الصلاحيات المفعّلة: ${_selectedIds.length} / ${_allPermissions.length}',
                      style: TextStyle(
                        color: AppColors.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('إغلاق'),
                        ),
                        if (widget.canEdit) ...[
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('حفظ'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleSection(String module) {
    final perms = _allPermissions.where((p) => p.module == module).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final moduleLabel = _moduleLabelsAr[module] ?? module;
    final moduleIcon = _moduleIcons[module] ?? Icons.folder_outlined;

    final modulePermIds = perms.map((p) => p.id).toSet();
    final selectedInModule = modulePermIds.intersection(_selectedIds).length;
    final allSelected = selectedInModule == perms.length && perms.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(moduleIcon, color: AppColors.primary),
        title: Row(
          children: [
            Expanded(
              child: Text(
                moduleLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$selectedInModule / ${perms.length}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        // زر "تحديد الكل / إلغاء الكل" داخل الوحدة
        trailing: widget.canEdit
            ? IconButton(
                tooltip: allSelected ? 'إلغاء تحديد الكل' : 'تحديد الكل',
                icon: Icon(
                  allSelected
                      ? Icons.deselect_outlined
                      : Icons.select_all_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
                onPressed: () => _toggleModule(module, !allSelected),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: perms.map((p) {
                final checked = _selectedIds.contains(p.id);
                return CheckboxListTile(
                  value: checked,
                  onChanged: widget.canEdit
                      ? (v) => _togglePermission(p.id, v ?? false)
                      : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: Text(p.name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(
                    p.code,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondaryLight,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

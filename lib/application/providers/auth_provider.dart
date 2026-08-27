import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database/app_database.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';

/// مزود المصادقة - يدير جلسة المستخدم الحالي والصلاحيات
class AuthProvider extends ChangeNotifier {
  final AppDatabase _db;
  final SharedPreferences _prefs;

  User? _currentUser;
  List<String> _permissions = [];
  bool _isLoading = false;

  AuthProvider(this._db, this._prefs);

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  List<String> get permissions => _permissions;
  int? get currentUserId => _currentUser?.id;
  String get currentDisplayName => _currentUser?.displayName ?? '';
  String get currentRoleName {
    if (_currentUser == null) return '';
    // نحتاج لجلب اسم الدور
    return _currentUser!.roleId.toString();
  }

  /// التحقق من صلاحية معينة
  bool hasPermission(String code) {
    if (_currentUser == null) return false;
    return _permissions.contains(code);
  }

  /// التحقق من صلاحية معينة وإلا رمي استثناء
  void requirePermission(String code) {
    if (!hasPermission(code)) {
      AppLogger.auth('Permission denied: $code for user ${_currentUser?.id}');
      throw PermissionDeniedException();
    }
  }

  /// تسجيل الدخول
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = await _db.userDao.findByUsername(username);
      if (user == null) {
        throw AuthenticationException('اسم المستخدم غير موجود');
      }
      if (!user.isActive) {
        throw UserInactiveException();
      }
      if (!PasswordHasher.verify(password, user.passwordHash)) {
        throw AuthenticationException('كلمة المرور غير صحيحة');
      }

      // تحديث آخر تسجيل دخول
      await _db.userDao.updateLastLogin(user.id);

      // جلب الصلاحيات
      final perms = await _db.userDao.getPermissionsForUser(user.id);
      _permissions = perms.map((p) => p.code).toList();
      _currentUser = user;

      // حفظ معرف المستخدم في الجلسة
      await _prefs.setInt('user_id', user.id);

      // تسجيل في الـ Audit Log
      await _db.auditLogDao.insertLog(AuditLogsCompanion.insert(
        userId: Value(user.id),
        action: 'LOGIN',
        module: const Value('auth'),
        entityType: const Value('user'),
        entityId: Value(user.id),
        description: const Value('تسجيل دخول ناجح'),
      ));

      AppLogger.auth('User logged in: ${user.username}');
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('Login failed', error: e);
      _currentUser = null;
      _permissions = [];
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// استعادة الجلسة المحفوظة عند بدء التطبيق
  Future<bool> restoreSession() async {
    final userId = _prefs.getInt('user_id');
    if (userId == null) return false;

    try {
      final user = await _db.userDao.findById(userId);
      if (user == null || !user.isActive) {
        await _prefs.remove('user_id');
        return false;
      }

      final perms = await _db.userDao.getPermissionsForUser(user.id);
      _permissions = perms.map((p) => p.code).toList();
      _currentUser = user;
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('Session restore failed', error: e);
      return false;
    }
  }

  /// تسجيل الخروج
  Future<void> logout() async {
    if (_currentUser != null) {
      await _db.auditLogDao.insertLog(AuditLogsCompanion.insert(
        userId: Value(_currentUser!.id),
        action: 'LOGOUT',
        module: const Value('auth'),
        entityType: const Value('user'),
        entityId: Value(_currentUser!.id),
        description: const Value('تسجيل خروج'),
      ));
    }
    _currentUser = null;
    _permissions = [];
    await _prefs.remove('user_id');
    notifyListeners();
  }
}

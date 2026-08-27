# Contributing to Grocery ERP

شكراً لاهتمامك بالمساهمة في نظام البقالة المحاسبي! 🎉

## 🚀 كيف تساهم

### 1. الإعداد المحلي

```bash
# Fork ثم Clone
git clone https://github.com/YOUR-USERNAME/Super-Market-.git
cd Super-Market-

# تثبيت الحزم
flutter pub get

# توليد ملفات Drift
flutter pub run build_runner build --delete-conflicting-outputs

# تشغيل التحليل
flutter analyze

# تشغيل الاختبارات
flutter test
```

### 2. إنشاء فرع جديد

```bash
git checkout -b feature/your-feature-name
# أو
git checkout -b fix/your-bug-fix
```

### 3. كتابة الكود

اتبع هذه المعايير:

#### أسلوب الكود
- استخدم TypeScript-like صرامة في الأنواع
- تجنب `dynamic` قدر الإمكان
- استخدم `final` للمتغيرات غير القابلة للتغيير
- علّق الدوال المعقدة بالعربية

#### البنية
- ضع الملفات في المجلدات الصحيحة حسب البنية المعمارية
- `core/` للطبقة الأساسية
- `data/` للوصول للبيانات
- `domain/` للمنطق
- `application/` لإدارة الحالة
- `features/` للواجهات

#### المعاملات المالية
- استخدم دائماً `_db.runInTransactionSafe()` للعمليات متعددة الخطوات
- تحقق من الصلاحيات قبل العمليات الحساسة
- سجّل في Audit Log

### 4. الاختبارات

أضف اختبارات لكل ميزة جديدة:

```dart
// test/unit/your_feature_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_erp/domain/services/your_service.dart';

void main() {
  group('YourService', () {
    test('should do something correctly', () {
      // ...
    });
  });
}
```

### 5. Commit والـ Push

```bash
git add .
git commit -m "feat: add new feature"
git push origin feature/your-feature-name
```

استخدم [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` ميزة جديدة
- `fix:` إصلاح خطأ
- `docs:` توثيق
- `style:` تنسيق
- `refactor:` إعادة هيكلة
- `test:` اختبارات
- `chore:` مهام عامة

### 6. فتح Pull Request

- اشرح التغييرات بوضوح
- ارفق صور إذا كان هناك تغييرات UI
- تأكد من نجاح `flutter analyze` و `flutter test`

## 📋 معايير القبول

- [ ] `flutter analyze` بدون أخطاء
- [ ] `flutter test` ناجح
- [ ] الكود يتبع البنية المعمارية
- [ ] تم إضافة اختبارات للميزات الجديدة
- [ ] تم تحديث التوثيق عند الحاجة
- [ ] المعاملات المالية ذرية
- [ ] الصلاحيات مُفْرضة على مستوى المنطق

## 🐛 الإبلاغ عن الأخطاء

استخدم [GitHub Issues](https://github.com/Mohammed503-qtb/Super-Market-/issues) مع:

- وصف واضح للمشكلة
- خطوات إعادة الإنتاج
- السلوك المتوقع vs الفعلي
- لقطات شاشة (إن أمكن)
- معلومات الجهاز (Android version, etc.)

## 💡 اقتراح ميزة

نرحب بالاقتراحات! افتح Issue مع:

- وصف الميزة
- لماذا هي مفيدة
- كيف ستكون الواجهة (إن أمكن)

## 📜 قواعد السلوك

- احترم جميع المساهمين
- استخدم لغة مهنية
- تقبل النقد البنّاء
- ركّز على ما هو الأفضل للمشروع

شكراً لمساهمتك! 🙏

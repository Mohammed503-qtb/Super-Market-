# Production Deployment Guide

دليل نشر تطبيق نظام البقالة المحاسبي في بيئة الإنتاج.

## 📋 المحتويات

- [متطلبات ما قبل النشر](#متطلبات-ما-قبل-النشر)
- [توليد مفتاح التوقيع](#توليد-مفتاح-التوقيع)
- [بناء APK للإنتاج](#بناء-apk-للإنتاج)
- [بناء App Bundle للمتجر](#بناء-app-bundle-للمتجر)
- [النشر على Google Play](#النشر-على-google-play)
- [النشر المباشر (APK)](#النشر-المباشر-apk)
- [ما بعد النشر](#ما-بعد-النشر)
- [الصيانة والتحديثات](#الصيانة-والتحديثات)

---

## متطلبات ما قبل النشر

### 1. التحقق من الجودة

```bash
# تشغيل التحليل - يجب أن يكون 0 أخطاء
flutter analyze

# تشغيل الاختبارات - يجب أن تكون كلها ناجحة
flutter test

# فحص الـ APK للتأكد من عدم وجود مشاكل
flutter build apk --release --analyze-size
```

### 2. تحديث الإصدار

عدّل `pubspec.yaml`:
```yaml
version: 1.0.0+1  # versionName+versionCode
```

- `versionName`: الإصدار الظاهر للمستخدم (مثل 1.0.0)
- `versionCode`: رقم صحيح متزايد (مثل 1، 2، 3...)

### 3. تغيير بيانات الدخول الافتراضية

> ⚠️ **مهم جداً**: بعد أول تشغيل في الإنتاج، يجب تغيير كلمة المرور الافتراضية (admin/admin123).

---

## توليد مفتاح التوقيع

### 1. إنشاء Keystore

```bash
keytool -genkey -v \
  -keystore ~/grocery-erp-keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias grocery-erp
```

أدخل المعلومات المطلوبة:
- كلمة مرور الـ keystore
- كلمة مرور الـ key
- اسمك
- اسم الوحدة
- اسم المنشأة
- المدينة
- الولاية
- رمز الدولة (YE لليمن)

### 2. إنشاء ملف key.properties

```bash
cp android/key.properties.example android/key.properties
```

عدّل `android/key.properties`:
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=grocery-erp
storeFile=/home/USER/grocery-erp-keystore.jks
```

> ⚠️ **تحذير**: لا ترفع ملف `key.properties` أو `.jks` إلى Git. كلاهما في `.gitignore`.

### 3. تأمين الـ Keystore

- احفظ نسخة احتياطية من الـ keystore في مكان آمن
- احفظ كلمات المرور في مدير كلمات مرور
- **لا تفقد الـ keystore** - بدونها لا يمكنك تحديث التطبيق على Google Play

---

## بناء APK للإنتاج

### APK كامل (للنشر المباشر)

```bash
flutter build apk --release
```

الناتج: `build/app/outputs/flutter-apk/app-release.apk`

### APK مقسمة (للأحجام المختلفة)

```bash
flutter build apk --split-per-abi --release
```

الناتج:
- `app-armeabi-v7a-release.apk` (للأجهزة القديمة)
- `app-arm64-v8a-release.apk` (للأجهزة الحديثة)
- `app-x86_64-release.apk` (للـ emulators)

---

## بناء App Bundle للمتجر

> 🎯 **موصى به لـ Google Play**

```bash
flutter build appbundle --release
```

الناتج: `build/app/outputs/bundle/release/app-release.aab`

---

## النشر على Google Play

### 1. إنشاء حساب Google Play Console

- اذهب إلى https://play.google.com/console
- سجل حساب مطور ($25 رسوم لمرة واحدة)
- أكمل إعداد الحساب

### 2. إنشاء التطبيق

- اضغط "Create app"
- اختر:
  - **App name**: نظام البقالة المحاسبي
  - **Default language**: العربية
  - **App type**: Application
  - **Pricing**: Free

### 3. إعداد قائمة المتجر

#### الوصف القصير
```
نظام محاسبي وإداري متكامل للبقالات ومحلات بيع الجملة - يعمل بدون إنترنت
```

#### الوصف الكامل
```
نظام ERP/POS محاسبي محلي متكامل للبقالات ومحلات بيع الجملة

✅ يعمل بالكامل بدون إنترنت
✅ مبيعات ومشتريات ومخزون
✅ عملاء وموردون وديون
✅ صندوق ومصروفات وأرباح
✅ تقارير شاملة
✅ نظام صلاحيات كامل
✅ نسخ احتياطي محلي
✅ دعم العربية كامل

المميزات:
- كاشير سريع (POS)
- إدارة المخزون مع التكلفة المرجحة
- كشوف حساب للعملاء والموردين
- تقارير الأرباح والصندوق
- نظام أدوار وصلاحيات
- سجل تدقيق كامل
- واجهة عربية RTL
- الوضع الفاتح والداكن
```

#### لقطات الشاشة
أضف لقطات شاشة للميزات الرئيسية (مطلوبة أحجام مختلفة)

#### أيقونة التطبيق
- 512x512 px PNG
- استخدم الأيقونة من `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`

#### لافتة التطبيق
- 1024x500 px PNG

### 4. رفع الـ AAB

- اذهب إلى Production → Create release
- ارفع ملف `app-release.aab`
- اكتب ملاحظات الإصدار
- اضغط Review release
- اضغط Start rollout to Production

### 5. مراجعة المحتوى

أكمل قسم Content rating:
- املأ الاستبيان
- احصل على التصنيف (E للجميع)

### 6. تحديد الفئة

- Category: Business
- Tags: POS, inventory, accounting

### 7. الخصوصية

أضف رابط سياسة الخصوصية (مطلوب):
```
هذا التطبيق لا يجمع أي بيانات شخصية. جميع البيانات محفوظة محلياً على جهازك.
```

---

## النشر المباشر (APK)

للنشر خارج Google Play:

1. ابنِ APK: `flutter build apk --release`
2. انسخ `app-release.apk` إلى جهاز Android
3. فعّل "تثبيت من مصادر غير معروفة"
4. افتح الملف وثبّت التطبيق

> 💡 **ملاحظة**: قد تحتاج لإرسال APK عبر WhatsApp أو Google Drive

---

## ما بعد النشر

### 1. التحقق من العمل

بعد التثبيت:
1. سجل الدخول بـ admin/admin123
2. غيّر كلمة المرور فوراً
3. أنشئ مستخدمين للأدوار المختلفة
4. أضف المنتجات والتصنيفات
5. اختبر دورة بيع كاملة
6. أنشئ نسخة احتياطية

### 2. الإعدادات الأولية

- اضبط بيانات المنشأة في الإعدادات
- حدد العملة
- اضبط الرصيد الافتتاحي للصندوق
- فعّل/عطل منع المخزون السالب

### 3. التدريب

درب الموظفين على:
- الكاشير
- إدارة المنتجات
- المدفوعات والديون
- النسخ الاحتياطي

---

## الصيانة والتحديثات

### تحديث التطبيق

1. عدّل الكود
2. حدّث الإصدار في `pubspec.yaml`
3. ابنِ APK/AAB جديد
4. ارفع على Google Play كإصدار جديد

### النسخ الاحتياطي المنتظم

ذكّر المستخدمين بـ:
- إنشاء نسخة احتياطية أسبوعية
- حفظ النسخ في مكان آمن
- اختبار الاستعادة بشكل دوري

### مراقبة الأخطاء

أضف أدوات مراقبة (اختياري):
- Firebase Crashlytics
- Sentry
- أكواد تتبع مخصصة

---

## استكشاف الأخطاء

### مشكلة: التطبيق لا يبني

```bash
# نظف وأعد البناء
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk --release
```

### مشكلة: خطأ في التوقيع

- تأكد من صحة `key.properties`
- تأكد من مسار الـ keystore
- تأكد من كلمات المرور

### مشكلة: التطبيق يغلق فوراً

- تأكد من توافق Android SDK
- تحقق من الأذونات
- راجع الـ logcat: `adb logcat`

---

## معلومات الإصدار الحالي

- **الإصدار**: 1.0.0
- **حجم APK**: ~30 MB
- **Android الأدنى**: 5.0 (API 21)
- **Android المستهدف**: 15 (API 35)
- **اللغة**: العربية
- **العملة الافتراضية**: ريال يمني (YER)

---

## الدعم

للدعم التقني:
- GitHub Issues: https://github.com/Mohammed503-qtb/Super-Market-/issues
- راجع [README.md](README.md) للمعلومات العامة
- راجع [CHANGELOG.md](CHANGELOG.md) للتغييرات

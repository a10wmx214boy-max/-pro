# مراسلة الشورجة — Android v1.000

وحدة Android أصلية مستقلة داخل مستودع سوق الشورجة. التطبيق يستخدم Supabase Auth/Postgres/Realtime/Storage عبر `supabase-kt 3.8.0`، ولا يحتوي أي service-role secret.

## إعداد محلي

أنشئ `android/local.properties` (لا ترفعه إلى Git):

```properties
sdk.dir=/path/to/Android/Sdk
SUPABASE_URL=https://tshzsyhjbrwptrlhtxdm.supabase.co
SUPABASE_KEY=<publishable-key>
```

شغّل الهجرة `supabase/migrations/20261002160000_messaging_v1.sql` على مشروع Supabase المرتبط. تم تطبيقها على المشروع الحالي عبر MCP مع الحفاظ على جداول السوق القديمة.

## البناء

```bash
cd android
./gradlew assembleDebug
./gradlew test
```

تحتاج البيئة Android SDK 35 وJDK 17. هذه الـSandbox لا تحتوي SDK/Gradle/ADB حالياً، لذلك يلزم تشغيل البناء على Android Studio أو CI مزود بـ Android SDK. لا يوجد APK مُعلن عنه قبل إتمام هذا التحقق.

## الحالة الحالية

- تسجيل/دخول/خروج Supabase Auth.
- بحث حقيقي في profiles.
- إنشاء محادثة فردية بدون تكرار على مستوى التطبيق.
- إرسال نص وحفظه في Postgres.
- قراءة أول 100 رسالة وترتيبها.
- `selectAsFlow` جاهز لربط Realtime في طبقة ViewModel التالية.
- مخطط RLS وStorage وreceipts وgroups في migration.

المراحل المتبقية قبل release APK: ربط تدفق Realtime داخل lifecycle، media picker/upload، audio recorder، notifications/FCM، واجهات المجموعات والإعدادات، UI tests، signing، واختبار جهاز حقيقي بحسابين.

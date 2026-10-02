# سوق الشورجة — Al-Sharji Market

## حالة التسليم: نسخة تطوير مرشحة وليست Production-ready مُعتمدة
تم تطوير المشروع المرفق فوق واجهته وأصوله الأصلية. أُعيدت كتابة طبقة الخادم غير الآمنة لأنها كانت تستخدم مصادقة مخصصة ونسخاً كاملة من الجداول في الذاكرة. التصميم RTL وملفات CSS والأيقونات المحلية بقيت أساس الواجهة.

**لا تنشر إلى الإنتاج قبل نجاح build واختبارات SQL والتكامل ومراجعة متصفح فعلية.** هذه البيئة لا توفر Node/npm/PostgreSQL أو اتصالاً بحساب Supabase، لذلك لا يوجد ادعاء بنجاح تشغيلها. انظر `docs/DELIVERY.md` و`docs/TEST-RESULTS.md`.

## المتطلبات
- Node.js 22 أو أحدث، npm، مشروع Supabase جديد.
- Supabase آخر بإعدادات منفصلة للاختبارات وPreview؛ لا تستخدم بيانات الإنتاج في Preview.
- GitHub جديد وVercel جديد. لا يحتاج المشروع حساب نشر سابقاً.

## 1. قاعدة البيانات
1. أنشئ مشروع Supabase جديداً تماماً.
2. شغّل بالترتيب في SQL Editor:
   - `supabase/migrations/001_marketplace_initial.sql`
   - `supabase/migrations/002_site_content.sql`
3. المخطط الجديد ليس migration ترقية تلقائية للقديم. **لا تشغّله فوق جداول النسخة القديمة**. بيانات المستخدمين القديمة لم تُنقل، وكلمات المرور القديمة لا تُستخدم.
4. RLS مفعّل، وحقول المدير والتحقق والترويج ليست قابلة للتعديل مباشرة. user_metadata يُستخدم فقط للاسم والمدينة أثناء التسجيل.
5. Storage bucket خاص باسم `marketplace-media` يُنشأ بواسطة SQL. الصور والفيديوهات لها روابط موقعة مؤقتة؛ أعد تحميل الصفحة لتجديدها. الملفات المرفوعة غير المرتبطة بإعلان تحتاج تنظيفاً دورياً تشغيلياً قبل الإنتاج.

## 2. إعداد Auth
- فعّل التسجيل بالبريد وتأكيد البريد. اضبط SMTP مناسباً للإنتاج.
- اضبط Site URL على نطاق Vercel النهائي، وأضف عنوان callback `/auth/confirm` إلى Redirect URLs لكل بيئة.
- فعّل Secure email change وإعادة التحقق/nonce وفق الخيارات المتاحة في Supabase. تدفقات nonce الإضافية ليست متكاملة في واجهة هذه النسخة؛ اختبرها قبل الإنتاج.
- في قوالب تأكيد التسجيل واستعادة كلمة المرور وتغيير البريد استخدم رابطاً إلى:
  `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=signup`
  وغيّر `type` إلى `recovery` أو `email_change` حسب قالب الرسالة. اختبر جميع الروابط في مشروع Preview.
- تغيير الهاتف يحتاج تفعيل Phone Auth وSMS provider. الرقم بصيغة `+9647xxxxxxxxx`، ثم تأكيد رمز phone_change من الإعدادات.
- استعادة كلمة المرور تستخدم verification من Auth وتذكرة خادمية أحادية الاستخدام لمدة 10 دقائق.
- الجلسة محفوظة في cookies HttpOnly/SameSite، وSecure في production. الطلبات المعدّلة تتطلب Origin مطابقاً، وليس bearer من المتصفح.
- إلغاء جلسات الأجهزة الأخرى يُلغي رموز التجديد؛ رموز الوصول قد تبقى حتى انتهاء صلاحيتها. اضبط JWT expiry مناسباً. قائمة أجهزة تفصيلية غير منفذة.

## 3. المدير الوحيد
1. أنشئ الحساب عبر التسجيل الطبيعي ثم أكد البريد.
2. انسخ UUID من Authentication → Users.
3. في SQL Editor فقط، نفّذ مع UUID حسابك الحقيقي:
   ```sql
   insert into public.admins(singleton,user_id)
   values(true,'REPLACE_WITH_AUTH_USER_UUID');
   ```
4. لا تضع كلمة مرور أو UUID حساب قديم في الكود. القيد boolean singleton يسمح بسجل واحد فقط.
5. دخول المدير يستخدم البريد وكلمة مرور Supabase نفسها. لا يمكن للمستخدم منح نفسه دوراً. حذف أو تعطيل المدير الحالي ممنوع.
6. يُوصى بإكمال MFA قبل الإنتاج؛ واجهة MFA ليست ضمن هذه النسخة.

## 4. البيئة المحلية
```bash
npm ci
cp .env.example .env
# املأ القيم محلياً فقط
npm run build
npm test
python3 tests/static_check.py
npm start
```
المتغيرات:
- `SUPABASE_URL`: عنوان مشروع جديد.
- `SUPABASE_ANON_KEY`: مفتاح anon العام المستخدم خادمياً مع JWT المستخدم.
- `SUPABASE_SERVICE_ROLE_KEY`: سر خادمي فقط للرفع المتحقق منه وAuth Admin والـrate limiter. ليس لطلبات CRUD العادية.
- `SITE_URL`: origin HTTPS النهائي، دون slash أخيرة.
- `NODE_ENV=production` على Vercel؛ محلياً استخدم development إذا شغلت HTTP.
- `PORT`: محلي فقط.

## 5. GitHub وVercel
- ارفع محتويات المشروع إلى مستودع جديد، وليس ZIP. `.gitignore` يمنع `.env` وnode_modules و.vercel وlogs.
- اربط المستودع بـVercel. `vercel.json` يوجه الطلبات إلى Express serverless، ويضم أصول الواجهة المطلوبة فقط.
- أضف القيم عبر Environment Variables، مع Supabase مستقل لـPreview.
- لا تضع متغيرات السر تحت أسماء PUBLIC أو NEXT_PUBLIC/VITE.
- شغّل CI الموجود في `.github/workflows/ci.yml` وأوقف النشر الإنتاجي عند فشله.
- `/health` يفحص اكتمال أسماء المتغيرات فقط، **ليس اختبار اتصال أو نجاح migrations**.
- الإعداد الحالي يستخدم legacy Vercel builds مع `@vercel/node`؛ اختبر Deployment Preview لأنه لم يُشغّل هنا.

## 6. الوسائط وحدود Vercel
رفع binary عبر backend يتحقق من magic bytes + Content-Type، ويقبل JPEG/PNG/WebP/MP4/WebM فقط. SVG والملفات التنفيذية مرفوضة. الصور تُضغط قبل الرفع.

**الحد الحالي 4MB للملف** لتجنب حد جسم طلب Vercel Functions؛ bucket أقصى حد 50MB لكن المسار الحالي لا يدعم تلك الأحجام. الفيديو الطويل يحتاج مسار signed/resumable upload موثوقاً مع تحقق خادمي لاحق قبل ربطه بالإعلان. لا يوجد ادعاء بتنفيذ ذلك.

تم التحقق من توقيع النوع، لا يوجد antivirus أو تحقق كامل من codec. لا تستخدم أسماء الملفات الأصلية؛ يولّد الخادم UUID تحت مجلد صاحب الحساب. حذف الملف عبر API ممنوع إذا ظل مرتبطاً بملف أو إعلان أو بنر. حذف الحساب لا ينظف Storage تلقائياً: أضف مهمة تنظيف مناسبة.

## 7. البيانات والصلاحيات
- CRUD المعتاد يذهب إلى Supabase باستخدام anon key + JWT المستخدم؛ PostgreSQL يفرض ownership.
- promotion ledger خاص مستقل عن الإعلان: أول نشر يستهلك الاستحقاق atomically. حذف الإعلان لا يعيده. التعديل يحفظ حالته. المدير يستطيع الإدارة عبر RPC محمي.
- الرسائل لأطرافها فقط؛ المدير يرى عدداً إجمالياً لا محتواها في لوحة البيانات. تحديث read فقط للمتلقي.
- favorites فريدة بمفتاح مركب. البلاغات للمرسل أو المدير، والملاحظات الإدارية تحتاج حماية إضافية إذا أضيف عرض بلاغات للمستخدم؛ الواجهة الحالية لا تعرضها له.
- عرض profiles العامة عبر RPC whitelist بلا بريد أو دور أو حالة إدارية. الهاتف اختيار خصوصية، والبريد يأتي من Auth لصاحبه فقط.
- ملفات listing_images/videos تتزامن مع حقول الوسائط بواسطة trigger؛ ليست مصادر متضاربة مستقلة.
- rate limiting خادمي مستمر في PostgreSQL لمسارات حساسة. يلزم أيضاً WAF/حدود Supabase Auth ومراجعة direct Data API abuse قبل الإنتاج.
- لا يوجد localStorage للبيانات أو جلسات التطبيق. بيانات العرض المؤقتة في الذاكرة ليست قاعدة بيانات. تفضيلات الحساب تحفظ في Supabase.

## 8. الاختبارات
```bash
npm run build  # syntax + JSON checks، ليس bundler
npm test      # unit tests؛ integration skipped بدون متغيراته
python3 tests/static_check.py
```
اختبار API على بيئة مؤقتة بحسابين مؤكدين:
```bash
RUN_INTEGRATION=1 TEST_SITE_URL=https://preview.example \
TEST_A_EMAIL=... TEST_A_PASSWORD=... TEST_B_EMAIL=... TEST_B_PASSWORD=... \
node --test tests/integration.test.js
```
حساب A يجب أن يكون جديداً لقياس أول نشر في اختبار SQL. الاختبارات تُنشئ ثم تحذف إعلانات وتُبقي رسالة اختبار؛ استخدم حسابات مؤقتة فقط.

اختبار مباشر لـRLS والترويج وصلاحيات الأعمدة:
```bash
psql "$TEST_DATABASE_URL" -v a="AUTH_A_UUID" -v b="AUTH_B_UUID" -f tests/rls.sql
```
اختبر أيضاً نشر إعلانين متزامنين لحساب جديد: يجب تمييز واحد فقط؛ الاختبار المتزامن غير مؤتمت حالياً.

## 9. ما يلزم قبل الإنتاج
راجع قائمة النواقص في DELIVERY: اختبار تشغيل ومراجعة SQL، pagination للمفضلة/المحادثات والإدارة، SEO للإعلانات، تقوية UX، مراجعة حماية الملفات ورفع الفيديو، MFA، تعطيل ذاتي وتصدير كامل وإدارة جلسات تفصيلية. المدونة والوظائف صفحات محتوى قابلة للتحرير وليستا CMS متعدد المقالات ونظام توظيف كامل.

## Android messaging app

The repository now includes an independent native Android messaging module at [`android/`](android/). It connects to the existing Supabase project using the publishable key only, with a tracked migration for conversations, chat messages, receipts, blocks, groups, Storage buckets, RLS, and Realtime publication. See [`android/README.md`](android/README.md) for setup and the current implementation boundary.

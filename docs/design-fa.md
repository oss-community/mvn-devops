# طراحی mvn-devops

## ایده در یک جمله

به‌جای اینکه برای هر موتور (Maven، Jenkins، Concourse) یه دسته اسکریپت جدا داشته باشیم که همه‌ی ابزارها رو از قبل توش گذاشتیم، **هر ابزار یک ماژول مستقل با اسکریپت خودشه**. یک اسکریپت اصلی (`devops.sh`) می‌پرسه چه ابزاری از هر دسته می‌خوای، و بعد فقط اسکریپت‌های همون ابزارها رو به ترتیب اجرا می‌کنه تا همه‌چیز بالا بیاد، تنظیم بشه و pipeline آماده‌ی اجرا باشه.

## مقایسه با pine-core-java

| | pine-core-java | mvn-devops |
|---|---|---|
| واحد کد | یک اسکریپت برای هر **موتور** که همه‌ی ابزارها داخلشه | یک ماژول برای هر **ابزار** |
| انتخاب ابزار | ثابت (Sonar، JFrog و Nexus همیشه هستن) | منو؛ از هر دسته هرچی بخوای |
| تکرار | سه نسخه‌ی تقریباً یکسان از secrets، pipeline و tokens | هر ابزار فقط یک بار نوشته شده |
| docker-compose | سه فایل کامل | هر ماژول یه تکه compose داره و موقع اجرا روی هم ادغام می‌شن |
| Jenkinsfile و pipeline.yml | دستی نوشته شده | از روی stage های ماژول‌های انتخاب‌شده **تولید** می‌شه |
| توکن‌ها | بخش زیادیش دستی از UI | خودکار (عوض‌کردن رمز ادمین، ساخت توکن، ثبت deploy key) |
| رسوندن متغیرها | `~/.bashrc`، `setx /M`، و REST جنکینز | فایل‌های `.devops/env` که فقط به فرایند pipeline داده می‌شن؛ اسرار همه‌جا mask می‌شن |

## دسته‌ها و ماژول‌ها

| دسته | نوع انتخاب | ماژول‌ها |
|---|---|---|
| Source control | اجباری | github |
| Build | اجباری | maven (validate، package، test، checkstyle، install) |
| Pipeline orchestrator | یکی | maven (روی سیستم خودت)، jenkins، concourse |
| Code quality | چندتایی | sonarqube |
| Artifact repositories | چندتایی | jfrog، nexus، github-packages |
| Project site | چندتایی | github-pages |

برای اضافه‌کردن ابزار جدید فقط یه پوشه‌ی تازه زیر `modules/<دسته>/<ابزار>/` لازمه؛ منو خودش پیداش می‌کنه ([module-guide.md](module-guide.md)).

## ساختار یک ماژول

```
modules/artifact/nexus/
  module.conf    اسم، توضیح، و ماژول‌هایی که بهشون وابسته‌ست
  compose.yml    container های این ابزار
  module.sh      hook ها
```

هر hook یه مرحله از چرخه‌ی عمره و اختیاریه:

| hook | کار |
|---|---|
| `module_secrets` | پرسیدن مقادیر لازم (پورت، رمز و ...) |
| `module_prepare` | آماده‌سازی قبل از بالا اومدن container ها |
| `module_configure` | تنظیم بعد از بالا اومدن: عوض‌کردن رمز ادمین، ساخت توکن و repository |
| `module_env` | معرفی متغیرهایی که pipeline لازم داره |
| `module_stages` | اضافه‌کردن stage های Maven به pipeline |
| `module_render`، `module_publish`، `module_run` | فقط برای orchestrator ها: ساختن، نصب و اجرای pipeline |

## نکته‌ی کلیدی: stage ها از ماژول‌ها میان

هر ماژول stage های خودش رو با شماره‌ی ترتیب و فاز (`ci` یا `cd`) اعلام می‌کنه. مثلاً sonarqube میگه «stage 45 در فاز ci: `sonar:sonar -P sonar`». orchestrator لیست مرتب‌شده رو می‌گیره و به زبان خودش تبدیل می‌کنه:

- **maven**: هر stage رو با `mvn` روی سیستم خودت اجرا می‌کنه.
- **jenkins**: یه Jenkinsfile و فایل `casc.yaml` می‌سازه که کاربر ادمین، credential ها و خود job رو تعریف می‌کنه. نه wizard داره، نه کار دستی توی UI.
- **concourse**: یه `pipeline.yml` می‌سازه با job `ci` که با هر push اجرا می‌شه، و job `cd` که بعد از موفقیت ci دستی اجرا می‌شه.

پس اگه فردا ابزار جدیدی اضافه کنی، هر سه orchestrator خودبه‌خود stage اون رو دارن.

## چرخه‌ی کار

```
init  →  secrets  →  up  →  configure  →  publish  →  run
منو      پرسیدن     Docker   توکن‌ها      نصب pipeline   اجرا
```

`devops.sh setup` پنج قدم اول رو پشت‌سرهم اجرا می‌کنه.

## گام‌های پیاده‌سازی (همونی که انجام شد)

1. **هسته** (`lib/`): لاگ و منو، مخزن مقادیر (`.devops/values`)، تولید فایل‌های env، جمع‌کردن stage ها، wrapper ِ docker compose.
2. **قرارداد ماژول**: `module.conf`، `compose.yml`، و hook های `module.sh`؛ هر hook در یه subshell جدا اجرا می‌شه تا ماژول‌ها با هم تداخل نداشته باشن.
3. **ماژول‌های ابزار**: github، maven build، sonarqube، nexus، jfrog، github-packages، github-pages.
4. **orchestrator ها**: maven (محلی)، jenkins (Configuration as Code)، concourse (quickstart و fly).
5. **اسکریپت اصلی** `devops.sh` و لانچر ویندوز `devops.bat` که Git Bash رو پیدا می‌کنه.
6. **تست**: `tests/smoke.sh` برای هر سه orchestrator، shellcheck، و workflow ِ GitHub Actions.
7. **مستندات**: README، راهنمای نوشتن ماژول، و نیازمندی‌های پروژه‌ی Maven.

## گام‌های بعدی پیشنهادی

- ماژول‌های بیشتر: GitLab در دسته‌ی scm، GitHub Actions به‌عنوان orchestrator، OWASP Dependency-Check در quality، Reposilite در artifact.
- مرحله‌ی release (`release:prepare release:perform`) به‌عنوان یه stage جدا در فاز cd.
- پشتیبانی از Podman.

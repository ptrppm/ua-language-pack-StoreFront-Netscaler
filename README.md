# Український мовний пакет для Citrix StoreFront та NetScaler Gateway

Українська мова для сторінки входу NetScaler Gateway і порталу Citrix StoreFront (CVAD).
Мова вмикається автоматично, якщо в браузері користувача обрано українську; інші мови,
зокрема російська, залишаються оригінальними.

**[⬇ Завантажити останню версію](https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler/releases/latest)** — архів `UA_language_pack_vX.Y.Z.zip` у розділі *Assets*.

| Продукт | Перевірено на | Що перекладається |
|---|---|---|
| NetScaler Gateway | 14.1 build 73.46 | сторінка входу, повідомлення про помилки, EPA, сторінка після виходу, старі сторінки `/vpn` і `/epa` — у всіх темах |
| Citrix StoreFront | 2507 (7.45), 2607 LTSR; Windows Server 2025 | класичний інтерфейс (receiver.html) і форма входу |

Зауваження, помилки в перекладі, нові білди: [Issues](https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler/issues) ·
[GitHub](https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler) · petr.pikulin@gmail.com

---

## Швидкий старт

### NetScaler

1. Скопіюйте теку `netscaler/ua_langpack` з архіву в `/nsconfig/` на NetScaler (WinSCP або `scp`).
2. Встановіть (SSH, далі `shell`):
   ```sh
   sh /nsconfig/ua_langpack/ua_langpack.sh install
   ```
3. У CLI NetScaler очистіть кеш сторінок входу:
   ```
   flush cache contentGroup loginstaticobjects
   ```
   Якщо команда повертає помилку, ймовірно, Integrated Caching вимкнено — тоді очищати нічого, крок можна пропустити.
4. Відкрийте портал у браузері з українською мовою.

HA-пара — на **обох** вузлах.

### StoreFront

1. Скопіюйте теку `storefront` з архіву на сервер StoreFront.
2. PowerShell від імені адміністратора в цій теці:
   ```powershell
   Get-ChildItem -Recurse | Unblock-File       # зняти позначку «завантажено з інтернету»
   .\Install-UALangPack.ps1 -WhatIf            # показати, що буде змінено
   .\Install-UALangPack.ps1 -RecycleAuthPool   # встановити
   ```
3. Відкрийте StoreFront у браузері з українською мовою.

Група серверів — запустіть на кожному сервері або один раз на основному з ключем `-Propagate`.

---

## NetScaler — докладно

### Що робить встановлення
- кладе переклад у `/var/netscaler/logon/LogonPoint/receiver/js/`;
- додає один рядок реєстрації мови в кінець `ctxs.core.min.js` (оригінал зберігається в `/nsconfig/ua_langpack/backup/`);
- для старих сторінок `/vpn` і `/epa` (сторінка після виходу, перевірка EPA, помилки VPN, зміна пароля) кладе `uk.xml`
  у `/var/netscaler/logon/themes/<тема>/resources/` кожної теми й додає `uk` до списку мов у `config.xml` теми
  (якщо `config.xml` — посилання на файл іншої теми, змінюється той файл; власний `uk.xml` без позначки пакета не перезаписується);
- додає першим рядком у `/nsconfig/rc.netscaler` виклик встановлення під час завантаження; інші рядки не змінюються.
  Якщо файлу немає або він порожній — це нормально, файл буде створено. Під час завантаження пакет встановлюється у фоні
  й ще кілька хвилин перевіряє, що файли порталу не замінено.

Тому пакет **сам відновлюється після перезавантаження та оновлення прошивки**. Перед оновленням інсталятор NetScaler
може повідомити, що `ctxs.core.min.js` змінено, і запропонувати зробити резервну копію — відповідайте `y`.

### Після оновлення прошивки: чи все перекладено
```sh
sh /nsconfig/ua_langpack/ua_langpack.sh check
```
Показує рядки нової прошивки, яких немає в перекладі (**NEW** — користувачі бачать їх англійською), і рядки, чий
англійський текст змінився (**CHANGED** — переклад варто переглянути). Якщо прошивка змінила рядки, під час завантаження
в `/var/log/ua_langpack.log` з'являється нагадування запустити `check`. Будь ласка, надсилайте результат в
[Issues](https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler/issues) — так переклад оновиться для всіх.

### Статус, журнал, видалення
```sh
sh /nsconfig/ua_langpack/ua_langpack.sh status
cat /var/log/ua_langpack.log
sh /nsconfig/ua_langpack/ua_langpack.sh uninstall     # потім: flush cache contentGroup loginstaticobjects
```
Після видалення файли NetScaler повертаються до оригіналу байт у байт.

Якщо `status` показує `boot hook: MISSING` — рядок зник з `/nsconfig/rc.netscaler` (наприклад, його перезаписав інший
скрипт; так робить штатний `consoleSetLoginPrompt.sh` під час зміни запрошення консолі). Просто запустіть `install` ще раз.

### Підписи і брендинг теми
У редакторі теми (GUI) немає української у списку мов — це нормально, список зашитий в інтерфейс адміністрування.
Власні українські підписи для теми задаються файлом `/var/netscaler/logon/themes/<Назва теми>/strings.uk.json`
у форматі `strings.en.json`:
```json
{"nsg_loginHeading":"Увійдіть у систему","nsg_username":"Ім'я користувача:"}
```
Якщо файлу немає — використовуються стандартні українські підписи. Збереження теми в GUI цей файл не видаляє.

> **Увага:** не залишайте підписи теми порожніми в GUI (для будь-якої мови). GUI записує порожнє значення,
> і замість стандартного перекладу користувачі бачать англійський текст. Впишіть текст.

### Перехід з версії 1.x
У 1.x переклад копіювався замість російського файлу. Поверніть оригінальну російську (shell NetScaler), потім встановіть 2.x:
```sh
mkdir -p /var/tmp/ua_orig
tar xzf /var/nsinstall/LogonPoint.tgz -C /var/tmp/ua_orig "*localization/ru/ctxs.strings.ru.js"
cp /var/tmp/ua_orig/logon/LogonPoint/receiver/js/localization/ru/ctxs.strings.ru.js /var/netscaler/logon/LogonPoint/receiver/js/localization/ru/
```
Якщо підписи теми для мови Russian раніше були вписані українською — виправте їх у GUI теми.

---

## StoreFront — докладно

### Що робить встановлення
- знаходить у `C:\inetpub\wwwroot\Citrix` сайти Receiver for Web і служби автентифікації, які обслуговує IIS
  (теки видалених Store пропускає); інша тека — ключ `-CitrixRoot`;
- копіює `culture.uk.js` і `wrstrings.uk.js` у `custom\` кожного сайту; `strings.uk.js` — лише якщо його там немає
  (ваші власні рядки не перезаписуються);
- **дописує** в кінець `custom\script.js` блок між мітками `UA_LANGPACK BEGIN / END` — ваші налаштування не змінюються;
- копіює `*.uk.resx` у `App_Data\resources` служб автентифікації;
- з `-RecycleAuthPool` перезапускає пул IIS служби автентифікації (зазвичай *Citrix Delivery Services Authentication*):
  служба читає переклад форми входу лише під час запуску. Сесії користувачів не перериваються;
- усе, що змінює, спершу зберігає в `C:\ProgramData\UA_LangPack\backup\<дата>`. Повторний запуск нічого не дублює.

Якщо PowerShell не дає запустити скрипт: `powershell -ExecutionPolicy Bypass -File .\Install-UALangPack.ps1`

### Статус і видалення
```powershell
.\Install-UALangPack.ps1 -Status
.\Install-UALangPack.ps1 -Uninstall -RecycleAuthPool
```
Файли, які хтось змінив після встановлення, при видаленні залишаються (скрипт про це повідомить).

### Після оновлення StoreFront: чи все перекладено
```powershell
.\Install-UALangPack.ps1 -Check
```
Порівнює англійські рядки цього StoreFront (інтерфейс і форма входу) з перекладом у пакеті й з маніфестом його
версії (`en.<версія>.manifest`; якщо такого немає — з найновішим): **NEW** — немає перекладу,
**CHANGED** — англійський текст змінився. Нічого не змінює; результат надсилайте в
[Issues](https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler/issues).

### Перехід з версії 1.x
У 1.x переклад підключався блоком `$.ctxsAjax(... culture.uk.js ...)`. На сучасних StoreFront (Content Security Policy)
він **не працює** — сторінка лишалася англійською. Встановлення 2.x знайде старий блок, залишить його і допише поруч робочий;
старий можна видалити вручну. Файли 1.x у теці `contrib\` не використовуються — їх можна видалити.

---

## Обмеження
- **NetScaler:** нову тему, створену в GUI після встановлення, пакет підхопить під час наступного завантаження
  або після `install`.
- **NetScaler:** вікна самого плагіна EPA на комп'ютері користувача не перекладаються (мова за мовою ОС, української в плагіні немає).
- **StoreFront:** перекладається класичний інтерфейс. Новий інтерфейс Workspace (якщо його ввімкнено для Store) має власну
  локалізацію — скрипт попередить про це.

## Вміст архіву
```
netscaler/ua_langpack/   ctxs.strings.uk.js, uk.xml, ua_langpack.sh, en.manifest  → копіювати в /nsconfig/
storefront/              Install-UALangPack.ps1, en.<версія>.manifest, custom/, resources/
tools/                   для оновлення перекладу під новий білд (Python 3)
```
`en.manifest` / `en.<версія>.manifest` — контрольні суми англійських рядків білдів, під які зроблено переклад
(самих текстів Citrix там немає);
за ним `check` / `-Check` визначають нові та змінені рядки.

## Для розробників: оновлення під новий білд
1. На оновленому NetScaler / StoreFront запустіть `check` / `-Check` — отримаєте список NEW і CHANGED з англійськими текстами.
2. Перекладіть їх. Для NetScaler є збирач за еталоном
   (`/var/netscaler/logon/LogonPoint/receiver/js/localization/en/ctxs.strings.js`):
   ```sh
   python tools/build_uk.py <en ctxs.strings.js> netscaler/ua_langpack/ctxs.strings.uk.js <новий ctxs.strings.uk.js>
   python tools/build_uk_xml.py <themes/Default/resources/en.xml> netscaler/ua_langpack/uk.xml <новий uk.xml>
   python tools/terminology.py apply <новий ctxs.strings.uk.js>     # «додаток» → «застосунок»
   ```
3. Оновіть маніфест під новий білд:
   ```sh
   python tools/manifest.py netscaler <en ctxs.strings.js> <themes/Default/resources/en.xml> <білд> > netscaler/ua_langpack/en.manifest
   python tools/manifest.py storefront <en ctxs.strings_*.js> <тека з en *.resx> <версія> > storefront/en.<версія>.manifest
   ```
   Для StoreFront маніфести попередніх версій не видаляйте, а переклади застарілих рядків не прибирайте:
   пакет один для всіх підтримуваних версій.
4. `python tools/validate.py` — має бути 0 помилок; оновіть таблицю «Перевірено на» та CHANGELOG.

Оригінальні файли Citrix у репозиторій не додаються.

Кожен коміт перевіряється автоматично: синтаксис JS / PowerShell / sh, XML у `.resx`, відсутність кирилиці в ключах і
те, що кожен рядок білду з маніфесту має переклад.
Реліз збирається сам при створенні тегу `vX.Y.Z` — див. [CHANGELOG](CHANGELOG.md).

## Ліцензія
[MIT](LICENSE). Citrix, NetScaler, StoreFront — торговельні марки Cloud Software Group; проєкт з ними не пов'язаний.

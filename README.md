# Український мовний пакет для Citrix StoreFront та NetScaler Gateway

Українська мова для сторінки входу NetScaler Gateway і порталу Citrix StoreFront (CVAD).
Мова вмикається автоматично, якщо в браузері користувача обрано українську; інші мови,
зокрема російська, залишаються оригінальними.

**[⬇ Завантажити останню версію](https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler/releases/latest)** — архів `UA_language_pack_vX.Y.Z.zip` у розділі *Assets*.

| Продукт | Перевірено на | Що перекладається |
|---|---|---|
| NetScaler Gateway | 14.1 build 73.46 | сторінка входу, повідомлення про помилки, EPA — у всіх темах RfWebUI та WStheme |
| Citrix StoreFront | 2507 (7.45), Windows Server 2025 | класичний інтерфейс (receiver.html) і форма входу |

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
- додає першим рядком у `/nsconfig/rc.netscaler` виклик встановлення під час завантаження; інші рядки не змінюються.

Тому пакет **сам відновлюється після перезавантаження та оновлення прошивки**. Перед оновленням інсталятор NetScaler
може повідомити, що `ctxs.core.min.js` змінено, і запропонувати зробити резервну копію — відповідайте `y`.

### Статус, журнал, видалення
```sh
sh /nsconfig/ua_langpack/ua_langpack.sh status
cat /var/log/ua_langpack.log
sh /nsconfig/ua_langpack/ua_langpack.sh uninstall     # потім: flush cache contentGroup loginstaticobjects
```
Після видалення файли NetScaler повертаються до оригіналу байт у байт.

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

### Перехід з версії 1.x
У 1.x переклад підключався блоком `$.ctxsAjax(... culture.uk.js ...)`. На сучасних StoreFront (Content Security Policy)
він **не працює** — сторінка лишалася англійською. Встановлення 2.x знайде старий блок, залишить його і допише поруч робочий;
старий можна видалити вручну. Файли 1.x у теці `contrib\` не використовуються — їх можна видалити.

---

## Обмеження
- **NetScaler:** вікна самого плагіна EPA на комп'ютері користувача не перекладаються (мова за мовою ОС, української в плагіні немає).
- **StoreFront:** перекладається класичний інтерфейс. Новий інтерфейс Workspace (якщо його ввімкнено для Store) має власну
  локалізацію — скрипт попередить про це.
- **StoreFront 2507:** 17 нових рядків інтерфейсу (PWA, кнопки Google Play / App Store, заборона завантаження ICA тощо)
  поки англійською — буде у 2.1.

## Вміст архіву
```
netscaler/ua_langpack/   ctxs.strings.uk.js, ua_langpack.sh  → копіювати в /nsconfig/
storefront/              Install-UALangPack.ps1, custom/, resources/
tools/                   для оновлення перекладу під новий білд (Python 3)
```

## Для розробників: оновлення під новий білд
Еталон — англійський файл нового білду (`/var/netscaler/logon/LogonPoint/receiver/js/localization/en/ctxs.strings.js`):
```sh
python tools/build_uk.py <en ctxs.strings.js> netscaler/ua_langpack/ctxs.strings.uk.js <новий ctxs.strings.uk.js>
python tools/terminology.py apply <новий ctxs.strings.uk.js>     # «додаток» → «застосунок»
```
`build_uk.py` показує ключі, яких бракує в перекладі, і зайві. Оригінальні файли Citrix у репозиторій не додаються.

Кожен коміт перевіряється автоматично (синтаксис JS / PowerShell / sh, XML у `.resx`, відсутність кирилиці в ключах).
Реліз збирається сам при створенні тегу `vX.Y.Z` — див. [CHANGELOG](CHANGELOG.md).

## Ліцензія
[MIT](LICENSE). Citrix, NetScaler, StoreFront — торговельні марки Cloud Software Group; проєкт з ними не пов'язаний.

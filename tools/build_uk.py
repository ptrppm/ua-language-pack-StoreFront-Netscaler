"""Build ctxs.strings.uk.js using the English bundle as the key template.
usage: build_uk.py <en ctxs.strings.js> <old ua bundle> <out ctxs.strings.uk.js>"""
import re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsbundle

en_path, ua_path, out_path = sys.argv[1:4]
en = jsbundle.parse(en_path)
ua = dict(jsbundle.parse(ua_path))

# v1.01 had the English *key* partially translated; move the value back under the real key
RENAMED = {
    "Ви перевищили максимальну кількість спроб входу. Please contact administrator":
        "You have exceeded the maximum login attempts. Please contact administrator",
    "Target URL не знайдено для перенаправлення після успішного входу. Please contact your administrator.":
        "Target URL not found for redirect after successful login. Please contact your administrator.",
    "Не вдалося змінити пароль. Переконайтеся, що ви ввели коректний існуючий пароль, і спробуйте ще раз.":
        "Password change failed. Make sure you supply correct existing password and try again.",
    "Шлюз зіткнувся з несподіваним станом. Please contact your admin for details":
        "Gateway encountered an unexpected condition. Please contact your admin for details",
    "Вам заборонено змінювати пароль. Please contact your admin for details.":
        "You are not allowed to change the password. Please contact your admin for details.",
    "Одне з полів порожнє. Будь ласка, введіть ваш пароль, і новий пароль двічі.":
        "One of the fields is empty. Please enter your password, and new password twice.",
    "Набрані вами паролі не збігаються. Please try again.":
        "The passwords you typed do not match. Please try again.",
}
for bad, good in RENAMED.items():
    if bad in ua:
        ua.setdefault(good, ua.pop(bad))

# keys missing from v1.01
NEW = {
    "epa_user_consent_msg": "Для доступу до певних корпоративних ресурсів потрібне сканування аналізу кінцевої точки. Інформацію про ваш пристрій буде передано на URL-адресу {0} для подальшої перевірки",
    "epa_error_msg": "Під час обробки запиту на сервері сталася помилка: 0x",
    "epa_config_error_msg": "Не знайдено відповідної політики для обробки EPA",
    "Your_administrator_requires_you_to_use_CSA": "Адміністратор вимагає використовувати Citrix Secure Access для автентифікації та доступу.",
    "Contact_your_system_administrator": "Якщо проблема не зникне, зверніться до системного адміністратора.",
}
for k, v in NEW.items():
    ua.setdefault(k, v)

def q(raw):
    # raw keeps original escapes; make sure bare double quotes are escaped
    return '"' + re.sub(r'(?<!\\)"', r'\\"', raw) + '"'

missing, seen, lines = [], set(), []
for k, v in en:
    if k in seen:
        continue  # en itself has TryAgain twice
    seen.add(k)
    if k not in ua:
        missing.append(k)
    lines.append('        %s: %s' % (q(k), q(ua.get(k, v))))
extra = [k for k in ua if k not in seen]
for k in extra:
    lines.append('        %s: %s' % (q(k), q(ua[k])))

with open(out_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write('// Ukrainian language pack for NetScaler Gateway (RfWebUI / WStheme)\n')
    f.write('// Petro Pikulin, petr.pikulin@gmail.com, https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler\n')
    f.write('(function ($) {\n    $.localization.addStringBundle("uk", {\n')
    f.write(',\n'.join(lines))
    f.write('\n    });\n})(jQuery);\n')
    # same as stock custom/strings.<lang>.js: per-theme labels from the theme's strings.uk.json, if present
    f.write('''
$.ctxsAjax({
    type: "GET",
    url: "/logon/LogonPoint/custom/strings.uk.json",
    dataType: "json",
    async: false,
    success: function (data, textStatus, xhr) {
        $.localization.customStringBundle("uk", xhr.responseJSON);
    },
    error: function () {
    },
    refreshSession: true
});
''')

print('written', len(lines), 'entries; untranslated (fell back to en):', missing, '; extra kept:', extra)

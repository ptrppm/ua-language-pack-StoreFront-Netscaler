"""Checks the language pack before a commit / in CI. Exit code 1 on any error.
usage: python tools/validate.py            (from the repository root)"""
import os, re, sys
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jsbundle

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CYR = re.compile('[Ѐ-ӿ]')
errors, warnings = [], []

def path(*p):
    return os.path.join(ROOT, *p)

def read_bytes(p):
    with open(p, 'rb') as f:
        return f.read()

def check_bundle(rel, lang):
    """Citrix string bundle: parses, right language, no Cyrillic in keys (v1.01 had 7 such broken keys)."""
    p = path(*rel.split('/'))
    try:
        items = jsbundle.parse(p)
    except Exception as e:
        errors.append('%s: cannot parse bundle: %s' % (rel, e))
        return
    text = read_bytes(p).decode('utf-8-sig')
    if not re.search(r'addStringBundle\(\s*"%s"' % lang, text):
        errors.append('%s: addStringBundle("%s", ...) not found' % (rel, lang))
    keys = [k for k, _ in items]
    for k in keys:
        if CYR.search(k):
            errors.append('%s: Cyrillic in key %r - the key must stay English' % (rel, k[:60]))
    dups = sorted({k for k in keys if keys.count(k) > 1})
    if dups:
        warnings.append('%s: duplicate keys (last one wins): %s' % (rel, ', '.join(dups)))
    # keys ending with "_" are prefixes that are empty in Citrix's English bundle too
    empty = [k for k, v in items if not v.strip() and not k.endswith('_')]
    if empty:
        warnings.append('%s: empty translations: %s' % (rel, ', '.join(empty)))
    print('ok  %-45s %d strings' % (rel, len(items)))

def check_resx(rel):
    p = path(*rel.split('/'))
    try:
        root = ET.parse(p).getroot()
    except ET.ParseError as e:
        errors.append('%s: invalid XML: %s' % (rel, e))
        return
    data = root.findall('data')
    for d in data:
        if CYR.search(d.get('name', '')):
            errors.append('%s: Cyrillic in resource name %r' % (rel, d.get('name')))
        v = d.find('value')
        if v is None or not (v.text or '').strip():
            warnings.append('%s: empty value for %s' % (rel, d.get('name')))
    print('ok  %-45s %d strings' % (rel, len(data)))

def check_text_rules():
    sh = read_bytes(path('netscaler', 'ua_langpack', 'ua_langpack.sh'))
    if b'\r' in sh:
        errors.append('netscaler/ua_langpack/ua_langpack.sh: CRLF line endings - NetScaler sh will fail')
    if any(b > 127 for b in sh):
        errors.append('netscaler/ua_langpack/ua_langpack.sh: non-ASCII bytes (keep Cyrillic as \\u escapes)')
    ps = read_bytes(path('storefront', 'Install-UALangPack.ps1'))
    if any(b > 127 for b in ps):
        errors.append('storefront/Install-UALangPack.ps1: non-ASCII bytes - Windows PowerShell 5.1 misreads UTF-8 without BOM')
    culture = read_bytes(path('storefront', 'custom', 'culture.uk.js')).decode('utf-8-sig')
    for needle in ('availableCulture("uk"', 'custom/wrstrings.uk.js', 'customStringBundle: "custom/strings.uk.js"'):
        if needle not in culture:
            errors.append('storefront/custom/culture.uk.js: missing %s' % needle)
    print('ok  line endings / encodings / culture.uk.js')

def check_manifest(rel, product, translated):
    """en.manifest: '# <product> <build> en-file-md5 <md5>' + 'source:key<TAB>md5' lines;
    every key of the build must have a translation in the pack."""
    p = path(*rel.split('/'))
    if not os.path.exists(p):
        errors.append('%s: missing (python tools/manifest.py ...)' % rel)
        return
    lines = read_bytes(p).decode('utf-8').splitlines()
    if not re.match(r'^# %s \S+ en-file-md5 [0-9a-f]{32}$' % product, lines[0] if lines else ''):
        errors.append('%s: bad header %r' % (rel, lines[0] if lines else ''))
        return
    untranslated = []
    for ln in lines[1:]:
        m = re.match(r'^([A-Za-z]+):(.+)\t[0-9a-f]{32}$', ln)
        if not m:
            errors.append('%s: bad line %r' % (rel, ln[:60]))
            continue
        if m.group(2) not in translated.get(m.group(1), set()):
            untranslated.append('%s:%s' % m.groups())
    if untranslated:
        errors.append('%s: %d string(s) of build %s have no translation: %s'
                      % (rel, len(untranslated), lines[0].split()[2], ', '.join(untranslated[:15])))
    print('ok  %-45s %d strings of %s' % (rel, len(lines) - 1, lines[0].split()[2]))

def keys_js(rel):
    return set(manifest.js_entries(path(*rel.split('/'))))

def keys_resx(rel):
    p = path(*rel.split('/'))
    return {d.get('name') for d in ET.parse(p).getroot().findall('data')} if os.path.exists(p) else set()

import manifest

check_bundle('netscaler/ua_langpack/ctxs.strings.uk.js', 'uk')
check_bundle('storefront/custom/wrstrings.uk.js', 'uk')
for name in sorted(os.listdir(path('storefront', 'resources'))):
    if name.endswith('.uk.resx'):
        check_resx('storefront/resources/' + name)
check_text_rules()
check_manifest('netscaler/ua_langpack/en.manifest', 'netscaler',
               {'js': keys_js('netscaler/ua_langpack/ctxs.strings.uk.js')})
check_manifest('storefront/en.manifest', 'storefront',
               dict([('js', keys_js('storefront/custom/wrstrings.uk.js'))] +
                    [(n, keys_resx('storefront/resources/%s.uk.resx' % n)) for n in manifest.RESX]))

for w in warnings:
    print('WARNING ' + w)
for e in errors:
    print('ERROR   ' + e)
print('%d error(s), %d warning(s)' % (len(errors), len(warnings)))
sys.exit(1 if errors else 0)

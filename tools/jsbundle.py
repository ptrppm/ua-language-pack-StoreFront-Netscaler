"""Parse a Citrix ctxs.strings*.js bundle: $.localization.addStringBundle("xx", { key: "value", ... })."""
import re, sys, json

def parse(path):
    s = open(path, encoding='utf-8-sig').read()
    i = s.index('addStringBundle')
    i = s.index('{', i) + 1
    items, n = [], len(s)
    def skip_ws(i):
        while i < n:
            if s[i].isspace() or s[i] == ',':
                i += 1
            elif s.startswith('//', i):
                i = s.index('\n', i)
            elif s.startswith('/*', i):
                i = s.index('*/', i) + 2
            else:
                break
        return i
    def read_str(i):
        q = s[i]; j = i + 1; out = []
        while s[j] != q:
            if s[j] == '\\':
                out.append(s[j:j+2]); j += 2
            else:
                out.append(s[j]); j += 1
        return ''.join(out), j + 1
    while True:
        i = skip_ws(i)
        if s[i] == '}':
            break
        if s[i] in '"\'':
            key, i = read_str(i)
        else:
            m = re.compile(r'[A-Za-z_$][\w$]*').match(s, i)
            key, i = m.group(0), m.end()
        i = skip_ws(i)
        assert s[i] == ':', (path, key, s[i:i+40])
        i = skip_ws(i + 1)
        assert s[i] in '"\'', (path, key, s[i:i+40])
        val, i = read_str(i)
        items.append((key, val))
    return items

if __name__ == '__main__':
    for p in sys.argv[1:]:
        it = parse(p)
        keys = [k for k, _ in it]
        dup = sorted({k for k in keys if keys.count(k) > 1})
        cyr = [k for k in keys if re.search('[Ѐ-ӿ]', k)]
        print(p.split('/')[-1], 'entries', len(it), 'unique', len(set(keys)), 'dups', dup, 'cyrillic-keys', cyr)

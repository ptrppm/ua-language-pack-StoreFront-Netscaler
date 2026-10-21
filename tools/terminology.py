"""Unify terminology: «додаток» (app) -> «застосунок», with case forms.
Leaves «додати» (add), «додатковий/додатково» (additional) untouched.
usage: terminology.py report <files...>
       terminology.py apply <files...>      (rewrites files in place, prints every change)"""
import re, sys
from collections import Counter

CYR = 'А-Яа-яІіЇїЄєҐґ'
WORD = re.compile('[%s\'’]+' % CYR)

# noun «додаток» -> «застосунок» (both masculine, so adjectives agree as before)
FORMS = {
    'додаток': 'застосунок',
    'додатка': 'застосунку',
    'додатку': 'застосунку',
    'додатком': 'застосунком',
    'додатки': 'застосунки',
    'додатків': 'застосунків',
    'додаткам': 'застосункам',
    'додатками': 'застосунками',
    'додатках': 'застосунках',
}

def convert(word):
    low = word.lower()
    if low not in FORMS:
        return None
    new = FORMS[low]
    if word.isupper():
        return new.upper()
    if word[0].isupper():
        return new[0].upper() + new[1:]
    return new

def main():
    sys.stdout.reconfigure(encoding='utf-8')
    mode, files = sys.argv[1], sys.argv[2:]
    seen = Counter()
    for path in files:
        s = open(path, encoding='utf-8-sig', newline='').read()  # keep CRLF as is
        bom = open(path, 'rb').read(3) == b'\xef\xbb\xbf'
        changes = []
        def sub(m):
            w = m.group(0)
            if 'додат' in w.lower():
                seen[w] += 1
            new = convert(w)
            if new:
                changes.append((w, new))
                return new
            return w
        out = WORD.sub(sub, s)
        print('%s: %d replacements' % (path, len(changes)))
        if mode == 'apply' and changes:
            with open(path, 'w', encoding='utf-8-sig' if bom else 'utf-8', newline='') as f:
                f.write(out)
    print('\nall word forms containing "додат":')
    for w, n in seen.most_common():
        print('  %4d  %-14s -> %s' % (n, w, convert(w) or '(kept)'))

if __name__ == '__main__':
    main()

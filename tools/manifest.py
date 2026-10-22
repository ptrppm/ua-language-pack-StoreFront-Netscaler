"""Build an en manifest: one line per English string, "<source>:<key><TAB><md5 of the English text>".
The pack ships it so that `check` on a newer build can tell new keys and changed English texts apart.
Only hashes are stored - no Citrix text goes into the repository.

usage:
  python tools/manifest.py netscaler <en/ctxs.strings.js> <themes/Default/resources/en.xml> <build> > netscaler/ua_langpack/en.manifest
  python tools/manifest.py storefront <en/ctxs.strings_*.js> <dir with *.resx> <build> > storefront/en.<build>.manifest

Hash rule (the same in ua_langpack.sh and Install-UALangPack.ps1):
  JS:   the raw text between the quotes on the "key: "value"," line, escapes as written, UTF-8, MD5
  resx: the text of <value> of each <data> in the neutral (English) <Name>.resx, UTF-8, MD5
  xml:  the raw text between the tags of each String/Property/Title line of the theme en.xml, UTF-8, MD5
"""
import hashlib, os, re, sys
import xml.etree.ElementTree as ET

# one entry per line, as in Citrix bundles; the same pattern is used by the sh and PowerShell checkers
LINE = re.compile(r'^\s*"?([A-Za-z0-9_][^":]*?)"?\s*:\s*"(.*)",?\s*$')
RESX = ['ExplicitAuth', 'ExplicitCore', 'ExplicitFormsCommon', 'ExplicitJson', 'FormsProtocol', 'SamlForms']


def md5(s):
    return hashlib.md5(s.encode('utf-8')).hexdigest()


def js_entries(path):
    out = {}
    with open(path, encoding='utf-8-sig') as f:
        for line in f:
            if re.match(r'^\s*\}\);', line):
                break                                    # end of addStringBundle; code may follow
            m = LINE.match(line.rstrip('\r\n'))
            if m:
                out.setdefault(m.group(1), m.group(2))   # first wins: duplicates are not expected in Citrix files
    return out


def xml_entries(path):
    """Theme resources (themes/<theme>/resources/<lang>.xml) of the legacy /vpn and /epa pages:
    "<partition>|<String|Property|Title>|<attributes as written>" -> raw text between the tags.
    One element per line, as in Citrix files; the same parser is in ua_langpack.sh (awk)."""
    out = {}
    with open(path, encoding='utf-8-sig') as f:
        for key, value in xml_lines(f):
            if key is not None:
                out.setdefault(key, value)
    return out


def xml_lines(lines):
    """(key, value) for each line; (None, None) for lines that are not translatable elements."""
    part = ''
    for line in lines:
        s = line.rstrip('\r\n').strip()
        m = re.match(r'<Partition id="([^"]*)"', s)
        if m:
            part = m.group(1)
        m = m or re.match(r'<(String|Property|Title)[\s>/]', s)
        if not m or s.startswith('<Partition'):
            yield None, None
            continue
        head, _, rest = s[1:].partition('>')
        tag, value = m.group(1), ''
        if head.endswith('/'):
            head = head[:-1]
        else:
            end = rest.rfind('</%s>' % tag)
            value = rest[:end] if end >= 0 else rest
        yield '%s|%s|%s' % (part, tag, head[len(tag):].strip()), value


def resx_entries(path):
    root = ET.parse(path).getroot()
    return {d.get('name'): (d.findtext('value') or '') for d in root.findall('data')}


def file_md5(path):
    with open(path, 'rb') as f:
        return hashlib.md5(f.read()).hexdigest()


def main():
    product = sys.argv[1]
    lines = []
    if product == 'netscaler':
        js, xml, build = sys.argv[2], sys.argv[3], sys.argv[4]
        lines.append('# netscaler %s en-file-md5 %s' % (build, file_md5(js)))
        lines += ['js:%s\t%s' % (k, md5(v)) for k, v in sorted(js_entries(js).items())]
        lines += ['xml:%s\t%s' % (k, md5(v)) for k, v in sorted(xml_entries(xml).items())]
    elif product == 'storefront':
        js, resx_dir, build = sys.argv[2], sys.argv[3], sys.argv[4]
        lines.append('# storefront %s en-file-md5 %s' % (build, file_md5(js)))
        lines += ['js:%s\t%s' % (k, md5(v)) for k, v in sorted(js_entries(js).items())]
        for name in RESX:
            p = os.path.join(resx_dir, name + '.resx')
            lines += ['%s:%s\t%s' % (name, k, md5(v)) for k, v in sorted(resx_entries(p).items())]
    else:
        sys.exit(__doc__)
    sys.stdout.buffer.write(('\n'.join(lines) + '\n').encode('utf-8'))


if __name__ == '__main__':
    main()

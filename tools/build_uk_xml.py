"""Build uk.xml (theme resources of the legacy /vpn and /epa pages) for a firmware's English file.

Takes the firmware's themes/Default/resources/en.xml line by line and puts in the Ukrainian text of the
same key (partition|tag|attributes) from the current uk.xml. Keys the current uk.xml does not have keep
the English text and are listed - translate them by hand, then run tools/validate.py.

usage: python tools/build_uk_xml.py <en.xml> <current uk.xml> <new uk.xml>
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manifest

MARK = '<!-- UA_LANGPACK: Ukrainian language pack, https://github.com/ptrppm/ua-language-pack-StoreFront-Netscaler -->'


def main():
    en_path, uk_path, out_path = sys.argv[1:4]
    uk = manifest.xml_entries(uk_path)
    with open(en_path, encoding='utf-8-sig') as f:
        lines = f.read().split('\n')
    out, missing = [], []
    for line, (key, value) in zip(lines, manifest.xml_lines(lines)):
        if key is not None and value and key in uk:
            # replace only the text between the tags; the line keeps its tag and attributes byte for byte
            tag = key.split('|')[1]
            start = line.index('>') + 1
            end = line.rindex('</%s>' % tag)
            line = line[:start] + uk[key] + line[end:]
        elif key is not None and value.strip() and re.search('[A-Za-z]{3}', value):
            missing.append(key)
        out.append(line)
    if not out[0].startswith('<?xml'):
        sys.exit('%s: no XML declaration on line 1' % en_path)
    out.insert(1, MARK)
    with open(out_path, 'w', encoding='utf-8', newline='') as f:
        f.write('\n'.join(out))
    sys.stdout.reconfigure(encoding='utf-8')
    print('%d strings from %s; not in it (English kept): %d' % (len(uk), uk_path, len(missing)))
    for k in missing:
        print('  ' + k)


if __name__ == '__main__':
    main()

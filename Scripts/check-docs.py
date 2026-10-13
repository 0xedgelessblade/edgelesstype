#!/usr/bin/env python3
"""Check local documentation links, knowledge-index sources and test claims."""
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json
import re

root = Path(__file__).resolve().parent.parent
errors = []
count = 0
edges = {}

def anchors(path):
    result = set()
    for line in path.read_text().splitlines():
        if re.match(r'^#{1,6}\s',line):
            title = re.sub(r'^#{1,6}\s+','',line).strip().lower()
            title = re.sub(r'[^\w\- ]','',title)
            result.add(re.sub(r' +','-',title))
    return result

def check(base, reference):
    global count
    parsed = urlsplit(reference.strip('<>'))
    prefixes = {
        'raw.githubusercontent.com': '/0xedgelessblade/edgelesstype/main/',
        'github.com': '/0xedgelessblade/edgelesstype/blob/main/',
    }
    prefix = prefixes.get(parsed.netloc)
    if prefix and parsed.path.startswith(prefix):
        path = (root / unquote(parsed.path[len(prefix):])).resolve()
    elif parsed.scheme or parsed.netloc:
        return
    else:
        path = (base.parent/unquote(parsed.path)).resolve() if parsed.path else base.resolve()
    edges.setdefault(base.resolve(), set()).add(path)
    count += 1
    if not path.is_relative_to(root): errors.append(f'{base.name}: link escapes project'); return
    if not path.exists(): errors.append(f'{base.name}: missing {reference}'); return
    if parsed.fragment and path.suffix=='.md' and unquote(parsed.fragment) not in anchors(path):
        errors.append(f'{base.name}: missing anchor {reference}')

documents = list(root.glob('*.md'))+list((root/'docs').rglob('*.md'))+[root/'llms.txt']
for path in documents:
    for reference in re.findall(r'\[[^\]\n]*\]\(([^\s)]+)\)',path.read_text()): check(path,reference)
    for reference in re.findall(r'<img[^>]+src=[\"\']([^\"\']+)', path.read_text()): check(path, reference)

# Reader routes are checked, not a fabricated SEO or LLM score.
required_entries = ['docs/OVERVIEW.md', 'docs/README.md', 'docs/USER-GUIDE.md',
                    'docs/FAQ.md', 'docs/INSTALL_WITH_AI.md', 'docs/ARCHITECTURE.md',
                    'docs/COMPATIBILITY.md', 'docs/AI-READING-CHECKS.md', 'SECURITY.md']
llms = root/'llms.txt'
if not llms.read_text().startswith('# edgelesstype\n') or '\n> ' not in llms.read_text():
    errors.append('llms.txt: missing project title or summary')
for entry in required_entries:
    if (root/entry).resolve() not in edges.get(llms.resolve(), set()):
        errors.append('llms.txt: missing reader entry '+entry)
reachable = set()
queue = [root/'README.md', llms]
while queue:
    node = queue.pop().resolve()
    if node in reachable: continue
    reachable.add(node)
    queue.extend(edges.get(node, set()) - reachable)
for page in (root/'docs').rglob('*.md'):
    if page.resolve() not in reachable: errors.append('unreachable documentation: '+str(page.relative_to(root)))

index = json.loads((root/'docs/knowledge-index.json').read_text())
assert index['schema_version']==1
seen = set()
for entry in index['problems']:
    for field in ['id','title_en','title_zh','queries','article','source_files','test_files','evidence','limits']:
        if not entry.get(field): errors.append(f'{entry.get("id")}: missing {field}')
    if entry['id'] in seen: errors.append('duplicate problem id')
    seen.add(entry['id'])
    check(root/'README.md',entry['article'])
    for source in entry['source_files']+entry['test_files']: check(root/'README.md',source)
    test_text='\n'.join((root/p).read_text() for p in entry['test_files'])
    for test in entry.get('test_names',[]):
        if not re.search(r'func\s+'+re.escape(test)+r'\(',test_text): errors.append(entry['id']+': missing test '+test)

test_count = sum(len(re.findall(r'func test\w+\(\)',p.read_text())) for p in (root/'Tests/EdgelessTypeTests').glob('*.swift'))
claim = re.search(r'(\d+) 個 Core 測試',(root/'docs/COMPATIBILITY.md').read_text())
if not claim or int(claim.group(1))!=test_count: errors.append('compatibility test count is out of date')

if errors:
    for error in errors: print('FAIL',error)
    raise SystemExit(1)
print(f'PASS docs: {count} local references, {len(seen)} problem entries, {test_count} test declarations')

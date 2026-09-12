#!/usr/bin/env bash
# Exercise accepted bodies and defects in disposable files, without a Git repo.
set -euo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr.sh"

python3 - "$SCRIPT" <<'PY'
import os
import subprocess
import sys
import tempfile
from pathlib import Path

script = sys.argv[1]
# macOS may inherit an unavailable C.UTF-8 locale; lint itself reads UTF-8 explicitly.
os.environ['LC_ALL'] = 'C'
base = '''Accented input now produces readable ASCII slugs.

### Changes

- Map `ß` explicitly because normalization leaves it unchanged.

### Related

- Specs: [Transliteration](https://example.com/spec-slugs.md).
- Tickets: [Slugify](project/done-slugify.md).
- Related PRs: None identified.

### Testing

- `python3 -m unittest` - passed: 10 tests at the proposed head.
'''

cases = [
    ('complete body', base, None),
    ('no related work and no tests', base.replace(
        '- Specs: [Transliteration](https://example.com/spec-slugs.md).',
        '- Specs: None identified.').replace(
        '- Tickets: [Slugify](project/done-slugify.md).',
        '- Tickets: None identified.').replace(
        '- `python3 -m unittest` - passed: 10 tests at the proposed head.',
        '- Not run: documentation-only change; no executable behavior changed.'), None),
    ('failed test is honest', base.replace('passed: 10 tests at the proposed head.',
        'failed: 1 assertion; the failure is still unresolved.'), None),
    ('lookup unavailable', base.replace('Related PRs: None identified.',
        'Related PRs: None identified. PR lookup unavailable: no forge credentials.'), None),
    ('balanced URL parentheses', base.replace('project/done-slugify.md',
        'https://example.com/change_(slugify)'), None),
    ('descriptive category link label', base.replace('[Slugify]', '[ticket]'), None),
    ('open ticket URL and descriptive labels', base.replace('[Transliteration]', '[Spec]').replace(
        '[Slugify](project/done-slugify.md)',
        '[Ticket](https://example.com/project/todo-slugify.md)'), None),
    ('missing overview', base[base.index('### Changes'):], 'PR001'),
    ('overview list', base.replace('Accented input', '- Accented input'), 'PR001'),
    ('missing section', base[:base.index('### Testing')], 'PR002'),
    ('empty section', base.replace(
        '- Map `ß` explicitly because normalization leaves it unchanged.', ''), 'PR003'),
    ('duplicate section', base + '\n### Changes\n\n- Repeat.\n', 'PR002'),
    ('out of order', base.replace('### Changes', '### Temporary').replace(
        '### Related', '### Changes').replace('### Temporary', '### Related'), 'PR002'),
    ('wrong heading level', base.replace('### Testing', '## Testing'), 'PR002'),
    ('missing heading whitespace', base.replace('### Changes\n\n', '### Changes\n'), 'PR004'),
    ('changes prose', base.replace('- Map `ß`', 'Map `ß`'), 'PR005'),
    ('missing category', base.replace('- Related PRs: None identified.\n', ''), 'PR006'),
    ('bare URL', base.replace('[Slugify](project/done-slugify.md)',
        'https://example.com/pull/1'), 'PR006'),
    ('empty link', base.replace('(project/done-slugify.md)', '()'), 'PR006'),
    ('unbalanced link', base.replace('(project/done-slugify.md)',
        '(project/done-slugify.md'), 'PR006'),
    ('empty label', base.replace('[Slugify]', '[]'), 'PR006'),
    ('not run without reason', base.replace(
        '- `python3 -m unittest` - passed: 10 tests at the proposed head.',
        '- Not run:'), 'PR007'),
    ('command without result', base.replace(' - passed: 10 tests at the proposed head.', ''), 'PR007'),
    ('generic tested claim', base.replace(
        '- `python3 -m unittest` - passed: 10 tests at the proposed head.',
        '- Tests passed.'), 'PR007'),
    ('template filler', base.replace('readable ASCII slugs.', 'TODO.'), 'PR008'),
    ('prose dash', base.replace('readable ASCII slugs.', 'readable slugs — reliably.'), 'PR008'),
    ('unclosed fence', base + '\n```text\nunfinished\n', 'PR009'),
    ('fenced example headings and fillers', base.replace('### Related',
        '````markdown\n### Testing\nTODO — example\n```\n````\n\n### Related'), None),
    ('tilde fenced example', base + '\n~~~markdown\n### Changes\nTBD – example\n~~~\n', None),
    ('inline literal filler', base.replace('readable ASCII slugs.',
        'readable ASCII slugs, including literal `TODO` and `—` input.'), None),
    ('fenced example cannot populate section', base.replace(
        '- Map `ß` explicitly because normalization leaves it unchanged.',
        '```text\n- An example, not the change.\n```'), 'PR003'),
]

with tempfile.TemporaryDirectory(prefix='pr-test.') as temp:
    body = Path(temp) / 'body with spaces.md'
    for name, text, code in cases:
        body.write_text(text, encoding='utf-8')
        run = subprocess.run(['bash', script, 'lint', str(body)], capture_output=True, text=True)
        if code is None:
            assert run.returncode == 0 and not run.stdout and not run.stderr, (name, run)
        else:
            assert run.returncode == 1 and code in run.stdout, (name, run)
        print('PASS:', name)
    missing = subprocess.run(['bash', script, 'lint', str(Path(temp) / 'missing.md')],
                             capture_output=True, text=True)
    assert missing.returncode == 2, missing
    usage = subprocess.run(['bash', script, 'lint'], capture_output=True, text=True)
    assert usage.returncode == 2, usage
print(f'PASS: {len(cases)} body scenarios and input errors')
PY

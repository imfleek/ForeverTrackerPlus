# Builds the dev install zip next to the repo: ..\..\ForeverTrackerPlus-<version>-dev.zip (in "claude stuff").
# Ships what git tracks plus new untracked files, minus the .pkgmeta ignore list and dev-only files.
# Run from anywhere: python tests/build_zip.py
import os, re, subprocess, sys, zipfile

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
skip = re.compile(r'^(tests/|\.github/|REQUIREMENTS\.md$|CLAUDE\.md$|CURSEFORGE\.md$|\.git|\.claude|\.pkgmeta$)')
files = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard'], cwd=repo,
                       capture_output=True, text=True, check=True).stdout.split('\n')
files = [f for f in files if f and not skip.match(f) and os.path.isfile(os.path.join(repo, f))]

toc = open(os.path.join(repo, 'ForeverTrackerPlus.toc'), encoding='utf-8').read()
version = re.search(r'^## Version:\s*(\S+)', toc, re.M).group(1)
missing = [l.strip() for l in toc.splitlines() if re.search(r'\.(lua|xml)\s*$', l) and l.strip() not in files]
if missing:
    sys.exit('toc files missing: ' + ', '.join(missing))

out = os.path.join(os.path.dirname(repo), f'ForeverTrackerPlus-{version}-dev.zip')
tmp = out + '.tmp'
with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(os.path.join(repo, f), 'ForeverTrackerPlus/' + f)
os.replace(tmp, out)
print(f'{out} ({len(files)} files)')

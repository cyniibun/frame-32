"""Verify selected upstream research snapshots without network access."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'References/repositories.json').read_text())
count = total = 0
for repo in manifest['repositories']:
    base = (root / 'References/Upstream' / repo['name']).resolve()
    snapshot = json.loads((base / 'FRAME32_SNAPSHOT.json').read_text())
    assert snapshot['commit'] == repo['commit'], repo['name']
    for item in repo['files']:
        path = (base / item['path']).resolve()
        assert path.is_relative_to(base), item['path']
        data = path.read_bytes()
        assert len(data) == item['bytes'], str(path)
        assert hashlib.sha256(data).hexdigest() == item['sha256'], str(path)
        blob = b'blob ' + str(len(data)).encode() + b'\0' + data
        assert hashlib.sha1(blob).hexdigest() == item['git_blob_sha'], str(path)
        count += 1
        total += len(data)
backlog = json.loads((root / 'Docs/effects-backlog.json').read_text())
assert len(backlog['effects']) == 15
assert len({item['id'] for item in backlog['effects']}) == 15
print(f'PASS: {len(manifest["repositories"])} pinned references, {count} files, {total} source bytes; 15 backlog entries.')

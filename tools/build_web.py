"""Build the workshop from Project Sun sources without including credentials or dependencies."""
from pathlib import Path
import argparse, json, shutil

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=Path('C:/Users/ASUS/Desktop/桌面/Project Sun/Web/frontline-workshop'))
args = parser.parse_args()
destination = root / 'web'
destination.mkdir(exist_ok=True)
for name in ['index.html', 'styles.css', 'workshop.css', 'app.mjs', 'model.mjs', 'accounts.mjs', 'stats.html', 'stats.mjs', 'stats.css']:
    shutil.copy2(args.source / name, destination / name)
contracts = {name: json.loads((root / 'docs/cards' / f'{name}.schema.json').read_text('utf-8')) for name in ['card', 'keyword']}
data = json.dumps(contracts, ensure_ascii=False, separators=(',', ':'))
(destination / 'contracts.json').write_text(data, 'utf-8')
(args.source / 'contracts.json').write_text(data, 'utf-8')
print('Workshop built:', destination)

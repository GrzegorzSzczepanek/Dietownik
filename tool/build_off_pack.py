#!/usr/bin/env python3
"""Builds assets/off_pl.tsv.gz: the most-scanned Polish products from the
Open Food Facts CSV dump (ODbL, https://world.openfoodfacts.org/data).

  curl -L -o off.csv.gz https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz
  python3 tool/build_off_pack.py off.csv.gz [N=8000]

Output columns (tab separated): code name brand kcal100 p100 c100 f100 serving_g
"""
import csv, gzip, sys

csv.field_size_limit(1 << 27)
src = sys.argv[1]
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 8000

def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

rows = []
with gzip.open(src, 'rt', encoding='utf-8', errors='replace', newline='') as f:
    r = csv.DictReader(f, delimiter='\t')
    for d in r:
        if 'en:poland' not in (d.get('countries_tags') or ''):
            continue
        name = (d.get('product_name_pl') or d.get('product_name') or '').strip()
        kcal = num(d.get('energy-kcal_100g'))
        code = (d.get('code') or '').strip()
        if not name or kcal is None or not code.isdigit() or not 0 <= kcal <= 900:
            continue
        p, c, fat = (num(d.get(k)) for k in ('proteins_100g', 'carbohydrates_100g', 'fat_100g'))
        if p is None or c is None or fat is None:
            continue
        scans = num(d.get('unique_scans_n')) or 0
        serving = num(d.get('serving_quantity')) or 0
        brand = (d.get('brands') or '').split(',')[0].strip()
        clean = lambda s: s.replace('\t', ' ').replace('\n', ' ')[:80]
        rows.append((scans, [code, clean(name), clean(brand), round(kcal, 1), round(p, 1), round(c, 1), round(fat, 1), round(serving) if 0 < serving < 2000 else 0]))

rows.sort(key=lambda x: -x[0])
rows = rows[:limit]
with gzip.open('assets/off_pl.tsv.gz', 'wt', encoding='utf-8') as out:
    for _, r in rows:
        out.write('\t'.join(map(str, r)) + '\n')
print(f'wrote {len(rows)} products')

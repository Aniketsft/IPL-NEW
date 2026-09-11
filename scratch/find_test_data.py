import sqlite3

conn = sqlite3.connect('InnodisApp.db')
c = conn.cursor()

def get_cust(code):
    return c.execute('SELECT code, name, bcgcod, tsccod FROM tbl_si_customers WHERE code = ?', (code,)).fetchone()

def get_prod(sku):
    return c.execute('SELECT sku, name FROM tbl_si_products WHERE sku = ?', (sku,)).fetchone()

print("="*80)
print("SCENARIO 4: Customer-Specific Contract Discount T140 + Base Price T100")
print("="*80)
rows = c.execute('''
    SELECT t140.matchKey1 as cust_code, t140.matchKey2 as sku, t140.discountPct, t100.basePrice
    FROM tbl_price_lists t140
    JOIN tbl_price_lists t100 ON t140.matchKey2 = t100.matchKey1 AND t100.pliCode = 'T100'
    WHERE t140.pliCode = 'T140' AND t140.discountPct > 0 AND t100.basePrice > 0
    LIMIT 10
''').fetchall()
for r in rows:
    cust = get_cust(r[0])
    prod = get_prod(r[1])
    cname = cust[1] if cust else "Unknown"
    pname = prod[1] if prod else "Unknown"
    print(f"Customer: {r[0]} ({cname}) | SKU: {r[1]} ({pname}) | T100 Base: Rs {r[3]} | T140 Disc: {r[2]}%")

print("\n" + "="*80)
print("SCENARIO 5: Customer Category Pricing (T110/T115/T120/T130)")
print("="*80)
# What categories exist in tbl_price_lists?
cat_plis = c.execute('SELECT DISTINCT pliCode, fld0, fld1 FROM tbl_price_lists WHERE fld0 IN ("BCGCOD", "BPCSHO")').fetchall()
print("Price lists with BCGCOD/BPCSHO:", cat_plis)

rows_cat = c.execute('''
    SELECT p.pliCode, p.matchKey1 as cat, p.matchKey2 as sku, p.basePrice, t100.basePrice as t100_base
    FROM tbl_price_lists p
    JOIN tbl_price_lists t100 ON p.matchKey2 = t100.matchKey1 AND t100.pliCode = 'T100'
    WHERE p.fld0 IN ("BCGCOD", "BPCSHO") AND p.basePrice > 0
    LIMIT 10
''').fetchall()
for r in rows_cat:
    sample_cust = c.execute('SELECT code, name, bcgcod FROM tbl_si_customers WHERE bcgcod = ? OR code = ? LIMIT 1', (r[1], r[1])).fetchone()
    prod = get_prod(r[2])
    cinfo = f"{sample_cust[0]} ({sample_cust[1]})" if sample_cust else f"Cat: {r[1]}"
    pname = prod[1] if prod else "Unknown"
    print(f"PLI: {r[0]} | Target: {r[1]} | Sample Cust: {cinfo} | SKU: {r[2]} ({pname}) | Cat Price: Rs {r[3]} vs T100 Base: Rs {r[4]}")

print("\n" + "="*80)
print("SCENARIO 6: Statistical Group Pricing (T160 / TSCCOD)")
print("="*80)
rows_stat = c.execute('''
    SELECT p.pliCode, p.matchKey1 as stat_grp, p.matchKey2 as sku, p.basePrice, p.discountPct
    FROM tbl_price_lists p
    WHERE p.fld0 = 'TSCCOD'
''').fetchall()
for r in rows_stat:
    sample_cust = c.execute('SELECT code, name, bcgcod, tsccod FROM tbl_si_customers WHERE tsccod = ? LIMIT 1', (r[1],)).fetchone()
    prod = get_prod(r[2])
    cinfo = f"{sample_cust[0]} ({sample_cust[1]}, TSC={sample_cust[3]})" if sample_cust else f"Stat: {r[1]}"
    pname = prod[1] if prod else "Unknown"
    print(f"PLI: {r[0]} | StatGrp: {r[1]} | Sample Cust: {cinfo} | SKU: {r[2]} ({pname}) | Base: Rs {r[3]} | Disc: {r[4]}%")

print("\n" + "="*80)
print("SCENARIO 7: Volume Quantity Breaks")
print("="*80)
rows_qty = c.execute('''
    SELECT pliCode, fld0, matchKey1, matchKey2, minQty, maxQty, basePrice, discountPct
    FROM tbl_price_lists
    WHERE isQtyBased = 2 OR (maxQty > 0 AND maxQty < 999999)
''').fetchall()
for r in rows_qty:
    prod = get_prod(r[3])
    pname = prod[1] if prod else "Unknown"
    print(f"PLI: {r[0]} | Target ({r[1]}): {r[2]} | SKU: {r[3]} ({pname}) | Range: [{r[4]} - {r[5]}] | Base: Rs {r[6]} | Disc: {r[7]}%")

print("\n" + "="*80)
print("SCENARIOS 11 & 12: Free Of Charge (FOC)")
print("="*80)
rows_foc = c.execute('''
    SELECT pliCode, fld0, matchKey1, matchKey2, focType, focQtyMin, focQtyBkt, focItmRef, focQty
    FROM tbl_price_lists
    WHERE focType IN (2, 3) AND focQty > 0
''').fetchall()
for r in rows_foc:
    prod = get_prod(r[3])
    foc_prod = get_prod(r[7]) if r[7] else prod
    pname = prod[1] if prod else "Unknown"
    fname = foc_prod[1] if foc_prod else "Unknown"
    foc_desc = f"Same Item ({r[3]})" if r[4] == 2 else f"Cross Item -> {r[7]} ({fname})"
    print(f"PLI: {r[0]} | Key: {r[2]} ({r[1]}) | Order SKU: {r[3]} ({pname}) | FOC Type: {r[4]} ({foc_desc}) | Min: {r[5]}, Bucket: {r[6]} -> Free Qty: {r[8]}")

import sqlite3

conn = sqlite3.connect('InnodisApp.db')
cur = conn.cursor()

def get_product_info(sku):
    # 1. name & tax level from tbl_si_item_stock_details
    st = cur.execute("SELECT itemName, taxLevel, location, warehouse FROM tbl_si_item_stock_details WHERE itemCode = ? LIMIT 1", (sku,)).fetchone()
    name = st[0] if st else ''
    tax = st[1] if st and st[1] else 'VAT0'
    loc = st[2] if st and st[2] else 'A-01'
    wh = st[3] if st and st[3] else 'CGD'
    
    # 2. base price from tbl_price_lists
    # Priority: T110 (MOD) or T100 or highest
    prices = cur.execute("SELECT basePrice, pliCode FROM tbl_price_lists WHERE (matchKey2 = ? OR matchKey1 = ?) AND basePrice > 0 ORDER BY basePrice DESC", (sku, sku)).fetchall()
    base_price = 0.0
    if prices:
        # Prefer T110 or T100
        for p, code in prices:
            if code in ['T110', 'T100']:
                base_price = p
                break
        if base_price == 0.0:
            base_price = prices[0][0]
            
    return {
        'sku': sku,
        'name': name,
        'tax': tax,
        'loc': loc,
        'wh': wh,
        'price': base_price,
    }

order1_items = [
    ('6243', 'Twin Cows ISMP 750g', 12.0, 'EA'),
    ('624006', 'Twin Cows UHT SSk 1L', 24.0, 'EA'),
    ('624005', 'Twin Cows UHT Sk 1L', 42.0, 'EA'),
    ('624049', 'EFRESH UHT MILK 1L FULLCREAMX6', 9.0, 'EA'),
    ('624004', 'Twin Cows UHT FC 1L', 42.0, 'EA'),
    ('721201', 'Lucky Star Pil TomSauce 425g', 168.0, 'EA'),
    ('721401', 'Princess Sardines VegOil 125g', 200.0, 'EA'),
    ('624315', 'Palm Corned Beef 326g', 48.0, 'EA'),
    ('6121', 'LVQR Light 8portions 120g', 40.0, 'EA'),
    ('6430', 'LVQR 8 Portions 112g', 36.0, 'EA'),
    ('6433', 'LVQR 32 Portions 448g', 10.0, 'EA'),
    ('8392', 'Sunbeam EdOil Canola 2L', 6.0, 'EA'),
    ('651426', 'Bois Cheri 3Pav Van 250g', 80.0, 'EA'),
    ('8257', 'Rimilda Basmati SpGrade 5Kg', 8.0, 'EA'),
    ('6435', 'LVQR Rouge 8 Portions 120g', 36.0, 'EA'),
    ('6437', 'LVQR XtraCrème 8 Portions 120g', 36.0, 'EA'),
    ('624035', 'Twin Cows UHT FC 1L*6', 1.0, 'EA'),
    ('624036', 'Twin Cows UHT SSK 1L*6', 1.0, 'EA'),
]

order2_items = [
    ('624251', 'Island Dairy FCMP 1Kg', 60.0, 'EA'),
    ('6252', 'Twin Cows IFCMP 500g', 48.0, 'EA'),
    ('6431', 'LVQR 16 Portions 224g', 32.0, 'EA'),
    ('6432', 'LVQR 24 Portions 336g', 60.0, 'EA'),
    ('6430', 'LVQR 8 Portions 112g', 36.0, 'EA'),
    ('6121', 'LVQR Light 8portions 120g', 36.0, 'EA'),
    ('721205', 'Lucky Star Pil SwChilSauce 425g', 30.0, 'EA'),
    ('720601', 'L STAR PILCHARDS TOMATO - 155G', 240.0, 'EA'),
    ('720503', 'L STAR PILCHARDS TOMATO - 215G', 240.0, 'EA'),
    ('721401', 'Princess Sardines VegOil 125g', 1000.0, 'EA'),
    ('624321', 'Palm Corned Beef 210g', 24.0, 'EA'),
    ('624315', 'Palm Corned Beef 326g', 24.0, 'EA'),
    ('842162', 'Pure Joy 100% Apple 1L', 6.0, 'EA'),
    ('842163', 'Pure Joy 100% Guava 1L', 6.0, 'EA'),
    ('842164', 'Pure Joy 100% Litchi 1L', 6.0, 'EA'),
    ('6360', 'Emborg Cooking Cream 1L 20%', 6.0, 'EA'),
    ('6361', 'Emborg Cooking Cream 200ml', 27.0, 'EA'),
    ('651426', 'Bois Cheri 3Pav Van 250g', 80.0, 'EA'),
    ('651431', 'Bois Cheri 3Pav Van 125g', 160.0, 'EA'),
]

for title, items in [('CGDSO250800002', order1_items), ('CGDSO250800006', order2_items)]:
    print(f"\n==================== {title} ====================")
    subtotal = 0.0
    vat_total = 0.0
    for sku, desc, qty, unit in items:
        info = get_product_info(sku)
        price = info['price']
        if price == 0.0:
            if sku == '721205':
                price = 77.01
            elif sku == '624004':
                price = 61.25
        is_taxable = info['tax'] == 'VAT15' or 'VAT15' in info['tax']
        # In Sage X3, tax rule VATR means standard VAT on taxable items
        line_excl = qty * price
        vat = (line_excl * 0.15) if is_taxable else 0.0
        line_total = line_excl + vat
        subtotal += line_excl
        vat_total += vat
        print(f"SKU {sku:7} | {desc[:28]:28} | Qty: {qty:5.1f} | Price: {price:7.2f} | VAT: {vat:6.2f} | Total: {line_total:8.2f}")
    
    total = subtotal + vat_total
    print(f"--- TOTALS ---")
    print(f"Subtotal Excl. Tax: Rs {subtotal:.2f}")
    print(f"VAT: Rs {vat_total:.2f}")
    print(f"Total Amount: Rs {total:.2f}")

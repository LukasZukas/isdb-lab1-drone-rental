"""Generate sql/01_original_data.sql - logical sample data for the original DB.

Deterministic (fixed seed), so re-running produces the same file.
Every row is generated so that it stays inside ONE region (Lithuania vs.
Latvia/Estonia): a customer only rents drones at branches of his home
region, maintenance is done by staff of the drone's branch, flights belong
to rentals of the same drone. This keeps foreign keys valid after the
derived horizontal fragmentation.

    python tools/generate_data.py
"""
import random
import unicodedata
from datetime import date, datetime, timedelta
from pathlib import Path

random.seed(129)  # P175B129
TODAY = date(2026, 9, 28)
OUT = Path(__file__).resolve().parent.parent / "sql" / "01_original_data.sql"

# ---------------------------------------------------------------- helpers

def ascii_slug(s):
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c)).lower().replace(" ", "")


def lit(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, datetime):
        return f"'{v:%Y-%m-%d %H:%M}'"
    if isinstance(v, date):
        return f"'{v:%Y-%m-%d}'"
    return "'" + str(v).replace("'", "''") + "'"


def insert(table, cols, rows):
    out = [f"INSERT INTO {table} ({', '.join(cols)}) VALUES"]
    out.append(",\n".join("  (" + ", ".join(lit(v) for v in r) + ")" for r in rows) + ";")
    return "\n".join(out) + "\n"


def rand_date(a, b):
    return a + timedelta(days=random.randint(0, (b - a).days))


def phone(prefix):
    return f"{prefix} {random.randint(600, 699)} {random.randint(10000, 99999)}"

# ---------------------------------------------------------------- classifiers

countries = [
    ("LT", "Lithuania", "EUR", "+370"), ("LV", "Latvia", "EUR", "+371"),
    ("EE", "Estonia", "EUR", "+372"), ("PL", "Poland", "PLN", "+48"),
    ("FI", "Finland", "EUR", "+358"), ("SE", "Sweden", "SEK", "+46"),
    ("DE", "Germany", "EUR", "+49"), ("DK", "Denmark", "DKK", "+45"),
    ("NO", "Norway", "NOK", "+47"), ("NL", "Netherlands", "EUR", "+31"),
]
prefix = {c[0]: c[3] for c in countries}

categories = [
    (1, "Photography", "Consumer drones for aerial photos and travel footage"),
    (2, "Cinematography", "Professional film and broadcast camera platforms"),
    (3, "Mapping & Surveying", "RTK drones for photogrammetry and land surveys"),
    (4, "Agriculture", "Spraying and crop-monitoring drones"),
    (5, "Inspection", "Industrial inspection of towers, bridges and power lines"),
    (6, "Thermal Imaging", "Drones with radiometric thermal sensors"),
    (7, "FPV", "First-person-view immersive flying"),
    (8, "Search & Rescue", "Rugged drones for emergency services"),
    (9, "Education", "Small programmable drones for training"),
    (10, "Delivery", "Cargo drones for parcel transport tests"),
]

# (id, category, manufacturer, model, flight min, payload kg, range km, camera MP, weight g, year, price EUR)
models = [
    (1, 1, "DJI", "Mini 4 Pro", 34, 0, 20.0, 48, 249, 2023, 959),
    (2, 1, "DJI", "Air 3", 46, 0, 20.0, 48, 720, 2023, 1099),
    (3, 2, "DJI", "Mavic 3 Pro", 43, 0, 28.0, 20, 958, 2023, 2199),
    (4, 2, "DJI", "Inspire 3", 28, 0, 15.0, 45, 3995, 2023, 16499),
    (5, 3, "Autel Robotics", "EVO II Pro RTK", 36, 0, 15.0, 20, 1191, 2021, 5900),
    (6, 5, "DJI", "Matrice 350 RTK", 55, 2.7, 20.0, None, 6470, 2023, 11500),
    (7, 6, "DJI", "Mavic 3 Thermal", 45, 0, 15.0, 48, 920, 2022, 6500),
    (8, 4, "DJI", "Agras T40", 18, 40, 7.0, 12, 50000, 2022, 24000),
    (9, 7, "DJI", "Avata 2", 23, 0, 13.0, 48, 377, 2024, 999),
    (10, 8, "Parrot", "Anafi USA", 32, 0, 5.0, 21, 500, 2020, 7000),
]
model_price = {m[0]: m[10] for m in models}
model_firmware = {1: "01.02", 2: "01.03", 3: "01.01", 4: "03.00", 5: "2.7",
                  6: "09.01", 7: "07.00", 8: "04.01", 9: "01.00", 10: "1.8"}

# ---------------------------------------------------------------- branches

branches_raw = [  # 10 in Lithuania (fragment 1) + 10 in Latvia/Estonia (fragment 2)
    ("SkyRent Vilnius Centras", "Vilnius", "LT", "Gedimino pr. 20"),
    ("SkyRent Vilnius Pašilaičiai", "Vilnius", "LT", "Gabijos g. 55"),
    ("SkyRent Kaunas", "Kaunas", "LT", "Laisvės al. 71"),
    ("SkyRent Klaipėda", "Klaipėda", "LT", "Taikos pr. 61"),
    ("SkyRent Šiauliai", "Šiauliai", "LT", "Tilžės g. 109"),
    ("SkyRent Panevėžys", "Panevėžys", "LT", "Respublikos g. 34"),
    ("SkyRent Alytus", "Alytus", "LT", "Naujoji g. 12"),
    ("SkyRent Marijampolė", "Marijampolė", "LT", "Kauno g. 8"),
    ("SkyRent Utena", "Utena", "LT", "Utenio a. 5"),
    ("SkyRent Palanga", "Palanga", "LT", "Vytauto g. 88"),
    ("SkyRent Riga Centrs", "Riga", "LV", "Brīvības iela 40"),
    ("SkyRent Riga Purvciems", "Riga", "LV", "Dzelzavas iela 51"),
    ("SkyRent Jūrmala", "Jūrmala", "LV", "Jomas iela 35"),
    ("SkyRent Liepāja", "Liepāja", "LV", "Lielā iela 13"),
    ("SkyRent Daugavpils", "Daugavpils", "LV", "Rīgas iela 22"),
    ("SkyRent Valmiera", "Valmiera", "LV", "Rīgas iela 10"),
    ("SkyRent Tallinn Kesklinn", "Tallinn", "EE", "Narva mnt 7"),
    ("SkyRent Tartu", "Tartu", "EE", "Riia 2"),
    ("SkyRent Pärnu", "Pärnu", "EE", "Rüütli 25"),
    ("SkyRent Narva", "Narva", "EE", "Tallinna mnt 19"),
]
branches = []
for i, (name, city, cc, addr) in enumerate(branches_raw, 1):
    branches.append((i, name, city, cc, addr, phone(prefix[cc]),
                     f"{ascii_slug(city)}{'' if i not in (2, 12) else '2'}@skyrent.eu",
                     rand_date(date(2019, 3, 1), date(2024, 6, 1))))
branch_cc = {b[0]: b[3] for b in branches}
LT_BRANCHES = [b[0] for b in branches if b[3] == "LT"]
FOREIGN_BRANCHES = [b[0] for b in branches if b[3] != "LT"]

# ---------------------------------------------------------------- people

names = {
    "LT": (["Jonas", "Tomas", "Mantas", "Lukas", "Paulius", "Darius", "Andrius", "Rokas", "Karolis", "Mindaugas"],
           ["Ieva", "Gabija", "Austėja", "Eglė", "Rūta", "Greta", "Monika", "Indrė", "Aistė", "Laura"],
           ["Kazlauskas", "Petrauskas", "Jankauskas", "Stankevičius", "Vasiliauskas", "Žukauskas", "Butkus", "Paulauskas", "Urbonas", "Kavaliauskas"],
           ["Kazlauskienė", "Petrauskaitė", "Jankauskienė", "Stankevičiūtė", "Vasiliauskaitė", "Žukauskienė", "Butkutė", "Paulauskaitė", "Urbonaitė", "Kavaliauskienė"]),
    "LV": (["Jānis", "Andris", "Mārtiņš", "Kārlis", "Edgars"], ["Anna", "Līga", "Ilze", "Kristīne", "Laura"],
           ["Bērziņš", "Kalniņš", "Ozoliņš", "Jansons", "Liepiņš"], ["Bērziņa", "Kalniņa", "Ozoliņa", "Jansone", "Liepiņa"]),
    "EE": (["Martin", "Rasmus", "Kristjan", "Mihkel", "Andres"], ["Mari", "Kadri", "Liis", "Triin", "Kertu"],
           ["Tamm", "Saar", "Sepp", "Mägi", "Kask", "Kukk", "Rebane", "Ilves", "Pärn", "Koppel"], None),
}
foreigners = [("PL", "Piotr", "Nowak"), ("FI", "Aino", "Korhonen"), ("DE", "Lena", "Schmidt"),
              ("SE", "Erik", "Johansson"), ("DK", "Mads", "Nielsen"), ("NO", "Ola", "Hansen"),
              ("NL", "Daan", "de Jong"), ("PL", "Anna", "Kowalska"), ("FI", "Mikko", "Virtanen"),
              ("DE", "Lukas", "Müller")]
used_emails = set()


def person(cc):
    male_first, female_first, male_last, female_last = names[cc]
    if random.random() < 0.5:
        first, last = random.choice(male_first), random.choice(male_last)
    else:
        first, last = random.choice(female_first), random.choice(female_last or male_last)
    return first, last


def email(first, last, domain):
    base = f"{ascii_slug(first)}.{ascii_slug(last)}"
    e, n = f"{base}@{domain}", 2
    while e in used_emails:
        e, n = f"{base}{n}@{domain}", n + 1
    used_emails.add(e)
    return e


customers = []
foreign_pool = foreigners[:]
random.shuffle(foreign_pool)
for cid in range(1, 41):
    region_lt = cid <= 20
    home = random.choice(LT_BRANCHES if region_lt else FOREIGN_BRANCHES)
    if cid % 7 == 0 and foreign_pool:          # some tourists / expats
        cc, first, last = foreign_pool.pop()
    else:
        cc = branch_cc[home]
        first, last = person(cc)
    customers.append((cid, first, last, email(first, last, random.choice(["gmail.com", "outlook.com", "inbox.lt" if cc == "LT" else "mail.com"])),
                      phone(prefix[cc]), rand_date(date(1965, 1, 1), date(2005, 12, 31)), cc, home,
                      f"{cc}-RP-{random.randint(100000, 999999)}", random.choices(["A1/A3", "A2", "STS"], [6, 3, 1])[0],
                      datetime.combine(rand_date(date(2023, 1, 10), date(2025, 12, 20)), datetime.min.time()) + timedelta(minutes=random.randint(480, 1260))))
cust_home = {c[0]: c[7] for c in customers}

employees = []
eid = 0
roles_extra = ["pilot_instructor", "branch_manager", "safety_inspector", "technician"]
certs = {"technician": "DJI Authorised Repair", "pilot_instructor": "EASA STS Instructor",
         "branch_manager": None, "safety_inspector": "EASA SORA Assessor"}
for b in branches:                       # every branch has a technician
    eid += 1
    first, last = person(b[3])
    employees.append((eid, b[0], first, last, email(first, last, "skyrent.eu"), "technician",
                      certs["technician"], rand_date(max(b[7], date(2020, 1, 1)), date(2025, 6, 1))))
for i in range(10):                      # plus one extra employee in 10 branches
    b = branches[i * 2 + (i % 2)]
    eid += 1
    first, last = person(b[3])
    role = roles_extra[i % 4]
    employees.append((eid, b[0], first, last, email(first, last, "skyrent.eu"), role,
                      certs[role], rand_date(max(b[7], date(2020, 1, 1)), date(2025, 6, 1))))
technician_of = {e[1]: e[0] for e in employees if e[5] == "technician"}

# ---------------------------------------------------------------- drones

drones = []
did = 0
model_cycle = [1, 2, 3, 9, 7, 5, 1, 2, 6, 10, 3, 4, 8, 9, 2, 1, 7, 3, 5, 2]
for b in branches:                       # 2 drones per branch
    for k in range(2):
        did += 1
        m = model_cycle[(b[0] * 2 + k) % len(model_cycle)]
        price = model_price[m]
        bought = rand_date(max(b[7], date(2021, 1, 1)), date(2025, 10, 1))
        age_days = (TODAY - bought).days
        hours = round(age_days / 365 * random.uniform(25, 70), 1)
        drones.append({
            "drone_id": did, "model_id": m, "branch_id": b[0],
            "serial_number": f"{'1581F' if m != 5 and m != 10 else 'AUT'}{random.randint(10**9, 10**10 - 1)}",
            "purchase_date": bought, "purchase_price": float(price),
            "daily_rate": round(max(25, price * 0.035), 0), "deposit_amount": round(price * 0.3, -1),
            "status": "available", "firmware_version": f"{model_firmware[m]}.{random.randint(100, 999):04d}",
            "total_flight_hours": hours, "battery_cycles": int(hours * random.uniform(1.6, 2.4)),
            "last_inspection_date": None,
            "condition": "excellent" if age_days < 400 else random.choice(["good", "good", "fair"]),
        })
drones_by_branch = {}
for d in drones:
    drones_by_branch.setdefault(d["branch_id"], []).append(d)

# ---------------------------------------------------------------- rentals, payments

rentals, payments, flights = [], [], []
pid = fid = 0
busy = {}                                # drone_id -> list of (start, end)
for rid in range(1, 71):
    cust = customers[(rid * 7) % 40] if rid > 40 else customers[rid - 1]
    home = cust[7]
    region = LT_BRANCHES if branch_cc[home] == "LT" else FOREIGN_BRANCHES
    for _ in range(100):
        br = home if random.random() < 0.7 else random.choice(region)
        d = random.choice(drones_by_branch[br])
        if rid > 64:                     # the last rentals are running right now
            start = TODAY - timedelta(days=random.randint(0, 3))
            end = TODAY + timedelta(days=random.randint(1, 4))
        else:
            start = rand_date(max(d["purchase_date"], date(2025, 1, 5)), date(2026, 10, 25))
            end = start + timedelta(days=random.choice([1, 1, 2, 2, 3, 4, 5, 7]))
        if all(end < s or start > e for s, e in busy.get(d["drone_id"], [])):
            break
    busy.setdefault(d["drone_id"], []).append((start, end))
    days = (end - start).days + 1
    total = round(days * d["daily_rate"] * (0.9 if days >= 5 else 1), 2)
    if start > TODAY:
        status = "reserved"
    elif end >= TODAY:
        status = "active"
        d["status"] = "rented"
    else:
        status = "cancelled" if random.random() < 0.08 else "completed"
    rentals.append((rid, cust[0], d["drone_id"], br, start, end, total, status))

    method = random.choice(["card", "card", "card", "bank_transfer", "cash", "paypal"])
    booked = datetime.combine(start - timedelta(days=random.randint(1, 14)), datetime.min.time()) + timedelta(minutes=random.randint(480, 1200))
    if status != "cancelled":
        pid += 1
        payments.append((pid, rid, d["deposit_amount"], method, "deposit", booked))
    if status in ("active", "completed"):
        pid += 1
        payments.append((pid, rid, total, method, "rental_fee", booked + timedelta(minutes=2)))
    if status == "completed":
        returned = datetime.combine(end, datetime.min.time()) + timedelta(hours=random.randint(9, 19))
        damaged = random.random() < 0.1
        pid += 1
        payments.append((pid, rid, d["deposit_amount"], method if method != "cash" else "bank_transfer", "deposit_refund", returned + timedelta(days=1)))
        if damaged:
            pid += 1
            payments.append((pid, rid, float(random.choice([45, 80, 120, 250])), "card", "damage_fee", returned))

    if status in ("active", "completed"):
        m = next(x for x in models if x[0] == d["model_id"])
        for day in range(days):
            fday = start + timedelta(days=day)
            if fday > TODAY or random.random() < 0.35:
                continue
            for _ in range(random.randint(1, 2)):
                fid += 1
                dur = random.randint(max(5, m[4] // 3), m[4] - 2)
                incident = random.random() < 0.04
                flights.append([fid, d["drone_id"], rid,
                                datetime.combine(fday, datetime.min.time()) + timedelta(minutes=random.randint(420, 1140)),
                                dur, random.randint(30, 120), round(dur * random.uniform(0.25, 0.7), 2),
                                min(100, int(dur / m[4] * 100) + random.randint(0, 8)), incident])

# ---------------------------------------------------------------- maintenance

mtypes = {
    "scheduled_inspection": ("Scheduled 50-hour inspection: frame, arms, gimbal, IMU check", 40, 2),
    "battery_replacement": ("Battery pack replaced after reaching cycle limit", 120, 1),
    "propeller_replacement": ("Full propeller set replaced", 25, 0.5),
    "firmware_update": ("Aircraft and remote controller firmware updated", 0, 1),
    "gimbal_calibration": ("Gimbal and camera calibration after customer complaint", 35, 1.5),
    "crash_repair": ("Repair after hard landing: arm and landing gear replaced", 290, 48),
    "motor_replacement": ("Motor replaced due to abnormal vibration", 160, 6),
}
maintenance = []
mid = 0
for i in range(50):
    d = drones[(i * 3) % 40] if i < 40 else random.choice(drones)
    mdate = rand_date(max(d["purchase_date"] + timedelta(days=20), date(2024, 1, 1)), TODAY - timedelta(days=1))
    mtype = random.choices(list(mtypes), [6, 2, 3, 4, 2, 1, 1])[0]
    desc, base_cost, dt = mtypes[mtype]
    scale = model_price[d["model_id"]] / 3000
    mid += 1
    maintenance.append((mid, d["drone_id"], technician_of[d["branch_id"]], mdate, mtype, desc,
                        round(base_cost * max(0.6, min(scale, 4)), 2), dt))
    if mtype == "scheduled_inspection" and (d["last_inspection_date"] is None or mdate > d["last_inspection_date"]):
        d["last_inspection_date"] = mdate
    if mtype == "crash_repair":             # post-repair test flight, no rental
        fid += 1
        m = next(x for x in models if x[0] == d["model_id"])
        flights.append([fid, d["drone_id"], None,
                        datetime.combine(mdate + timedelta(days=2), datetime.min.time()) + timedelta(hours=11),
                        8, 30, 0.8, int(8 / m[4] * 100) + 3, False])

for d in drones:
    if d["last_inspection_date"] is None:
        d["last_inspection_date"] = rand_date(max(d["purchase_date"], date(2025, 6, 1)), TODAY - timedelta(days=3))
# a few drones out of service
for d in drones:
    if d["status"] == "available" and d["drone_id"] in (6, 17, 33):
        d["status"] = "maintenance"
    if d["drone_id"] == 26 and d["status"] == "available":
        d["status"], d["condition"] = "retired", "poor"

flights.sort(key=lambda f: f[3])
for i, f in enumerate(flights, 1):
    f[0] = i

# ---------------------------------------------------------------- write

drone_cols = ["drone_id", "model_id", "branch_id", "serial_number", "purchase_date", "purchase_price",
              "daily_rate", "deposit_amount", "status", "firmware_version", "total_flight_hours",
              "battery_cycles", "last_inspection_date", "condition"]
sql = [
    "-- =====================================================================",
    "-- Sample data for the ORIGINAL database (DBVS1 / isdb_original)",
    "-- GENERATED by tools/generate_data.py - do not edit by hand.",
    "-- =====================================================================\n",
    "BEGIN;\n",
    insert("country", ["country_code", "name", "currency_code", "phone_prefix"], countries),
    insert("drone_category", ["category_id", "name", "description"], categories),
    insert("drone_model", ["model_id", "category_id", "manufacturer", "model_name", "max_flight_time_min",
                           "max_payload_kg", "max_range_km", "camera_mp", "weight_g", "launch_year"],
           [m[:10] for m in models]),
    insert("branch", ["branch_id", "name", "city", "country_code", "address", "phone", "email", "opened_on"], branches),
    insert("customer", ["customer_id", "first_name", "last_name", "email", "phone", "birth_date", "country_code",
                        "home_branch_id", "pilot_license_no", "license_class", "registered_at"], customers),
    insert("drone", drone_cols, [[d[c] for c in drone_cols] for d in drones]),
    insert("rental", ["rental_id", "customer_id", "drone_id", "branch_id", "start_date", "end_date",
                      "total_price", "status"], rentals),
    insert("payment", ["payment_id", "rental_id", "amount", "method", "payment_type", "paid_at"], payments),
    insert("employee", ["employee_id", "branch_id", "first_name", "last_name", "email", "role",
                        "certification", "hired_on"], employees),
    insert("maintenance", ["maintenance_id", "drone_id", "employee_id", "maintenance_date", "maintenance_type",
                           "description", "cost", "downtime_hours"], maintenance),
    insert("flight_log", ["flight_id", "drone_id", "rental_id", "started_at", "duration_min", "max_altitude_m",
                          "distance_km", "battery_used_pct", "incident_reported"], flights),
    "COMMIT;\n",
]
OUT.write_text("\n".join(sql), encoding="utf-8", newline="\n")
print(f"wrote {OUT} - customers={len(customers)} drones={len(drones)} rentals={len(rentals)} "
      f"payments={len(payments)} employees={len(employees)} maintenance={len(maintenance)} flights={len(flights)}")

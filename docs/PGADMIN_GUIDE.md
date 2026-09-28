# Defence walkthrough in pgAdmin

This is a click-by-click script for showing the lab to the lecturer. It follows the two points from the task's **"GYNIMO METU"** section:

1. the original DB model and the vertically split schemas of both fragments;
2. the fragmentation implemented in the DBMS, with data (horizontal and vertical).

It takes about 10 minutes. Lines starting with 🗣 are what to say.

---

## 0. Before the defence (5 min, do it at home first)

1. Start **Docker Desktop** and wait until it says *Engine running*.
2. In the repo folder run:
   ```bash
   docker compose up -d
   ```
3. Wait **about 1 minute** (pgAdmin initialises on first start), then open **http://localhost:5050**.
4. In the left **Object Explorer**, expand **ISDB Lab 1**. You will see:
   * `DBVS1 - M1 Customers and Rentals (db11, db12)`
   * `DBVS2 - M2 Fleet and Maintenance (db21, db22)`

   Click the arrow next to each one: it connects without asking for a password.
5. Keep these ready in browser tabs:
   * the GitHub repo page (it shows the three model diagrams), and
   * optionally https://dbdiagram.io with `docs/model/m0_original.dbml` pasted in.

> Using the **desktop** pgAdmin instead? *Object → Register → Server…*, add
> Host `localhost`, Port `5433`, user/password `postgres`/`postgres` for DBVS1, and port `5434` for DBVS2.
> Everything below works the same, except the "Open File" path in step 5.

Reset to a clean state at any time: `docker compose run --rm setup` (about 10 s). Note that running `docker compose up -d` again also rebuilds the data.

---

## 1. The original model and the vertical split (GYNIMO point 1)

### 1a. The diagrams (modelling tool = DBML / dbdiagram.io instead of MSOSA)

Show the README on GitHub, or the SVGs in `docs/model/`:

* **M0** `m0_original.svg`
  🗣 *"The domain is a drone rental network. The original model has 11 tables. `drone` is the widest table, with 14 attributes. Grey tables are classifiers. The coloured groups show which module each table goes to."*
* **M1** `m1_customers_rentals.svg` and **M2** `m2_fleet_maintenance.svg`
  🗣 *"Vertical fragmentation is by function. M1 is the commercial module: customers, rentals, payments. M2 is the technical module: employees, maintenance, flight logs. The `drone` table is split in two: `drone_commercial` with price, rate, deposit and status goes to M1, and `drone_technical` with serial number, firmware, flight hours, battery and condition goes to M2. Both halves keep the key `drone_id`. The classifiers and `branch` are copied into both fragments because each fragment needs them."*

If asked why the tool isn't MSOSA: the task allows *"kitą įrankį, leidžiantį grafiškai atvaizduoti duomenų bazės duomenų modelį"*. DBML is a text-based modelling language, and dbdiagram.io is its graphical editor.

### 1b. The same models live in pgAdmin (ERD Tool)

1. Expand **DBVS1 → Databases**, right-click **db11** → **ERD For Database**.
2. If the tables overlap, click the **Auto align** button in the ERD toolbar.
   🗣 *"This is M1 as implemented in the DBMS. pgAdmin generates the diagram from the real tables and foreign keys."*
3. Do the same for **DBVS2 → Databases → db21** → **ERD For Database**.
   🗣 *"And this is M2. `flight_log.rental_id` has no FK line because the rental lives on the other server. It is a cross-fragment reference."*

---

## 2. Infrastructure: two DBMS instances, four fragment DBs

Expand **DBVS1 → Databases** and **DBVS2 → Databases**:

| DBVS1 (port 5433) | DBVS2 (port 5434) |
|---|---|
| `db11`: M1, Lithuania | `db21`: M2, Lithuania |
| `db12`: M1, Latvia + Estonia | `db22`: M2, Latvia + Estonia |
| `isdb_global`: coordinator, no own data | |

* Click a database. Its description appears in the **status bar at the bottom**. You can also right-click → **Properties** → *Comment*.
* 🗣 *"Two independent PostgreSQL 17 servers, one per vertical fragment. `db12` was created as an identical clone of `db11` using `CREATE DATABASE db12 TEMPLATE db11`, then horizontally split. The same was done for `db22` from `db21`. We used scenario 2: we built the full database first, moved the data into the vertical fragments with queries, verified it, and then deleted the original."*

---

## 3. Vertical fragmentation, with data

1. **DBVS1 → db11 → Schemas → public → Tables**: 8 tables.
   **DBVS2 → db21 → Schemas → public → Tables**: 8 tables.
2. Expand **db11 → … → Tables → drone_commercial → Columns** and **db21 → … → Tables → drone_technical → Columns**. Show the different column sets.
3. Right-click **drone_commercial** (db11) → **View/Edit Data → All Rows**.
   Then do the same for **drone_technical** (db21).
   🗣 *"Same `drone_id` values 1–20 on both servers. The commercial attributes are here, the technical ones are on DBVS2."*
4. Show the classifiers are complete everywhere: **drone_model → View/Edit Data → All Rows** in db11 and db22. Both have the same 10 rows.

---

## 4. Horizontal fragmentation, with data

1. **db11 → branch → View/Edit Data → All Rows**: 10 branches, all `LT` (Vilnius, Kaunas…).
   **db12 → branch → View/Edit Data → All Rows**: 10 branches, all `LV`/`EE` (Riga, Tallinn…).
2. Open a Query Tool on **db12** (right-click db12 → **Query Tool**) and run:
   ```sql
   SELECT b.country_code, count(*) AS customers
   FROM customer c JOIN branch b ON b.branch_id = c.home_branch_id
   GROUP BY 1;
   ```
   Only LV and EE come back.
   🗣 *"Primary horizontal fragmentation is on `branch.country_code`. The other tables are fragmented by derived fragmentation, following their foreign key to `branch`. The criterion is the same for M1 and M2, so db11 and db21 hold the two halves of exactly the same Lithuanian drones. Classifiers are not fragmented horizontally."*
3. Optionally, in db21 run `SELECT * FROM drone_technical;` and in db11 run `SELECT * FROM drone_commercial;`. Both return IDs 1–20.

---

## 5. Everything together: distributed queries in `isdb_global`

1. Right-click **DBVS1 → Databases → isdb_global** → **Query Tool** (or press Alt+Shift+Q).
2. Click the **folder icon (Open File)** in the Query Tool toolbar. Go to **`/home/sql`** (type it into the path box if needed) and open **`60_demo_queries.sql`**.
   *(Desktop pgAdmin: open the file from your cloned repo's `sql/` folder instead.)*
3. **Highlight one query and press F5.** F5 runs only the highlighted text. Go through the queries in order:

| # | Query | What it shows / what to say |
|---|---|---|
| 1 | `SELECT * FROM global.fragment_overview;` | Row counts of every table in all 4 fragments, fetched live from both servers. Every table has ≥ 10 rows. |
| 2 | branches of DB11 vs DB12, rentals per country | The horizontal criterion. |
| 3 | drone 1 as JSON from db11 and db21, then `global.drone` | 🗣 *"One drone, two halves on two servers, joined back into the original 14-column row."* |
| 4 | `SELECT * FROM global.drone` | The whole original table rebuilt: `UNION ALL` of the horizontal fragments, `JOIN` of the vertical ones. |
| 5 | top pilots by minutes flown | 🗣 *"A distributed join. Customer and rental come from M1 on DBVS1, flights come from M2 on DBVS2."* |
| 6 | income vs maintenance cost per model | Aggregation across all 4 fragments. |
| 7 | `EXPLAIN (VERBOSE …)` | Look at **Remote SQL** in the Data Output. 🗣 *"PostgreSQL pushes `WHERE drone_id = 1` to each fragment server."* |
| 8 | `BEGIN … INSERT into db12 and db22 … SELECT` | Highlight from `BEGIN;` down to the `SELECT` and press F5. It inserts both halves of a new drone (Riga, so DB12 + DB22) in one transaction on two servers, and the SELECT shows it as one row. Then highlight `ROLLBACK;` and press F5: the insert is undone on both servers. |

4. Also show **isdb_global → Schemas**:
   * `db11`, `db12`, `db21`, `db22` → **Foreign Tables**. These are links, not copies.
   * `global` → **Views**. These are the reconstruction views.

   Right-click a view, e.g. **global → Views → drone**, then **Properties → Code** or the **SQL** tab, to show the `UNION ALL` / `JOIN` definition.

---

## 6. Proof that the fragmentation is correct

Run in a terminal:

```bash
docker compose logs setup
```

(The same output is saved in `docs/build-log.txt`.) The build compares the original database with the reconstruction before deleting the original:

```
OK  customer         (40 rows: original = reconstructed)
OK  drone            (40 rows: original = reconstructed)
...
OK  horizontal fragments are disjoint
OK  vertical fragments drone_commercial / drone_technical have the same keys
```

🗣 *"For every table the reconstruction has the same row count, and `EXCEPT` in both directions is empty. That means the fragmentation is complete, reconstructable and disjoint. After that the original database was dropped, as scenario 2 requires."*

If you want to show the original database live, rebuild without dropping it: `KEEP_ORIGINAL=1 docker compose run --rm setup` (in PowerShell: `$env:KEEP_ORIGINAL=1; docker compose run --rm setup`). `isdb_original` then stays on DBVS1.

---

## Likely questions

* **Why is `branch` in both vertical fragments?** Both modules need it: rentals happen at a branch, and drones and staff belong to a branch. It is also the attribute the horizontal fragmentation is based on. The task says fragments should also receive the tables *"kurios reikalingos visam fragmentui aptarnauti"* (needed to serve the whole fragment).
* **Why are `model_id` and `branch_id` in both drone halves?** They are FKs to tables that are local to each fragment. Keeping `branch_id` in both halves also means each half can be fragmented horizontally without asking the other server.
* **How are the fragments linked?** By the shared primary key `drone_id`, and by the logical reference `flight_log.rental_id` (M2) → `rental` (M1). Foreign keys cannot cross DBMS instances, so this one is not enforced by a constraint.
* **Why no SERIAL / auto-increment?** Vertically split rows must have identical keys in both halves. Explicit integer keys avoid the synchronisation problem the task mentions.
* **What does `isdb_global` store?** Nothing. It only contains `postgres_fdw` foreign tables and views, as a distributed query layer.

-- =====================================================================
-- M2 - VERTICAL FRAGMENT 2: "Fleet Operations & Maintenance" (technical module)
-- Runs in: DBVS2 / db21   (db22 is later cloned from db21)
--
--   replicated classifiers : country, drone_category, drone_model
--   replicated domain table: branch (horizontal fragmentation attribute)
--   own domain tables      : employee, maintenance, flight_log
--   vertically split table : drone -> drone_technical (this fragment)
--                                   + drone_commercial (M1, DBVS1)
-- =====================================================================

-- ---------- Replicated classifiers ----------

CREATE TABLE country (
    country_code  char(2)     PRIMARY KEY,
    name          varchar(60) NOT NULL UNIQUE,
    currency_code char(3)     NOT NULL,
    phone_prefix  varchar(5)  NOT NULL
);
COMMENT ON TABLE country IS 'Replicated classifier (identical copy in all fragments).';

CREATE TABLE drone_category (
    category_id integer     PRIMARY KEY,
    name        varchar(60) NOT NULL UNIQUE,
    description text        NOT NULL
);
COMMENT ON TABLE drone_category IS 'Replicated classifier (identical copy in all fragments).';

CREATE TABLE drone_model (
    model_id            integer      PRIMARY KEY,
    category_id         integer      NOT NULL REFERENCES drone_category,
    manufacturer        varchar(60)  NOT NULL,
    model_name          varchar(80)  NOT NULL,
    max_flight_time_min smallint     NOT NULL,
    max_payload_kg      numeric(5,2) NOT NULL DEFAULT 0,
    max_range_km        numeric(5,1) NOT NULL,
    camera_mp           numeric(4,1),
    weight_g            integer      NOT NULL,
    launch_year         smallint     NOT NULL,
    UNIQUE (manufacturer, model_name)
);
COMMENT ON TABLE drone_model IS 'Replicated classifier (identical copy in all fragments).';

-- ---------- Domain tables ----------

CREATE TABLE branch (
    branch_id    integer      PRIMARY KEY,
    name         varchar(80)  NOT NULL UNIQUE,
    city         varchar(60)  NOT NULL,
    country_code char(2)      NOT NULL REFERENCES country,
    address      varchar(120) NOT NULL,
    phone        varchar(20)  NOT NULL,
    email        varchar(120) NOT NULL,
    opened_on    date         NOT NULL
);
COMMENT ON TABLE branch IS 'Needed by both vertical fragments; horizontally fragmented by country_code (primary horizontal fragmentation).';

CREATE TABLE drone_technical (
    drone_id             integer      PRIMARY KEY,
    model_id             integer      NOT NULL REFERENCES drone_model,
    branch_id            integer      NOT NULL REFERENCES branch,
    serial_number        varchar(40)  NOT NULL UNIQUE,
    firmware_version     varchar(20)  NOT NULL,
    total_flight_hours   numeric(7,1) NOT NULL DEFAULT 0,
    battery_cycles       integer      NOT NULL DEFAULT 0,
    last_inspection_date date,
    condition            varchar(10)  NOT NULL CHECK (condition IN ('excellent', 'good', 'fair', 'poor'))
);
COMMENT ON TABLE drone_technical IS 'VERTICAL fragment of drone: technical attributes. Joined with M1.drone_commercial on drone_id.';

CREATE TABLE employee (
    employee_id   integer      PRIMARY KEY,
    branch_id     integer      NOT NULL REFERENCES branch,
    first_name    varchar(60)  NOT NULL,
    last_name     varchar(60)  NOT NULL,
    email         varchar(120) NOT NULL UNIQUE,
    role          varchar(20)  NOT NULL CHECK (role IN ('technician', 'pilot_instructor', 'branch_manager', 'safety_inspector')),
    certification varchar(60),
    hired_on      date         NOT NULL
);
COMMENT ON TABLE employee IS 'Derived horizontal fragmentation via branch_id -> branch.country_code.';

CREATE TABLE maintenance (
    maintenance_id   integer      PRIMARY KEY,
    drone_id         integer      NOT NULL REFERENCES drone_technical,
    employee_id      integer      NOT NULL REFERENCES employee,
    maintenance_date date         NOT NULL,
    maintenance_type varchar(25)  NOT NULL,
    description      text         NOT NULL,
    cost             numeric(8,2) NOT NULL,
    downtime_hours   numeric(5,1) NOT NULL
);
COMMENT ON TABLE maintenance IS 'Derived horizontal fragmentation via drone -> branch.country_code.';

CREATE TABLE flight_log (
    flight_id         integer      PRIMARY KEY,
    drone_id          integer      NOT NULL REFERENCES drone_technical,
    rental_id         integer,     -- logical reference to M1.rental (other DBMS, cannot be a FK)
    started_at        timestamp    NOT NULL,
    duration_min      smallint     NOT NULL,
    max_altitude_m    smallint     NOT NULL CHECK (max_altitude_m <= 120),
    distance_km       numeric(6,2) NOT NULL,
    battery_used_pct  smallint     NOT NULL CHECK (battery_used_pct BETWEEN 1 AND 100),
    incident_reported boolean      NOT NULL DEFAULT false
);
COMMENT ON TABLE flight_log IS 'Derived horizontal fragmentation via drone -> branch.country_code. rental_id points to M1.rental on DBVS1 (cross-fragment reference, no FK).';
COMMENT ON COLUMN flight_log.rental_id IS 'Cross-fragment reference to M1.rental.rental_id (DBVS1). Not enforced by a FK.';

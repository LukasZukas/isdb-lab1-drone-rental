-- =====================================================================
-- M0 - ORIGINAL (unfragmented) database model: "SkyRent" drone rental
-- Runs in: DBVS1 / isdb_original
--
-- Primary keys are plain INTEGER values (no SERIAL / IDENTITY) so that
-- vertically split rows keep identical keys in every fragment and no
-- auto-increment synchronisation between fragments is needed.
-- =====================================================================

-- ---------- Classifiers (replicated in full to every fragment) ----------

CREATE TABLE country (
    country_code  char(2)     PRIMARY KEY,
    name          varchar(60) NOT NULL UNIQUE,
    currency_code char(3)     NOT NULL,
    phone_prefix  varchar(5)  NOT NULL
);
COMMENT ON TABLE country IS 'Classifier: countries (customer nationality, branch location).';

CREATE TABLE drone_category (
    category_id integer     PRIMARY KEY,
    name        varchar(60) NOT NULL UNIQUE,
    description text        NOT NULL
);
COMMENT ON TABLE drone_category IS 'Classifier: purpose category of a drone model.';

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
COMMENT ON TABLE drone_model IS 'Classifier: drone model catalogue with manufacturer specifications.';

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
COMMENT ON TABLE branch IS 'Rental branch. branch.country_code is the horizontal fragmentation attribute.';

CREATE TABLE customer (
    customer_id      integer      PRIMARY KEY,
    first_name       varchar(60)  NOT NULL,
    last_name        varchar(60)  NOT NULL,
    email            varchar(120) NOT NULL UNIQUE,
    phone            varchar(20)  NOT NULL,
    birth_date       date         NOT NULL,
    country_code     char(2)      NOT NULL REFERENCES country,
    home_branch_id   integer      NOT NULL REFERENCES branch,
    pilot_license_no varchar(30)  NOT NULL UNIQUE,
    license_class    varchar(5)   NOT NULL CHECK (license_class IN ('A1/A3', 'A2', 'STS')),
    registered_at    timestamp    NOT NULL
);
COMMENT ON TABLE customer IS 'Customer (drone pilot) registered at a home branch.';

CREATE TABLE drone (
    drone_id             integer       PRIMARY KEY,
    model_id             integer       NOT NULL REFERENCES drone_model,
    branch_id            integer       NOT NULL REFERENCES branch,
    serial_number        varchar(40)   NOT NULL UNIQUE,
    purchase_date        date          NOT NULL,
    purchase_price       numeric(10,2) NOT NULL,
    daily_rate           numeric(8,2)  NOT NULL,
    deposit_amount       numeric(8,2)  NOT NULL,
    status               varchar(12)   NOT NULL CHECK (status IN ('available', 'rented', 'maintenance', 'retired')),
    firmware_version     varchar(20)   NOT NULL,
    total_flight_hours   numeric(7,1)  NOT NULL DEFAULT 0,
    battery_cycles       integer       NOT NULL DEFAULT 0,
    last_inspection_date date,
    condition            varchar(10)   NOT NULL CHECK (condition IN ('excellent', 'good', 'fair', 'poor'))
);
COMMENT ON TABLE drone IS 'Physical drone unit (14 attributes) - the table that is split VERTICALLY into drone_commercial (M1) and drone_technical (M2).';

CREATE TABLE rental (
    rental_id   integer       PRIMARY KEY,
    customer_id integer       NOT NULL REFERENCES customer,
    drone_id    integer       NOT NULL REFERENCES drone,
    branch_id   integer       NOT NULL REFERENCES branch,
    start_date  date          NOT NULL,
    end_date    date          NOT NULL,
    total_price numeric(10,2) NOT NULL,
    status      varchar(10)   NOT NULL CHECK (status IN ('reserved', 'active', 'completed', 'cancelled')),
    CHECK (end_date >= start_date)
);
COMMENT ON TABLE rental IS 'Rental agreement of one drone by one customer at a branch.';

CREATE TABLE payment (
    payment_id   integer       PRIMARY KEY,
    rental_id    integer       NOT NULL REFERENCES rental,
    amount       numeric(10,2) NOT NULL CHECK (amount > 0),
    method       varchar(15)   NOT NULL CHECK (method IN ('card', 'bank_transfer', 'cash', 'paypal')),
    payment_type varchar(15)   NOT NULL CHECK (payment_type IN ('deposit', 'rental_fee', 'deposit_refund', 'damage_fee')),
    paid_at      timestamp     NOT NULL
);
COMMENT ON TABLE payment IS 'Money movement related to a rental (deposit, fee, refund, damage fee).';

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
COMMENT ON TABLE employee IS 'Branch staff (technicians do maintenance).';

CREATE TABLE maintenance (
    maintenance_id   integer       PRIMARY KEY,
    drone_id         integer       NOT NULL REFERENCES drone,
    employee_id      integer       NOT NULL REFERENCES employee,
    maintenance_date date          NOT NULL,
    maintenance_type varchar(25)   NOT NULL,
    description      text          NOT NULL,
    cost             numeric(8,2)  NOT NULL,
    downtime_hours   numeric(5,1)  NOT NULL
);
COMMENT ON TABLE maintenance IS 'Service / repair record of a drone.';

CREATE TABLE flight_log (
    flight_id         integer      PRIMARY KEY,
    drone_id          integer      NOT NULL REFERENCES drone,
    rental_id         integer      REFERENCES rental,
    started_at        timestamp    NOT NULL,
    duration_min      smallint     NOT NULL,
    max_altitude_m    smallint     NOT NULL CHECK (max_altitude_m <= 120),
    distance_km       numeric(6,2) NOT NULL,
    battery_used_pct  smallint     NOT NULL CHECK (battery_used_pct BETWEEN 1 AND 100),
    incident_reported boolean      NOT NULL DEFAULT false
);
COMMENT ON TABLE flight_log IS 'Telemetry summary of one flight. rental_id is NULL for staff test flights.';

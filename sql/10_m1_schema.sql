-- =====================================================================
-- M1 - VERTICAL FRAGMENT 1: "Customers & Rentals" (PostgreSQL)
-- Runs in: m1_lt   (m1_lvee is later cloned from m1_lt)
--
--   classifiers (full copy): country, drone_category, drone_model
--   domain tables          : branch, customer, rental, payment
--   vertically split table : drone -> drone_commercial (this fragment)
--                                   + technical part   (M2, document DB)
--   link to M2             : drone_id, branch_id, rental_id (UUID)
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
    branch_id    uuid         PRIMARY KEY,
    name         varchar(80)  NOT NULL UNIQUE,
    city         varchar(60)  NOT NULL,
    country_code char(2)      NOT NULL REFERENCES country,
    address      varchar(120) NOT NULL,
    phone        varchar(20)  NOT NULL,
    email        varchar(120) NOT NULL,
    opened_on    date         NOT NULL
);
COMMENT ON TABLE branch IS 'Primary horizontal fragmentation by country_code (LT vs LV/EE). M2 refers to branch_id.';

CREATE TABLE customer (
    customer_id      integer      PRIMARY KEY,
    first_name       varchar(60)  NOT NULL,
    last_name        varchar(60)  NOT NULL,
    email            varchar(120) NOT NULL UNIQUE,
    phone            varchar(20)  NOT NULL,
    birth_date       date         NOT NULL,
    country_code     char(2)      NOT NULL REFERENCES country,
    home_branch_id   uuid         NOT NULL REFERENCES branch,
    pilot_license_no varchar(30)  NOT NULL UNIQUE,
    license_class    varchar(5)   NOT NULL CHECK (license_class IN ('A1/A3', 'A2', 'STS')),
    registered_at    timestamp    NOT NULL
);
COMMENT ON TABLE customer IS 'Derived horizontal fragmentation via home_branch_id -> branch.country_code.';

CREATE TABLE drone_commercial (
    drone_id       uuid          PRIMARY KEY,
    model_id       integer       NOT NULL REFERENCES drone_model,
    branch_id      uuid          NOT NULL REFERENCES branch,
    purchase_date  date          NOT NULL,
    purchase_price numeric(10,2) NOT NULL,
    daily_rate     numeric(8,2)  NOT NULL,
    deposit_amount numeric(8,2)  NOT NULL,
    status         varchar(12)   NOT NULL CHECK (status IN ('available', 'rented', 'maintenance', 'retired'))
);
COMMENT ON TABLE drone_commercial IS 'VERTICAL fragment of drone: commercial attributes. Linked to the M2 drone document by drone_id (UUID).';

CREATE TABLE rental (
    rental_id   uuid          PRIMARY KEY,
    customer_id integer       NOT NULL REFERENCES customer,
    drone_id    uuid          NOT NULL REFERENCES drone_commercial,
    branch_id   uuid          NOT NULL REFERENCES branch,
    start_date  date          NOT NULL,
    end_date    date          NOT NULL,
    total_price numeric(10,2) NOT NULL,
    status      varchar(10)   NOT NULL CHECK (status IN ('reserved', 'active', 'completed', 'cancelled')),
    CHECK (end_date >= start_date)
);
COMMENT ON TABLE rental IS 'Derived horizontal fragmentation via branch_id -> branch.country_code.';

CREATE TABLE payment (
    payment_id   integer       PRIMARY KEY,
    rental_id    uuid          NOT NULL REFERENCES rental,
    amount       numeric(10,2) NOT NULL CHECK (amount > 0),
    method       varchar(15)   NOT NULL CHECK (method IN ('card', 'bank_transfer', 'cash', 'paypal')),
    payment_type varchar(15)   NOT NULL CHECK (payment_type IN ('deposit', 'rental_fee', 'deposit_refund', 'damage_fee')),
    paid_at      timestamp     NOT NULL
);
COMMENT ON TABLE payment IS 'Derived horizontal fragmentation via rental -> branch.country_code.';

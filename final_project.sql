-- ============================================================
-- goit-rdb-fp: фінальний проєкт, датасет infectious_cases
-- ============================================================

-- ------------------------------------------------------------
-- 1. Схема та завантаження даних
-- ------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS pandemic;
SET search_path TO pandemic;

-- Сира таблиця. Усі показники беремо як TEXT, бо в CSV є порожні значення,
-- і безпечніше спочатку завантажити все як є, а приводити типи в запитах.
CREATE TABLE IF NOT EXISTS infectious_cases (
    Entity               TEXT,
    Code                 TEXT,
    Year                 INT,
    Number_yaws          TEXT,
    polio_cases          TEXT,
    cases_guinea_worm    TEXT,
    Number_rabies        TEXT,
    Number_malaria       TEXT,
    Number_hiv           TEXT,
    Number_tuberculosis  TEXT,
    Number_smallpox      TEXT,
    Number_cholera_cases TEXT
);

-- Імпорт CSV: тим самим способом, що й у HW3 (DBeaver -> Import Data
-- або psql):
-- \copy pandemic.infectious_cases FROM 'infectious_cases.csv' WITH (FORMAT csv, HEADER true)

-- Перегляд даних
SELECT * FROM infectious_cases LIMIT 10;
SELECT COUNT(*) FROM infectious_cases;


-- ------------------------------------------------------------
-- 2. Нормалізація до 3НФ
-- ------------------------------------------------------------
-- Таблиця 1: унікальні комбінації Entity + Code
CREATE TABLE IF NOT EXISTS entities (
    id     SERIAL PRIMARY KEY,
    entity TEXT NOT NULL,
    code   TEXT,
    UNIQUE (entity, code)
);

INSERT INTO entities (entity, code)
SELECT DISTINCT entity, code
FROM infectious_cases
ORDER BY entity;

-- Таблиця 2: показники захворювань, посилання на entities через id
CREATE TABLE IF NOT EXISTS infectious_cases_norm (
    id                   SERIAL PRIMARY KEY,
    entity_id            INT NOT NULL REFERENCES entities (id),
    year                 INT,
    number_yaws          TEXT,
    polio_cases          TEXT,
    cases_guinea_worm    TEXT,
    number_rabies        TEXT,
    number_malaria       TEXT,
    number_hiv           TEXT,
    number_tuberculosis  TEXT,
    number_smallpox      TEXT,
    number_cholera_cases TEXT
);

INSERT INTO infectious_cases_norm (
    entity_id, year, number_yaws, polio_cases, cases_guinea_worm,
    number_rabies, number_malaria, number_hiv, number_tuberculosis,
    number_smallpox, number_cholera_cases
)
SELECT
    e.id, ic.year, ic.number_yaws, ic.polio_cases, ic.cases_guinea_worm,
    ic.number_rabies, ic.number_malaria, ic.number_hiv, ic.number_tuberculosis,
    ic.number_smallpox, ic.number_cholera_cases
FROM infectious_cases ic
JOIN entities e
  ON e.entity = ic.entity
 AND e.code IS NOT DISTINCT FROM ic.code;

-- Перевірка: кількість рядків має збігатися з сирою таблицею
SELECT
    (SELECT COUNT(*) FROM infectious_cases)      AS raw_rows,
    (SELECT COUNT(*) FROM infectious_cases_norm) AS norm_rows;


-- ------------------------------------------------------------
-- 3. Аналіз Number_rabies
-- ------------------------------------------------------------
-- Беремо тільки числові значення (порожні та нечислові відсікає регулярний вираз)
SELECT
    e.id,
    e.entity,
    e.code,
    AVG(n.number_rabies::NUMERIC) AS avg_rabies,
    MIN(n.number_rabies::NUMERIC) AS min_rabies,
    MAX(n.number_rabies::NUMERIC) AS max_rabies,
    SUM(n.number_rabies::NUMERIC) AS sum_rabies
FROM infectious_cases_norm n
JOIN entities e ON e.id = n.entity_id
WHERE n.number_rabies ~ '^-?[0-9]+(\.[0-9]+)?$'
GROUP BY e.id, e.entity, e.code
ORDER BY avg_rabies DESC
LIMIT 10;


-- ------------------------------------------------------------
-- 4. Різниця в роках (вбудовані функції)
-- ------------------------------------------------------------
SELECT
    n.id,
    e.entity,
    n.year,
    MAKE_DATE(n.year, 1, 1)                                         AS year_start,
    CURRENT_DATE                                                    AS today,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(n.year, 1, 1)))::INT AS year_diff
FROM infectious_cases_norm n
JOIN entities e ON e.id = n.entity_id
WHERE n.year IS NOT NULL
ORDER BY n.id
LIMIT 20;


-- ------------------------------------------------------------
-- 5. Власні функції
-- ------------------------------------------------------------
-- 5.1 Різниця в роках між поточною датою та 1 січня заданого року
CREATE OR REPLACE FUNCTION pandemic.year_diff(p_year INT)
RETURNS INT
LANGUAGE SQL
STABLE
AS $$
    SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(p_year, 1, 1)))::INT;
$$;

-- 5.2 Середня кількість захворювань за період (кількість за рік / дільник)
CREATE OR REPLACE FUNCTION pandemic.avg_cases_per_period(p_cases NUMERIC, p_divisor NUMERIC)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT p_cases / NULLIF(p_divisor, 0);
$$;

-- Використання обох функцій в одному запиті.
-- Тільки записи з числовим значенням Number_rabies.
SELECT
    e.entity,
    n.year,
    pandemic.year_diff(n.year)                                          AS years_ago,
    n.number_rabies::NUMERIC                                            AS rabies_per_year,
    ROUND(pandemic.avg_cases_per_period(n.number_rabies::NUMERIC, 12), 2) AS avg_per_month,
    ROUND(pandemic.avg_cases_per_period(n.number_rabies::NUMERIC, 4), 2)  AS avg_per_quarter,
    ROUND(pandemic.avg_cases_per_period(n.number_rabies::NUMERIC, 2), 2)  AS avg_per_half_year
FROM infectious_cases_norm n
JOIN entities e ON e.id = n.entity_id
WHERE n.number_rabies ~ '^-?[0-9]+(\.[0-9]+)?$'
ORDER BY e.entity, n.year
LIMIT 20;

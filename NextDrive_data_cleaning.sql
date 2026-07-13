SELECT 
    COUNT_BIG(*) AS total_rows,

    COUNT(DISTINCT name) AS distinct_listing_names,

    MIN(TRY_CAST(price AS BIGINT)) AS min_price,
    MAX(TRY_CAST(price AS BIGINT)) AS max_price,
    AVG(TRY_CAST(price AS DECIMAL(18,2))) AS avg_price,

    MIN(TRY_CAST(yearOfRegistration AS INT)) AS min_registration_year,
    MAX(TRY_CAST(yearOfRegistration AS INT)) AS max_registration_year,

    MIN(TRY_CAST(kilometer AS BIGINT)) AS min_kilometer,
    MAX(TRY_CAST(kilometer AS BIGINT)) AS max_kilometer,
    AVG(TRY_CAST(kilometer AS DECIMAL(18,2))) AS avg_kilometer,

    MIN(TRY_CAST(powerPS AS BIGINT)) AS min_power,
    MAX(TRY_CAST(powerPS AS BIGINT)) AS max_power,
    AVG(TRY_CAST(powerPS AS DECIMAL(18,2))) AS avg_power

FROM raw_used_car_listings;

SELECT
    COUNT(*) AS invalid_price_count
FROM raw_used_car_listings
WHERE TRY_CAST(price AS BIGINT) <= 0
   OR TRY_CAST(price AS BIGINT) > 100000
   OR TRY_CAST(price AS BIGINT) IS NULL;

-- Check invalid registration year
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE 
            WHEN TRY_CAST(yearOfRegistration AS INT) < 1900 
              OR TRY_CAST(yearOfRegistration AS INT) > 2016
              OR TRY_CAST(yearOfRegistration AS INT) IS NULL
            THEN 1 ELSE 0 
        END) AS invalid_year_count
FROM raw_used_car_listings;

-- Check invalid powerPS
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE 
            WHEN TRY_CAST(powerPS  AS INT) < 30 
              OR TRY_CAST(powerPS AS INT) > 700
              OR TRY_CAST(powerPS  AS INT) IS NULL
            THEN 1 ELSE 0 
        END) AS invalid_power_count
FROM raw_used_car_listings;

-- Check missing value
SELECT
    COUNT(*) AS total_rows,

    SUM(CASE WHEN brand IS NULL OR brand = '' THEN 1 ELSE 0 END) AS missing_brand,
    SUM(CASE WHEN model IS NULL OR model = '' THEN 1 ELSE 0 END) AS missing_model,
    SUM(CASE WHEN vehicleType IS NULL OR vehicleType = '' THEN 1 ELSE 0 END) AS missing_vehicle_type,
    SUM(CASE WHEN gearbox IS NULL OR gearbox = '' THEN 1 ELSE 0 END) AS missing_gearbox,
    SUM(CASE WHEN fuelType IS NULL OR fuelType = '' THEN 1 ELSE 0 END) AS missing_fuel_type,
    SUM(CASE WHEN notRepairedDamage IS NULL OR notRepairedDamage = '' THEN 1 ELSE 0 END) AS missing_damage_status

FROM raw_used_car_listings;

-- Create clean datatable to seperate with raw data
SELECT
    ROW_NUMBER() OVER (ORDER BY dateCrawled, name) AS listing_id,

    TRY_CAST(dateCrawled AS DATETIME) AS date_crawled,
    TRY_CAST(dateCreated AS DATETIME) AS date_created,
    TRY_CAST(lastSeen AS DATETIME) AS last_seen,

    name,
    seller,
    offerType,

    TRY_CAST(price AS DECIMAL(18,2)) AS price,

    abtest,

    vehicleType AS vehicle_type,

    TRY_CAST(yearOfRegistration AS INT) AS registration_year,
    TRY_CAST(monthOfRegistration AS INT) AS registration_month,

    CASE
        WHEN gearbox = 'manuell' THEN 'Manual'
        WHEN gearbox = 'automatik' THEN 'Automatic'
        WHEN gearbox IS NULL OR gearbox = '' THEN 'Unknown'
        ELSE gearbox
    END AS gearbox,

    TRY_CAST(powerPS AS INT) AS power_ps,

    model,
    brand,

    TRY_CAST(kilometer AS INT) AS kilometer,

    CASE
        WHEN fuelType = 'benzin' THEN 'Petrol'
        WHEN fuelType = 'diesel' THEN 'Diesel'
        WHEN fuelType = 'lpg' THEN 'LPG'
        WHEN fuelType = 'cng' THEN 'CNG'
        WHEN fuelType = 'hybrid' THEN 'Hybrid'
        WHEN fuelType = 'elektro' THEN 'Electric'
        WHEN fuelType = 'andere' THEN 'Other'
        WHEN fuelType IS NULL OR fuelType = '' THEN 'Unknown'
        ELSE fuelType
    END AS fuel_type,

    CASE
        WHEN notRepairedDamage = 'ja' THEN 'Damaged'
        WHEN notRepairedDamage = 'nein' THEN 'No Damage'
        WHEN notRepairedDamage IS NULL OR notRepairedDamage = '' THEN 'Unknown'
        ELSE notRepairedDamage
    END AS damage_status,

    postalCode AS postal_code,
    TRY_CAST(Lattitude AS FLOAT) AS latitude,
    TRY_CAST(Longitude AS FLOAT) AS longitude

INTO clean_used_car_listings
FROM raw_used_car_listings
WHERE TRY_CAST(price AS DECIMAL(18,2)) BETWEEN 100 AND 100000
  AND TRY_CAST(yearOfRegistration AS INT) BETWEEN 1900 AND 2016
  AND TRY_CAST(powerPS AS INT) BETWEEN 30 AND 700
  AND TRY_CAST(dateCreated AS DATETIME) IS NOT NULL
  AND TRY_CAST(lastSeen AS DATETIME) IS NOT NULL
  AND DATEDIFF(
        DAY,
        TRY_CAST(dateCreated AS DATETIME),
        TRY_CAST(lastSeen AS DATETIME)
      ) >= 0;

-- Add calculated column --
--- Create vehicle age
ALTER TABLE clean_used_car_listings
ADD vehicle_age INT;

UPDATE clean_used_car_listings
SET vehicle_age = 2016 - registration_year;

--- Create listings days
ALTER TABLE clean_used_car_listings
ADD listing_days INT;

UPDATE clean_used_car_listings
SET listing_days = DATEDIFF(DAY, date_created, last_seen);

--- Create mileage band
ALTER TABLE clean_used_car_listings
ADD mileage_band VARCHAR(50);

UPDATE clean_used_car_listings
SET mileage_band =
    CASE
        WHEN kilometer < 50000 THEN 'Under 50K'
        WHEN kilometer >= 50000 AND kilometer < 100000 THEN '50K-100K'
        WHEN kilometer >= 100000 AND kilometer < 150000 THEN '100K-150K'
        ELSE '150K+'
    END;

--- Create power band
ALTER TABLE clean_used_car_listings
ADD power_band VARCHAR(50);

UPDATE clean_used_car_listings
SET power_band =
    CASE
        WHEN power_ps < 75 THEN 'Low Power'
        WHEN power_ps >= 75 AND power_ps < 150 THEN 'Standard'
        WHEN power_ps >= 150 AND power_ps < 250 THEN 'Performance'
        ELSE 'High Performance'
    END;

--- Create inventory speed segment
ALTER TABLE clean_used_car_listings
ADD inventory_speed_segment VARCHAR(50);

UPDATE clean_used_car_listings
SET inventory_speed_segment =
    CASE
        WHEN listing_days < 7 THEN 'Fast Moving'
        WHEN listing_days >= 7 AND listing_days <= 30 THEN 'Normal'
        WHEN listing_days > 30 THEN 'Slow Moving'
        ELSE 'Unknown'
    END;

--- Create inventory risk segment
ALTER TABLE clean_used_car_listings
ADD inventory_risk_segment VARCHAR(50);

UPDATE clean_used_car_listings
SET inventory_risk_segment =
    CASE
        WHEN listing_days > 30 AND kilometer >= 150000 THEN 'High Risk'
        WHEN listing_days > 30 THEN 'Slow Moving Risk'
        WHEN kilometer >= 150000 THEN 'High Mileage Risk'
        ELSE 'Normal'
    END;

--- Check clean table
SELECT
    COUNT(*) AS clean_total_rows,

    MIN(price) AS min_price,
    MAX(price) AS max_price,
    AVG(price) AS avg_price,

    MIN(registration_year) AS min_registration_year,
    MAX(registration_year) AS max_registration_year,

    MIN(power_ps) AS min_power_ps,
    MAX(power_ps) AS max_power_ps,

    MIN(vehicle_age) AS min_vehicle_age,
    MAX(vehicle_age) AS max_vehicle_age,

    MIN(listing_days) AS min_listing_days,
    MAX(listing_days) AS max_listing_days,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS avg_listing_days

FROM clean_used_car_listings;

-- Before heading to PowerBI, I want to run some query to further understand about data and get some insights --
--- Market overview
SELECT DISTINCT
    COUNT(*) OVER () AS total_listings,
    AVG(price) OVER () AS average_price,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) OVER () AS median_price,
    AVG(CAST(kilometer AS DECIMAL(18,2))) OVER () AS average_mileage,
    AVG(CAST(vehicle_age AS DECIMAL(18,2))) OVER () AS average_vehicle_age,
    AVG(CAST(listing_days AS DECIMAL(18,2))) OVER () AS average_listing_days
FROM clean_used_car_listings;

--- Top brands by listing volumn
SELECT TOP 10
    brand,
    COUNT(*) AS total_listings,
    AVG(price) AS average_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM clean_used_car_listings
WHERE brand IS NOT NULL
GROUP BY brand
ORDER BY total_listings DESC;

--- Top models by listing volume
SELECT TOP 10
    brand,
    model,
    COUNT(*) AS total_listings,
    AVG(price) AS average_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM clean_used_car_listings
WHERE model IS NOT NULL
GROUP BY brand, model
ORDER BY total_listings DESC;

--- Average price by vehicle age
SELECT
    vehicle_age,
    COUNT(*) AS total_listings,
    AVG(price) AS average_price
FROM clean_used_car_listings
GROUP BY vehicle_age
ORDER BY vehicle_age;

--- Average price by mileage band
SELECT
    mileage_band,
    COUNT(*) AS total_listings,
    AVG(price) AS average_price
FROM clean_used_car_listings
GROUP BY mileage_band
ORDER BY
    CASE mileage_band
        WHEN 'Under 50K' THEN 1
        WHEN '50K-100K' THEN 2
        WHEN '100K-150K' THEN 3
        WHEN '150K+' THEN 4
    END;

--- Damage penalty
SELECT
    damage_status,
    COUNT(*) AS total_listings,
    AVG(price) AS average_price
FROM clean_used_car_listings
GROUP BY damage_status
ORDER BY average_price DESC;

WITH damage_price AS (
    SELECT
        damage_status,
        AVG(price) AS avg_price
    FROM clean_used_car_listings
    WHERE damage_status IN ('Damaged', 'No Damage')
    GROUP BY damage_status
)
SELECT
    MAX(CASE WHEN damage_status = 'No Damage' THEN avg_price END) AS no_damage_avg_price,
    MAX(CASE WHEN damage_status = 'Damaged' THEN avg_price END) AS damaged_avg_price,
    (
        MAX(CASE WHEN damage_status = 'No Damage' THEN avg_price END)
        -
        MAX(CASE WHEN damage_status = 'Damaged' THEN avg_price END)
    )
    /
    MAX(CASE WHEN damage_status = 'No Damage' THEN avg_price END) * 100 AS damage_penalty_percent
FROM damage_price;

--- Gearbox premium
WITH gearbox_price AS (
    SELECT
        gearbox,
        AVG(price) AS avg_price
    FROM clean_used_car_listings
    WHERE gearbox IN ('Automatic', 'Manual')
    GROUP BY gearbox
)
SELECT
    MAX(CASE WHEN gearbox = 'Automatic' THEN avg_price END) AS automatic_avg_price,
    MAX(CASE WHEN gearbox = 'Manual' THEN avg_price END) AS manual_avg_price,
    (
        MAX(CASE WHEN gearbox = 'Automatic' THEN avg_price END)
        -
        MAX(CASE WHEN gearbox = 'Manual' THEN avg_price END)
    )
    /
    MAX(CASE WHEN gearbox = 'Manual' THEN avg_price END) * 100 AS gearbox_premium_percent
FROM gearbox_price;

--- Inventory speed breakdown
SELECT
    inventory_speed_segment,
    COUNT(*) AS total_listings,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS listing_share_percent,
    AVG(price) AS average_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM clean_used_car_listings
GROUP BY inventory_speed_segment
ORDER BY total_listings DESC;

--- Slow-moving models
SELECT TOP 10
    brand,
    model,
    COUNT(*) AS total_listings,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days,
    AVG(price) AS average_price,
    AVG(CAST(kilometer AS DECIMAL(18,2))) AS average_mileage
FROM clean_used_car_listings
WHERE model IS NOT NULL
GROUP BY brand, model
HAVING COUNT(*) >= 100
ORDER BY average_listing_days DESC;

--- Fast-moving models
SELECT TOP 10
    brand,
    model,
    COUNT(*) AS total_listings,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days,
    AVG(price) AS average_price,
    AVG(CAST(kilometer AS DECIMAL(18,2))) AS average_mileage
FROM clean_used_car_listings
WHERE model IS NOT NULL
GROUP BY brand, model
HAVING COUNT(*) >= 100
ORDER BY average_listing_days ASC;

-- Create underprice opportunity -- 
--- Create percentile table according to brand / model
SELECT DISTINCT
    brand,
    model,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY price)
        OVER (PARTITION BY brand, model) AS model_price_p25,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price)
        OVER (PARTITION BY brand, model) AS model_price_median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY price)
        OVER (PARTITION BY brand, model) AS model_price_p75
INTO model_price_percentiles
FROM clean_used_car_listings
WHERE brand IS NOT NULL
  AND model IS NOT NULL;

--- create procurement opportunity
SELECT
    c.listing_id,
    c.brand,
    c.model,
    c.registration_year,
    c.vehicle_age,
    c.kilometer,
    c.mileage_band,
    c.gearbox,
    c.fuel_type,
    c.damage_status,
    c.power_ps,
    c.price,
    p.model_price_p25,
    p.model_price_median,
    p.model_price_p75,
    c.listing_days,
    c.inventory_speed_segment,
    c.inventory_risk_segment,

    CASE
        WHEN c.registration_year >= 2003
         AND c.damage_status = 'No Damage'
         AND c.kilometer < 150000
         AND c.price < p.model_price_p25
        THEN 'Underpriced Opportunity'
        ELSE 'Normal'
    END AS underpriced_flag

INTO procurement_opportunity_list
FROM clean_used_car_listings c
LEFT JOIN model_price_percentiles p
    ON c.brand = p.brand
   AND c.model = p.model;

--- Check number of underpriced vehicles
SELECT
    underpriced_flag,
    COUNT(*) AS total_listings,
    AVG(price) AS average_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM procurement_opportunity_list
GROUP BY underpriced_flag;

SELECT
    COUNT(*) AS total_clean_rows,
    SUM(CASE WHEN underpriced_flag = 'Underpriced Opportunity' THEN 1 ELSE 0 END) AS underpriced_count,
    AVG(price) AS avg_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS avg_listing_days
FROM procurement_opportunity_list;
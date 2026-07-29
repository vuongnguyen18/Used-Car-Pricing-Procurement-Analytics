/*==============================================================================
 Project: Used-Car Pricing & Procurement Analytics
 Platform: Microsoft SQL Server
 Purpose : Data profiling, cleaning, feature engineering, market analysis,
           and year-aware procurement opportunity identification.

 Notes:
 - One row represents one vehicle listing, not a completed sale.
 - Listing price is the seller's asking price.
 - Listing days is used as a proxy for inventory liquidity.
 - The source dataset ends in 2016, so vehicle age is calculated relative to 2016.
==============================================================================*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

-------------------------------------------------------------------------------
-- 0. OPTIONAL CLEAN-UP FOR RE-RUNNING THE SCRIPT
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS dbo.procurement_opportunity_list;
DROP TABLE IF EXISTS dbo.model_price_percentiles;
DROP TABLE IF EXISTS dbo.clean_used_car_listings;
GO

-------------------------------------------------------------------------------
-- 1. RAW DATA PROFILING
-------------------------------------------------------------------------------
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
    MIN(TRY_CAST(powerPS AS BIGINT)) AS min_power_ps,
    MAX(TRY_CAST(powerPS AS BIGINT)) AS max_power_ps,
    AVG(TRY_CAST(powerPS AS DECIMAL(18,2))) AS avg_power_ps
FROM dbo.raw_used_car_listings;

SELECT
    COUNT_BIG(*) AS total_rows,
    SUM(CASE
            WHEN TRY_CAST(price AS DECIMAL(18,2)) IS NULL
              OR TRY_CAST(price AS DECIMAL(18,2)) < 100
              OR TRY_CAST(price AS DECIMAL(18,2)) > 100000
            THEN 1 ELSE 0
        END) AS invalid_price_count
FROM dbo.raw_used_car_listings;

SELECT
    COUNT_BIG(*) AS total_rows,
    SUM(CASE
            WHEN TRY_CAST(yearOfRegistration AS INT) IS NULL
              OR TRY_CAST(yearOfRegistration AS INT) < 1900
              OR TRY_CAST(yearOfRegistration AS INT) > 2016
            THEN 1 ELSE 0
        END) AS invalid_registration_year_count
FROM dbo.raw_used_car_listings;

SELECT
    COUNT_BIG(*) AS total_rows,
    SUM(CASE
            WHEN TRY_CAST(powerPS AS INT) IS NULL
              OR TRY_CAST(powerPS AS INT) < 30
              OR TRY_CAST(powerPS AS INT) > 700
            THEN 1 ELSE 0
        END) AS invalid_power_count
FROM dbo.raw_used_car_listings;

SELECT
    COUNT_BIG(*) AS total_rows,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(brand)), '') IS NULL THEN 1 ELSE 0 END) AS missing_brand,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(model)), '') IS NULL THEN 1 ELSE 0 END) AS missing_model,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(vehicleType)), '') IS NULL THEN 1 ELSE 0 END) AS missing_vehicle_type,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(gearbox)), '') IS NULL THEN 1 ELSE 0 END) AS missing_gearbox,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(fuelType)), '') IS NULL THEN 1 ELSE 0 END) AS missing_fuel_type,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(notRepairedDamage)), '') IS NULL THEN 1 ELSE 0 END) AS missing_damage_status
FROM dbo.raw_used_car_listings;

-------------------------------------------------------------------------------
-- 2. CLEANING AND FEATURE ENGINEERING
--    Derived fields are created inline to avoid repeated ALTER/UPDATE scans.
-------------------------------------------------------------------------------
;WITH typed_source AS
(
    SELECT
        TRY_CAST(dateCrawled AS DATETIME2(0)) AS date_crawled,
        TRY_CAST(dateCreated AS DATETIME2(0)) AS date_created,
        TRY_CAST(lastSeen AS DATETIME2(0)) AS last_seen,
        NULLIF(LTRIM(RTRIM(name)), '') AS name,
        NULLIF(LTRIM(RTRIM(seller)), '') AS seller,
        NULLIF(LTRIM(RTRIM(offerType)), '') AS offer_type,
        TRY_CAST(price AS DECIMAL(18,2)) AS price,
        NULLIF(LTRIM(RTRIM(abtest)), '') AS abtest,
        NULLIF(LTRIM(RTRIM(vehicleType)), '') AS vehicle_type,
        TRY_CAST(yearOfRegistration AS INT) AS registration_year,
        TRY_CAST(monthOfRegistration AS INT) AS registration_month,
        NULLIF(LTRIM(RTRIM(gearbox)), '') AS gearbox_raw,
        TRY_CAST(powerPS AS INT) AS power_ps,
        NULLIF(LTRIM(RTRIM(model)), '') AS model,
        NULLIF(LTRIM(RTRIM(brand)), '') AS brand,
        TRY_CAST(kilometer AS INT) AS kilometer,
        NULLIF(LTRIM(RTRIM(fuelType)), '') AS fuel_type_raw,
        NULLIF(LTRIM(RTRIM(notRepairedDamage)), '') AS damage_status_raw,
        TRY_CAST(postalCode AS INT) AS postal_code,
        TRY_CAST(Lattitude AS FLOAT) AS latitude,
        TRY_CAST(Longitude AS FLOAT) AS longitude
    FROM dbo.raw_used_car_listings
),
valid_source AS
(
    SELECT *, DATEDIFF(DAY, date_created, last_seen) AS listing_days
    FROM typed_source
    WHERE price BETWEEN 100 AND 100000
      AND registration_year BETWEEN 1900 AND 2016
      AND power_ps BETWEEN 30 AND 700
      AND date_created IS NOT NULL
      AND last_seen IS NOT NULL
      AND DATEDIFF(DAY, date_created, last_seen) >= 0
)
SELECT
    ROW_NUMBER() OVER
    (
        ORDER BY date_crawled, name, price, registration_year, postal_code
    ) AS listing_id,
    date_crawled,
    date_created,
    last_seen,
    name,
    seller,
    offer_type,
    price,
    abtest,
    vehicle_type,
    registration_year,
    registration_month,
    CASE
        WHEN gearbox_raw = 'manuell' THEN 'Manual'
        WHEN gearbox_raw = 'automatik' THEN 'Automatic'
        WHEN gearbox_raw IS NULL THEN 'Unknown'
        ELSE gearbox_raw
    END AS gearbox,
    power_ps,
    model,
    brand,
    kilometer,
    CASE
        WHEN fuel_type_raw = 'benzin' THEN 'Petrol'
        WHEN fuel_type_raw = 'diesel' THEN 'Diesel'
        WHEN fuel_type_raw = 'lpg' THEN 'LPG'
        WHEN fuel_type_raw = 'cng' THEN 'CNG'
        WHEN fuel_type_raw = 'hybrid' THEN 'Hybrid'
        WHEN fuel_type_raw = 'elektro' THEN 'Electric'
        WHEN fuel_type_raw = 'andere' THEN 'Other'
        WHEN fuel_type_raw IS NULL THEN 'Unknown'
        ELSE fuel_type_raw
    END AS fuel_type,
    CASE
        WHEN damage_status_raw = 'ja' THEN 'Damaged'
        WHEN damage_status_raw = 'nein' THEN 'No Damage'
        WHEN damage_status_raw IS NULL THEN 'Unknown'
        ELSE damage_status_raw
    END AS damage_status,
    postal_code,
    latitude,
    longitude,
    2016 - registration_year AS vehicle_age,
    listing_days,
    CASE
        WHEN kilometer < 50000 THEN 'Under 50K'
        WHEN kilometer < 100000 THEN '50K-100K'
        WHEN kilometer < 150000 THEN '100K-150K'
        ELSE '150K+'
    END AS mileage_band,
    CASE
        WHEN kilometer < 50000 THEN 1
        WHEN kilometer < 100000 THEN 2
        WHEN kilometer < 150000 THEN 3
        ELSE 4
    END AS mileage_band_sort,
    CASE
        WHEN power_ps < 75 THEN 'Low Power'
        WHEN power_ps < 150 THEN 'Standard'
        WHEN power_ps < 250 THEN 'Performance'
        ELSE 'High Performance'
    END AS power_band,
    CASE
        WHEN listing_days < 7 THEN 'Fast Moving'
        WHEN listing_days <= 30 THEN 'Normal'
        ELSE 'Slow Moving'
    END AS inventory_speed_segment,
    CASE
        WHEN listing_days > 30 AND kilometer >= 150000 THEN 'High Risk'
        WHEN listing_days > 30 THEN 'Slow Moving Risk'
        WHEN kilometer >= 150000 THEN 'High Mileage Risk'
        ELSE 'Normal'
    END AS inventory_risk_segment
INTO dbo.clean_used_car_listings
FROM valid_source;
GO

-------------------------------------------------------------------------------
-- 3. INDEXES
-------------------------------------------------------------------------------
CREATE UNIQUE CLUSTERED INDEX IX_clean_used_car_listings_listing_id
    ON dbo.clean_used_car_listings (listing_id);

CREATE NONCLUSTERED INDEX IX_clean_used_car_listings_market_peer
    ON dbo.clean_used_car_listings (brand, model, registration_year)
    INCLUDE (price, kilometer, listing_days, damage_status);

-------------------------------------------------------------------------------
-- 4. CLEAN DATA VALIDATION
-------------------------------------------------------------------------------
SELECT
    COUNT_BIG(*) AS clean_total_rows,
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
FROM dbo.clean_used_car_listings;

-------------------------------------------------------------------------------
-- 5. EXPLORATORY BUSINESS QUERIES
-------------------------------------------------------------------------------
SELECT
    COUNT_BIG(*) AS total_listings,
    AVG(price) AS average_price,
    AVG(CAST(kilometer AS DECIMAL(18,2))) AS average_mileage,
    AVG(CAST(vehicle_age AS DECIMAL(18,2))) AS average_vehicle_age,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM dbo.clean_used_car_listings;

SELECT TOP (1)
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) OVER () AS median_price
FROM dbo.clean_used_car_listings;

SELECT TOP (10)
    brand,
    COUNT_BIG(*) AS total_listings,
    AVG(price) AS average_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM dbo.clean_used_car_listings
WHERE brand IS NOT NULL
GROUP BY brand
ORDER BY total_listings DESC;

SELECT TOP (10)
    brand,
    model,
    COUNT_BIG(*) AS total_listings,
    AVG(price) AS average_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM dbo.clean_used_car_listings
WHERE brand IS NOT NULL AND model IS NOT NULL
GROUP BY brand, model
ORDER BY total_listings DESC;

SELECT
    vehicle_age,
    COUNT_BIG(*) AS total_listings,
    AVG(price) AS average_price
FROM dbo.clean_used_car_listings
GROUP BY vehicle_age
ORDER BY vehicle_age;

SELECT
    mileage_band,
    MIN(mileage_band_sort) AS mileage_band_sort,
    COUNT_BIG(*) AS total_listings,
    AVG(price) AS average_price
FROM dbo.clean_used_car_listings
GROUP BY mileage_band
ORDER BY mileage_band_sort;

WITH damage_price AS
(
    SELECT damage_status, AVG(price) AS avg_price
    FROM dbo.clean_used_car_listings
    WHERE damage_status IN ('Damaged', 'No Damage')
    GROUP BY damage_status
)
SELECT
    MAX(CASE WHEN damage_status = 'No Damage' THEN avg_price END) AS no_damage_avg_price,
    MAX(CASE WHEN damage_status = 'Damaged' THEN avg_price END) AS damaged_avg_price,
    (
        MAX(CASE WHEN damage_status = 'No Damage' THEN avg_price END)
        - MAX(CASE WHEN damage_status = 'Damaged' THEN avg_price END)
    ) / NULLIF(MAX(CASE WHEN damage_status = 'No Damage' THEN avg_price END), 0)
      * 100.0 AS damage_penalty_percent
FROM damage_price;

WITH gearbox_price AS
(
    SELECT gearbox, AVG(price) AS avg_price
    FROM dbo.clean_used_car_listings
    WHERE gearbox IN ('Automatic', 'Manual')
    GROUP BY gearbox
)
SELECT
    MAX(CASE WHEN gearbox = 'Automatic' THEN avg_price END) AS automatic_avg_price,
    MAX(CASE WHEN gearbox = 'Manual' THEN avg_price END) AS manual_avg_price,
    (
        MAX(CASE WHEN gearbox = 'Automatic' THEN avg_price END)
        - MAX(CASE WHEN gearbox = 'Manual' THEN avg_price END)
    ) / NULLIF(MAX(CASE WHEN gearbox = 'Manual' THEN avg_price END), 0)
      * 100.0 AS gearbox_premium_percent
FROM gearbox_price;

SELECT
    inventory_speed_segment,
    COUNT_BIG(*) AS total_listings,
    COUNT_BIG(*) * 100.0 / SUM(COUNT_BIG(*)) OVER () AS listing_share_percent,
    AVG(price) AS average_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM dbo.clean_used_car_listings
GROUP BY inventory_speed_segment
ORDER BY total_listings DESC;

SELECT TOP (10)
    brand,
    model,
    COUNT_BIG(*) AS total_listings,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days,
    AVG(price) AS average_price,
    AVG(CAST(kilometer AS DECIMAL(18,2))) AS average_mileage
FROM dbo.clean_used_car_listings
WHERE brand IS NOT NULL AND model IS NOT NULL
GROUP BY brand, model
HAVING COUNT_BIG(*) >= 100
ORDER BY average_listing_days DESC;

SELECT TOP (10)
    brand,
    model,
    COUNT_BIG(*) AS total_listings,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days,
    AVG(price) AS average_price,
    AVG(CAST(kilometer AS DECIMAL(18,2))) AS average_mileage
FROM dbo.clean_used_car_listings
WHERE brand IS NOT NULL AND model IS NOT NULL
GROUP BY brand, model
HAVING COUNT_BIG(*) >= 100
ORDER BY average_listing_days ASC;

-------------------------------------------------------------------------------
-- 6. YEAR-AWARE PRICE PERCENTILES
-------------------------------------------------------------------------------
;WITH percentile_source AS
(
    SELECT
        brand,
        model,
        registration_year,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY price)
            OVER (PARTITION BY brand, model, registration_year) AS model_price_p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY price)
            OVER (PARTITION BY brand, model, registration_year) AS model_price_median,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY price)
            OVER (PARTITION BY brand, model, registration_year) AS model_price_p75,
        COUNT_BIG(*) OVER
            (PARTITION BY brand, model, registration_year) AS peer_group_size,
        ROW_NUMBER() OVER
        (
            PARTITION BY brand, model, registration_year
            ORDER BY brand, model, registration_year
        ) AS peer_row_number
    FROM dbo.clean_used_car_listings
    WHERE brand IS NOT NULL AND model IS NOT NULL
)
SELECT
    brand,
    model,
    registration_year,
    CAST(model_price_p25 AS DECIMAL(18,2)) AS model_price_p25,
    CAST(model_price_median AS DECIMAL(18,2)) AS model_price_median,
    CAST(model_price_p75 AS DECIMAL(18,2)) AS model_price_p75,
    peer_group_size
INTO dbo.model_price_percentiles
FROM percentile_source
WHERE peer_row_number = 1;
GO

CREATE UNIQUE CLUSTERED INDEX IX_model_price_percentiles_peer
    ON dbo.model_price_percentiles (brand, model, registration_year);
GO

-------------------------------------------------------------------------------
-- 7. PROCUREMENT OPPORTUNITY TABLE
-------------------------------------------------------------------------------
SELECT
    c.listing_id,
    c.brand,
    c.model,
    c.registration_year,
    c.vehicle_age,
    c.kilometer,
    c.mileage_band,
    c.mileage_band_sort,
    c.gearbox,
    c.fuel_type,
    c.damage_status,
    c.power_ps,
    c.power_band,
    c.price,
    p.model_price_p25,
    p.model_price_median,
    p.model_price_p75,
    p.peer_group_size,
    c.listing_days,
    c.inventory_speed_segment,
    c.inventory_risk_segment,
    CASE
        WHEN c.registration_year >= 2003
         AND c.damage_status = 'No Damage'
         AND c.kilometer < 150000
         AND p.model_price_p25 IS NOT NULL
         AND c.price < p.model_price_p25
        THEN 'Underpriced Opportunity'
        ELSE 'Normal'
    END AS underpriced_flag,
    CASE
        WHEN p.model_price_median IS NULL OR p.model_price_median = 0 THEN NULL
        ELSE (p.model_price_median - c.price) / p.model_price_median * 100.0
    END AS discount_to_median_percent,
    CONCAT(c.brand, ' | ', c.model) AS brand_model_key
INTO dbo.procurement_opportunity_list
FROM dbo.clean_used_car_listings AS c
LEFT JOIN dbo.model_price_percentiles AS p
    ON c.brand = p.brand
   AND c.model = p.model
   AND c.registration_year = p.registration_year;
GO

CREATE UNIQUE CLUSTERED INDEX IX_procurement_opportunity_list_listing_id
    ON dbo.procurement_opportunity_list (listing_id);

CREATE NONCLUSTERED INDEX IX_procurement_opportunity_list_flag
    ON dbo.procurement_opportunity_list (underpriced_flag)
    INCLUDE (brand, model, registration_year, price, model_price_median, listing_days);

-------------------------------------------------------------------------------
-- 8. FINAL VALIDATION
-------------------------------------------------------------------------------
SELECT
    underpriced_flag,
    COUNT_BIG(*) AS total_listings,
    AVG(price) AS average_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM dbo.procurement_opportunity_list
GROUP BY underpriced_flag;

SELECT
    COUNT_BIG(*) AS total_clean_rows,
    SUM(CASE WHEN underpriced_flag = 'Underpriced Opportunity' THEN 1 ELSE 0 END) AS underpriced_count,
    AVG(price) AS average_price,
    AVG(CAST(listing_days AS DECIMAL(18,2))) AS average_listing_days
FROM dbo.procurement_opportunity_list;

SELECT
    COUNT_BIG(*) AS listings_without_percentile_benchmark
FROM dbo.procurement_opportunity_list
WHERE model_price_median IS NULL;
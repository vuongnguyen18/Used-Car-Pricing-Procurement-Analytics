# SQL Data Cleaning and Transformation Documentation

## Project: Used-Car Inventory Optimisation & Pricing Analytics

## 1. Purpose of SQL Processing

The purpose of the SQL stage was to convert raw used-car listing data into a clean and analysis-ready dataset for Power BI reporting.

The original dataset was collected from online used-car marketplaces, meaning it contained common issues found in web-crawled data such as invalid prices, unrealistic registration years, incorrect engine power values, missing vehicle attributes, inconsistent German category labels, and abnormal listing dates.

Since the project focuses on used-car procurement, inventory optimisation, and pricing strategy, the SQL process was designed to make sure the final dataset could support reliable business analysis.

The main SQL objectives were:

```text
1. Profile the raw dataset
2. Identify data quality issues
3. Remove invalid or unrealistic records
4. Standardise category values
5. Create business-ready fields
6. Segment vehicles by mileage, power, inventory speed, and risk
7. Create a procurement opportunity flag for underpriced vehicles
```

This step is important because the project requires more than simply loading a CSV file into Power BI. The goal is to demonstrate a real analyst workflow: data validation, cleaning, metric preparation, and business logic creation before dashboard development.

---

## 2. Raw Data Understanding

Each row in the dataset represents one used-car listing from an online marketplace.

The raw dataset contains vehicle, listing, pricing, technical, condition, and location information.

| Column | Meaning | Business Use |
|---|---|---|
| `price` | Listed vehicle price in Euro | Pricing analysis and procurement decision |
| `brand` | Vehicle brand | Brand demand and market share |
| `model` | Vehicle model | Model-level pricing and opportunity detection |
| `yearOfRegistration` | First registration year | Vehicle age and depreciation analysis |
| `kilometer` | Mileage | Usage level and pricing impact |
| `gearbox` | Manual or automatic transmission | Gearbox price premium |
| `fuelType` | Fuel category | Technical price driver |
| `powerPS` | Engine power | Performance segment and price relationship |
| `notRepairedDamage` | Whether the vehicle has unrepaired damage | Damage penalty and quality filter |
| `dateCreated` | Listing creation date | Listing duration |
| `lastSeen` | Last time the listing was seen | Liquidity proxy |
| `abtest` | Test/control group | Platform experiment behaviour |
| `Lattitude`, `Longitude` | Location coordinates | Geographic market activity |

The dataset is **listing data**, not confirmed transaction data. Therefore, the project does not treat `price` as actual sales revenue. Instead, it is treated as **listed market price**.

Similarly, the project does not have confirmed sale dates. Therefore, the time between `dateCreated` and `lastSeen` is used as a **proxy for market liquidity**, not as a confirmed sale duration.

---

## 3. SQL Data Profiling

Before cleaning the dataset, SQL profiling was performed to understand the raw data quality.

The profiling process checked:

```text
- Total row count
- Minimum and maximum price
- Invalid price values
- Invalid registration years
- Invalid engine power values
- Missing categorical fields
- Listing date issues
```

### 3.1 Invalid Price Check

The first major data quality issue was invalid or unrealistic vehicle prices.

During SQL profiling, **11,181 invalid price records** were identified. These records included prices that were zero, negative, missing, or above the business threshold.

These records were removed because price is the most important field in this project. It is used for:

```text
- Average price
- Median price
- Depreciation analysis
- Mileage impact analysis
- Damage penalty calculation
- Gearbox premium calculation
- Model-level price percentile
- Underpriced vehicle detection
```

If invalid prices were kept, they would distort the pricing analysis and make the procurement matrix unreliable.

### 3.2 Arithmetic Overflow Issue

During the initial SQL profiling stage, an arithmetic overflow error occurred when calculating aggregate values such as `AVG(price)`.

This happened because some raw price values were extremely large and the `price` field was being aggregated as an integer. To prevent this issue, numeric fields were converted using `TRY_CAST()` and larger numeric data types such as `BIGINT` and `DECIMAL(18,2)`.

This helped prevent aggregation errors and also revealed that the dataset contained extreme outliers.

Example logic:

```sql
AVG(TRY_CAST(price AS DECIMAL(18,2))) AS avg_price
```

This step shows that the raw dataset required proper validation before business metrics could be trusted.

---

## 4. Cleaning Rules Applied

The cleaned dataset was created from the raw table using several business rules.

### 4.1 Price Cleaning

Only vehicles with realistic listed prices were kept.

```sql
WHERE TRY_CAST(price AS DECIMAL(18,2)) BETWEEN 100 AND 100000
```

#### Why this rule was used

Vehicles with a price of 0 or extremely unrealistic prices are not useful for pricing analysis. A zero price may represent missing information, placeholder values, or incorrectly entered listings.

The upper threshold of €100,000 was used to remove extreme luxury or incorrectly entered values that could distort average price and market value calculations.

#### Business reason

The project focuses on normal used-car procurement decisions. Keeping extreme outliers would reduce the usefulness of the pricing matrix for the buying team.

---

### 4.2 Registration Year Cleaning

Only vehicles registered between 1900 and 2016 were kept.

```sql
WHERE TRY_CAST(yearOfRegistration AS INT) BETWEEN 1900 AND 2016
```

#### Why this rule was used

The dataset was crawled in 2016. Therefore, a vehicle with a registration year after 2016 is not realistic for this dataset.

Very old registration years below 1900 were also removed because they are likely data entry errors or irrelevant outliers.

#### Business reason

Registration year is used to calculate vehicle age and depreciation. Invalid years would create incorrect vehicle age values and distort depreciation analysis.

---

### 4.3 Engine Power Cleaning

Only vehicles with engine power between 30 and 700 PS were kept.

```sql
WHERE TRY_CAST(powerPS AS INT) BETWEEN 30 AND 700
```

#### Why this rule was used

A `powerPS` value of 0 usually indicates missing or incorrectly entered data. Extremely high values may also represent data entry errors.

The 30–700 PS range was selected as a practical business range for normal used-car market analysis.

#### Business reason

Engine power is used to analyse the relationship between vehicle performance and price. Invalid power values would distort the Power vs Price analysis and power segment classification.

---

### 4.4 Date Cleaning

Records were kept only when both listing dates were valid and listing duration was not negative.

```sql
AND TRY_CAST(dateCreated AS DATETIME) IS NOT NULL
AND TRY_CAST(lastSeen AS DATETIME) IS NOT NULL
AND DATEDIFF(DAY, TRY_CAST(dateCreated AS DATETIME), TRY_CAST(lastSeen AS DATETIME)) >= 0
```

#### Why this rule was used

The project uses listing duration as a proxy for market liquidity. If `dateCreated` or `lastSeen` is missing, listing duration cannot be calculated.

Negative listing duration is logically invalid because a listing cannot be last seen before it was created.

#### Business reason

Listing duration is used to identify fast-moving and slow-moving inventory. Invalid dates would create misleading inventory liquidity insights.

---

## 5. Standardising Category Labels

The dataset contains several German category values. These were standardised into English labels to make the Power BI dashboard clearer and more professional.

### 5.1 Gearbox Standardisation

Original values:

```text
manuell
automatik
```

Cleaned values:

```text
Manual
Automatic
Unknown
```

SQL logic:

```sql
CASE
    WHEN gearbox = 'manuell' THEN 'Manual'
    WHEN gearbox = 'automatik' THEN 'Automatic'
    WHEN gearbox IS NULL OR gearbox = '' THEN 'Unknown'
    ELSE gearbox
END AS gearbox
```

#### Why this was done

Standardising the labels makes dashboard visuals easier to read and supports clearer business communication.

---

### 5.2 Fuel Type Standardisation

Original values such as `benzin`, `diesel`, `elektro`, and `andere` were converted into English labels.

| Original Value | Cleaned Value |
|---|---|
| `benzin` | Petrol |
| `diesel` | Diesel |
| `lpg` | LPG |
| `cng` | CNG |
| `hybrid` | Hybrid |
| `elektro` | Electric |
| `andere` | Other |
| blank/null | Unknown |

#### Why this was done

Fuel type is used as a pricing and technical specification driver. Clean category labels help users understand the dashboard without needing to know the original German terms.

---

### 5.3 Damage Status Standardisation

Original values:

```text
ja
nein
```

Cleaned values:

```text
Damaged
No Damage
Unknown
```

SQL logic:

```sql
CASE
    WHEN notRepairedDamage = 'ja' THEN 'Damaged'
    WHEN notRepairedDamage = 'nein' THEN 'No Damage'
    WHEN notRepairedDamage IS NULL OR notRepairedDamage = '' THEN 'Unknown'
    ELSE notRepairedDamage
END AS damage_status
```

#### Why this was done

Damage status is one of the most important fields for procurement analysis. Vehicles with unrepaired damage may have lower resale value and higher risk.

Standardising this field allows the project to calculate damage penalty and filter procurement opportunities.

---

## 6. Feature Engineering

After cleaning the raw data, new business-ready fields were created to support Power BI analysis.

These fields make the dataset easier to analyse and help translate raw vehicle attributes into business segments.

---

### 6.1 Vehicle Age

```sql
vehicle_age = 2016 - registration_year
```

#### Why this field was created

Vehicle age is needed for depreciation analysis.

Since the dataset was collected in 2016, the year 2016 was used as the reference year.

| Registration Year | Vehicle Age |
|---:|---:|
| 2015 | 1 |
| 2010 | 6 |
| 2005 | 11 |
| 2000 | 16 |

#### Business use

Vehicle age helps answer:

```text
How does vehicle price decrease as the car gets older?
```

This is directly linked to depreciation analysis and pricing strategy.

---

### 6.2 Listing Days

```sql
listing_days = DATEDIFF(DAY, date_created, last_seen)
```

#### Why this field was created

The dataset does not provide confirmed sale dates. Therefore, listing duration was used as a proxy for market liquidity.

A shorter listing duration may indicate stronger demand or faster market movement. A longer listing duration may indicate weaker demand, overpricing, or higher inventory risk.

#### Business use

Listing days helps answer:

```text
Which vehicle models appear to move faster in the market?
Which models may create slow-moving inventory risk?
```

Important note:

```text
Listing days is a proxy for liquidity, not confirmed sale duration.
```

---

### 6.3 Mileage Band

Vehicles were grouped into mileage bands.

```sql
CASE
    WHEN kilometer < 50000 THEN 'Under 50K'
    WHEN kilometer >= 50000 AND kilometer < 100000 THEN '50K-100K'
    WHEN kilometer >= 100000 AND kilometer < 150000 THEN '100K-150K'
    ELSE '150K+'
END AS mileage_band
```

#### Why these bands were selected

Mileage is one of the most important factors in used-car pricing.

The bands were selected to reflect common used-car market thresholds:

| Mileage Band | Business Meaning |
|---|---|
| Under 50K | Low mileage, usually higher resale value |
| 50K–100K | Moderate usage |
| 100K–150K | Higher usage but still potentially acceptable |
| 150K+ | High mileage, higher depreciation and risk |

The 150,000 km threshold is especially important because the project uses below 150,000 km as part of the underpriced vehicle rule.

#### Business use

Mileage band helps answer:

```text
How does price change as mileage increases?
Do vehicles above 150,000 km show a clear price drop?
```

---

### 6.4 Power Band

Vehicles were grouped into engine power bands.

```sql
CASE
    WHEN power_ps < 75 THEN 'Low Power'
    WHEN power_ps >= 75 AND power_ps < 150 THEN 'Standard'
    WHEN power_ps >= 150 AND power_ps < 250 THEN 'Performance'
    ELSE 'High Performance'
END AS power_band
```

#### Why these bands were selected

PowerPS measures engine power. Instead of analysing every individual power value, grouping vehicles into bands makes it easier to compare vehicle segments.

| Power Band | Business Meaning |
|---|---|
| Low Power | Small city cars or low-performance vehicles |
| Standard | Mainstream vehicles |
| Performance | Higher-performance vehicles |
| High Performance | Premium or performance-focused vehicles |

#### Business use

Power band helps answer:

```text
Does higher engine power generally relate to higher listed price?
Which power segment is most common in the market?
```

---

### 6.5 Inventory Speed Segment

Vehicles were segmented based on listing duration.

```sql
CASE
    WHEN listing_days < 7 THEN 'Fast Moving'
    WHEN listing_days >= 7 AND listing_days <= 30 THEN 'Normal'
    WHEN listing_days > 30 THEN 'Slow Moving'
    ELSE 'Unknown'
END AS inventory_speed_segment
```

#### Why these segments were selected

The goal of the project is inventory optimisation. Therefore, listing duration was converted into a business-friendly inventory speed segment.

| Segment | Rule | Business Meaning |
|---|---|---|
| Fast Moving | Listing days < 7 | Appears to move quickly in the market |
| Normal | 7–30 days | Normal market movement |
| Slow Moving | > 30 days | Potential inventory holding risk |

#### Business use

This segment helps the procurement team identify which vehicles may be safer to buy because they appear to have stronger market liquidity.

It also helps identify vehicle types or models that may stay longer in inventory.

---

### 6.6 Inventory Risk Segment

Inventory risk was created using listing duration and mileage.

```sql
CASE
    WHEN listing_days > 30 AND kilometer >= 150000 THEN 'High Risk'
    WHEN listing_days > 30 THEN 'Slow Moving Risk'
    WHEN kilometer >= 150000 THEN 'High Mileage Risk'
    ELSE 'Normal'
END AS inventory_risk_segment
```

#### Why this segment was created

Inventory risk is not based on one factor only. A vehicle may be risky because it is slow-moving, high-mileage, or both.

| Segment | Rule | Business Meaning |
|---|---|---|
| High Risk | Listing days > 30 and mileage >= 150,000 km | Long listing duration and high mileage |
| Slow Moving Risk | Listing days > 30 | Slow liquidity risk |
| High Mileage Risk | Mileage >= 150,000 km | Higher usage and depreciation risk |
| Normal | None of the above | Lower risk based on these rules |

#### Business use

This segment supports inventory optimisation by helping the team avoid vehicles that may be difficult to resell or may require a larger buying discount.

---

## 7. Model Price Percentiles

To support procurement decision-making, model-level price percentiles were calculated.

The following percentile fields were created for each brand and model:

```text
model_price_p25
model_price_median
model_price_p75
```

SQL logic:

```sql
PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY price)
    OVER (PARTITION BY brand, model) AS model_price_p25
```

#### Why percentiles were used

Average price alone can be distorted by outliers. Percentiles provide a more robust way to understand the market price range for each model.

| Metric | Meaning |
|---|---|
| 25th percentile | Lower market price boundary |
| Median | Typical market price |
| 75th percentile | Upper market price boundary |

#### Business use

Price percentiles help answer:

```text
Is this vehicle cheaper than most similar vehicles?
Is the listed price below the normal market range for this model?
```

This is more useful than comparing every vehicle against the overall market average, because different models have very different normal price ranges.

---

## 8. Underpriced Opportunity Logic

After creating model-level price percentiles, a procurement opportunity flag was created.

A vehicle was flagged as an underpriced opportunity if it met all of the following conditions:

```text
1. Registration year >= 2003
2. Damage status = No Damage
3. Mileage < 150,000 km
4. Listed price < 25th percentile price of the same brand/model
```

SQL logic:

```sql
CASE
    WHEN c.registration_year >= 2003
     AND c.damage_status = 'No Damage'
     AND c.kilometer < 150000
     AND c.price < p.model_price_p25
    THEN 'Underpriced Opportunity'
    ELSE 'Normal'
END AS underpriced_flag
```

### Why these rules were selected

#### Registration year >= 2003

This rule removes very old vehicles from the opportunity list. Older vehicles may be cheaper, but they may also carry higher maintenance and resale risk.

#### No Damage

Only vehicles without unrepaired damage were included because damage can reduce resale value and buyer confidence.

#### Mileage below 150,000 km

This threshold was selected because vehicles above 150,000 km usually carry higher usage risk.

#### Price below model-level 25th percentile

This rule identifies vehicles that are cheaper than the lower quartile of similar vehicles in the same brand/model group.

Using the model-level 25th percentile prevents unfair comparison across different vehicle types. For example, a BMW should not be compared with a small Opel or Volkswagen city car using one overall average price.

### Business meaning

A vehicle flagged as an underpriced opportunity is not automatically a guaranteed good purchase. It means the vehicle meets quality filters and appears to be priced below the lower market range for similar vehicles.

The procurement team should review these listings first because they may represent better buying opportunities.

---

## 9. Final SQL Output Summary

After applying SQL cleaning, transformation, segmentation, percentile calculation, and underpriced opportunity logic, the final dataset produced the following results:

| Metric | Result |
|---|---:|
| Clean listings | 310,565 |
| Underpriced opportunities | 2,759 |
| Underpriced share | 0.89% |
| Average listed price | €6,213.58 |
| Average listing duration | 9.04 days |

### Interpretation

The final cleaned dataset contains **310,565 valid used-car listings** ready for Power BI analysis.

The average listed price is approximately **€6.2K**, and the average listing duration is approximately **9 days**.

The procurement opportunity logic identified **2,759 potential underpriced vehicles**, representing approximately **0.89%** of the cleaned dataset.

This is a realistic output because true underpriced opportunities should represent a small subset of the market after applying quality filters such as no damage, acceptable mileage, newer registration year, and model-level price comparison.

---

## 10. SQL Output Prepared for Power BI

The final SQL table used for Power BI is:

```text
procurement_opportunity_list
```

This table includes:

```text
- Cleaned vehicle attributes
- Standardised category labels
- Vehicle age
- Listing days
- Mileage band
- Power band
- Inventory speed segment
- Inventory risk segment
- Model price percentiles
- Underpriced opportunity flag
```

This table is suitable to be used as the main fact table in Power BI.

---

## 11. Business Value of the SQL Stage

The SQL stage created business value by turning messy raw listing data into a reliable procurement and inventory analytics dataset.

The cleaned and transformed data allows NextDrive to:

```text
1. Analyse the used-car market with reliable price metrics
2. Understand depreciation by vehicle age
3. Compare pricing across mileage bands
4. Measure the impact of damage status
5. Identify fast-moving and slow-moving inventory
6. Segment vehicles by inventory risk
7. Detect underpriced procurement opportunities
8. Build an interactive Power BI pricing matrix
```

Without this SQL stage, the Power BI dashboard would be unreliable because it would be affected by invalid prices, unrealistic years, incorrect power values, and inconsistent category labels.

---

## 12. Limitations

The SQL cleaning and business rules were designed to support portfolio-level analysis, but there are some limitations.

### 12.1 Listing duration is not confirmed sale duration

The dataset does not provide confirmed sale dates. Therefore, `listing_days` is used only as a proxy for liquidity.

A listing disappearing from the platform may mean the car was sold, removed, expired, or edited.

### 12.2 Listed price is not final transaction price

The `price` field represents the listed asking price, not the final sale price. Therefore, pricing insights should be interpreted as market listing behaviour rather than confirmed transaction behaviour.

### 12.3 Underpriced flag is a screening tool

The underpriced opportunity flag identifies vehicles that appear cheaper than similar vehicles based on selected business rules. It does not guarantee that the vehicle is a profitable purchase.

Final procurement decisions would still require inspection, negotiation, vehicle history checks, and operational cost assessment.

---

## 13. Summary

The SQL stage was used to build the analytical foundation of the project.

The main work completed in SQL included:

```text
- Profiling raw vehicle listing data
- Identifying invalid price records
- Handling numeric overflow caused by extreme values
- Removing unrealistic prices, years, power values, and date issues
- Standardising German category values into English
- Creating vehicle age and listing duration fields
- Creating mileage and power bands
- Creating inventory speed and inventory risk segments
- Calculating model-level price percentiles
- Creating an underpriced opportunity flag
```

The final output is a clean, business-ready dataset containing **310,565 valid listings** and **2,759 potential procurement opportunities**.

This dataset is now ready to be connected to Power BI for dashboard development.

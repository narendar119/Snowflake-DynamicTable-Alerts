-- Use an existing database/role, e.g., USE ROLE SYSADMIN; USE WAREHOUSE COMPUTE_WH;
CREATE SCHEMA IF NOT EXISTS PIPELINE;
USE SCHEMA PIPELINE;

--------------------------------------------------------------------------------
-- 1. STAGE TABLES & DUMMY DATA (Simulating Snowpipe Ingestion)
--------------------------------------------------------------------------------

-- STAGE CUSTOMER TABLE
CREATE OR REPLACE TABLE STG_CUSTOMER (
    C_ID VARCHAR,
    C_NAME VARCHAR,
    LOCATION VARCHAR,
    CREATION_DATE DATETIME
);

-- Inserting dummy data into STG_CUSTOMER (C101 has two records, C102/C103 have one)
INSERT INTO STG_CUSTOMER VALUES
('C101', 'RAMAN', 'DELHI', '2024-05-01 10:00:00'),
('C102', 'RAHUL', 'MUMBAI', '2024-05-01 11:00:00'),
('C101', 'RAMAN', 'DELHI', '2024-05-01 10:30:00'), -- The latest C101 record
('C103', 'PRIYA', 'CHENNAI', '2024-05-01 12:00:00');

-- STAGE ITEM TABLE
CREATE OR REPLACE TABLE STG_ITEM (
    I_ID VARCHAR,
    I_NAME VARCHAR,
    CUSTOMER_ID VARCHAR,
    PRICE DECIMAL(10, 2),
    COUNT INT
);

-- Inserting dummy data into STG_ITEM (A101 has two prices, A102/A103/A104 have one)
INSERT INTO STG_ITEM VALUES
('A101', 'PRINTER', 'C101', 200.00, 4),
('A102', 'MONITOR', 'C102', 300.00, 2),
('A103', 'LAPTOP', 'C103', 100.00, 1),
('A101', 'PRINTER', 'C101', 500.00, 4), -- The highest price A101 record
('A104', 'KEYBOARD', 'C102', 150.00, 1);

SELECT * FROM STG_CUSTOMER;
SELECT * FROM STG_ITEM;


--------------------------------------------------------------------------------
-- 2. DYNAMIC TABLES (CLEANSE & TARGET LAYERS)
--------------------------------------------------------------------------------

-- Dynamic Table for Customer (Latest Record based on Creation Date)
CREATE OR REPLACE DYNAMIC TABLE CUSTOMER_DT
TARGET_LAG = '1 minute'
WAREHOUSE = YOUR_WAREHOUSE_NAME
AS
SELECT
    C_ID,
    C_NAME,
    LOCATION,
    CREATION_DATE
FROM STG_CUSTOMER
QUALIFY ROW_NUMBER() OVER (PARTITION BY C_ID ORDER BY CREATION_DATE DESC) = 1;

-- Dynamic Table for Item (Highest Price Record)
CREATE OR REPLACE DYNAMIC TABLE ITEM_DT
TARGET_LAG = '1 minute'
WAREHOUSE = YOUR_WAREHOUSE_NAME
AS
SELECT
    I_ID,
    I_NAME,
    CUSTOMER_ID,
    PRICE,
    COUNT
FROM STG_ITEM
QUALIFY ROW_NUMBER() OVER (PARTITION BY I_ID ORDER BY PRICE DESC) = 1;

-- Dynamic Table for Combining (Final Target Layer, refresh every 1 minute)
CREATE OR REPLACE DYNAMIC TABLE CUSTOMER_ITEM_DT
TARGET_LAG = '1 minute'
WAREHOUSE = YOUR_WAREHOUSE_NAME
AS
SELECT
    c.C_ID,
    c.C_NAME,
    c.LOCATION,
    i.I_ID,
    i.I_NAME,
    i.PRICE,
    i.COUNT,
    -- Added NULLIF to prevent Division by Zero, which is later forced to test the Alert
    ROUND(i.PRICE / NULLIF(i.COUNT, 0), 2) AS PRICE_PER_ITEM
FROM CUSTOMER_DT c
JOIN ITEM_DT i ON c.C_ID = i.CUSTOMER_ID;

SELECT * FROM CUSTOMER_ITEM_DT;


--------------------------------------------------------------------------------
-- 3. ALERT CONFIGURATION (For Automated Failure Notification)
--------------------------------------------------------------------------------

-- 1. Create Notification Integration (Required for sending emails)
CREATE NOTIFICATION INTEGRATION DYNAMIC_FAILURE_ALERT
    TYPE = EMAIL
    ALLOWED_RECIPIENTS = ('your.email@example.com') -- **REPLACE WITH YOUR EMAIL**
    ENABLED = TRUE;

-- 2. Create the Alert (Checks for failure in the CUSTOMER_ITEM_DT history)
CREATE OR REPLACE ALERT DT_FAILURE_NOTIFICATION
WAREHOUSE = YOUR_WAREHOUSE_NAME
SCHEDULE = '1 minute'
IF (EXISTS (
    SELECT 1
    FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
        DATE_RANGE_START => DATEADD(HOUR, -1, CURRENT_TIMESTAMP()),
        DYNAMIC_TABLE_NAME => 'CUSTOMER_ITEM_DT'
    ))
    WHERE STATE = 'FAILED'
    LIMIT 1 -- Trigger only if there is a recent failure
))
THEN
    CALL SYSTEM$SEND_EMAIL(
        'DYNAMIC_FAILURE_ALERT',
        'your.email@example.com', -- **REPLACE WITH YOUR EMAIL**
        '🚨 Dynamic Table Failure Notification: CUSTOMER_ITEM_DT FAILED',
        'Issue with data caused CUSTOMER_ITEM_DT to fail. Please check the refresh history. Main Error: Division by Zero.'
    );

-- 3. Resume the Alert
ALTER ALERT DT_FAILURE_NOTIFICATION RESUME;


--------------------------------------------------------------------------------
-- 4. TEST ALERT FAILURE (Optional: To test the Alert, run the following insert)
--------------------------------------------------------------------------------
-- This insert will create a Division by Zero error on the next DT refresh.
INSERT INTO STG_ITEM VALUES ('A999', 'TEST ITEM', 'C101', 100.00, 0);

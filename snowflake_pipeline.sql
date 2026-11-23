-- =============================================================================
-- AMPLITUDE EVENT INGESTION & MEDALLION PIPELINE (S3 -> SNOWFLAKE -> TASKS)
-- Database: TIL_DATA_ENGINEERING
-- Schema:   GWEBB_AMPLITUDE_STAGING
-- Author:   Georgia Webb
-- =============================================================================

-- The pipeline automatically ingests raw Amplitude JSON files from an AWS S3 bucket into Snowflake via Snowpipe, landing them in a raw table. A stream detects those new rows and triggers a chain of 
-- three automated tasks: the first flattens the nested JSON into structured columns in a Bronze table; the second reads from a Bronze stream to update Silver dimension tables—enriching newly seen IP addresses 
-- with company details via an external IPinfo API Python function—and populates a Silver Star Schema fact table; and the third aggregates that fact data into session-level page views, time spent, and bounce 
-- rates in a final Gold analytics table.

CREATE SCHEMA IF NOT EXISTS TIL_DATA_ENGINEERING.GWEBB_AMPLITUDE_STAGING;
USE SCHEMA TIL_DATA_ENGINEERING.GWEBB_AMPLITUDE_STAGING;

-- =============================================================================
-- SECTION 1: AWS S3 STORAGE INTEGRATION, STAGE & SNOWPIPE
-- =============================================================================

-- Storage Integration to authorize Snowflake to read from private S3 bucket
CREATE OR REPLACE STORAGE INTEGRATION gwebb_amplitude_python_import -- creates snowflake object that stores the authentication link between Snowflaek and AWS S3
  TYPE = EXTERNAL_STAGE -- read/writing files stored outside of snowflake
  STORAGE_PROVIDER = 'S3' -- Connection is to external cloud storage is Amazon S3 
  ENABLED = TRUE -- Turns connection on 
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::192699161875:role/gwebb-snowflake-amplitude-python'  --Provides the Amazon Resource Name (ARN) of the specific AWS IAM role. 
  -- Instead of storing static AWS access keys, Snowflake uses AWS Security Token Service (STS) to assume this IAM role and inherit its S3 read permissions.
  STORAGE_ALLOWED_LOCATIONS = ('s3://gwebb-amplitude-storage/python-import/'); -- Restricts access to only the python-import/ prefix inside the gwebb-amplitude-storage S3 bucket

-- Note: Run 'DESC INTEGRATION gwebb_amplitude_python_import;' once to retrieve snowflake's unique STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID. 
-- You paste these 2 values in the trust policy of the gwebb-snowflake-amplitude-python role inside AWS (AWS IAM Trust Policy).


 gwebb-snowflake-amplitude-python role inside AWS. Once both sides recognize each other, Snowpipe can read files from S3 automatically.

-- JSON File Format
CREATE OR REPLACE FILE FORMAT gwebb_json_format
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE;

-- External Stage pointing to S3 bucket prefix
CREATE OR REPLACE STAGE gwebb_amplitude_python_stage 
  STORAGE_INTEGRATION = gwebb_amplitude_python_import
  URL = 's3://gwebb-amplitude-storage/python-import/'
  FILE_FORMAT = gwebb_json_format;

-- Raw Landing Table
CREATE TABLE IF NOT EXISTS amplitude_events_raw_python (
  json_data VARIANT,
  source_filename VARCHAR,
  loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Continuous Auto-Ingestion via Snowpipe
CREATE OR REPLACE PIPE gw_des7_amplitude_snowpipe
  AUTO_INGEST = TRUE
AS
COPY INTO amplitude_events_raw_python (json_data, source_filename)
FROM (
    SELECT $1, metadata$filename 
    FROM @gwebb_amplitude_python_stage
)
FILE_FORMAT = (TYPE = 'JSON' STRIP_OUTER_ARRAY = TRUE);


-- =============================================================================
-- SECTION 2: EXTERNAL ACCESS INTEGRATION & IPINFO API ENRICHMENT
-- =============================================================================

-- 1. Network Rule for outbound egress to IPinfo API
CREATE OR REPLACE NETWORK RULE ip_api_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('ipinfo.io');

-- 2. Secret: Run this once manually directly in Snowflake (do not commit real token):
-- CREATE OR REPLACE SECRET ip_api_key
--   TYPE = GENERIC_STRING
--   SECRET_STRING = '<YOUR_IPINFO_API_TOKEN>';

-- 3. External Access Integration binding network access with stored authentication
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION ip_api_external_access_integration
  ALLOWED_NETWORK_RULES = (ip_api_network_rule)
  ALLOWED_AUTHENTICATION_SECRETS = (ip_api_key)
  ENABLED = TRUE;

-- 4. Python User Defined Function (UDF) for reverse-IP company resolution
CREATE OR REPLACE FUNCTION GET_COMPANY_FROM_IP(ip VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('requests', 'snowflake-snowpark-python')
EXTERNAL_ACCESS_INTEGRATIONS = (ip_api_external_access_integration)
SECRETS = ('api_key' = ip_api_key)
HANDLER = 'fetch_company_data'
AS
$$ 
import _snowflake 
import requests  
def fetch_company_data(ip: str): 
    if not ip or ip in ('0.0.0.0', '127.0.0.1', 'Unknown'): 
        return {"company_name": "Internal/Unknown", "domain": None}      
  
    api_token = _snowflake.get_generic_secret_string('api_key') 
    url = f"https://ipinfo.io/{ip}/json?token={api_token}"  
  
    try: 
        response = requests.get(url, timeout=3) 
        if response.status_code == 200: 
            data = response.json() 
            org_info = data.get('org', 'Unknown') 
            company_domain = data.get('company', {}).get('domain', None) 
            return { 
                "company_name": org_info, 
                "domain": company_domain 
            } 
        else: 
            return {"company_name": "API_Error", "domain": None} 
  except Exception: 
      return {"company_name": "Request_Failed", "domain": None} 
  $$;


-- =============================================================================
-- SECTION 3: TARGET DATA TABLES (MEDALLION ARCHITECTURE)
-- =============================================================================

-- Bronze Layer: Flattened raw extraction
CREATE TABLE IF NOT EXISTS amplitude_bronze (
    id VARCHAR,
    device_id VARCHAR,
    session_id INT,
    event_id INT,
    event_time TIMESTAMP_NTZ,
    event_type VARCHAR,
    ip_address VARCHAR,
    page_path VARCHAR,
    page_title VARCHAR
);

-- Silver Layer: Dimension - Page Titles
CREATE TABLE IF NOT EXISTS page_table_silver (
    page_title VARCHAR PRIMARY KEY,
    page_title_id NUMBER
);

-- Silver Layer: Dimension - Event Types
CREATE TABLE IF NOT EXISTS event_table_silver (
    event_type VARCHAR PRIMARY KEY,
    event_type_id NUMBER
);

-- Silver Layer: Dimension - IP Addresses & Companies
CREATE TABLE IF NOT EXISTS ip_table_silver (
    ip_address VARCHAR PRIMARY KEY,
    ip_address_id NUMBER,
    company_name VARCHAR,
    company_domain VARCHAR
);

-- Silver Layer: Star Schema Fact Table
CREATE TABLE IF NOT EXISTS fact_table_silver (
    id VARCHAR,
    device_id VARCHAR,
    session_id INT,
    event_id INT,
    event_time TIMESTAMP_NTZ,
    page_title_id NUMBER,
    event_type_id NUMBER,
    ip_address_id NUMBER
);

-- Gold Layer: Aggregated Session & Page Metrics
CREATE TABLE IF NOT EXISTS amplitude_gold_session_metrics (
    page_title VARCHAR PRIMARY KEY,
    total_page_views INT,
    avg_time_spent_seconds FLOAT,
    median_time_spent_seconds FLOAT,
    bounce_rate_percentage FLOAT
);


-- =============================================================================
-- SECTION 4: CHANGE DATA CAPTURE (STREAMS)
-- =============================================================================

-- Tracks new raw JSON records inserted by Snowpipe
CREATE OR REPLACE STREAM amplitude_raw_stream 
ON TABLE amplitude_events_raw_python;

-- Tracks newly extracted events appended to Bronze
CREATE OR REPLACE STREAM amplitude_bronze_stream 
ON TABLE amplitude_bronze;

-- =============================================================================
-- SECTION 5: AUTOMATED TRANSFORMATION TASKS (BRONZE -> SILVER -> GOLD)
-- =============================================================================

-- Task 1: Raw JSON Stream -> Bronze Layer (runs when Snowpipe ingests new files)
CREATE OR REPLACE TASK task_raw_to_bronze
  WAREHOUSE = <DATASCHOOL_WH>
  SCHEDULE = '5 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('TIL_DATA_ENGINEERING.GWEBB_AMPLITUDE_STAGING.amplitude_raw_stream')
AS
INSERT INTO amplitude_bronze (
    id, device_id, session_id, event_id, event_time, event_type, ip_address, page_path, page_title
)
SELECT
    json_data:uuid::VARCHAR AS id,
    json_data:device_id::VARCHAR AS device_id,
    json_data:session_id::INT AS session_id,
    json_data:event_id::INT AS event_id,
    json_data:event_time::TIMESTAMP_NTZ AS event_time,
    json_data:event_type::VARCHAR AS event_type,
    json_data:ip_address::VARCHAR AS ip_address,
    json_data:event_properties:"[Amplitude] Page Path"::VARCHAR AS page_path,
    json_data:event_properties:"[Amplitude] Page Title"::VARCHAR AS page_title
FROM amplitude_raw_stream
WHERE METADATA$ACTION = 'INSERT';


-- Task 2: Bronze Stream -> Silver Dimensions & Fact Table (runs right after Task 1)
CREATE OR REPLACE TASK task_bronze_to_silver
  WAREHOUSE = <DATASCHOOL_WH>
  AFTER task_raw_to_bronze
  WHEN SYSTEM$STREAM_HAS_DATA('TIL_DATA_ENGINEERING.GWEBB_AMPLITUDE_STAGING.amplitude_bronze_stream')
AS
BEGIN
    -- 2a. Insert any newly seen Page Titles into Dimension
    MERGE INTO page_table_silver AS target
    USING (
        SELECT DISTINCT page_title 
        FROM amplitude_bronze_stream 
        WHERE page_title IS NOT NULL AND METADATA$ACTION = 'INSERT'
    ) AS src
    ON target.page_title = src.page_title
    WHEN NOT MATCHED THEN
        INSERT (page_title, page_title_id)
        VALUES (src.page_title, ABS(HASH(src.page_title)));

    -- 2b. Insert any newly seen Event Types into Dimension
    MERGE INTO event_table_silver AS target
    USING (
        SELECT DISTINCT event_type 
        FROM amplitude_bronze_stream 
        WHERE event_type IS NOT NULL AND METADATA$ACTION = 'INSERT'
    ) AS src
    ON target.event_type = src.event_type
    WHEN NOT MATCHED THEN
        INSERT (event_type, event_type_id)
        VALUES (src.event_type, ABS(HASH(src.event_type)));

    -- 2c. Insert newly seen IP Addresses & call IPinfo UDF ONLY for new IPs (saves API credits)
    MERGE INTO ip_table_silver AS target
    USING (
        SELECT DISTINCT 
            ip_address,
            GET_COMPANY_FROM_IP(ip_address) AS enriched_data
        FROM amplitude_bronze_stream 
        WHERE ip_address IS NOT NULL AND METADATA$ACTION = 'INSERT'
    ) AS src
    ON target.ip_address = src.ip_address
    WHEN NOT MATCHED THEN
        INSERT (ip_address, ip_address_id, company_name, company_domain)
        VALUES (
            src.ip_address,
            ABS(HASH(src.ip_address)),
            src.enriched_data:company_name::VARCHAR,
            src.enriched_data:domain::VARCHAR
        );

    -- 2d. Load the Silver Star Schema Fact Table
    INSERT INTO fact_table_silver (
        id, device_id, session_id, event_id, event_time, page_title_id, event_type_id, ip_address_id
    )
    SELECT
        b.id,
        b.device_id,
        b.session_id,
        b.event_id,
        b.event_time,
        p.page_title_id,
        e.event_type_id,
        i.ip_address_id
    FROM amplitude_bronze_stream b
    LEFT JOIN page_table_silver p ON b.page_title = p.page_title
    LEFT JOIN event_table_silver e ON b.event_type = e.event_type
    LEFT JOIN ip_table_silver i ON b.ip_address = i.ip_address
    WHERE b.METADATA$ACTION = 'INSERT';
END;


-- Task 3: Refresh Gold Aggregated Metrics (runs right after Task 2)
CREATE OR REPLACE TASK task_silver_to_gold
  WAREHOUSE = <DATASCHOOL_WH>
  AFTER task_bronze_to_silver
AS
MERGE INTO amplitude_gold_session_metrics AS target
USING (
    WITH event_durations AS (
        SELECT
            p.page_title,
            f.session_id,
            DATEDIFF(
                'second',
                f.event_time,
                LEAD(f.event_time) OVER (PARTITION BY f.session_id ORDER BY f.event_time)
            ) AS time_spent_seconds,
            COUNT(*) OVER (PARTITION BY f.session_id) AS events_in_session
        FROM fact_table_silver f
        JOIN page_table_silver p ON f.page_title_id = p.page_title_id
    )
    SELECT
        page_title,
        COUNT(*) AS total_page_views,
        AVG(time_spent_seconds) AS avg_time_spent_seconds,
        MEDIAN(time_spent_seconds) AS median_time_spent_seconds,
        (COUNT_IF(events_in_session = 1) / NULLIF(COUNT(*), 0)) * 100 AS bounce_rate_percentage
    FROM event_durations
    GROUP BY page_title
) AS src
ON target.page_title = src.page_title
WHEN MATCHED THEN UPDATE SET
    target.total_page_views = src.total_page_views,
    target.avg_time_spent_seconds = src.avg_time_spent_seconds,
    target.median_time_spent_seconds = src.median_time_spent_seconds,
    target.bounce_rate_percentage = src.bounce_rate_percentage
WHEN NOT MATCHED THEN INSERT (
    page_title, total_page_views, avg_time_spent_seconds, median_time_spent_seconds, bounce_rate_percentage
) VALUES (
    src.page_title, src.total_page_views, src.avg_time_spent_seconds, src.median_time_spent_seconds, src.bounce_rate_percentage
);

-- =============================================================================
-- SECTION 6: ACTIVATE TASKS (Snowflake creates tasks in SUSPENDED state)
-- =============================================================================
-- Child tasks must be resumed BEFORE their root parent task:
ALTER TASK task_silver_to_gold RESUME;
ALTER TASK task_bronze_to_silver RESUME;
ALTER TASK task_raw_to_bronze RESUME;

-- =============================================================================
-- AMPLITUDE EVENT INGESTION & MEDALLION PIPELINE (S3 -> SNOWFLAKE -> TASKS)
-- Database: TIL_DATA_ENGINEERING
-- Schema:   GWEBB_AMPLITUDE_STAGING
-- Author:   Georgia Webb
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS TIL_DATA_ENGINEERING.GWEBB_AMPLITUDE_STAGING;
USE SCHEMA TIL_DATA_ENGINEERING.GWEBB_AMPLITUDE_STAGING;

-- =============================================================================
-- SECTION 1: AWS S3 STORAGE INTEGRATION, STAGE & SNOWPIPE
-- =============================================================================

-- Storage Integration to authorize Snowflake to read from private S3 bucket
CREATE OR REPLACE STORAGE INTEGRATION gwebb_amplitude_python_import
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::192699161875:role/gwebb-snowflake-amplitude-python'
  STORAGE_ALLOWED_LOCATIONS = ('s3://gwebb-amplitude-storage/python-import/');

-- Note: Run 'DESC INTEGRATION gwebb_amplitude_python_import;' once to retrieve 
-- STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID for the AWS IAM Trust Policy.

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
$$ import _snowflake import requests  def fetch_company_data(ip: str): if not ip or ip in ('0.0.0.0', '127.0.0.1', 'Unknown'): return {"company_name": "Internal/Unknown", "domain": None}      api_token = _snowflake.get_generic_secret_string('api_key') url = f"https://ipinfo.io/{ip}/json?token={api_token}"  try: response = requests.get(url, timeout=3) if response.status_code == 200: data = response.json() org_info = data.get('org', 'Unknown') company_domain = data.get('company', {}).get('domain', None) return { "company_name": org_info, "domain": company_domain } else: return {"company_name": "API_Error", "domain": None} except Exception: return {"company_name": "Request_Failed", "domain": None} $$
;


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


--

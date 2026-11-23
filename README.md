# Amplitude Data Extraction Pipeline
This project is a full-stack, automated ETL (Extract, Transform, Load) data pipeline that takes raw website user-behavior events from Amplitude, stores them in AWS S3, automatically loads them into Snowflake, enriches the IP addresses using an external API, and models the data into a Medallion Architecture (Bronze → Silver → Gold) ready for business intelligence and analytics.

Every morning at 7am, GitHub Actions runs this script with saved secret AWS/APIkeys. The python pipeline pulls the previous day's event logs from Amplitude, unpacks the nested compressed archives into clean JSON files, and uploads them to an AWS S3 bucket. Once the files arrive in S3, Snowpipe automatically ingests the raw JSON into Snowflake, where a chain of Streams and Tasks flattens the data, enriches new IP addresses with company details via the IPinfo API, and builds an analytics-ready Star Schema and Gold metrics table.

**Tech Stack**

* **Language:** Python 3.12 (`requests`, `boto3`, `python-dotenv`)
* **Orchestration:** GitHub Actions (Cron schedule & manual dispatch)
* **Cloud Storage:** AWS S3 (with IAM Role authentication)
* **Data Warehouse:** Snowflake (Snowpipe, Streams, Tasks, Python UDF, External Access Integration)
* **Data Sources:** Amplitude Export API (EU), IPinfo API

---

**Repository Structure**

* `.github/workflows/main.yml` — GitHub Actions workflow scheduled to run daily at 07:00 UTC.
* `extract_load.py` — Main production orchestration script that coordinates logging, extraction, and S3 uploading.
* `modules/extract_function.py` — Connects to Amplitude's Export API, streams the `.zip` download in 8KB chunks, extracts nested `.json.gz` files into standard `.json`, and cleans up temporary archives.
* `modules/load_function.py` — Uploads extracted `.json` files to S3 under the `python-import/` prefix and deletes local files upon confirmation.
* `modules/logging_function.py` — Configures timestamped file logging alongside console output.
* `snowflake_pipeline.sql` — Complete Snowflake setup script defining the S3 Storage Integration, Snowpipe, IPinfo Python UDF, Bronze/Silver/Gold tables, Streams, and automated Tasks.
* `requirements.txt` — Python package dependencies required by the runner.

---

**How the Pipeline Works**

1. **Extract (Python):** `extract_load.py` calculates yesterday's UTC date range (`00:00` to `23:59`) and calls the Amplitude Export API. Because Amplitude returns a `.zip` file containing hourly `.json.gz` files inside subfolders, `extract_amplitude_data` unpacks both compression layers into flat `.json` files and removes empty folders.
2. **Load (Python to AWS S3):** `load_data_to_s3` iterates through the local `amplitude_data/` folder, uploads each `.json` file to `s3://gwebb-amplitude-storage/python-import/`, and deletes the local copy once uploaded.
3. **Auto-Ingest (S3 to Snowflake Raw):** Snowpipe (`gw_des7_amplitude_snowpipe`) detects new files arriving in the S3 stage and loads them into `amplitude_events_raw_python`.
4. **Transform & Enrich (Bronze to Silver to Gold):**
   * `task_raw_to_bronze` reads new rows from `amplitude_raw_stream` and flattens the nested JSON into typed columns in `amplitude_bronze`.
   * `task_bronze_to_silver` reads from `amplitude_bronze_stream`, merges new page titles, event types, and IP addresses into Silver dimension tables (calling the `GET_COMPANY_FROM_IP` Python UDF only for newly discovered IPs), and populates `fact_table_silver`.
   * `task_silver_to_gold` calculates page views, average and median time spent per page, and bounce rates into `amplitude_gold_session_metrics`.

---

**Setup & Configuration**

**1. Local Environment**
Clone the repository, install dependencies, and create a `.env` file in the root directory:

```bash
pip install -r requirements.txt

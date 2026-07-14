# Amplitude Data Extraction Pipeline

A lightweight, automated Python pipeline designed to extract daily event data from the Amplitude Analytics API (EU Residency), handle complex nested decompression, and save clean, uncompressed JSON files locally.

```text
your_project_folder/
│
├── .env                  <-- Your hidden keys
├── .venv/                <-- Your local environment
├── script.py             <-- Your Python code
├── requirements.txt      <-- Your library list
│
└── amplitude_data/       <-- Data folder
    ├── json_20260709T06/  <-- Data from 6:00 AM UTC
    │   └── 12345_2026-07-09_6#1.json
    │
    ├── json_20260709T07/  <-- Data from 7:00 AM UTC
    │   └── 12345_2026-07-09_7#1.json
    │
    └── json_20260709T08/  <-- Data from 8:00 AM UTC
        └── 12345_2026-07-09_8#1.json
```

Load:

========================================================================
SCRIPT EXPLANATION: S3 DATA UPLOADER WITH CLEANUP
========================================================================

WHAT THIS SCRIPT DOES:
This Python script automatically uploads JSON files from a local computer
folder into an Amazon S3 storage bucket, logs the results, and deletes
the local files as soon as they are safely uploaded.

---

## STEP-BY-STEP PROCESS:

1. CREATES A LOG FILE
   - It creates a folder called 'logs' (if it doesn't already exist).
   - It starts a new text log file named with the exact date and time
     the script was run (e.g., 'logs/load_2026-07-14 09-30-00.log').
   - It writes "Logger successfully initiated" to start the log.

2. LOADS SECURITY CREDENTIALS
   - It reads your secret AWS credentials (AWS_ACCESS_KEY, AWS_SECRET_KEY,
     and AWS_BUCKET_NAME) from a hidden file named '.env'. This keeps
     your passwords safe.

3. SCANS THE LOCAL DATA FOLDER
   - It looks inside the local folder: 'amplitude_data\json_20260709'
   - It gathers a list of all the files sitting in that folder.

4. UPLOADS, LOGS, AND CLEANS UP (FOR EACH FILE)
   - It loops through the files one by one.
   - It attempts to upload each file to your S3 bucket under a folder
     called 'python-import/'.
   - IF THE UPLOAD SUCCEEDS:
     - It writes a success message to the log file.
     - WARNING: It permanently deletes the file from your local computer
       to save hard drive space (using 'os.remove').
   - IF THE UPLOAD FAILS:
     - It keeps the file safe on your computer.
     - It writes the exact error message to the log file so you can
       troubleshoot what went wrong.

---

## WHAT YOU NEED TO RUN IT:

- Python installed on your machine.
- The external libraries 'boto3' and 'python-dotenv' installed.
- A '.env' file in the same folder as this script containing:
  AWS_ACCESS_KEY=your_key
  AWS_SECRET_KEY=your_secret
  AWS_BUCKET_NAME=your_bucket_name
- # Your files sitting in the 'amplitude_data/json_20260709/' folder.

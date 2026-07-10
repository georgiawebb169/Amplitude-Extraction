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

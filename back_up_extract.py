from datetime import datetime, timezone, timedelta 
import os 
import logging 
import zipfile
import gzip
import shutil 
from dotenv import load_dotenv 
import requests 

# 1. Load secret keys from your .env file
load_dotenv()

# Setup logging
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s - [%(levelname)s] - %(message)s'
)

# 2. Setup folder that data wil be saved to 
main_folder = "amplitude_data"
os.makedirs(main_folder, exist_ok=True)

# 3. Pull API Credentials from environment variables
api_key = os.getenv('AMP_API_KEY')
secret_key = os.getenv('AMP_SECRET_KEY')
base_url = 'https://analytics.eu.amplitude.com/api/2/export'

# 4. Get yesterday's timestamp for API parameters
now_utc = datetime.now(timezone.utc)
yesterday_dt = now_utc - timedelta(days=1)

start_time = yesterday_dt.strftime('%Y%m%dT00')
end_time = yesterday_dt.strftime('%Y%m%dT23')

params = {
    'start': start_time,
    'end': end_time
}

# 5. Define zipped file and folder paths
zip_filename = f"zipped_{start_time}.zip" 
zip_filepath = os.path.join(main_folder, zip_filename) 

# 6. Make API call
logging.info(f"Requesting full day data from Amplitude for: {yesterday_dt.strftime('%Y-%m-%d')}")
# Note: Fixed 'aws_key' typo to 'api_key' here
response = requests.get(base_url, params=params, auth=(api_key, secret_key), stream=True) 

if response.status_code == 200:
    # download the data in 8KB chunks
    with open(zip_filepath, 'wb') as f:
        for chunk in response.iter_content(chunk_size=8192):
            f.write(chunk)
    logging.info(f"Saved initial zipped file: {zip_filepath}")
    
    # Create folder where unzipped files will be saved to
    extract_folder = os.path.join(main_folder, f"json_{yesterday_dt.strftime('%Y%m%d')}")
    os.makedirs(extract_folder, exist_ok=True)
    
    # Unzip the files
    with zipfile.ZipFile(zip_filepath, 'r') as zip_ref:
        zip_ref.extractall(extract_folder) 
    
    # Delete big zipped file
    os.remove(zip_filepath)
    
    logging.info("Now we are looking through the zipped files")
    
    # Process and extract all the .json.gz files
    for folder, subfolders, files in os.walk(extract_folder):
        for filename in files: 
            if filename.endswith(".json.gz"):
                current_file_path = os.path.join(folder, filename) 
        
                clean_json_name = filename.replace(".json.gz", ".json") 
                json_file_path = os.path.join(extract_folder, clean_json_name)
            
                # unzip the gzipped files 
                with gzip.open(current_file_path, 'rb') as gzipped: 
                    with open(json_file_path, 'wb') as un_gzipped: 
                        shutil.copyfileobj(gzipped, un_gzipped) 
                os.remove(current_file_path) 
                logging.info(f"Extracted and cleaned up: {filename}")

    # NEW: Walk bottom-up to delete the empty subfolders left behind by the zip file
    for folder, subfolders, files in os.walk(extract_folder, topdown=False):
        if folder != extract_folder:
            if not os.listdir(folder):
                os.rmdir(folder)
                logging.info(f"Deleted empty folder: {folder}")
                
    logging.info("All data successfully processed and organized.")
else:
    logging.error(f"Amplitude responded with status code: {response.status_code}")
    logging.error(f"Response Details: {response.text}")
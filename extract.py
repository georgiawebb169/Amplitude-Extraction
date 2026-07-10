from datetime import datetime, timezone, timedelta 
import os 
import logging 
import zipfile
import gzip
import shutil #shutil provides operations for copying, moving, renaming, and archiving entire files and directories.
from dotenv import load_dotenv 
import requests 

# 1. Load secret keys from your .env file
load_dotenv()

# Setup logging
logging.basicConfig(
    level=logging.INFO, #Only show me messages that are INFO level or worse
    format='%(asctime)s - [%(levelname)s] - %(message)s'
)

# 2. Setup folder that data wil be saved to 
main_folder = "amplitude_data"
os.makedirs(main_folder, exist_ok=True)

# 3. Pull API Credentials from environment variables
api_key = os.getenv("AMPLITUDE_API_KEY")
secret_key = os.getenv("AMPLITUDE_SECRET_KEY")
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
zip_filename = f"zipped_{start_time}.zip" #contains 1 big zipped file 
zip_filepath = os.path.join(main_folder, zip_filename) #thew 1 big zipped file lives in the amplitude_data folder 


# 6. Make API call
logging.info(f"Requesting full day data from Amplitude for: {yesterday_dt.strftime('%Y-%m-%d')}")
response = requests.get(base_url, params=params, auth=(api_key, secret_key), stream=True)

if response.status_code == 200:
    # download the data in 8KB chunks to avoid memory on computer being too full 
    with open(zip_filepath, 'wb') as f:
        for chunk in response.iter_content(chunk_size=8192): #The number 8192 represents 8 Kilobytes (8 KB) of data ($8 \times 1024$ bytes).
            f.write(chunk)
    logging.info(f"Saved initial zipped file: {zip_filepath}")
    
    # Create folder where unzipped files will be saved to (these are still gzipped)
    extract_folder = os.path.join(main_folder, f"json_{yesterday_dt.strftime('%Y%m%d')}")
    os.makedirs(extract_folder, exist_ok=True)
    
    # Unzip the files
    with zipfile.ZipFile(zip_filepath, 'r') as zip_ref:
        zip_ref.extractall(extract_folder) #extract all the files and save to extract_folder
    
    # Delete big zipped file
    os.remove(zip_filepath)
    
    logging.info("Now we are looking through the zipped files")
    
    # os.walk looks at every individual file in a folder, including going through sub folders and it records the main file name, the subfolder name, and the filename. 
    for folder, subfolders, files in os.walk(extract_folder):
        for filename in files: #for every unzipped file, identify all the gzipped files 
            if filename.endswith(".json.gz"):
                current_file_path = os.path.join(folder, filename) #e.g. amplitude_data/json_20260708/12345/67890/2026-07-08_00#1.json.gz
        
                clean_json_name = filename.replace(".json.gz", ".json") #change file to .json
                json_file_path = os.path.join(extract_folder, clean_json_name)#make file path with .json extension
            
                # unzip the gzipped files 
                with gzip.open(current_file_path, 'rb') as gzipped: #open the gzipped and decompress it 
                    with open(json_file_path, 'wb') as un_gzipped: #open a new file ending in.json
                        shutil.copyfileobj(gzipped, un_gzipped) #move the data from the gzipped file to the new json file
                os.remove(current_file_path) #delete the gzipped file
                logging.info("Data successfully unzipped.")
else:
    logging.error(f"Amplitude responded with status code: {response.status_code}")
    logging.error(f"Response Details: {response.text}")

    #The with statement ensures that no matter what happens (even if the script crashes mid-unzip), Python will automatically and safely close both files the exact moment the code inside that indented block finishes executing.
from datetime import datetime, timezone, timedelta 
import os 
import logging 
import zipfile
import gzip
import shutil #shutil provides operations for copying, moving, renaming, and archiving entire files and directories.
from dotenv import load_dotenv 
import requests 

def extract_amplitude_data(start_time, end_time, api_key, secret_key, main_folder='amplitude_data'):
    """
    Extract data from Amplitude's Export API for a given date range.
    
    Args:
        start_time (str): Start date in format 'YYYYMMDDTHH' (e.g., '20241101T00')
        end_time (str): End date in format 'YYYYMMDDTHH' (e.g., '20241101T23')
        api_key (str): Amplitude API key
        secret_key (str): Amplitude secret key
        output_file (str): Output filename for the downloaded data (default: 'amplitude_data')
    
    Returns:
        bool: True if successful, False otherwise
    """

    base_url = 'https://analytics.eu.amplitude.com/api/2/export'
    params = {
        'start': start_time,
        'end': end_time
    }

    # Define zipped file and folder paths
    zip_filename = f"zipped_{start_time}.zip" 
    zip_filepath = os.path.join(main_folder, zip_filename) 
    
    # Ensure main directory exists
    os.makedirs(main_folder, exist_ok=True)

    logging.info(f"Requesting data from Amplitude for range: {start_time} to {end_time}")
    
    # Make the API call
    response = requests.get(base_url, params=params, auth=(api_key, secret_key), stream=True)

    if response.status_code == 200:
        # Download the data in 8KB chunks to protect RAM
        with open(zip_filepath, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        logging.info(f"Saved initial zipped file: {zip_filepath}")
        
        # Create folder where unzipped files will go (using start date to name the folder)
        date_str = start_time[:8] # Extracts 'YYYYMMDD' from 'YYYYMMDDT00'
        extract_folder = os.path.join(main_folder, f"json_{date_str}")
        os.makedirs(extract_folder, exist_ok=True)
        
        # Unzip the files
        with zipfile.ZipFile(zip_filepath, 'r') as zip_ref:
            zip_ref.extractall(extract_folder) 
        
        # Delete big zipped file
        os.remove(zip_filepath)
        logging.info("Main zip file extracted and deleted. Decompressing individual .json.gz files...")
        
        # Find and decompress nested .json.gz files
        for folder, subfolders, files in os.walk(extract_folder):
            for filename in files: 
                if filename.endswith(".json.gz"):
                    current_file_path = os.path.join(folder, filename) 
            
                    clean_json_name = filename.replace(".json.gz", ".json") 
                    json_file_path = os.path.join(extract_folder, clean_json_name)
                
                    # Unzip gzipped files
                    with gzip.open(current_file_path, 'rb') as gzipped: 
                        with open(json_file_path, 'wb') as un_gzipped: 
                            shutil.copyfileobj(gzipped, un_gzipped) 
                    
                    os.remove(current_file_path) 
        
        logging.info("Extraction complete. Deleting remaining empty nested folders...")

        # Walk bottom-up to delete the empty subfolders left behind by the zip file
        for folder, subfolders, files in os.walk(extract_folder, topdown=False):
            if folder != extract_folder:
                if not os.listdir(folder):
                    os.rmdir(folder)
                    logging.info(f"Deleted empty folder: {folder}")
                    
        logging.info("Extraction process completely finished!")
        return True
    else:
        logging.error(f"Amplitude responded with status code: {response.status_code}")
        logging.error(f"Response Details: {response.text}")
        return False
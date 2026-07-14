from datetime import datetime, timezone, timedelta 
import os 
import logging 
from dotenv import load_dotenv  

# Import all three helper functions
from modules.logging_function import setup_logger
from modules.extract_function import extract_amplitude_data
from modules.load_function import load_data_to_s3

# 1. Initialize the custom logger using your function
timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
log_dir = 'logs'
logger = setup_logger(timestamp=timestamp, log_dir=log_dir)

# 2. Load all environment variables
load_dotenv()

# Amplitude Configuration
AMP_API_KEY = os.getenv('AMP_API_KEY')
AMP_SECRET_KEY = os.getenv('AMP_SECRET_KEY')
MAIN_FOLDER = "amplitude_data"

# AWS Configuration
AWS_ACCESS_KEY = os.getenv('AWS_ACCESS_KEY')
AWS_SECRET_KEY = os.getenv('AWS_SECRET_KEY')
AWS_BUCKET_NAME = os.getenv('AWS_BUCKET_NAME')

# 3. Calculate target dates (Yesterday UTC)
now_utc = datetime.now(timezone.utc)
yesterday_dt = now_utc - timedelta(days=1)

start_time = yesterday_dt.strftime('%Y%m%dT00')
end_time = yesterday_dt.strftime('%Y%m%dT23')


# 4. Orchestrate the pipeline execution
if __name__ == "__main__":
    logger.info("=============================================")
    logger.info("STARTING AMPLITUDE TO S3 DATA PIPELINE")
    logger.info("=============================================")
    
    # --- STEP 1: EXTRACT ---
    logger.info(f"Step 1: Extracting Amplitude data for date: {yesterday_dt.strftime('%Y-%m-%d')}...")
    extract_success = extract_amplitude_data(
        api_key=AMP_API_KEY,
        secret_key=AMP_SECRET_KEY,
        start_time=start_time,
        end_time=end_time,
        main_folder=MAIN_FOLDER
    )
    
    # --- STEP 2: LOAD (Only runs if Step 1 succeeds) ---
    if extract_success:
        logger.info("Step 1 Complete! Proceeding to Step 2: Uploading to Amazon S3...")
        
        load_success = load_data_to_s3(
            aws_access_key=AWS_ACCESS_KEY,
            aws_secret_key=AWS_SECRET_KEY,
            bucket_name=AWS_BUCKET_NAME,
            data_dir=MAIN_FOLDER,
            s3_prefix='python-import'
        )
        
        if load_success:
            logger.info("=============================================")
            logger.info("SUCCESS: Entire ETL Pipeline executed seamlessly!")
            logger.info("=============================================")
        else:
            logger.error("FAILURE: Extraction completed, but the S3 upload failed.")
            
    else:
        logger.error("CRITICAL: Pipeline halted. Extraction from Amplitude failed.")
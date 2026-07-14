from datetime import datetime, timezone, timedelta 
import os 
import logging 
from dotenv import load_dotenv  
from extract_function import extract_amplitude_data

# Setup logging
logging.basicConfig(
    level=logging.INFO, #Only show me messages that are INFO level or worse
    format='%(asctime)s - [%(levelname)s] - %(message)s'
)

load_dotenv()

# 2. Setup folder that data wil be saved to 
main_folder = "amplitude_data"


# 3. Pull API Credentials from environment variables
api_key = os.getenv('AMP_API_KEY')
secret_key = os.getenv('AMP_SECRET_KEY')


# 4. Get yesterday's timestamp for API parameters
now_utc = datetime.now(timezone.utc)
yesterday_dt = now_utc - timedelta(days=1)

start_time = yesterday_dt.strftime('%Y%m%dT00')
end_time = yesterday_dt.strftime('%Y%m%dT23')

if __name__ == "__main__":
    logging.info("Starting Amplitude Data Extraction Pipeline...")
    
    success = extract_amplitude_data(
        api_key=api_key,
        secret_key=secret_key,
        start_time=start_time,
        end_time=end_time,
        main_folder=main_folder
    )
    
    if success:
        logging.info("Pipeline executed successfully.")
    else:
        logging.error("Pipeline failed.")

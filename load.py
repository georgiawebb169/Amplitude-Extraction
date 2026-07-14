import os 
from datetime import datetime
import logging 
from dotenv import load_dotenv
# Import your newly created function
from load_function import load_data_to_s3

# Setup dynamic log file naming
timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
log_dir = 'logs'
os.makedirs(log_dir, exist_ok=True)
log_filename = f'{log_dir}/load_{timestamp}.log'

logging.basicConfig(
    filename=log_filename,
    format='%(asctime)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

# Load environment keys
load_dotenv()

AWS_ACCESS_KEY = os.getenv('AWS_ACCESS_KEY')
AWS_SECRET_KEY = os.getenv('AWS_SECRET_KEY')
AWS_BUCKET_NAME = os.getenv('AWS_BUCKET_NAME')

if __name__ == "__main__":
    logging.info('Load orchestration script initiated.')
    
    # Run the function
    success = load_data_to_s3(
        aws_access_key=AWS_ACCESS_KEY,
        aws_secret_key=AWS_SECRET_KEY,
        bucket_name=AWS_BUCKET_NAME,
        data_dir='amplitude_data',
        s3_prefix='python-import'
    )
    
    if success:
        logging.info("Load pipeline completed successfully.")
    else:
        logging.error("Load pipeline encountered issues.")
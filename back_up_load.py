import os 
from datetime import datetime
import logging 
from dotenv import load_dotenv
import boto3

# Safer file naming
timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
log_dir = 'logs'
os.makedirs(log_dir, exist_ok=True)
log_filename = f'{log_dir}/load_{timestamp}.log'

logging.basicConfig(
    filename=log_filename,
    format='%(asctime)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

logger = logging.getLogger()
logger.info('Logger successfully initiated')

load_dotenv()

AWS_ACCESS_KEY = os.getenv('AWS_ACCESS_KEY')
AWS_SECRET_KEY = os.getenv('AWS_SECRET_KEY')
AWS_BUCKET_NAME = os.getenv('AWS_BUCKET_NAME')

s3_client = boto3.client(
    's3',
    aws_access_key_id=AWS_ACCESS_KEY,
    aws_secret_access_key=AWS_SECRET_KEY
)

data_dir = 'amplitude_data'

if os.path.exists(data_dir):
    # os.walk will look inside amplitude_data AND all of its subfolders (like json_20260713)
    for folder, subfolders, files in os.walk(data_dir):
        for file in files:
            # Construct the absolute path to the file
            to_upload = os.path.join(folder, file)
            
            # Keep the S3 folder structure clean by just using the filename
            s3key = f'python-import/{file}'
            
            try:
                s3_client.upload_file(to_upload, AWS_BUCKET_NAME, s3key)
                logger.info(f'{file} successfully uploaded to S3.')
                
                os.remove(to_upload)
                logger.info(f'Local file {file} deleted.')
            except Exception as e:
                logger.error(f"Failed to upload {file}", exc_info=True)
                
    # Optional cleanup: Remove empty subfolders left behind after files are deleted
    for folder, subfolders, files in os.walk(data_dir, topdown=False):
        if folder != data_dir and not os.listdir(folder):
            os.rmdir(folder)
            logger.info(f"Cleaned up empty local folder: {folder}")
else:
    logger.warning(f"Data directory '{data_dir}' does not exist.")
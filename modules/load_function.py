import os
import logging
import boto3

def load_data_to_s3(aws_access_key, aws_secret_key, bucket_name, data_dir='amplitude_data', s3_prefix='python-import'):
    """
    Walks through the local data directory, uploads all discovered files to S3,
    deletes the local copies upon successful upload, and cleans up empty subfolders.
    """
    # Initialize the S3 client inside the function
    s3_client = boto3.client(
        's3',
        aws_access_key_id=aws_access_key,
        aws_secret_access_key=aws_secret_key
    )

    if not os.path.exists(data_dir):
        logging.warning(f"Data directory '{data_dir}' does not exist. Skipping S3 load.")
        return False

    logging.info(f"Starting S3 upload process for directory: {data_dir}")
    files_uploaded = 0

    # 1. Walk through folders and upload files
    for folder, subfolders, files in os.walk(data_dir):
        for file in files:
            to_upload = os.path.join(folder, file)
            s3key = f'{s3_prefix}/{file}'
            
            try:
                s3_client.upload_file(to_upload, bucket_name, s3key)
                logging.info(f'{file} successfully uploaded to S3.')
                
                os.remove(to_upload)
                logging.info(f'Local file {file} deleted.')
                files_uploaded += 1
            except Exception as e:
                logging.error(f"Failed to upload {file}", exc_info=True)

    # 2. Clean up empty subfolders left behind
    for folder, subfolders, files in os.walk(data_dir, topdown=False):
        if not os.listdir(folder):
            os.rmdir(folder)
            logging.info(f"Cleaned up empty local folder: {folder}")

    logging.info(f"S3 load process complete. Total files uploaded: {files_uploaded}")
    return True
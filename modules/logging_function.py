import logging
import os

def setup_logger(timestamp: str, log_dir: str):
    """
    This initialises the logger for everything.

    Args:
        timestamp (str): For the filenames of the logs.
        log_dir (str): Where the logs should be stored.
    """
    os.makedirs(log_dir, exist_ok=True)
    log_filename = f'{log_dir}/pipeline_{timestamp}.log'

    logging.basicConfig(
        format='%(asctime)s - [%(levelname)s] - %(message)s',
        level=logging.INFO,
        handlers=[
            logging.FileHandler(log_filename),
            logging.StreamHandler()  # Keeps logs visible in your terminal too!
        ]
    )

    return logging.getLogger()
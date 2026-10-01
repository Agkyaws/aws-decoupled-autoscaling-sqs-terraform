#!/usr/bin/env python3
import logging
import time
import sys
import boto3
from botocore.exceptions import ClientError


PARAMETER_NAME = "/lab/sqs/queue_name"
REGION = "us-east-1"

logging.basicConfig(format="[%(levelname)s] %(message)s", level="INFO")

def get_queue_name():
    """Fetches the queue name from SSM Parameter Store."""
    ssm = boto3.client("ssm", region_name=REGION)
    try:
        logging.info(f"Fetching config from SSM: {PARAMETER_NAME}")
        param = ssm.get_parameter(Name=PARAMETER_NAME, WithDecryption=False)
        return param['Parameter']['Value']
    except ClientError as e:
        logging.error(f"Failed to fetch parameter from SSM: {e}")
        sys.exit(1)


sqs = boto3.client("sqs", region_name=REGION)


queue_name = get_queue_name()

try:
    logging.info(f"Resolving URL for queue: {queue_name}")
    response = sqs.get_queue_url(QueueName=queue_name)
    queue_url = response["QueueUrl"]
    logging.info(f"Listening on: {queue_url}")
except ClientError as e:
    logging.error(f"Error finding queue: {e}")
    sys.exit(1)

logging.info("Worker started. Waiting for messages...")


while True:
    try:
        
        messages = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=10,
            WaitTimeSeconds=20
        )
        
        if "Messages" in messages:
            for message in messages["Messages"]:
                logging.info(f"Processing: {message['Body']}")
                
                time.sleep(0.5)
                
                
                sqs.delete_message(
                    QueueUrl=queue_url,
                    ReceiptHandle=message["ReceiptHandle"]
                )
        else:
            logging.info("No messages found. Polling again...")
            
    except ClientError as e:
        logging.error(f"Receive error: {e}")
        time.sleep(5)
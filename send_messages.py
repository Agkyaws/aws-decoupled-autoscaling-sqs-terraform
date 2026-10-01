#!/usr/bin/env python3
import argparse
import logging
import sys
import uuid
from time import sleep
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
    logging.info(f"Target Queue URL: {queue_url}")
except ClientError as e:
    logging.error(f"Error finding queue: {e}")
    sys.exit(1)


parser = argparse.ArgumentParser()
parser.add_argument("--interval", "-i", default=0.1, help="timer interval", type=float)
args = parser.parse_args()


while True:
    try:
        message_body = str(uuid.uuid4())
        logging.info(f"Sending message: {message_body}")
        sqs.send_message(QueueUrl=queue_url, MessageBody=message_body)
        sleep(args.interval)
    except ClientError as e:
        logging.error(f"Send failed: {e}")
        sleep(1)
#!/bin/bash
dnf update -y
dnf install python3-pip -y
pip3 install boto3

mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

aws s3 cp s3://${bucket_name}/receive_messages.py .

sed -i 's/\r$//' receive_messages.py
chmod +x receive_messages.py

nohup ./receive_messages.py > /home/ec2-user/receive.log 2>&1 &
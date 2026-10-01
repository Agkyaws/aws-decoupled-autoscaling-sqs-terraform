#!/bin/bash
dnf update -y
dnf install python3-pip -y
pip3 install boto3

cd /home/ec2-user

aws s3 cp s3://${bucket_name}/send_messages.py /home/ec2-user/

sed -i 's/\r$//' /home/ec2-user/send_messages.py
chmod +x /home/ec2-user/send_messages.py
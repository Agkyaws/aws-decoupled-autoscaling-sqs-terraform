# Building a Resilient, Decoupled AWS Architecture with SQS and Auto Scaling

In modern cloud computing, handling unpredictable workloads without over-provisioning resources is a constant challenge. Monolithic, tightly coupled systems often struggle with sudden spikes in traffic, leading to bottlenecks or system crashes. 

**The solution?** Decoupling your application components and implementing queue-based auto-scaling.

In this project, we will walk through a hands-on project to build a highly scalable, decoupled architecture on AWS.

---

## 🎯 The Objective

The primary objective of this project is to design a decoupled architecture where an Auto Scaling Group (ASG) of EC2 instances dynamically scales based on Amazon SQS queue depth. The ASG scales out (adds instances) when CloudWatch alarms indicate the queue is filling up, and scales in (removes instances) when the queue empties and thresholds are met.

## 💡 Why This Matters: Business Benefits

Before diving into the technical implementation, let’s look at why businesses adopt this architectural pattern:

*   **Cost Optimization:** You only pay for the compute you need. When the queue is empty, the architecture scales in, shutting down idle EC2 instances to save money.
*   **High Availability & Fault Tolerance:** If a worker node (receiver) crashes while processing a message, the message becomes visible in the SQS queue again after a timeout, allowing another instance to process it. No data is lost.
*   **Decoupled Systems:** By placing an SQS queue between the data producers (senders) and consumers (receivers), you break hard dependencies. Senders can continue generating messages even if the receiving backend is temporarily overwhelmed.

## 🏗️ Architecture Overview

Our architecture utilizes several core AWS services to create a seamless, event-driven loop:

*   **Amazon SQS:** Acts as the message queue holding incoming requests.
*   **Amazon EC2 & ASG:** A standalone “Sender” instance pushes messages, while a “Receiver” Auto Scaling Group pulls and processes them.
*   **Amazon S3 & SSM:** S3 acts as an artifact store for our Python scripts, while Systems Manager (SSM) Parameter Store securely holds the SQS queue name for both sender and receiver to reference.
*   **Amazon CloudWatch & SNS:** CloudWatch monitors the `ApproximateNumberOfMessagesVisible` metric and triggers an SNS topic to initiate ASG scaling actions.

### Infrastructure as Code (IaC) implementation

Since we are deploying this project using Infrastructure as Code (IaC), we can skip the manual AWS Console setup entirely. The entire architecture is defined in Terraform configuration:

*   **Foundational Resources:** We define an `aws_s3_bucket` to store our scripts, an `aws_ssm_parameter` for our configuration data, and an `aws_sqs_queue`. We also provision an `aws_iam_role` granting EC2 instances access to these services.
*   **The Receiver ASG:** We utilize an `aws_launch_template` that bootstraps our worker nodes using a bash script to download and execute `receive_messages.py`. This template is attached to an `aws_autoscaling_group` configured with a minimum size of 1 and a maximum of 3.
*   **The Sender Instance:** A standalone `aws_instance` is provisioned to act as our traffic generator, configured to download `send_messages.py` upon boot.
*   **Monitoring & Scaling Logic:** We define `aws_cloudwatch_metric_alarm` resources to monitor the queue. These alarms target an `aws_sns_topic` and trigger our `aws_autoscaling_policy` resources to add or remove capacity.

---

## 🚀 Testing the Architecture in Action

To see the auto-scaling magic happen, we need to generate a workload. Follow these steps:

1.  **SSH** into the Sender EC2 instance.
2.  **Execute the sender script** to start pushing messages to the queue by running:
    ```bash
    ./send_messages.py --interval 1.0
    ```
    > **Understanding the Interval:** The `--interval` flag controls the delay between messages. An interval of `1.0` sends exactly 1 message per second. To aggressively fill the queue and trigger your scale-out alarms faster, you can lower this value (e.g., `0.01` equates to 100 messages per second). 
3.  **Navigate** to the CloudWatch dashboard and monitor the `ApproximateNumberOfMessagesVisible` metric.
4.  As the queue depth exceeds 200 messages, the **Scale-Out alarm** will transition into an “In alarm” state, triggering the ASG to launch a new worker instance.
5.  To test the **scale-in functionality**, return to your Sender SSH session and press `Ctrl+C` to stop sending messages, simulating a drop in traffic.
6.  Wait 5 to 10 minutes and watch the message count drop on the CloudWatch graph.
7.  Once the queue depth falls below the threshold, the **Scale-In alarm** will trigger, and the ASG will begin terminating instances at a rate of one every 60 seconds.
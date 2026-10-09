# Report 
**Mihaela Stoyanova, Krisztián Kozári**

## Introduction 
The goal of this project is to design and deploy a cloud infrastructure for CloudShirt, a startup company from Germany. The solution uses Amazon Web Services (AWS) and AWS CloudFormation to automate the deployment and configuration of the infrastructure.
The application is based on the CloudShirt ASP.NET Core 8.0 web application. The infrastructure includes a Virtual Private Cloud (VPC), subnets across multiple Availability Zones, security groups, Amazon EC2, an Application Load Balancer (ALB), an Auto Scaling Group, Amazon Elastic File System (EFS), Amazon RDS, Amazon S3, and an Elastic Stack monitoring solution.
The infrastructure is divided into separate CloudFormation templates. A master template, main.yaml, orchestrates the deployment of the individual components. A UserData script automates the installation and configuration of the CloudShirt application on EC2 instances.
The main objectives are to provide high availability, support scheduled scaling, store application logs centrally, provision a relational database using Infrastructure as Code, and provide monitoring and serverless functionality.

## Learning objectives 
The assignment requires the solution to cover the nine learning objectives described in the course manual. The following points describe the AWS concepts used in the project. They should be matched with the exact learning-objective wording in the course manual before submission.

Cloud infrastructure and AWS services: The solution uses AWS services including EC2, VPC, Elastic Load Balancing, EFS, RDS, S3, and CloudFormation.

**Networking:** A VPC provides an isolated network environment. Public and private subnets are configured across two Availability Zones, with routing and security groups controlling access.

**Infrastructure as Code:** CloudFormation templates define and provision the infrastructure in a repeatable and maintainable way.

**Compute resources:** EC2 instances host the CloudShirt ASP.NET Core application. A Launch Template defines the configuration used when instances are created.

**High availability and scalability:** An Application Load Balancer distributes incoming HTTP traffic to application instances managed by an Auto Scaling Group.

**Storage:** EFS provides shared file storage for application logs, while S3 stores objects such as exported data.

**Databases:** Amazon RDS for SQL Server provides a managed relational database for the application.

**Monitoring and logging:** Elasticsearch and Kibana provide a monitoring and log-analysis environment. Filebeat is configured to forward logs to Elasticsearch.

**Automation and serverless computing:** UserData automates EC2 instance configuration, while a separate CloudFormation template, `07-serverless.yaml`, is included for the serverless part of the solution.


## Requirements 

| REQ    | Solution |
| -------- | ------- |
| REQ-01  | The CloudShirt .NET application runs on an EC2 auto scaling group with a minimum og two instnaces. The instances are distrubuted across two availability zones and are registered behind an application load balancer. The ALB provides a single URL for accessing the application and distributes trafic betweek the available instances    |
| REQ-02 | The auto scaling group is configured to scale out from 2 to 4 instances at 18:00 eastern time and scale back to 2 instances at 20:00. This allows the applicaztion to handle insreased traffic during the expected peak period.     |
| REQ-03    | EFS is provisioned using Cloud formation and mounted on the CloudShirt web services at `/mnt/cloudshirt-logs`. The file system can be shared by the applciation instances so that log files are stored centrally and remain acceptable whrn instances are replaced or scaled.     |
| REQ-04  | An Amazon RDS SQL Server database is provisioned using AWS CloudFormation. The database is deployed in the private subnets and the CloudShirt application connects to it using the RDS endpoint. Database credentials and connection information are passed to the application through CloudFormation parameters.    |
| REQ-05 |  The `06-monitoring.yaml` template provisions an Elastic Stack monitoring instance with Elasticsearch and Kibana v8.x. Elasticsearch receives log data, while Kibana provides a web interface for searching and analysing it. The deployed services and access to the dashboard should be tested.   |
| REQ-06    | The UserData script attempts to install Filebeat on each application instance and configures it to collect files from `/mnt/cloudshirt-logs/*.log` and system logs from `/var/log/messages`. Filebeat is configured to send data to Elasticsearch. The script allows the application setup to continue if Filebeat installation fails.  |
|REQ-07 |A script is used to export the order data from the RDS database and store the exported data in an Amazon S3 bucket. This provides a scripted way of transferring database order information to durable object storage|

### IaC
The infrastructure is separated into the following templates:

`01-networking.yaml` — VPC, subnets, and networking resources.

`02-security.yaml` — security groups for the load balancer, web servers, EFS, RDS, and monitoring.

`03-storage.yaml` — EFS and S3 storage resources.

`04-database.yaml` — Amazon RDS database.

`05-application.yaml` — EC2 Launch Template, Application Load Balancer, target group, and Auto Scaling Group.

`06-monitoring.yaml` — Elastic Stack monitoring instance.

`07-serverless.yaml` — serverless resources.

`main.yaml` — master template that orchestrates the nested stacks.

The `scripts/userdata.sh` script installs the required dependencies, mounts EFS, configures the application database connection, publishes the .NET application, creates a systemd service, and attempts to configure Filebeat.

## Justification of choices 

## Roll-out manual 

1. **Prepare the AWS environment:** Sign in to the AWS Academy environment and select the configured AWS region. Confirm that the required EC2 key pair is available.

2. **Prepare the repository.** Ensure that the CloudFormation templates and scripts are committed to the repository and that scripts/userdata.sh is available at the URL referenced by the deployment script.

3. **Deploy the infrastructure.** Run the provided provisioning script, scripts/provision.sh, to package the templates and create or update the master CloudFormation stack.

## Recommmendations 

## Conclusion 

The project defines a modular AWS infrastructure for the CloudShirt application using CloudFormation. The application tier is designed to support high availability across two Availability Zones and scheduled scaling between 18:00 and 20:00 Eastern Time. The solution also provisions EFS, RDS, an Elastic Stack monitoring environment, and a separate serverless stack.

The configuration addresses the main infrastructure requirements, but some capabilities must be confirmed through deployment and testing. In particular, successful Filebeat log delivery, daily log rotation, the scripted RDS order export, and the exact serverless functionality require verification before the project can be reported as fully complete.
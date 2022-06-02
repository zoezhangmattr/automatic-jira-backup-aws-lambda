# automatic-jira-backup-aws-lambda

## Overview
this is a small py script deployed to aws lambda to retrive jira backup zip file by calling jira api , the lambda is triggered by cloudwatch event schedule, and upload backup zip file to aws s3 bucket.

### jira apis

* https://{site}/rest/backup/1/export
* https://{site}/rest/backup/1/export/runbackup
* https://{site}/rest/backup/1/export/lastTaskId
* https://{site}/rest/backup/1/export/getProgress
* https://{site}/plugins/servlet

## Deploy

### lambda layer
lambda removed the built-in python requests package, so that it is necessary to create layers with the package. in infra/scripts folder , there is `requirements.txt` file to install requests locally to `infra/layer/python` folder just run `infra/scripts/install.sh` with correct python 3.8 installed.

### jira api token
* [create-api-token](https://id.atlassian.com/manage-profile/security/api-tokens)
* make sure all required jira parameters are stored in aws parameter store, use `infra/scripts/ssm-put.sh` to create parameters in aws parameter store.

### terraform
* once layer and ssm are ready, make sure you have aws access to run the terraform
run `terraform init`, `terraform plan`, `terraform apply` as needed.

* if you need to change variables, just create a testing.tfvars file in infra, then run terraform plan -var-file testing.tfvars
```tf
function_name= "jira-backup"
lambda_runtime = "python3.8"
# lambda extra environment variables
extra_env_vars={}
# weekly every monday,thursday 21:30 utc time
schedule_expression= "cron(30 21 ? * MON,THU *)"
# maxium is 900(15 mins) if the backup is very big
lambda_timeout=300
# prefix path of parameter store for jira backup
ssm_prefix_path = "/jira-backup"
slack_channel = "#backup-notification"
slack_username = "jira-backup"
create_s3_bucket = true
s3_bucket_name="uniquebucketname"
enable_s3_lifecycle="Enabled"
# in days the backup object in s3 will be deleted
expired_in_days= 30
```


## jira automation rule
* jira backup usually takes around 30 mins to finish, so instead of putting in lambda to consume the timeout, create a jira automation rule to runbackup.
* create a jira automation rule if not yet https://{site}.atlassian.net/jira/settings/automation to trigger api call `https://{site}/rest/backup/1/export/runbackup`
the automation will run with schedule cron(0 0 21 ? * MON,THU) , utc time every monday,thursday 21:00

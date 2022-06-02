# coding=utf-8

import json
import time
import os
import requests
import boto3
from botocore.exceptions import ClientError
from time import gmtime, strftime
import urllib.parse
import urllib.request
from urllib.error import HTTPError
import logging

logging.basicConfig()

def get_logger():
    logger = logging.getLogger()
    if os.environ.get("LOG_LEVEL", "info") == "debug":
        logger.setLevel(logging.DEBUG)
    else:
        logger.setLevel(logging.INFO)
    return logger

logger = get_logger()
# -------------------------- #
# Parameter Store Client
# -------------------------- #
region=os.environ["AWS_REGION"]
ssm_client = boto3.client('ssm', region_name=region)
s3_client = boto3.client('s3', region_name=region)
def get_parameter(path):
    try:
        response = ssm_client.get_parameter(Name=path, WithDecryption=True)
        return response['Parameter']['Value']

    except ClientError as err:
        raise Exception(f'Unable to fetch parameter [{path}]: {err}')

# env configs
ssm_prefix = os.environ["SSM_PREFIX"]
s3_bucket=os.environ["BACKUP_S3"]
INCLUDE_ATTACHMENTS=os.environ.get('INCLUDE_ATTACHMENTS',"true")

site = os.environ.get("JIRA_SITE",get_parameter(f"{ssm_prefix}/site"))
user_name = os.environ.get("JIRA_USER",get_parameter(f"{ssm_prefix}/user"))
api_token = os.environ.get("JIRA_API_TOKEN",get_parameter(f"{ssm_prefix}/api-token"))
slack_url = os.environ.get("JIRA_SLACK_URL",get_parameter(f"{ssm_prefix}/slack-url"))
# it took too long to create backup so will disable it in lambda, and use jira automation rule
create_backup = os.environ.get("CREATE_BACKUP", "disabled")
# -------------------------- #
# Atalassian Jira API Request
# -------------------------- #
class Atlassian:
    """
    A class used to query jira api
    """

    def __init__(self):
        self.session = requests.Session()
        self.session.auth = (user_name, api_token)
        self.session.headers.update({'Content-Type': 'application/json', 'Accept': 'application/json'})
        self.payload = {"cbAttachments": INCLUDE_ATTACHMENTS, "exportToCloud": "true"}
        self.backup_endpoint = f"https://{site}/rest/backup/1/export"
        self.jira_backup_url = f"{self.backup_endpoint}/runbackup"
        self.jira_last_task_url=f"{self.backup_endpoint}/lastTaskId"
        self.jira_task_progress_url=f"{self.backup_endpoint}/getProgress"
        self.jira_servlet_url=f"https://{site}/plugins/servlet"
        self.backup_status = {}
        self.wait = 2

    def get_last_task_id(self):
        """
        get_last_task_id retrives the backup last task id.
        :return: task id
        """
        id = self.session.get(self.jira_last_task_url)
        if id.status_code != 200:
            raise Exception(id, id.text)
        else:
            logger.info(f"-> Last task id={id.text}")
            return id.text

    def get_task_progress(self, task_id):
        """
        get_task_progress gets the task progress status
        :parameter task_id: task id
        :return: download url of the backup
        """
        jira_task_status = f"{self.jira_task_progress_url}?taskId={task_id}"
        logger.info(f"-> Start to check task {task_id} status {jira_task_status}")
        time.sleep(self.wait)
        while 'result' not in self.backup_status.keys():
            r = self.session.get(jira_task_status)
            if r.status_code != 200:
                raise Exception(r, r.text)
                break
            self.backup_status = json.loads(r.text)
            status=self.backup_status['status'], 
            progress=self.backup_status['progress'], 
            description=self.backup_status['description']
            logger.info(f"-> [{task_id}] Current status: {status} progress: {progress}; desc: {description}")
            time.sleep(self.wait)
        download_url=f"{self.jira_servlet_url}/{self.backup_status['result']}"
        logger.info(f"-> Download url {download_url}")
        return download_url

    def create_jira_backup(self):
        """
        create_jira_backup creates a backup task
        :return: download url of the backup
        """
        payload=json.dumps(self.payload)
        backup = self.session.post(self.jira_backup_url, data=payload)
        if backup.status_code != 200:
            logger.error(f"-> Backup process failed to start url:{self.jira_backup_url} data:{payload}")
            notify_slack(":warning: Jira backup failed due to frequency limitation(every 48 hours)")
            raise Exception(backup, backup.text)
        else:
            task_id = json.loads(backup.text)['taskId']
            logger.info(f"-> Backup process successfully started: generated taskId={task_id}")
            download_url=self.get_task_progress(task_id)
            return download_url

    def stream_to_s3(self, url):
        """
        stream_to_s3 use the backup download url and stream the content to s3 bucket
        :parameter url: backup download url
        :return: none
        """
        logger.info('-> Streaming to S3')
        date = time.strftime("%Y%m%d%H%M%S")

        s3_file_path = f"jira/{date}.zip"

        response = self.session.get(url, stream=True)

        if response.status_code == 200:
            with response as part:
                part.raw.decode_content = True
                conf = boto3.s3.transfer.TransferConfig(multipart_threshold=10000, max_concurrency=4)
                try:
                    s3_res = s3_client.upload_fileobj(part.raw, s3_bucket, s3_file_path, Config=conf)
                except ClientError as err:
                    raise Exception(f'Unable to upload to s3 [{s3_bucket}/{s3_file_path}]: {err}')
            logger.info(f"-> Stream done [{s3_bucket}/{s3_file_path}]")
            notify_slack(f":white_check_mark: Jira backup is completed {s3_file_path}")
        else:
            logger.error(f"-> Get download file[{url}] failed {response.text}")
            raise Exception(response, response.text)

def notify_slack(message):
    username=os.environ["SLACK_USERNAME"]
    icon_emoji=os.environ.get("SLACK_ICON", ":atlassian-jra:")
    slack_channel=os.environ["SLACK_CHANNEL"]
    webhook_url=slack_url

    try:
        if webhook_url == "":
            logger.warning("-> Slack webhook url is empty. No message will be posted to slack")
            logger.info(f"-> notification message: {message}")
        else:
            logger.info(f"-> Notifying slack channel [{slack_channel}] with message: {message}")

            payload = {"channel": slack_channel, "username": username, "text": message, "icon_emoji": icon_emoji}

            logger.info(f"-> slack payload: {payload}")
            requests.post(webhook_url, json=payload)
    except Exception as err:
        logger.warning(f"-> Whoops... could not post to slack: {err}")

def lambda_handler(event, context):
    """
    Lambda function to do jira backup

    :param event: lambda expected event object
    :param context: lambda expected context object
    :returns: none
    """
    atlass = Atlassian()
    # by default this var is disabled, cause we dont want to create_jira_backup in lambda, takes too long.
    if create_backup == "enabled":
        url=atlass.create_jira_backup()
    else:
        id = atlass.get_last_task_id()
        logger.info(f"-> Last backup task id {id}")
        url=atlass.get_task_progress(id)
        logger.info(f"-> The backup download url is {url}")
    atlass.stream_to_s3(url)

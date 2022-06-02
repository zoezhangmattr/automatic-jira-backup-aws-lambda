
#!/bin/sh

aws ssm put-parameter --name /jira-backup/user --value $JIRA_USER --type String

aws ssm put-parameter --name /jira-backup/site --value $JIRA_SITE --type String

aws ssm put-parameter --name /jira-backup/api-token --value $JIRA_API_TOKEN --type SecureString 

aws ssm put-parameter --name /jira-backup/slack-url --value $SLACK_URL --type SecureString 

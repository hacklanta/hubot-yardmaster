Hubot Yardmaster
=============
Yardmaster is a Hubot plugin that allows you to change your current git branch on Jenkins.

###Environment Variables Required
* HUBOT_JENKINS_URL
* HUBOT_JENKINS_USER
* HUBOT_JENKINS_USER_API_KEY - Not your password. Find at {HUBOT_JENKINS_URL}/{HUBOT_JENKINS_USER}/configure
* HUBOT_JENKINS_JOB_NAME - Hubot job name on Jenkins (optional)
* GITHUB_TOKEN - Github API Auth token (optional)

###Usage
* hubot switch | change | build {job} to | with {branch} - Change job to branch on Jenkins and build.
* hubot (show | current | show current) branch for {job} - Shows current branch for job on Jenkins.
* hubot (go) build yourself | (go) ship yourself - Rebuilds default branch if set.
* hubot list jobs | jenkins list | all jobs | jobs {job} - Shows all jobs in Jenkins. Filters by job if provided.
* hubot build | rebuild {job} - Rebuilds job.
* hubot enable | disable {job} - Enable or disable job on jenkins.
* hubot show | show last | last (build | failure | output) for {job} - show output for last job
* hubot show | show output | output for {job} {number} - show output job output for number given
* hubot set branch message to {message} - set custom message when switching branches on a job
* hubot remove branch message - remove custom message. Uses default message.
* hubot show | show last | last (build | failure | output) for {job} - show output for last job.
* hubot show | show output | output for {job} {number} - show output job output for number given.
* hubot {job} status - show current build status and percent compelete of job and its dependencies.
* hubot set job repos - Pulls list of jobs and repos from jenkins and places in memory to validate branch names if github token provided.
* hubot remove job repos - Will remove job repos from memory.
* hubot watch job {job-url} - Will check job every minute and notify you on completion
* hubot (show|show last|last) (build) (date|time) for {job} - shows the last build date and time for a job

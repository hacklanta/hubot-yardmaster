# Description:
#   Interact with Jenkins instance remotely. Build jobs, change branches, start builders, lock jobs... The list goes on.
#
# Dependencies:
#   Nope
#
# Configuration:
#   HUBOT_JENKINS_URL - Jenkins base URL
#   HUBOT_JENKINS_USER - Jenins admin user
#   HUBOT_JENKINS_USER_API_KEY - Admin user API key. Not your password. Find at "{HUBOT_JENKINS_URL}/{HUBOT_JENKINS_USER}/configure" 
#   HUBOT_JENKINS_JOB_NAME - Hubot job name on Jenkins (optional)
#   GITHUB_TOKEN - Github API Auth token (optional)
#   MONITOR_JENKINS - true | false : If true, hubot will monitor the jenkins queue and start nodes when job queue is greater than 2.
#
# Commands:
#   hubot switch|change|build {job} to|with {branch} - Change job to branch on Jenkins and build.
#   hubot (show|current|show current) branch for {job} - Shows current branch for job on Jenkins.
#   hubot (go) build yourself|(go) ship yourself - Rebuilds default branch if set.
#   hubot list jobs|jenkins list|all jobs|jobs {job} - Shows all jobs in Jenkins. Filters by job if provided.
#   hubot build|rebuild {job} - Rebuilds job.
#   hubot show|show last|last (build|failure|output) for {job} - show output for last job
#   hubot show|show output|output for {job} {number} - show output job output for number given
#   hubot show|show output|output for {job} {number} - show output job output for number given.
#   hubot {job} status - show current build status and percent compelete of job and its dependencies.
#   hubot watch job {job-url} - Will check job every minute and notify you on completion
#   hubot (show|show last|last) (build) (date|time) for {job} - shows the last build date and time for a job
# 
# Author: 
#   @riveramj
#   @jalev

{parseString} = require 'xml2js'
cronJob = require('cron').CronJob

jenkinsURL = process.env.HUBOT_JENKINS_URL
jenkinsUser = process.env.HUBOT_JENKINS_USER
jenkinsUserAPIKey = process.env.HUBOT_JENKINS_USER_API_KEY
jenkinsHubotJob = process.env.HUBOT_JENKINS_JOB_NAME || ''
githubToken = process.env.GITHUB_TOKEN || ''
monitorJenkins = process.env.MONITOR_JENKINS || ''

JOBS = {}

getByFullUrl = (robot, url, callback) ->
  robot.http(url)
    .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
    .get() (err, res, body) ->
      if err
        robot.send "Encountered an error :( #{err}"
      else
        callback(res, body)

get = (robot, msg, queryOptions, callback) ->
  robot.http("#{jenkinsURL}/#{queryOptions}")
    .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
    .get() (err, res, body) ->
      if err
        msg.send "Encountered an error :( #{err}"
      else
        callback(res, body)

post = (robot, queryOptions, postOptions, callback) ->
  robot.http("#{jenkinsURL}/#{queryOptions}")
    .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
    .post(postOptions) (err, res, body) ->
      callback(err, res, body)

postByFullUrl = (robot, url, postOptions, callback) ->
  robot.http(url)
    .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
    .post(postOptions) (err, res, body) ->
      callback(err, res, body)

ifJobEnabled = (robot, msg, job, callback) ->
  get robot, msg, "job/#{job}/config.xml", (res, body) ->
    if res.statusCode is 404
      msg.send "Job '#{job}' does not exist."
    else
      parseString body, (err, result) ->
        jobStatus = (result?.project?.disabled[0] == 'true')
        
        if jobStatus
          msg.send "No can do. '#{job}' is disabled."
        else
          callback()

doesJobExist = (robot, msg, job, callback) ->
  yardmaster = robot.brain.get 'yardmaster' || {}
  if yardmaster?.jobRepos?
    possibleJob = yardmaster.jobRepos.filter (potentialJob) -> potentialJob.job == job
    if possibleJob.length
       callback(true)
    else
      msg.send "Job '#{job}' does not exist. If the job does exist, you need to update your job repos. Run 'set job repos' and then try again."
  else
    get robot, msg, "job/#{job}/config.xml", (res, body) ->
      if res.statusCode is 404
        msg.send "Job '#{job}' does not exist."
      else
        callback(true)

buildBranch = (robot, msg, job, branch = "") ->
  params = msg.match['4']

  if typeIsArray job
    for jobName in job
      do (jobName) ->
        console.log(jobName)
        if params
          #msg.send "I'm building #{jobName}"
          post robot, "job/#{jobName}/buildWithParameters?#{params}", "", (err, res, body) ->
            queueUrl = res.headers?["location"]
            if err
              msg.reply "Encountered an error on build. Error I got back was: #{err}"
            else if res.statusCode is 201
              msg.reply "#{jobName} has been added to the queue with the following parameters: \"#{params}\"."
              watchQueue robot, queueUrl, msg, jobName
        else
          msg.send "I'm building #{jobName}"
          post robot, "job/#{jobName}/buildWithParameters?#{params}", "", (err, res, body) ->
            queueUrl = res.headers?["location"]
            if err
              msg.reply "Encountered an error on build. Error I got back was: #{err}"
            else if res.statusCode is 201
              msg.reply "#{jobName} hsa been added to the queue."
              watchQueue robot, queueUrl, msg, jobName

  else
    console.log(job)
    if params
      post robot, "job/#{job}/buildWithParameters?", "", (err, res, body) ->
        queueUrl = res.headers?["location"]
        if err
          msg.reply "Encountered an error on build. Error I got back was: #{err}"
        else if res.statusCode is 201
          msg.reply "#{job} has been added to the queue."
          watchQueue robot, queueUrl, msg, job
    else
      post robot, "job/#{job}/build/", "", (err, res, body) ->
        queueUrl = res.headers?["location"]
        if err
          msg.reply "Encountered an error on build. Error I got back was: #{err}"
        else if res.statusCode is 201
          msg.reply "#{job} has been added to the queue."
          watchQueue robot, queueUrl, msg, job


typeIsArray = Array.isArray || ( value ) -> return {}.toString.call( value ) is '[object Array]'

# Finds out whether or not an item exists in our array.
Array::where = (query) ->
    return [] if typeof query isnt "object"
    hit = Object.keys(query).length
    results = @filter (item) ->
        match = 0
        for key, val of query
            match += 1 if item[key] is val
        if match is hit then true else false

    if results.length >=1
      return true
    false

getCurrentBranch = (body) ->
  branch = ""
  parseString body, (err, result) ->
    branch = result?.project?.scm[0]?.branches[0]['hudson.plugins.git.BranchSpec'][0].name[0]

  branch

buildJob = (robot, msg) ->
  # Enable specification of multiple jobs via job1, job2, jobN...
  jobTemp = msg.match[3]

  if not jobTemp
    job = msg.match[2].trim().split(",")
  else
    job = jobTemp.trim().split(",")
      
  console.log("I got a request. It says: #{job}")

  # Flatten into a single value since we don't want to do any array parsing later.
  if job.length == 1
    job = job[0]
    
  # Ensure that a job exists by parsing the list of jobs
  get robot, msg, "api/json", (res, body) ->
    jenkinsJobs = JSON.parse(body)

    if typeIsArray job
      for jobName in job
        jobExist = jenkinsJobs['jobs'].where name: "#{jobName}"
        if not jobExist
          msg.reply "Sorry, I couldn't find job with name #{jobName}"
          return
    else
      jobExist = jenkinsJobs['jobs'].where name: "#{job}"
      if not jobExist
        msg.reply "sorry, I couldn't find job with name #{job}"
        return

    # We succeeded the check, now we actually do the building
    buildBranch(robot, msg, job)

listJobs = (robot, msg) ->
  jobFilter = new RegExp(msg.match[2].trim(),"i")
  
  get robot, msg, "api/json", (res, body) ->
    response = ""
    jobs = JSON.parse(body).jobs
    for job in jobs
      lastBuildState = if job.color == "blue" then "PASSING" else "FAILING"

      if jobFilter?
        if jobFilter.test job.name
          response += "#{job.name} is #{lastBuildState}: #{job.url}\n"
      else
        response += "#{job.name} is #{lastBuildState}: #{job.url}\n"
      
    msg.send """
      Here are the jobs
      #{response}
    """

getJobTimeStamp = (robot, msg, jobUrl, callback) ->
  get robot, msg, "#{jobUrl}/api/json", (res, body) ->
    rawDateTime = JSON.parse(body).timestamp
    timeAndDate = new Date(rawDateTime)
    callback(timeAndDate)

showBuildOuput = (robot, msg) ->
  lastJob = if msg.match[2].trim() == "failure" then "lastFailedBuild" else "lastBuild"
  job = msg.match[3].trim()

  get robot, msg, "job/#{job}/#{lastJob}/logText/progressiveText", (res, body) ->
    if res.statusCode is 404
      msg.send "Did not find job '#{job}."
    else
      getJobTimeStamp robot, msg, "job/#{job}/#{lastJob}", (timeAndDate) ->
        msg.send """
          Job last built on #{timeAndDate}
          #{jenkinsURL}/job/#{job}/#{lastJob}/console
          Output is:
          #{body}
        """

showSpecificBuildOutput = (robot, msg) ->
  job = msg.match[2].trim()
  jobNumber = msg.match[3].trim()
  
  get robot, msg, "job/#{job}/#{jobNumber}/logText/progressiveText", (res, body) ->
    if res.statusCode is 404
      msg.send "Did not find output for job number '#{jobNumber}' for '#{job}."
    else
      getJobTimeStamp robot, msg, "job/#{job}/#{lastJob}", (timeStamp) ->
      msg.send """
        #{jenkinsURL}/job/#{job}/#{jobNumber}/console
        Output is: 
        #{body}
      """
isJobBuilding = (robot, msg, job, callback) ->
  get robot, msg, "job/#{job}/lastBuild/api/xml?depth=1", (res, body) ->
    parseString body, (err, result) ->
      isBuilding = result?.freeStyleBuild?.building[0] == "true"
      percentComplete = result?.freeStyleBuild?.executor?[0].progress[0] || 0
      callback(isBuilding, percentComplete)

getDownstreamJobs = (robot, msg, job, callback) ->
  get robot, msg, "job/#{job}/api/json", (res, body) ->
    jobs = JSON.parse(body).downstreamProjects
    downstreamJobs = []
    for job in jobs
      downstreamJobs.push job.name
    callback(downstreamJobs)

trackJobs = (robot, msg, jobs, jobStatus, callback) ->
  job = jobs.shift()
  isJobBuilding robot, msg, job, (isBuilding, percentComplete) ->
    if isBuilding
      jobStatus.push { name: job, percent: percentComplete }
      callback(jobStatus)
    else
      getDownstreamJobs robot, msg, job, (downstreamJobs) ->
        if downstreamJobs.length
          jobs = jobs.concat(downstreamJobs)
          trackJobs robot, msg, jobs, jobStatus, (callback)
        else if jobs.length
           trackJobs robot, msg, jobs, jobStatus, (callback)
        else
          jobStatus.push { name: job }
          callback(jobStatus)

        jobStatus.push { name: job }

registerNewWatchedJob = (robot, id, user, url, queue, msg) ->
  job = new WatchJob(id, user)
  if queue
    job.startQueue robot, url, msg
  else
    job.start robot, url, msg
  JOBS[id] = job

unregisterWatchedJob = (robot, id)->
  if JOBS[id]
    JOBS[id].stop()
    yardmaster = robot.brain.get('yardmaster') || {}
    yardmaster.watchJobs ||= {}
    delete yardmaster.watchJobs[id]
    delete JOBS[id]
    robot.brain.set 'yardmaster', yardmaster

createCronWatchJob = (robot, url, msg, queue = false, jobName="") -> 
  id = Math.floor(Math.random() * 1000000) while !id? || JOBS[id]

  user = msg.message.user

  yardmaster = robot.brain.get('yardmaster') || {}
  yardmaster.watchJobs ||= {}
  yardmaster.watchJobs[id] = { jobUrl: url, user: user }
  robot.brain.set 'yardmaster', yardmaster
  
  registerNewWatchedJob robot, id, user, url, queue, msg
  
  if !queue
    msg.reply "job #{jobName} is now building at #{url}"

trimUrl = (url) ->
  urlCorrect = /[0-9]/.test(url.slice (url.length - 1))
  if urlCorrect
    url
  else
    trimUrl url.slice(0, -1)

findJobNumber = (url, originalURL) ->
  possibleNumber = /[0-9]/.test(url.slice(url.length - 1))
  if !possibleNumber
    originalURL.slice(url.length, originalURL.length)
  else
    findJobNumber url.slice(0, -1), originalURL


watchQueue = (robot, url, msg) ->
  trimmedURL = url.slice(0, url.length - 1)

  jobNumber = findJobNumber trimmedURL, trimmedURL

  queueUrl = "#{jenkinsURL}/queue/item/#{jobNumber}/api/json"

  getByFullUrl robot, queueUrl, (res, body) ->
    if res.statusCode is 404
      msg.send "#{url} does not seem to be a valid url. Couldn't watch job."
    else
      createCronWatchJob robot, queueUrl, msg, true

watchJob = (robot, msg) ->
  jobUrl = trimUrl msg.match[1].trim()

  getByFullUrl robot, "#{jobUrl}/api/json", (res, body) ->
    if res.statusCode is 404
      msg.send "#{jobUrl} does not seem to be a valid job url."
    else
      createCronWatchJob robot, jobUrl, msg

cancelJob = (robot, msg) ->
  jobUrl = trimUrl msg.match[1].trim()

  postByFullUrl robot, "#{jobUrl}/stop", "", (err, res, body) ->
    if err
      msg.send "got #{err} when tryign to post to #{jobUrl}/stop"
    else if res.statusCode is 404
      msg.send "#{jobUrl} does not seem to be a valid job url."
    else
      getByFullUrl robot, "#{jobUrl}/api/json", (res, body) ->
        result = JSON.parse(body).result
        if result == "ABORTED"
          msg.send "Job successfully canceled. Ready for new orders."
        else
          msg.send "I tried to cancel job but I'm not 100% sure if it worked."

module.exports = (robot) ->
  getWithoutMsg = (queryOptions, callback) ->
    robot.http("#{jenkinsURL}/#{queryOptions}")
      .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
      .get() (err, res, body) ->
        if err
          console.log "Encountered an error :( #{err}"
        else
          callback(res, body)

  checkBuildQueue = (callback) ->
    getWithoutMsg "/queue/api/json", (res, body) ->
      callback(JSON.parse(body).items)

  if monitorJenkins
    cronjob = new cronJob("*/1 * * * *", =>
      checkBuildQueue (queue) ->
        if queue.length != 0
          startSlaveNode (result) ->
            console.log result
    )
    cronjob.start()

  robot.respond /(list jobs|jenkins list|all jobs|jobs)\s*(.*)\.?/i, (msg) ->
    listJobs(robot, msg)

  robot.respond /(build|rebuild)\s(([\w\.\-_][,\w\.\-_]+)\swith\s(.*)|([\w+\.\-_ ][,\w\.\-_ ]+)|([\w+\.\-_ ]))/i, (msg) ->
    console.log("Hit multijob with params switch")
    buildJob(robot, msg)

  robot.respond /(show|show last|last) (build|failure|output) for (.+)\.?/i, (msg) ->
    showBuildOuput(robot, msg)
  
  robot.respond /(?:show|show last|last) (?:build\s)?(?:date|time) for (.+)\.?/i, (msg) ->
    job = msg.match[1].trim()
    getJobTimeStamp robot, msg, "job/#{job}/lastBuild", (timeAndDate) ->
        msg.send "#{job} last built on #{timeAndDate[0]} at #{timeAndDate[1]} utc"
  
  robot.respond /(.+) status\.?/i, (msg) ->
    job = msg.match[1].trim()
    doesJobExist robot, msg, job, (exists) ->
      if exists
        msg.send "Checking on #{job} and its dependencies for you."

        trackJobs robot, msg, [job], [], (callback) ->
          jobStatus = ""
          callback.map (jobEntry) ->
            if jobEntry.percent
              jobStatus = jobStatus + "#{jobEntry.name} is building and is #{jobEntry.percent}% complete.\n"
            else
              jobStatus = jobStatus + "#{jobEntry.name} is not building.\n"
          msg.send jobStatus

  robot.respond /watch job (.+)\.?/i, (msg) ->
    watchJob robot, msg

  robot.respond /(?:delete|cancel)(?: job)? (.+)/i, (msg) ->
    cancelJob robot, msg

class WatchJob
  constructor: (id, user) ->
    @id = id
    @user = user

  checkJobStatus: (url, robot, job, msg) ->
    getByFullUrl robot, "#{url}/api/json", (res, body) ->
      if res.statusCode is 404
        unregisterWatchedJob robot, job.id
        msg.send "#{url} does not seem to be a valid job url. Removing from watch list"
      else
        result = JSON.parse(body).result

        if result?
          unregisterWatchedJob robot, job.id
          msg.reply "Hi there! job #{url} has finished with status: #{result}."

  checkQueueStatus: (url, robot, job, msg) ->
    getByFullUrl robot, url, (res, body) ->
      if res.statusCode is 404
        unregisterWatchedJob robot, job.id
        msg.send "#{url} does not seem to be a valid job url. Removing from watch list"
      else
        jobUrl = JSON.parse(body).executable?.url

        if jobUrl?
          unregisterWatchedJob robot, job.id
          createCronWatchJob robot, jobUrl, msg

  start: (robot, url, msg) ->
    @cronjob = new cronJob("*/1 * * * *", =>
      @checkJobStatus url, robot, this, msg
    )
    @cronjob.start()

  startQueue: (robot, url, msg) ->
    @cronjob = new cronJob("*/1 * * * *", =>
      @checkQueueStatus url, robot, this, msg
    )
    @cronjob.start()


  stop: ->
    @cronjob.stop()

  sendMessage: (robot, message) ->
    envelope = user: @user, room: @user.room
    robot.reply envelope, message



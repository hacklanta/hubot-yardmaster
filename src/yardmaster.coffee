# Description:
#   Changes the branch on your jenkins instance remotely
#
# Dependencies:
#   Nope
#
# Configuration:
#   HUBOT_JENKINS_URL - Jenkins base URL
#   HUBOT_JENKINS_USER - Jenins admin user
#   HUBOT_JENKINS_USER_API_KEY - Admin user API key. Not your password. Find at "{HUBOT_JENKINS_URL}/{HUBOT_JENKINS_USER}/configure" 
#   HUBOT_JENKINS_JOB_NAME - Hubot job name on Jenkins (optional)
#
# Commands:
#   hubot switch|change|build {job} to|with {branch} - Change job to branch on Jenkins and build.
#   hubot (show) current branch for {job} - Shows current branch for job on Jenkins.
#   hubot (go) build yourself|(go) ship yourself - Rebuilds default branch if set.
#   hubot list jobs|jenkins list|all jobs|jobs {job} - Shows all jobs in Jenkins. Filters by job if provided.
#   hubot build|rebuild {job} - Rebuilds job.
#   hubot enable|disable {job} - Enable or disable job on jenkins.
#   hubot show|show last|last (build|failure|output) for {job} - show output for last job
#   hubot show|show output|output for {job} {number} - show output job output for number given
#   hubot set branch message to {message} - set custom message when switching branches on a job
#   hubot remove branch message - remove custom message. Uses default message.
#   hubot show|show last|last (build|failure|output) for {job} - show output for last job.
#   hubot show|show output|output for {job} {number} - show output job output for number given.
#   hubot {job} status - show current build status and percent compelete of job and its dependencies.
# 
# Author: 
#   hacklanta

{parseString} = require 'xml2js'

jenkinsURL = process.env.HUBOT_JENKINS_URL
jenkinsUser = process.env.HUBOT_JENKINS_USER
jenkinsUserAPIKey = process.env.HUBOT_JENKINS_USER_API_KEY
jenkinsHubotJob = process.env.HUBOT_JENKINS_JOB_NAME || ''

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
  get robot, msg, "job/#{job}/config.xml", (res, body) ->
    if res.statusCode is 404
      msg.send "Job '#{job}' does not exist."
    else 
      callback(true)

buildBranch = (robot, msg, job, branch = "") ->
  ifJobEnabled robot, msg, job, (jobStatus) ->
    post robot, "job/#{job}/build", "", (err, res, body) ->
      if err
        msg.send "Encountered an error on build :( #{err}"
      else if res.statusCode is 201
        if branch
          customMessage = robot.brain.get("yardmaster")?["build-message"]
          if customMessage
            customMessage = customMessage.replace /job/, job
            customMessage = customMessage.replace /branch/, branch
            msg.send customMessage
          else
            msg.send "#{job} is building with #{branch}"
        else if job == jenkinsHubotJob
          msg.send "I'll Be right back"
        else
          msg.send "#{job} is building."
      else
        msg.send "something went wrong with #{res.statusCode} :(" 

getCurrentBranch = (body) ->
  branch = ""
  parseString body, (err, result) ->
    branch = result?.project?.scm[0]?.branches[0]['hudson.plugins.git.BranchSpec'][0].name[0]

  branch

buildJob = (robot, msg) ->
  job = msg.match[2]

  get robot, msg, "job/#{job}/", (res, body) ->
    if res.statusCode is 404
      msg.send "No can do. Didn't find job '#{job}'."
    else if res.statusCode == 200
      buildBranch(robot, msg, job)

switchBranch = (robot, msg) ->
  job = msg.match[2]
  branch = msg.match[4]

  ifJobEnabled robot, msg, job, (jobStatus) ->
    get robot, msg, "job/#{job}/config.xml", (res, body) ->
      # this is a regex replace for the branch name
      # Spaces below are to keep the xml formatted nicely
      # TODO: parse as XML and replace string (drop regex)
      config = body.replace /\<hudson.plugins.git.BranchSpec\>\n\s*\<name\>.*\<\/name\>\n\s*<\/hudson.plugins.git.BranchSpec\>/g, "<hudson.plugins.git.BranchSpec>\n        <name>#{branch}</name>\n      </hudson.plugins.git.BranchSpec>"   

      # try to update config
      post robot, "job/#{job}/config.xml", config, (err, res, body) ->
        if err
          msg.send "Encountered an error :( #{err}"
        else if res.statusCode is 200
          # if update successful build branch
          buildBranch(robot, msg, job, branch)  
        else if res.statusCode is 404
          msg.send "Job '#{job}' not found" 
        else
          msg.send "something went wrong :(" 

showCurrentBranch = (robot, msg) ->
  job = msg.match[2]
 
  get robot, msg, "job/#{job}/config.xml", (res, body) ->
    currentBranch = getCurrentBranch(body)
    if currentBranch? 
       msg.send("current branch is '#{currentBranch}'")
    else
       msg.send("Did not find job '#{job}'")

listJobs = (robot, msg) ->
  jobFilter = new RegExp(msg.match[2],"i")
  
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

changeJobState = (robot, msg) ->
  changeState = msg.match[1]
  job = msg.match[2]

  post robot, "job/#{job}/#{changeState}", "", (err, res, body) ->
    if err
      msg.send "something went wrong! Error: #{err}."
    else if res.statusCode == 302
      msg.send "#{job} has been set to #{changeState}."
    else if res.statusCode == 404
      msg.send "Job '#{job}' does not exist."
    else
      msg.send "Not sure what happened. You should check #{jenkinsURL}/job/#{job}/"

showBuildOuput = (robot, msg) ->
  lastJob = if msg.match[2] == "failure" then "lastFailedBuild" else "lastBuild"
  job = msg.match[3]

  get robot, msg, "job/#{job}/#{lastJob}/logText/progressiveText", (res, body) ->
    if res.statusCode is 404 
      msg.send "Did not find job '#{job}."
    else
      msg.send """
        #{jenkinsURL}/job/#{job}/#{lastJob}/console
        Output is: 
        #{body}
      """

showSpecificBuildOutput = (robot, msg) -> 
  job = msg.match[2]
  jobNumber = msg.match[3]
  
  get robot, msg, "job/#{job}/#{jobNumber}/logText/progressiveText", (res, body) ->
    if res.statusCode is 404 
      msg.send "Did not find output for job number '#{jobNumber}' for '#{job}."
    else
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

trackJob = (robot, msg, job, callback) ->
  isJobBuilding robot, msg, job, (isBuilding, percentComplete) ->
    if isBuilding
      callback("#{job} is currently building and is #{percentComplete}% complete.")
    else 
      callback("#{job} is not building.")
      getDownstreamJobs robot, msg, job, (downstreamJobs) ->
        if downstreamJobs
          for downstreamJob in downstreamJobs
            trackJob robot, msg, downstreamJob, (callback)
        

module.exports = (robot) ->             
  robot.respond /(switch|change|build) (.+) (to|with) (.+)/i, (msg) ->
    switchBranch(robot, msg)

  robot.respond /(show\s)?current branch for (.+)/i, (msg) ->
    showCurrentBranch(robot, msg)
  
  robot.respond /(go )?(build yourself)|(go )?(ship yourself)/i, (msg) ->
    if jenkinsHubotJob
      buildBranch(robot, msg, jenkinsHubotJob)
    else
      msg.send("No hubot job found. Set {HUBOT_JENKINS_JOB_NAME} to job name.")

  robot.respond /(list jobs|jenkins list|all jobs|jobs)\s*(.*)/i, (msg) ->
    listJobs(robot, msg)

  robot.respond /(build|rebuild) (.+)/i, (msg) ->
    buildJob(robot, msg)

  robot.respond /(disable|enable) (.+)/i, (msg) ->
    changeJobState(robot, msg)
  
  robot.respond /(show|show last|last) (build|failure|output) for (.+)/i, (msg) ->
    showBuildOuput(robot, msg)
  
  robot.respond /(show|show output|output) for (.+) ([0-9]+)/i, (msg) ->
    showSpecificBuildOutput(robot, msg)
  
  robot.respond /set branch message to (.+)/i, (msg) ->
    message = msg.match[1]
    robot.brain.set 'yardmaster', { "build-message": message }
    msg.send "Custom branch message set."

  robot.respond /remove branch message/i, (msg) ->
    robot.brain.remove 'yardmaster'
    msg.send "Custom branch message removed."
  
  robot.respond /(.+) status/i, (msg) ->
    job = msg.match[1]
    doesJobExist robot, msg, job, (exists) ->
      if exists
        msg.send "Checking on #{job} and its dependencies for you."
      
        trackJob robot, msg, job, (jobStatus) ->

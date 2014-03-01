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
#   hubot switch|change|build {job} to|with {branch} - Change {job} to {branch} on Jenkins and build
#   hubot (show) current branch for {job} - Shows current branch for {job} on Jenkins
# 
# Author: 
#   hacklanta

{parseString} = require 'xml2js'

module.exports = (robot) ->

  jenkinsURL = process.env.HUBOT_JENKINS_URL
  jenkinsUser = process.env.HUBOT_JENKINS_USER
  jenkinsUserAPIKey = process.env.HUBOT_JENKINS_USER_API_KEY
  jenkinsHubotJob = process.env.HUBOT_JENKINS_JOB_NAME || ''

  buildBranch = (job, msg, branch = '') ->
    robot.http("#{jenkinsURL}/job/#{job}/build")
      .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
      .post() (err, res, body) ->
        if err
          msg.send "Encountered an error on build :( #{err}"
        else if res.statusCode is 201
          if branch 
            msg.send "#{job} is building with #{branch}"
          else
            msg.send "#{robot.name} is rebuilding."
        else
          msg.send "something went wrong with #{res.statusCode} :(" 

  getCurrentBranch = (body) ->
    branch = ""
    parseString body, (err, result) ->
      branch = result?.project?.scm[0]?.branches[0]['hudson.plugins.git.BranchSpec'][0].name[0]

    branch
    
  # Switch Current Branch  
  robot.respond /(switch|change|build) (.+) (to|with) (.+)/i, (msg) ->
    job = msg.match[2]
    branch = msg.match[3]

    robot.http("#{jenkinsURL}/job/#{job}/config.xml")
      .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
      .get() (err, res, body) ->
        if err
          msg.send "Encountered an error :( #{err}"
        else
          # this is a regex replace for the branch name
          # Spaces below are to keep the xml formatted nicely
          # TODO: parse as XML and replace string (drop regex)
          config = body.replace /\<hudson.plugins.git.BranchSpec\>\n\s*\<name\>.*\<\/name\>\n\s*<\/hudson.plugins.git.BranchSpec\>/g, "<hudson.plugins.git.BranchSpec>\n        <name>#{branch}</name>\n      </hudson.plugins.git.BranchSpec>"   
          
          # try to update config
          robot.http("#{jenkinsURL}/job/#{job}/config.xml")
            .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
            .post(config) (err, res, body) ->
              if err
                msg.send "Encountered an error :( #{err}"
              else if res.statusCode is 200
                # if update successful build branch
                buildBranch(job, msg, branch)  
              else if  res.statusCode is 404
                 msg.send "job '#{job}' not found" 
              else
                msg.send "something went wrong :(" 
  

  # Show Current Branch 
  robot.respond /(show\s)?current branch for (.+)/i, (msg) ->
    job = msg.match[2]
    
    robot.http("#{jenkinsURL}/job/#{job}/config.xml")
      .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
      .get() (err, res, body) ->
        if err
          msg.send "Encountered an error :( #{err}"
        else  
          currentBranch = getCurrentBranch(body)
          if currentBranch? 
             msg.send("current branch is '#{currentBranch}'")
          else
             msg.send("Did not find job '#{job}'")
  

  robot.respond /(go )?(build yourself)|(go )?(ship yourself)/i, (msg) ->
    if jenkinsHubotJob
      buildBranch(jenkinsHubotJob, msg)
    else
      msg.send("No hubot job found. Set {HUBOT_JENKINS_JOB_NAME} to job name.")


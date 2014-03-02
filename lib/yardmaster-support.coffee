_ = require 'underscore'

class Yardmaster
  constructor: (@robot) ->

  jenkinsURL = process.env.HUBOT_JENKINS_URL
  jenkinsUser = process.env.HUBOT_JENKINS_USER
  jenkinsUserAPIKey = process.env.HUBOT_JENKINS_USER_API_KEY
  jenkinsHubotJob = process.env.HUBOT_JENKINS_JOB_NAME || ''

  baseQuery: (job, queryOptions="", headers) ->
    url = "#{jenkinsURL}/job/#{job}"
    
    headers ||= {}
    
    base =
      _.reduce(
        Object.keys(headers),
        (base, header) -> base.header(header, headers[header]),
        @robot.http("#{url}/#{queryOptions}")
      )
    
    base
      .auth("#{jenkinsUser}", "#{jenkinsUserAPIKey}")
   

  post: (callback, config = "") ->
    @baseQuery
      .post(config) (err, res, body) ->
        callback?(err, res, body)

module.exports = Yardmaster

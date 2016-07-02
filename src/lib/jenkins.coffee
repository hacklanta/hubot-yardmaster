# jenkins.coffee

# Our abstractions over various Jenkins actions that hubot-yardmaster uses. We try to minimize
# shared state, but there are a few global defaults that we will require. Particularly, the Jenkins
# URL, user, and API key.
class JenkinsAPI
  # The URL that this JenkinsAPI instance is associated with.
  jenkinsURL: undefined

  # The default Jenkins username that this JenkinsAPI instance will use in absence of any other
  # credentials.
  defaultJenkinsUser: undefined

  # The default Jenkins API key that this JenkinsAPI instance will use in absence of any other
  # credentials.
  defaultJenkinsAPIKey: undefined

  # Init the Jenkins connection with a url, default user, and default key.
  # The defaults are used whenever override values aren't provided in an individual call.
  constructor: (url, user, key) ->
    this.jenkinsURL = url
    this.defaultJenkinsUser = user
    this.defaultJenkinsAPIKey = key

  # Invoke a function with the current user and API key provided to that function.
  #
  # @param [Object] robot The robot object provided by Hubot.
  # @param [String] username The chat username to pull authentication information for.
  # @param [Function] callback A callback function to pass the computed user and apiKey to. The
  #   function should accept two parameters: an error parameter that error messages will be passed
  #   into and an object that contains the keys user and apiKey.
  withAuthentication: (robot, username, callback) ->
    authStructure = robot.brain.get('yardmaster')?.auth?[username] || {}

    user = authStructure.user || this.defaultJenkinsUser
    apiKey = authStructure.apiKey || this.defaultJenkinsAPIKey

    callback(undefined, user: user, apiKey: apiKey)

  # Determine if custom authentication information exists for a particular user.
  #
  # @param [Object] robot The robot object provided by Hubot.
  # @param [String] username The chat username to check for custom authentication under.
  # @param [Function] callback A callback function that accepts one parameter: an error parameter.
  #   If no error is passed into the function, then the user has custom authentication information
  #   in the robot brain.
  checkAuthentcation: (robot, username, callback) ->
    yardmaster = robot.brain.get('yardmaster') || {}
    yardmaster.auth ||= {}
    jenkinsUsername = yardmaster.auth[username]?.user

    if jenkinsUsername?
      callback()
    else
      callback("No such user found.")

  # Clear custom authentication information for a user.
  #
  # @param [Object] robot The robot object provided by Hubot.
  # @param [String] username The chat username to clear authentication for.
  # @param [Function] callback A callback that accepts a single parameter: an error parameter that
  #   contains an error message if no authentication information is found for the user.
  clearAuthentication: (robot, username, callback) ->
    yardmaster = robot.brain.get('yardmaster') || {}
    yardmaster.auth ||= {}

    if yardmaster.auth[username]?
      delete yardmaster.auth[username]
      robot.brain.set 'yardmaster', yardmaster

      callback()
    else
      callback("No such user found.")

  # Set Jenkins authentication information for a chat user. This method will attempt to validate
  # the information provided to it and will only record the credentials if they appear to be valid.
  #
  # @param [Object] robot The robot object provided by Hubot.
  # @param [String] username The chat username we're setting authentication for.
  # @param [String] jenkinsUsername The Jenkins username of the chat user.
  # @param [String] jenkinsApiKey The API key for the Jenkins username.
  # @param [Function] callback A callback that accepts a single error parameter that will contain
  #   an error message if the credentials are invalid and will be undefined if the authentication
  #   was successful.
  setAuthentication: (robot, username, jenkinsUsername, jenkinsApiKey, callback) ->
    url = this.jenkinsURL + "/api/json"
    robot.http(url)
      .auth(jenkinsUsername, jenkinsApiKey)
      .get() (err, res, body) ->
        if err
          callback(err)
        else if res.statusCode != 200
          callback("Status code #{res.statusCode}")
        else
          yardmaster = robot.brain.get('yardmaster') || {}
          yardmaster.auth ||= {}

          yardmaster.auth[username] =
            user: jenkinsUsername
            apiKey: jenkinsApiKey

          robot.brain.set 'yardmaster', yardmaster

          callback()

  # Execute a get request against Jenkins with the Jenkins URL prefixed on the path and user
  # authentication information provided.
  #
  # @param [Object] robot The robot object provided by Hubot.
  # @param [String] username The chat username we're executing the request on behalf of.
  # @param [String] path The path under Jenkins to access.
  # @param [Function] callback A standard http function callback with three parameters: err, res, and body.
  get: (robot, username, path, callback) ->
    this.unprefixedGet(robot, username, "#{this.jenkinsURL}/#{path}", callback)

  # Execute a get request against Jenkins with authentication information provided.
  #
  # @param [Object] robot The robot object provided by Hubot.
  # @param [String] username The chat username we're executing the request on behalf of.
  # @param [String] url The full Jenkins URL to access.
  # @param [Function] callback A standard http function callback with three parameters: err, res, and body.
  unprefixedGet: (robot, username, url, callback) ->
    this.withAuthentication robot, username, (err, {user, apiKey}) ->
      robot.http(url)
        .auth("#{user}", "#{apiKey}")
        .get()(callback)

  # Execute a post request against Jenkins with the Jenkins URL prefixed on the path and user
  # authentication information provided.
  #
  # @param [Object] robot The robot object provided by Hubot.
  # @param [String] username The chat username we're executing the request on behalf of.
  # @param [String] path The path under Jenkins to access.
  # @param [Function] callback A standard http function callback with three parameters: err, res, and body.
  post: (robot, username, path, postOptions, callback) ->
    this.unprefixedPost(robot, username, "#{this.jenkinsURL}/#{path}", callback)

  # Execute a post request against Jenkins with authentication information provided.
  #
  # @param [Object] robot The robot object provided by Hubot.
  # @param [String] username The chat username we're executing the request on behalf of.
  # @param [String] url The full Jenkins URL to access.
  # @param [Function] callback A standard http function callback with three parameters: err, res, and body.
  unprefixedPost: (robot, username, url, postOptions, callback) ->
    withAuthentication robot, username, (err, {user, apiKey}) ->
      robot.http(url)
        .auth("#{user}", "#{apiKey}")
        .post(postOptions)(callback)

module.exports = JenkinsAPI

fs = require 'fs'
path = require 'path'
mkdirp = require 'mkdirp'

_ = require 'lodash'
progeny = require 'progeny'


# Allows modules included by jaded-brunch to be overwritten by
# a module in the current working directory's ./node_modules.
localRequire = (module) ->
  try
    modulePath = path.join process.cwd(), 'node_modules', module
    return require modulePath

  catch userError
    throw userError unless userError.code is 'MODULE_NOT_FOUND'

    try
      return require module

    catch localError
      throw localError


module.exports = class PugBrunchPlugin
  brunchPlugin: yes
  type: 'template'
  extension: 'pug'
  pattern: '/(\.pug|\.jade)$/'
  pugOptions: {}

  staticPath: 'public'
  projectPath: path.resolve process.cwd()

  staticPatterns: /^app(\/|\\)(.+)\.static(\.pug|\.jade)$/

  extensions:
    static: 'html'
    client: 'js'

  constructor: (@config) ->
    @configure()

    discoverDependencies = progeny
      rootPath: @config.paths.root

    @getDependencies = (compiler, data, path) ->
      discoverDependencies data, path, compiler

  configure: ->
    if @config.plugins?.pug?
      options = @config?.plugins?.pug or @config.plugins.pug
    else
      options = {}

    if options.staticPatterns?
      @staticPatterns = options.staticPatterns

    if options.locals?
      @locals = options.locals
    else
      @locals = {}

    if options.path?
      @staticPath = options.path
    else if @config.paths?.public?
      @staticPath = @config.paths.public

    if options.pug?
      @pugOptions = options.pug
    else
      @pugOptions = _.omit options, 'staticPatterns', 'path', 'module', 'extension', 'clientExtension', 'patches'

    @pugOptions.compileDebug ?= @config.optimize is false
    @pugOptions.pretty ?= @config.optimize is false

    pugPath = path.dirname require.resolve 'pug'

    @include = [
      path.join pugPath, '..', 'runtime.js'
    ]

    pugModule = options.module or 'pug'

    @pug = localRequire pugModule

    if options.extensions?
      for key, value of options.extensions
        @extensions[key] = value

    patches = options.patches or []
    patches = [patches] if _.isString patches

    patches.map (patch) =>
      console.log patch
      patchModule = localRequire patch
      patchModule @pug

  makeOptions: (data) ->
    # Allow for default data in the jade options hash
    if @pugOptions.locals?
      locals = _.extend {}, @pugOptions.locals, data
    else
      locals = data

    # Allow for custom options to be passed to jade
    return _.extend {}, @pugOptions,
      locals: data

  templateFactory: (data, options, templatePath, callback, clientMode) ->
    try
      if clientMode is true
        method = @pug.compileClient
      else
        method = @pug.compile

      template = method data, options

    catch e
      error = e

    callback error, template, clientMode


  compile: (data, originalPath, callback) ->
    templatePath = path.resolve originalPath

    if not _.isArray @staticPatterns
      patterns = [@staticPatterns]
    else
      patterns = @staticPatterns

    relativePath = path.relative @projectPath, templatePath
    pathTestResults = _.filter patterns, (pattern) -> pattern.test relativePath

    options = _.extend {}, @pugOptions
    options.filename ?= relativePath

    successHandler = (error, template, clientMode) =>
      if error?
        callback error

    return

    if pathTestResults.length
        output = template _.defaults @locals,
          filename: relativePath

        staticPath = path.join @projectPath, @staticPath
        matches = relativePath.match pathTestResults[0]

        if clientMode
          extension = @extensions.client
        else
          extension = @extensions.static

        outputPath = matches[matches.length-1]

        extensionStartIndex = (outputPath.length - extension.length)

        if outputPath[extensionStartIndex..] == extension
          outputPath = outputPath[0..extensionStartIndex-2]

        outputPath = outputPath + '.' + extension

        outputPath = path.join staticPath, outputPath
        outputDirectory = path.dirname outputPath

        # TODO: Save this block from an eternity in callback hell.
        mkdirp outputDirectory, (err) ->
          if err
            callback err, null
          else
            fs.writeFile outputPath, output, (err, written, buffer) ->
              if err
                callback err, null
              else

                  callback()

      else
        callback null, "module.exports = #{template};"

    clientMode = pathTestResults.length == 0

    @templateFactory data, options, templatePath, successHandler, clientMode

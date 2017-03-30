{BufferedProcess} = require 'atom'
path = require 'path'
fs = require "fs"
exec = require('child_process').exec

PlainMessageView = null
panel = null
error = (message, className) ->
  if not panel
    {MessagePanelView, PlainMessageView} = require "atom-message-panel"
    panel = new MessagePanelView title: "Atom Ctags"

  panel.attach()
  panel.add new PlainMessageView
    message: message
    className: className || "text-error"
    raw: true

simpleExec = (command, exit)->
  exec command, (error, stdout, stderr)->
    console.log('stdout: ' + stdout) if stdout
    console.log('stderr: ' + stderr) if stderr
    console.log('exec error: ' + error) if error

getProjectPath = (codepath) ->
  for directory in atom.project.getDirectories()
    dirPath = directory.getPath()
    return dirPath if dirPath is codepath or directory.contains(codepath)

module.exports = (codepath, isAppend, cmdArgs, callback)->
  command = atom.config.get("atom-ctags.cmd").trim()
  if command == ""
    command = path.resolve(__dirname, '..', 'vendor', "ctags-#{process.platform}")

  args = []
  args.push cmdArgs... if cmdArgs

  projectPath = getProjectPath(codepath)

  ctagsConfigRelativePath = atom.config.get("atom-ctags.ctagsConfigPath")
  if ctagsConfigRelativePath
    ctagsConfigPath = path.join(projectPath, ctagsConfigRelativePath)
    args.push("--options=#{ctagsConfigPath}") if fs.existsSync(ctagsConfigPath)

  tagsRelativePath = atom.config.get("atom-ctags.tagsPath").trim()
  tagsPath = path.join(projectPath, tagsRelativePath)
  tagsFolderPath = path.dirname(tagsPath)
  if !fs.existsSync(tagsFolderPath) || !fs.lstatSync(tagsFolderPath).isDirectory()
    console.log "[atom-ctags:tagGenerator] The folder #{tagsFolderPath} is not found, create it recursively."
    tagsFolderPath.split('/').forEach (dir, index, splits) ->
      parent = splits.slice(0, index).join('/')
      dirPath = path.resolve(parent, dir)
      unless fs.existsSync(dirPath)
        fs.mkdirSync(dirPath)
  if isAppend
    genPath = path.join(projectPath, tagsRelativePath + ".tmp")
  else
    genPath = tagsPath
  args.push('-f', genPath)

  args.push(codepath)

  stderr = (data)->
    console.error("atom-ctags: command error, " + data, genPath)

  exit = ->
    clearTimeout(t)

    if isAppend
      if process.platform in 'win32'
        simpleExec "type '#{tagsPath}' | findstr /V /C:'#{codepath}' > '#{tagsPath}.new' & ren '#{tagsPath}.new' '#{tagsPath}' & more +6 '#{genPath}' >> '#{tagsPath}'"
      else
        simpleExec "grep -v '#{codepath}' '#{tagsPath}' > '#{tagsPath}.new'; mv '#{tagsPath}.new' '#{tagsPath}'; tail -n +7 '#{genPath}' >> '#{tagsPath}'"

    callback(genPath)

  console.log('command', command)
  console.log('args', args)

  childProcess = new BufferedProcess({command, args, stderr, exit})

  timeout = atom.config.get('atom-ctags.buildTimeout')
  t = setTimeout ->
    childProcess.kill()
    error """
    Stopped: Build more than #{timeout/1000} seconds, check if #{codepath} contain too many files.<br>
            Suggest that add CmdArgs at atom-ctags package setting, example:<br>
                --exclude=some/path --exclude=some/other"""
  , timeout

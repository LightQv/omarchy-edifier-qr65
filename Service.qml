import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Quickshell exposes QProcess signal parameters that qmllint cannot resolve.
// qmllint disable signal-handler-parameters

QtObject {
  id: root

  property var shell: null
  property var manifest: null

  property bool available: false
  property bool compatible: false
  property bool terminating: false
  readonly property bool busy: commandProcess.running || terminating || currentKind !== ""
  property int version: 0
  property int apiVersion: 0
  property string daemonVersion: ""
  property string mode: "dynamic"
  property string configuredStaticColor: "#FFFFFF"
  property int configuredBrightness: -1
  property bool colorMatching: false
  property string requestedColor: ""
  property string requestedSource: ""
  property string appliedColor: ""
  property int appliedBrightness: -1
  property string connection: "starting"
  property string message: ""
  property double updatedAt: 0
  property string actionMessage: ""
  property string error: ""

  property var queuedAction: null
  property bool queuedSync: false
  property bool queuedStatus: false
  property string currentKind: ""
  property string activeDynamicColor: ""
  property string pendingMode: ""
  property bool timedOut: false

  readonly property string homeDirectory: String(Quickshell.env("HOME") || "")
  readonly property string executable: homeDirectory === ""
    ? "" : homeDirectory + "/.local/bin/edifier-qr65"
  readonly property string timeoutExecutable: "/usr/bin/timeout"
  readonly property int commandTimeoutSeconds: 15
  readonly property int streamCharacterLimit: 16384
  readonly property var processEnvironment: ({
    "PATH": "/usr/bin:/bin",
    "HOME": homeDirectory,
    "XDG_CONFIG_HOME": String(Quickshell.env("XDG_CONFIG_HOME") || homeDirectory + "/.config"),
    "XDG_STATE_HOME": String(Quickshell.env("XDG_STATE_HOME") || homeDirectory + "/.local/state"),
    "XDG_RUNTIME_DIR": String(Quickshell.env("XDG_RUNTIME_DIR") || ""),
    "DBUS_SESSION_BUS_ADDRESS": String(Quickshell.env("DBUS_SESSION_BUS_ADDRESS") || ""),
    "LANG": String(Quickshell.env("LANG") || "C.UTF-8"),
    "LC_ALL": "C.UTF-8"
  })
  readonly property string themeAccent: String(Color.accent || "").toUpperCase()
  readonly property bool themeAccentValid: validColor(themeAccent, false)
  readonly property int statusHeartbeatMaxAgeSec: 60
  readonly property int statusFutureSkewSec: 5
  readonly property bool ready: compatible && available
  readonly property bool connected: available && connection === "connected"

  function validColor(value, allowEmpty) {
    var text = value === null || value === undefined ? "" : String(value)
    return (allowEmpty && text === "") || /^#[0-9A-Fa-f]{6}$/.test(text)
  }

  function boundedDiagnostic(value, fallback) {
    var text = String(value || "").trim()
    if (text.length > 512) text = text.slice(0, 509) + "..."
    return text || fallback
  }

  function guardStream(stream) {
    if (stream.overflowed) return
    var length = String(stream.text || "").length
    if (length > 0) stream.sawData = true
    if (length > streamCharacterLimit) {
      stream.overflowed = true
      if (commandProcess.running) commandProcess.running = false
    }
  }

  function resetStreams() {
    commandOut.overflowed = false
    commandOut.sawData = false
    commandErr.overflowed = false
    commandErr.sawData = false
  }

  function setUnavailable(reason) {
    available = false
    connection = "error"
    requestedColor = ""
    requestedSource = ""
    appliedColor = ""
    appliedBrightness = -1
    configuredBrightness = -1
    message = ""
    updatedAt = 0
    error = boundedDiagnostic(reason, "QR65 status is unavailable.")
  }

  function invalidateApi(reason) {
    compatible = false
    apiVersion = 0
    daemonVersion = ""
    if (!queuedAction || (queuedAction.kind !== "release" && queuedAction.kind !== "resume"))
      queuedAction = null
    queuedSync = false
    pendingMode = ""
    setUnavailable(reason)
  }

  function statusIsStale(timestamp) {
    var now = Date.now() / 1000
    return timestamp <= 0 || timestamp > now + statusFutureSkewSec
      || now - timestamp > statusHeartbeatMaxAgeSec
  }

  function enforceStatusAge() {
    if (available && connection === "connected" && statusIsStale(updatedAt))
      setUnavailable("QR65 connected status is stale or has an invalid timestamp.")
  }

  function applyStatus(raw) {
    var text = String(raw || "")
    if (text.length === 0 || text.length > 65536) {
      invalidateApi(text.length > 65536 ? "QR65 status exceeded 64 KiB." : "QR65 returned no status.")
      return false
    }

    var status
    try { status = JSON.parse(text) } catch (parseError) {
      invalidateApi("QR65 returned malformed JSON.")
      return false
    }
    var connections = ["starting", "scanning", "activation-required", "connecting", "connected", "released", "error"]
    if (!status || Array.isArray(status) || typeof status !== "object"
        || status.version !== 1
        || (status.mode !== "dynamic" && status.mode !== "static")
        || !validColor(status.configuredStaticColor, false)
        || !(status.configuredBrightness === undefined
          || status.configuredBrightness === null
          || (typeof status.configuredBrightness === "number"
            && isFinite(status.configuredBrightness)
            && Math.floor(status.configuredBrightness) === status.configuredBrightness
            && status.configuredBrightness >= 0 && status.configuredBrightness <= 100))
        || !(status.colorMatching === undefined || typeof status.colorMatching === "boolean")
        || !validColor(status.requestedColor, true)
        || !validColor(status.appliedColor, true)
        || !(status.appliedBrightness === undefined
          || status.appliedBrightness === null
          || (typeof status.appliedBrightness === "number"
            && isFinite(status.appliedBrightness)
            && Math.floor(status.appliedBrightness) === status.appliedBrightness
            && status.appliedBrightness >= 0 && status.appliedBrightness <= 100))
        || typeof status.requestedSource !== "string" || status.requestedSource.length > 128
        || connections.indexOf(status.connection) < 0
        || typeof status.message !== "string" || status.message.length > 2048
        || typeof status.updatedAt !== "number" || !isFinite(status.updatedAt)) {
      invalidateApi("QR65 returned an unsupported status payload.")
      return false
    }
    if (status.connection === "connected" && statusIsStale(status.updatedAt)) {
      setUnavailable("QR65 connected status is stale or has an invalid timestamp.")
      return false
    }

    version = status.version
    mode = status.mode
    configuredStaticColor = status.configuredStaticColor.toUpperCase()
    configuredBrightness = status.configuredBrightness === undefined
      || status.configuredBrightness === null ? -1 : status.configuredBrightness
    colorMatching = status.colorMatching === undefined ? false : status.colorMatching
    requestedColor = String(status.requestedColor || "").toUpperCase()
    requestedSource = status.requestedSource
    appliedColor = String(status.appliedColor || "").toUpperCase()
    appliedBrightness = status.appliedBrightness === undefined
      || status.appliedBrightness === null ? -1 : status.appliedBrightness
    connection = status.connection
    message = status.message
    updatedAt = status.updatedAt
    available = connection !== "error"
    error = available ? "" : boundedDiagnostic(message, "QR65 status reported an error.")
    pendingMode = ""
    queueThemeColor()
    return true
  }

  function applyApi(raw) {
    var text = String(raw || "")
    if (text.length === 0 || text.length > 65536) {
      invalidateApi(text.length > 65536 ? "QR65 API response exceeded 64 KiB."
        : "Edifier QR65 daemon is not installed or unavailable.")
      return false
    }
    var api
    try { api = JSON.parse(text) } catch (parseError) {
      invalidateApi("Edifier QR65 daemon returned malformed API metadata.")
      return false
    }
    if (!api || Array.isArray(api) || typeof api !== "object"
        || api.apiVersion !== 1 || api.statusVersion !== 1
        || typeof api.daemonVersion !== "string" || api.daemonVersion.length > 64) {
      invalidateApi("Edifier QR65 daemon API version 1 is required.")
      return false
    }
    apiVersion = api.apiVersion
    daemonVersion = api.daemonVersion
    compatible = true
    error = ""
    return true
  }

  function queueThemeColor() {
    var queuedColor = queuedAction && queuedAction.kind === "dynamic"
      ? queuedAction.args[2] : ""
    if (!compatible || !available || connection === "released" || mode !== "dynamic"
        || !validColor(themeAccent, false)) return
    if (currentKind === "release" || currentKind === "resume"
        || (queuedAction && queuedAction.kind !== "dynamic")) return
    if (pendingMode === "static" || currentKind === "static"
        || (queuedAction && queuedAction.kind === "static")) return
    if (activeDynamicColor === themeAccent
        || (requestedColor === themeAccent && activeDynamicColor === "")) {
      if (queuedAction && queuedAction.kind === "dynamic") queuedAction = null
      return
    }
    if (queuedColor === themeAccent) return
    var action = { kind: "dynamic", args: ["mode", "dynamic", themeAccent] }
    if (busy) {
      queuedAction = action
      queuedSync = false
    } else launch(action.kind, action.args)
  }

  function launch(kind, args) {
    if (busy || executable === "") return false
    currentKind = kind
    activeDynamicColor = kind === "dynamic" ? args[2] : ""
    timedOut = false
    resetStreams()
    commandProcess.command = [timeoutExecutable, "-k", "2",
      String(commandTimeoutSeconds), executable].concat(args)
    commandProcess.running = true
    return true
  }

  function refresh() {
    if (busy) {
      queuedStatus = true
      return
    }
    if (compatible) launch("status", ["status", "--json"])
    else launch("api", ["api-version", "--json"])
  }

  function lightingAvailable() {
    if (!ready) {
      actionMessage = "QR65 status is unavailable."
      actionMessageTimer.restart()
      return false
    }
    if (connection !== "released") return true
    actionMessage = "Resume QR65 control before changing lighting."
    actionMessageTimer.restart()
    return false
  }

  function setDynamic() {
    if (!compatible || !themeAccentValid) {
      actionMessage = !compatible ? "QR65 daemon API is not ready."
        : "Theme accent is unavailable or invalid. Reload the shell and try again."
      actionMessageTimer.restart()
      return false
    }
    if (!lightingAvailable()) return false
    pendingMode = "dynamic"
    var action = { kind: "dynamic", args: ["mode", "dynamic", themeAccent] }
    if (busy) {
      queuedAction = action
      queuedSync = false
    }
    else launch(action.kind, action.args)
    return true
  }

  function setStatic(color) {
    if (!compatible) return false
    if (!lightingAvailable()) return false
    var normalized = String(color || "").toUpperCase()
    if (!validColor(normalized, false)) {
      actionMessage = "Enter a color as #RRGGBB."
      actionMessageTimer.restart()
      return false
    }
    pendingMode = "static"
    var action = { kind: "static", args: ["mode", "static", normalized] }
    if (busy) {
      queuedAction = action
      queuedSync = false
    }
    else launch(action.kind, action.args)
    return true
  }

  function sync() {
    if (!compatible || !lightingAvailable()) return false
    if (mode === "dynamic") return setDynamic()
    if (busy) queuedSync = true
    else launch("sync", ["sync"])
    return true
  }

  function setBrightness(value) {
    if (!compatible || !lightingAvailable()) return false
    var percent = Math.max(0, Math.min(100, Math.round(Number(value))))
    var action = { kind: "brightness", args: ["brightness", String(percent)] }
    configuredBrightness = percent
    if (busy) {
      queuedAction = action
      queuedSync = false
    } else launch(action.kind, action.args)
    return true
  }

  function setColorMatching(enabled) {
    if (!compatible || !lightingAvailable()) return false
    var value = !!enabled
    var action = { kind: "matching", args: ["color-matching", value ? "on" : "off"] }
    colorMatching = value
    if (busy) {
      queuedAction = action
      queuedSync = false
    } else launch(action.kind, action.args)
    return true
  }

  function releaseToApp() {
    if (!compatible) return false
    var action = { kind: "release", args: ["release"] }
    if (busy) {
      queuedAction = action
      queuedSync = false
    } else launch(action.kind, action.args)
    return true
  }

  function resumeDaemon() {
    if (!compatible) return false
    var action = { kind: "resume", args: ["resume"] }
    if (busy) {
      queuedAction = action
      queuedSync = false
    } else launch(action.kind, action.args)
    return true
  }

  function statusJson() {
    return JSON.stringify({
      available: available, compatible: compatible, ready: ready,
      themeAccent: themeAccent, themeAccentValid: themeAccentValid,
      currentKind: currentKind, pendingMode: pendingMode, queuedAction: queuedAction,
      apiVersion: apiVersion, daemonVersion: daemonVersion,
      version: version, mode: mode,
      configuredStaticColor: configuredStaticColor,
      configuredBrightness: configuredBrightness, colorMatching: colorMatching,
      requestedColor: requestedColor, requestedSource: requestedSource,
      appliedColor: appliedColor, appliedBrightness: appliedBrightness, connection: connection,
      message: message, updatedAt: updatedAt, busy: busy, error: error
    })
  }

  function drainQueue() {
    if (busy) return
    if (queuedAction) {
      var action = queuedAction
      queuedAction = null
      launch(action.kind, action.args)
    } else if (queuedSync) {
      queuedSync = false
      launch("sync", ["sync"])
    } else if (queuedStatus) {
      queuedStatus = false
      refresh()
    }
  }

  onThemeAccentChanged: queueThemeColor()
  property IpcHandler diagnosticIpc: IpcHandler {
    target: "lightqv.edifier-qr65"
    function status(): string { return root.statusJson() }
    function followTheme(): bool { return root.setDynamic() }
    function staticColor(color: string): bool { return root.setStatic(color) }
  }
  Component.onCompleted: refresh()
  Component.onDestruction: {
    timeoutTimer.stop()
    if (commandProcess.running) commandProcess.running = false
  }

  property Timer pollTimer: Timer {
    interval: 8000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  property Timer statusAgeTimer: Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.enforceStatusAge()
  }

  property Timer timeoutTimer: Timer {
    interval: (root.commandTimeoutSeconds + 3) * 1000
    onTriggered: {
      root.timedOut = true
      root.terminating = true
      root.queuedStatus = true
      root.invalidateApi("QR65 command timed out.")
      if (root.commandProcess.running) root.commandProcess.running = false
    }
  }

  property Timer actionMessageTimer: Timer {
    interval: 3000
    onTriggered: root.actionMessage = ""
  }

  property Process commandProcess: Process {
    running: false
    command: []
    clearEnvironment: true
    environment: root.processEnvironment
    stdout: StdioCollector {
      id: commandOut
      property bool overflowed: false
      property bool sawData: false
      waitForEnd: false
      onDataChanged: root.guardStream(commandOut)
    }
    stderr: StdioCollector {
      id: commandErr
      property bool overflowed: false
      property bool sawData: false
      waitForEnd: false
      onDataChanged: root.guardStream(commandErr)
    }

    onStarted: root.timeoutTimer.restart()
    onExited: function(exitCode) {
      root.timeoutTimer.stop()
      var kind = root.currentKind
      var overflowed = commandOut.overflowed || commandErr.overflowed
      var commandTimedOut = root.timedOut || exitCode === 124
      root.currentKind = ""
      root.activeDynamicColor = ""
      if (overflowed) {
        root.invalidateApi("QR65 command produced too much output and was stopped.")
      } else if (commandTimedOut) {
        root.invalidateApi("QR65 command timed out.")
      } else {
        if (kind === "api") {
          if (exitCode === 0 && commandOut.sawData && root.applyApi(commandOut.text))
            root.queuedStatus = true
          else if (exitCode === 0)
            root.invalidateApi("Edifier QR65 daemon returned no API metadata.")
          else if (exitCode !== 0) {
            root.invalidateApi(root.boundedDiagnostic(commandErr.sawData ? commandErr.text : "",
              "Edifier QR65 daemon is not installed or unavailable."))
          }
        } else if (kind === "status") {
          if (exitCode === 0 && commandOut.sawData) root.applyStatus(commandOut.text)
          else if (exitCode === 0) root.invalidateApi("QR65 returned no status.")
          else root.invalidateApi(root.boundedDiagnostic(
            commandErr.sawData ? commandErr.text : "", "QR65 status command failed."))
        } else {
          if (exitCode === 0) {
            root.actionMessage = kind === "dynamic" ? "Following theme colors."
              : kind === "static" ? "Static color selected."
              : kind === "brightness" ? "Brightness updated."
              : kind === "matching" ? "Screen matching updated." : "Color reapplied."
            if (kind === "release") root.actionMessage = "BLE released to ConneX."
            else if (kind === "resume") root.actionMessage = "QR65 daemon resumed."
            root.error = ""
          } else {
            root.actionMessage = root.boundedDiagnostic(
              commandErr.sawData ? commandErr.text : "", "QR65 command failed.")
            if (kind === "dynamic" || kind === "static") root.pendingMode = ""
          }
          root.actionMessageTimer.restart()
          root.queuedStatus = true
        }
      }
      root.timedOut = false
      root.terminating = false
      Qt.callLater(root.drainQueue)
    }
  }
}

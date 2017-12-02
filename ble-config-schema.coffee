module.exports = {
  title: "BLE"
  type: "object"
  properties: 
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false
    deviceDebug:
      description: "Device debug mode. Writes details of unrecognised devices to the pimatic log, if set to true."
      type: "boolean"
      default: false
}

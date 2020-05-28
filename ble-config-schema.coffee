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
    scanInterval:
      description: "Interval between scans"
      type: "number"
      default: 300000
    bluetoothInterface:
      description: "The bluetooth interface"
      type: "string"
      default: "hci0"
}

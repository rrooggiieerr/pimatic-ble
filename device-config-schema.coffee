module.exports = {
  title: "pimatic-ble-presence device config schemas"
  BLEPresenceSensor: {
    title: "BLE Presence Sensor config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      uuid:
        description: "uuid of the BLE device"
        type: "string"
  }
}

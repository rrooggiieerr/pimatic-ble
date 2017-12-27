pimatic-ble
===========

Pimatic Plugin that allows multiple BLE sources on Pimatic

This plugin it acts as a common discovery for multiple BLE devices, this is due to noble blocking procedure in order to discover bluetooth low energy devices

Also it provides a BLEPresenceSensor which simly keeps track of the pressence of any BLE device

Configuration
-------------
Add the plugin to the plugin section:
    {
      "plugin": "ble",
      "debug": false,
      "deviceDebug": false
    }
If you enable the deviceDebug option you get extensive information on the devices that are being found while scanning for BLE devices.
It is advised to only enable this if you are developing support for a new BLE device.

Then add the device entry for your device into the devices section:
    {
      "id": "ble-presence",
      "class": "BLEPresenceSensor",
      "name": "BLE Presence",
      "uuid": "01234567890a",
      "timeout": 30000
    }

Then you can add the items into the mobile frontend

Developing support for BLE devices
----------------------------------

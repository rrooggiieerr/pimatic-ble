module.exports = (env) ->
  Promise = env.require 'bluebird'
  
  events = require 'events'

  class BLEPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      @debug =  @config.debug
      @deviceDebug = @config.deviceDebug
      @devices = []
      @peripheralNames = {}
      @discoveredPeripherals = []
      @discoverMode = false

      @noble = require 'noble'

      # Reset Bluetooth device
      exec = require('child_process').exec
      exec '/bin/hciconfig hci0 reset'

      deviceConfigDef = require('./device-config-schema')
      @framework.deviceManager.registerDeviceClass('BLEPresenceSensor', {
        configDef: deviceConfigDef.BLEPresenceSensor,
        createCallback: (config, lastState) =>
          device = new BLEPresenceSensor(config, @, lastState)
          @addToScan config.uuid, device
          return device
      })

      # Auto discover
      @framework.deviceManager.on 'discover', (eventData) =>
          @framework.deviceManager.discoverMessage 'pimatic-ble', 'Scanning for BLE devices'
          @discoverMode = true

          @.on 'discover', (peripheral) =>
            env.logger.debug 'Device %s found, state: %s', peripheral.uuid, peripheral.state
            config = {
              class: 'BLEPresenceSensor',
              uuid: peripheral.uuid
            }
            @framework.deviceManager.discoveredDevice(
              'pimatic-ble', 'Presence of ' + peripheral.uuid, config
            )

          setTimeout =>
            @discoverMode = false
          , 20000

          @startScanning()

      @noble.on 'discover', (peripheral) =>
        if peripheral.uuid not in @discoveredPeripherals && peripheral.state == 'disconnected'
          env.logger.debug 'Device found %s %s', peripheral.uuid, peripheral.advertisement.localName
          if peripheral.uuid in @devices
            @discoveredPeripherals.push peripheral.uuid
            @emit 'discover-' + peripheral.uuid, peripheral
          else if @discoverMode && @peripheralNames[peripheral.advertisement.localName]
            #@discoveredPeripherals.push peripheral.uuid
            @emit 'discover-' + @peripheralNames[peripheral.advertisement.localName], peripheral
            @emit 'discover', peripheral
          else if @discoverMode
            @emit 'discover', peripheral
          else if @deviceDebug && peripheral.advertisement.localName
            @discoveredPeripherals.push peripheral.uuid
            peripheral.on 'disconnect', (error) =>
              env.logger.debug 'Device %s %s disconnected', peripheral.uuid, peripheral.advertisement.localName
              if peripheral.uuid in @discoveredPeripherals
                @discoveredPeripherals.splice @discoveredPeripherals.indexOf(peripheral.uuid), 1
                env.logger.debug 'Removed %s from %s', peripheral.uuid, @discoveredPeripherals

            env.logger.debug 'Trying to connect to %s %s', peripheral.uuid, peripheral.advertisement.localName
            # Stop scanning for new devices when we're trying to connect to a device
            @stopScanning()
            #setTimeout =>
            #  env.logger.debug 'peripheral.state: %s', peripheral.state
            #  if peripheral.state == 'connecting'
            #    #ToDo Cancel connection
            #, 1000
            peripheral.connect (error) =>
              if !error
                env.logger.debug 'Device %s %s connected', peripheral.uuid, peripheral.advertisement.localName
                @readData peripheral
                # Disconnect the device after 1 second
                setTimeout =>
                  if peripheral.state == 'connected'
                    env.logger.debug 'Disconnecting device %s %s', peripheral.uuid, peripheral.advertisement.localName
                    peripheral.disconnect()
                , 1000
              else
                env.logger.debug 'Device %s %s connection failed: %s', peripheral.uuid, peripheral.advertisement.localName, error
              # Continue scanning for new devices
              @startScanning()
          #else if @deviceDebug
          #  env.logger.debug peripheral

      @noble.on 'stateChange', (state) =>
        env.logger.debug 'stateChange %s', state
        if state == 'poweredOn'
          clearInterval @scanInterval
          @scanInterval = setInterval( =>
            @startScanning()
          , 60000)
          @startScanning()
        else
          @stopScanning()

    registerName: (name, plugin) =>
      env.logger.debug 'Registering peripheral name %s', name
      @peripheralNames[name] = plugin

    startScanning: ->
      if @noble.state is 'poweredOn' && (@deviceDebug || @devices?.length > 0)
        env.logger.debug 'Scan for devices'
        @noble.startScanning()

    stopScanning: ->
      @noble.stopScanning()

    addToScan: (uuid, device) =>
      env.logger.debug 'Adding device %s', uuid
      @devices.push uuid

    removeFromScan: (uuid) =>
      if uuid in @devices
        env.logger.debug 'Removing device %s', uuid
        @devices.splice @devices.indexOf(uuid), 1
      if uuid in @discoveredPeripherals
        @discoveredPeripherals.splice @discoveredPeripherals.indexOf(uuid), 1

    readData: (peripheral) ->
      env.logger.debug 'Reading data from %s %s', peripheral.uuid, peripheral.advertisement.localName
      peripheral.discoverSomeServicesAndCharacteristics null, [], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          switch characteristic.uuid
            when '2a00'
              @logValue peripheral, characteristic, 'Device Name'
            when '2a24'
              @logValue peripheral, characteristic, 'Model Number'
            when '2a25'
              @logValue peripheral, characteristic, 'Serial Number'
            when '2a26'
              @logValue peripheral, characteristic, 'Firmware Revision'
            when '2a27'
              @logValue peripheral, characteristic, 'Hardware Revision'
            when '2a28'
              @logValue peripheral, characteristic, 'Software Revision'
            when '2a29'
              @logValue peripheral, characteristic, 'Manufacturer Name'
            else
              @logValue peripheral, characteristic, 'Unknown'

    logValue: (peripheral, characteristic, desc) ->
      characteristic.read (error, data) =>
        if !error
          if data
            env.logger.debug '(%s:%s) %s: %s', peripheral.uuid, characteristic.uuid, desc, data
        else
          env.logger.debug '(%s:%s) %s: error %s', peripheral.uuid, characteristic.uuid, desc, error

  class BLEPresenceSensor extends env.devices.PresenceSensor
    attributes:
      presence:
        description: "Presence of the BLE device"
        type: 'boolean'
        labels: ['present', 'absent']

    template: 'presence'

    constructor: (@config, plugin, lastState) ->
      @id = @config.id
      @name = @config.name
      @timeout = @config.timeout
      @uuid = @config.uuid
      @peripheral = null
      @plugin = plugin

      @_presence = lastState?.presence?.value or false
      @_resetPresenceTimeout = setTimeout @_resetPresence, 60000 * 2

      @plugin.on 'discover-' + @uuid, (peripheral) =>
        env.logger.debug 'Device %s found, state: %s', @name, peripheral.state
        @_setPresence true
        clearTimeout @_resetPresenceTimeout
        @_resetPresenceTimeout = setTimeout @_resetPresence, 60000 * 2
        if @plugin.deviceDebug
          @connect peripheral

      super()

    connect: (peripheral) ->
      @peripheral = peripheral

      @peripheral.on 'disconnect', (error) =>
        env.logger.debug 'Device %s disconnected', @name

      if @peripheral.state == 'disconnected'
        @plugin.stopScanning()
        @peripheral.connect (error) =>
          if !error
            env.logger.debug 'Device %s connected', @name
            @readData @peripheral
            # Disconnect the device after 1 second
            setTimeout =>
              if peripheral.state == 'connected'
                env.logger.debug 'Disconnecting %s', @name
                peripheral.disconnect()
            , 1000
          else
            env.logger.debug 'Device %s connection failed: %s', @name, error
          @plugin.startScanning()

    readData: (peripheral) ->
      env.logger.debug 'Reading data from %s', @name
      peripheral.discoverSomeServicesAndCharacteristics null, [], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          switch characteristic.uuid
            when '2a00'
              @logValue peripheral, characteristic, 'Device Name'
            when '2a24'
              @logValue peripheral, characteristic, 'Model Number'
            when '2a25'
              @logValue peripheral, characteristic, 'Serial Number'
            when '2a26'
              @logValue peripheral, characteristic, 'Firmware Revision'
            when '2a27'
              @logValue peripheral, characteristic, 'Hardware Revision'
            when '2a28'
              @logValue peripheral, characteristic, 'Software Revision'
            when '2a29'
              @logValue peripheral, characteristic, 'Manufacturer Name'
            else
              @logValue peripheral, characteristic, 'Unknown'

    logValue: (peripheral, characteristic, desc) ->
      characteristic.read (error, data) =>
        if !error
          if data
            env.logger.debug '(%s:%s) %s: %s', peripheral.uuid, characteristic.uuid, desc, data
        else
          env.logger.debug '(%s:%s) %s: error %s', peripheral.uuid, characteristic.uuid, desc, error

    _resetPresence: =>
      @_setPresence false

    destroy: ->
      clearTimeout(@_resetPresenceTimeout)
      @plugin.removeFromScan @uuid
      super()

  return new BLEPlugin

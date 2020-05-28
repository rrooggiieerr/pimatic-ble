module.exports = (env) ->
  Promise = env.require 'bluebird'
  
  events = require 'events'

  class BLEPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      @debug =  @config.debug
      @deviceDebug = @config.deviceDebug
      @scanInterval = @config.scanInterval
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
              'pimatic-ble', 'BLE Presence Sensor ' + peripheral.uuid, config
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
          , @scanInterval)
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

  class BLEDevice extends env.devices.Device
    constructor: (config, plugin, lastState) ->
      if !@config || Object.keys(@config).length == 0
        @config = config
      if !@plugin
        @plugin = plugin

      @id = @config.id
      @name = @config.name
      @uuid = @config.uuid
      @interval = if @config.interval then @config.interval else config.interval
      @presence_timeout = if @config.presence_timeout then @config.presence_timeout else @interval * 1.5
      env.logger.debug 'Connection interval for device %s: %s', @name, @interval

      @peripheral = null

      @_presence = lastState?.presence?.value or false
      @_resetPresenceTimeout = setTimeout @_resetPresence, @interval * 1.5

      super()

    connect: (peripheral) ->
      if @_destroyed then return

      if !peripheral then return
      @peripheral = peripheral

      @peripheral.on 'disconnect', (error) =>
        if @_destroyed then return
        env.logger.debug 'Device %s disconnected', @name
        @onDisconnect()

      # Set up reconnect interval
      clearInterval @reconnectInterval
      @reconnectInterval = setInterval( =>
        @_connect()
      , @interval)

      @_connect(peripheral)

    _connect: (peripheral) ->
      if @_destroyed then return

      if @peripheral
        if @peripheral.state == 'disconnected'
          env.logger.debug 'Trying to connect to %s', @name
          @plugin.ble.stopScanning()
          @peripheral.connect (error) =>
            if !error
              env.logger.debug 'Device %s connected', @name
              @onConnect()
            else
              env.logger.debug 'Device %s connection failed: %s', @name, error
              env.logger.debug 'Device state: %s', @peripheral.state
              @peripheral.disconnect()
            @plugin.ble.startScanning()
        else if @peripheral.state == 'connected'
          env.logger.debug 'Device %s still connected', @name
          clearTimeout @_resetPresenceTimeout
          @_resetPresenceTimeout = setTimeout @_resetPresence, @presence_timeout
        else if @peripheral.state != 'connecting' && @peripheral.state != 'connected'
          env.logger.error 'Device %s not disconnected: %s', @name, @peripheral.state
        else
          env.logger.debug 'Device %s not disconnected: %s', @name, @peripheral.state

    onConnect: () ->
      @_setPresence true

      # Reset the presence timeout
      clearTimeout @_resetPresenceTimeout
      @_resetPresenceTimeout = setTimeout @_resetPresence, @presence_timeout

      @readData @peripheral

    onDisconnect: () ->

    _setPresence: (value) ->
      if @_presence is value then return
      @_presence = value
      @emit 'presence', value

    _resetPresence: =>
      @_setPresence false

    readData: (peripheral) ->

    destroy: ->
      env.logger.debug 'Destroy %s', @name
      @_destroyed = true

      clearInterval(@_reconnectInterval)
      clearTimeout(@_resetPresenceTimeout)

      @emit('destroy', @)
      @removeAllListeners('destroy')
      @removeAllListeners(attrName) for attrName of @attributes

      if @peripheral && @peripheral.state == 'connected'
        @peripheral.disconnect()
      @plugin.removeFromScan @uuid
      super()

    getPresence: -> Promise.resolve(@_presence)

  env.devices.BLEDevice = BLEDevice

  class BLEPresenceSensor extends BLEDevice
    attributes:
      presence:
        description: "Presence of the BLE device"
        type: 'boolean'
        labels: ['present', 'absent']

    template: 'presence'

    constructor: (@config, @plugin, lastState) ->
      config = {}
      config.interval = @plugin.scanInterval

      @plugin.noble.on 'discover', (peripheral) =>
        if peripheral.uuid == @uuid
          env.logger.debug 'Device %s found, state: %s', @name, peripheral.state
          @_setPresence true

          # Reset the presence timeout
          clearTimeout @_resetPresenceTimeout
          @_resetPresenceTimeout = setTimeout @_resetPresence, @presence_timeout

      super(config, @plugin, lastState)

    # Disable connecting to the device by overriding the connect function
    connect: () ->

    destroy: ->
      super()

  return new BLEPlugin

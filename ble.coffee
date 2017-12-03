module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  
  events = require 'events'

  class BLEPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      @debug =  @config.debug
      @deviceDebug = @config.deviceDebug
      @devices = []
      @peripheralNames = []
      @discoveredPeripherals = []

      @noble = require 'noble'

      # Reset Bluetooth device
      exec = require('child_process').exec
      exec '/bin/hciconfig hci0 reset'

      deviceConfigDef = require('./device-config-schema')
      @framework.deviceManager.registerDeviceClass('BLEPresenceSensor', {
        configDef: deviceConfigDef.BLEPresenceSensor,
        createCallback: (config, lastState) =>
          @addOnScan config.uuid
          new BLEPresenceSensor(config, @, lastState)
      })

      @noble.on 'discover', (peripheral) =>
        if peripheral.uuid in @devices && peripheral.uuid not in @discoveredPeripherals
          @discoveredPeripherals.push peripheral.uuid
          env.logger.debug 'Device found %s', peripheral.uuid
          @emit 'discover', peripheral
          @emit 'discover-' + peripheral.uuid, peripheral
        else if peripheral.advertisement.localName in @peripheralNames && peripheral.uuid not in @discoveredPeripherals
          #@discoveredPeripherals.push peripheral.uuid
          env.logger.debug 'Device found %s %s', peripheral.advertisement.localName, peripheral.uuid
          # ToDo: Auto discover
          #@emit 'discover', peripheral
        else if @deviceDebug && peripheral.state == 'disconnected' && peripheral.uuid not in @discoveredPeripherals
          @discoveredPeripherals.push peripheral.uuid
          peripheral.on 'disconnect', (error) =>
            env.logger.debug 'Device %s disconnected', peripheral.uuid
            if peripheral.uuid in @discoveredPeripherals
              #env.logger.debug 'Removing %s from %s', peripheral.uuid, @discoveredPeripherals
              @discoveredPeripherals.splice @discoveredPeripherals.indexOf(peripheral.uuid), 1
              env.logger.debug 'Removed %s from %s', peripheral.uuid, @discoveredPeripherals

          @stopScanning()
          peripheral.connect (error) =>
            if !error
              env.logger.debug 'Device %s %s connected', peripheral.uuid, peripheral.advertisement.localName
              @startScanning()
              @readData peripheral
            else
              env.logger.debug 'Device %s connection failed: %s', peripheral.uuid, error

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

    registerName: (name) =>
      env.logger.debug 'Registering peripheral name %s', name
      @peripheralNames.push name

    startScanning: ->
      if @noble.state is 'poweredOn' && (@deviceDebug || @devices?.length > 0)
        env.logger.debug 'Scan for devices'
        @noble.startScanning([], true)

    stopScanning: ->
      @noble.stopScanning()

    addOnScan: (uuid) =>
      env.logger.debug 'Adding device %s', uuid
      @devices.push uuid

    removeFromScan: (uuid) =>
      if uuid in @devices
        env.logger.debug 'Removing device %s', uuid
        @devices.splice @devices.indexOf(uuid), 1

    readData: (peripheral) ->
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
      @_triggerAutoReset()

      @plugin.on('discover-' + @uuid, (peripheral) =>
        env.logger.debug 'Device %s found, state: %s', @name, peripheral.state
        @_setPresence true
        if @plugin.deviceDebug
          @connect peripheral
      )

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
            env.logger.debug '%s', peripheral.advertisement.localName
            @plugin.startScanning()
            @readData @peripheral
          else
            env.logger.debug 'Device %s connection failed: %s', @name, error

      #setTimeout @peripheral.disconnect, 5000 * 2

    readData: (peripheral) ->
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

    _triggerAutoReset: ->
      if @config.autoReset and @_presence
        clearTimeout @_resetPresenceTimeout
        @_resetPresenceTimeout = setTimeout @_resetPresence, 60000 * 2

    _resetPresence: =>
      @_setPresence false

    destroy: ->
      clearTimeout(@_resetPresenceTimeout)
      @plugin.removeFromScan @uuid
      super()

  return new BLEPlugin

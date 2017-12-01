module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  
  events = require 'events'

  class BLEPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      @debug =  @config.debug
      @deviceDebug = false
      @devices = []
      @peripheralNames = []
      @discoveredPeripherals = []

      @noble = require 'noble'

      # Reset Bluetooth device
      exec = require('child_process').exec
      exec '/bin/hciconfig hci0 reset'

      @noble.on 'discover', (peripheral) =>
        if peripheral.uuid not in @discoveredPeripherals
          @discoveredPeripherals.push peripheral.uuid
          if (@peripheralNames.indexOf(peripheral.advertisement.localName) >= 0)
            env.logger.debug 'Device found %s %s', peripheral.advertisement.localName, peripheral.uuid
            @emit 'discover', peripheral
          else if @deviceDebug && peripheral.state == 'disconnected'
            peripheral.on 'disconnect', (error) =>
              env.logger.debug 'Device %s disconnected', peripheral.uuid
              if peripheral.uuid in @discoveredPeripherals
                #env.logger.debug 'Removing %s from %s', peripheral.uuid, @discoveredPeripherals
                @discoveredPeripherals.splice @discoveredPeripherals.indexOf(peripheral.uuid), 1
                env.logger.debug 'Removed %s from %s', peripheral.uuid, @discoveredPeripherals

            @stopScanning()
            peripheral.connect (error) =>
              if !error
                env.logger.debug 'Device %s connected', peripheral.uuid
                @startScanning()
                @readData peripheral
              else
                env.logger.debug 'Device %s connection failed: %s', peripheral.uuid, error

      @noble.on 'stateChange', (state) =>
        env.logger.debug 'stateChange %s', state
        if state == 'poweredOn'
          setInterval( =>
            if @deviceDebug || @devices?.length > 0
              @startScanning()
          , 60000)
          @startScanning()
        else
          @stopScanning()

    registerName: (name) =>
      env.logger.debug 'Registering peripheral name %s', name
      @peripheralNames.push name

    startScanning: ->
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
              @logValue characteristic, 'Device Name'
            when '2a24'
              @logValue characteristic, 'Model Number'
            when '2a25'
              @logValue characteristic, 'Serial Number'
            when '2a26'
              @logValue characteristic, 'Firmware Revision'
            when '2a27'
              @logValue characteristic, 'Hardware Revision'
            when '2a28'
              @logValue characteristic, 'Software Revision'
            when '2a29'
              @logValue characteristic, 'Manufacturer Name'
            else
              @logValue characteristic, 'Unknown'

    logValue: (characteristic, desc) ->
      characteristic.read (error, data) =>
        if !error
          if data
            env.logger.debug '(%s) %s: %s', characteristic.uuid, desc, data
        else
          env.logger.debug '(%s) %s: error %s', characteristic.uuid, desc, error

  return new BLEPlugin

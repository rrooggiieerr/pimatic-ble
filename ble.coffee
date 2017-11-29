module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  
  events = require "events"

  class BLEPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      @debug =  @config.debug
      @devices = []
      @peripheralNames = []
      @discovered = false

      @noble = require "noble"

      @noble.on 'discover', (peripheral) =>
        if not @discovered
          @discovered = true
          env.logger.debug 'peripheral.advertisement.localName '+peripheral.advertisement.localName
          if (@peripheralNames.indexOf(peripheral.advertisement.localName) >= 0)
            env.logger.debug "Device found "+ peripheral.uuid
            @noble.stopScanning()
            @emit "discover", peripheral
          @discovered = false

      if @noble.state == 'poweredOn'
        env.logger.debug "Scan for devices"
        @noble.startScanning([],true)
      else
        @noble.on 'stateChange', (state) =>
          env.logger.debug 'stateChange ' + state
          if state == 'poweredOn'
            setInterval( =>
              if @devices?.length > 0
                env.logger.debug "Scan for devices"
                @noble.startScanning([],true)
            , 10000)

          #  env.logger.debug "Scan for devices"
          #  @noble.startScanning([],true)
          #else
          #  @noble.stopScanning();

    registerName: (name) =>
      env.logger.debug "Registering peripheral name "+name
      @peripheralNames.push name

    addOnScan: (uuid) =>
      env.logger.debug "Adding device "+uuid
      @devices.push uuid

    removeFromScan: (uuid) =>
      env.logger.debug "Removing device "+uuid
      @devices.splice @devices.indexOf(uuid), 1

  return new BLEPlugin

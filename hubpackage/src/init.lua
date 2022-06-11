--[[
  Copyright 2021 Todd Austin

  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
  except in compliance with the License. You may obtain a copy of the License at:

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the
  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
  either express or implied. See the License for the specific language governing permissions
  and limitations under the License.


  DESCRIPTION
  
  MQTT Device Handler Driver

--]]

-- Edge libraries
local capabilities = require "st.capabilities"
local Driver = require "st.driver"
local cosock = require "cosock"
local socket = require "cosock.socket"          -- just for time
--local Thread = require "st.thread"
local log = require "log"

local mqtt = require "mqtt"


-- Module variables
thisDriver = {}

client = nil
client_reset_inprogress = false

local config_initialized = false

local TOPIC_PREFIX = 'smartthings'
local SUBSCRIBE_TOPIC = 'smartthings/#'


-- Custom Capabilities
local cap_status = capabilities["partyvoice23922.status"]
local cap_refresh = capabilities["partyvoice23922.refresh"]


local function disptable(table, tab, maxlevels, currlevel)

	if not currlevel then; currlevel = 0; end
  currlevel = currlevel + 1
  for key, value in pairs(table) do
    if type(key) ~= 'table' then
      log.debug (tab .. '  ' .. key, value)
    else
      log.debug (tab .. '  ', key, value)
    end
    if (type(value) == 'table') and (currlevel < maxlevels) then
      disptable(value, '  ' .. tab, maxlevels, currlevel)
    end
  end
end


local profiles =  {
                    ['mqttdisco'] = 'mqttconfig.v1',
                    ['switch'] = 'mqttswitch.v1',
                    ['momentary'] = 'mqttmomentary.v1',
                    ['motion'] = 'mqttmotion.v1',
                    ['presence'] = 'mqttpresence.v1',
                    ['plug'] = 'mqttplug.v1',
                    ['light'] = 'mqttlight.v1',
                  }


local function create_device(driver, topic)

  local MFG_NAME = 'SmartThings Community'
  local MODEL = topic.cap
  local VEND_LABEL = topic.name
  local ID = 'MQTT_' .. topic.path .. '_' .. socket.gettime()
  
  local PROFILE = profiles[topic.cap]
  
  log.info (string.format('Creating new device: label=<%s>, id=<%s>', VEND_LABEL, ID))

  local create_device_msg = {
                              type = "LAN",
                              device_network_id = ID,
                              label = VEND_LABEL,
                              profile = PROFILE,
                              manufacturer = MFG_NAME,
                              model = MODEL,
                              vendor_provided_label = VEND_LABEL,
                            }
                      
  assert (driver:try_create_device(create_device_msg), "failed to create device")

end


local function determine_device(topic)

  local device_list = thisDriver:get_devices()
  
  for _, device in ipairs(device_list) do
    if device.device_network_id:find(topic.path, 1, 'plaintext') then; return device; end
  end

end


local function proc_config(topic, msg)

  if not determine_device(topic) then
  
    create_device(thisDriver, topic)
    
  end

end


local function proc_state(topic, state)

  local device = determine_device(topic)
  
  log.debug (string.format('Device name <%s> sent updated state value = "%s"', topic.name, state))
  
  if device then

    if topic.cap == 'switch' or topic.cap == 'plug' or topic.cap == 'light' then
    
      device:emit_event(capabilities.switch.switch(state))
    
    elseif topic.cap == 'momentary' then
    
      device:emit_event(capabilities.button.button[state]({state_change = true}))
    
    elseif topic.cap == 'motion' then
    
      device:emit_event(capabilities.motionSensor.motion(state))
    
    elseif topic.cap == 'presence' then
    
      device:emit_event(capabilities.presenceSensor.presence(state))
    
    else
      log.warn ('Unsupported capability:', topic.cap)
    end
  
  else
    log.warn('Unrecognized device; message ignored', topic.name)
  end

end


local function parse_topic(msgtopic)

  -- Topic format:  smartthings/<capability>/[<node_id>/]<unique_name>/<config | state>

  local topic = {}
  local topic_parts = {}
  local i = 1
  
  for element in string.gmatch(msgtopic, "[^/]+") do
    topic_parts[i] = element
    i = i + 1
  end
  
  if #topic_parts < 4 then; return; end
  
  topic.prefix = topic_parts[1]
  topic.cap = topic_parts[2]
  if #topic_parts > 4 then
    topic.node = topic_parts[3]
    topic.name = topic_parts[4]
    topic.action = topic_parts[5]
  else
    topic.node = nil
    topic.name = topic_parts[3]
    topic.action = topic_parts[4]
  end

  topic.path = msgtopic:match('smartthings/(.+)/%w+$')
  
  return topic

end


local function create_MQTT_client(device)

	-- create mqtt client
  client = mqtt.client { uri = device.preferences.broker, clean = true, driver = thisDriver, device = device }

  client:on{
    connect = function(connack)
      if connack.rc ~= 0 then
				log.error ("Connection to broker failed:", connack:reason_string(), connack)
      else
        log.info("Connected to MQTT broker:", connack) -- successful connection
        device:emit_event(cap_status.status('Connected to Broker'))
        
        -- subscribe to smartthings topic
        assert(client:subscribe{ topic=SUBSCRIBE_TOPIC, qos=1, callback=function(suback)
          log.info("Subscribed to smartthings topic:", suback)
          device:emit_event(cap_status.status('Connected & Subscribed'))
        end})
        
      end

    end,

    message = function(msg)
      assert(client:acknowledge(msg))

      log.info("Received:", msg)
      -- example msg:  PUBLISH{payload="Hello world", topic="testmqtt/pimylifeup", dup=false, type=3, qos=0, retain=false}

      local topic = parse_topic(msg.topic)
      
      if topic then
      
        if topic.prefix ~= TOPIC_PREFIX then; return; end
        
        if topic.action == 'config' then
          proc_config(topic, msg.payload)
          
        elseif topic.action == 'state' then
          proc_state(topic, msg.payload)
          
        end
      
      else
        log.error ('Invalid topic structure received')
      end
      
    end,

    error = function(err)
      log.error("MQTT client error:", err)
      device:emit_event(cap_status.status(err))
    end,
  }

	return client

end


local function init_mqtt(device)

  if device.preferences.broker == '192.168.1.xxx' then

      log.warn ('Broker address not initialized')
      return
  end

  if client then
    log.debug ('Unsubscribing and disconnecting current client...')
    local rc, err = client:unsubscribe{ topic=SUBSCRIBE_TOPIC, callback=function(unsuback)
				log.info("\t\tUnsubscribe callback:", unsuback)
      end}
      
    if rc == false then
			log.debug ('\tUnsubscribe failed with err:', err)
		else
			log.debug ('\tUnsubscribed')
		end
		
    rc, err = client:disconnect()
    if rc == false then
			log.debug ('\tDisconnect failed with err:', err)
		elseif rc == true then
			log.debug ('\tDisconnected')
		end
  end

  device:emit_event(cap_status.status('Connecting...'))

	client = create_MQTT_client(device)

	-- Run MQTT loop in separate thread

  cosock.spawn(function()
		while true do
		  local ok, err = mqtt.run_sync(client)
		  
		  if ok == false then
		    if string.lower(err):find('connection refused', 1, 'plaintext') or err == "closed" then
					if client_reset_inprogress == true then; break; end
					
		      local connected = false
		      --client = nil
		      device:emit_event(cap_status.status('Reconnecting...'))
          
		      repeat
						-- create new mqtt client
						cosock.socket.sleep(15)
						if client_reset_inprogress == true then
							client_reset_inprogress = false
							return
						end
						log.info ('Attempting to reconnect to broker...')
						client = create_MQTT_client(device)
					until client
					
				else
					break
				end
			else
				log.error ('Unexpected return from MQTT client:', ok, err)
			end
		end
	end, 'MQTT synch mode')	

end


local function init_devices()

  if client then
    
    log.debug ('Initializing device topic subscriptions')

    local device_list = thisDriver:get_devices()

    for _, device in ipairs(device_list) do

      local cap, name = device.device_network_id:match('MQTT_(%w+)_([%w%s_]+)_')
      
      if cap ~= 'config' then
      
        if not device:get_field('MQTT_subscribed') then
      
          local topic = 'smartthings/state/' .. cap .. '/' .. name
          assert(client:subscribe{ topic=topic, qos=1, callback=function(suback)
            log.info("Subscribed to device topic:", topic)
            device:set_field('MQTT_subscribed', true)
          end})
        end
      end
    end
  else
    log.error ('Cannot subscribe to device topics; broker not connected')
  end

end


local function send_command(device, cmd)

  if (device.preferences.cmdTopic ~= 'xxxxx/xxxxx') and (device.preferences.cmdTopic ~= nil) then
  
    if client then
  
      assert(client:publish {
                              topic = device.preferences.cmdTopic,
                              payload = cmd,
                              qos = 1
                            })
                            
      log.info ('Command published to', device.preferences.cmdTopic)
    end
  end

end




-----------------------------------------------------------------------
--											COMMAND HANDLERS
-----------------------------------------------------------------------

local function handle_refresh(driver, device, command)

  log.info ('Refresh requested')

	client_reset_inprogress = true
  init_mqtt(device)
    
end


local function handle_switch(driver, device, command)

  log.info ('Switch command received:', command.command)
  
  device:emit_event(capabilities.switch.switch(command.command))
  
  send_command(device, command.command)
  
end


------------------------------------------------------------------------
--                REQUIRED EDGE DRIVER HANDLERS
------------------------------------------------------------------------

-- Lifecycle handler to initialize existing devices AND newly discovered devices
local function device_init(driver, device)
  
  log.debug(device.id .. ": " .. device.device_network_id .. "> INITIALIZING")
  
  if device.device_network_id:find('mqttdisco', 1, 'plaintext') then
    init_mqtt(device)
    config_initialized = true
  end
  
end


-- Called when device was just created in SmartThings
local function device_added (driver, device)

  log.info(device.id .. ": " .. device.device_network_id .. "> ADDED")
  
  if not device.device_network_id:find("mqttdisco", 1, 'plaintext') then
  
    local caps = device.st_store.profile.components.main.capabilities
    
    for _, cap in pairs(caps) do
    
      if cap.id == 'switch' then
  
        device:emit_event(capabilities.switch.switch('off'))
        
      elseif cap.id == 'motionSensor' then
    
        device:emit_event(capabilities.motionSensor.motion('inactive'))
        
      elseif cap.id == 'presenceSensor' then
    
        device:emit_event(capabilities.presenceSensor.presence('not present'))
        
      elseif cap.id == 'momentary' then
      
        local supported_values =  {
                                    capabilities.button.button.pushed.NAME,
                                    capabilities.button.button.held.NAME,
                                    capabilities.button.button.double.NAME,
                                    capabilities.button.button.pushed_2x.NAME,
                                    capabilities.button.button.pushed_3x.NAME,
                                  }
        device:emit_event(capabilities.button.supportedButtonValues(supported_values))
      end
      
    end
  end
  
end


-- Called when SmartThings thinks the device needs provisioning
local function device_doconfigure (_, device)

  log.info ('Device doConfigure lifecycle invoked')

end


-- Called when device was deleted via mobile app
local function device_removed(_, device)
  
  log.warn(device.id .. ": " .. device.device_network_id .. "> removed")
  
  local device_list = thisDriver:get_devices()
  
  if #device_list == 0 then
  
    if client then
    
      client:unsubscribe{ topic=SUBSCRIBE_TOPIC, callback=function(unsuback)
				log.info("Unsubscribed")
      end}
      client:disconnect()
      log.info("Disconnected from broker")
    end
    
  end
  
end


local function handler_driverchanged(driver, device, event, args)

  log.debug ('*** Driver changed handler invoked ***')

end


local function handler_infochanged (driver, device, event, args)

  log.debug ('Info changed handler invoked')

  -- Did preferences change?
  if args.old_st_store.preferences then
    
		if args.old_st_store.preferences.broker ~= device.preferences.broker then
      log.info ('Broker URI changed to: ', device.preferences.broker)
    elseif args.old_st_store.preferences.cmdTopic ~= device.preferences.cmdTopic then
      log.info (string.format('Device <%s> command topic changed to: %s', device.label, device.preferences.cmdTopic))
    end

  end
end


local function discovery_handler(driver, _, should_continue)
  
  if not config_initialized then
  
    log.info("Creating MQTT config device")
    
    create_device(driver, parse_topic('smartthings/mqttdisco/MQTT Discovery/config'))
    
  end
  
  log.debug("Exiting device creation")
end


-----------------------------------------------------------------------
--        DRIVER MAINLINE: Build driver context table
-----------------------------------------------------------------------
thisDriver = Driver("thisDriver", {
  discovery = discovery_handler,
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    driverSwitched = handler_driverchanged,
    infoChanged = handler_infochanged,
    doConfigure = device_doconfigure,
    removed = device_removed
  },
  
  capability_handlers = {
  	[cap_refresh.ID] = {
      [cap_refresh.commands.push.NAME] = handle_refresh,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch,
      [capabilities.switch.commands.off.NAME] = handle_switch,
    },
  }
})

log.info ('MQTT Device Handler V1 Started!!!')

thisDriver:run()

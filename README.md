# MQTT-Discovery
A SmartThings Edge version of Home Assistant's MQTT Discovery feature

This driver is provides a general-purpose way to create and update basic SmartThings devices via MQTT messages. These messages can be initiated through configurable MQTT-enabled applications, or custom applications or scripts running on your home network. It is easy to set up, and requires no programming expertise to implement.

### Caveats
- Supports device types: switch, momentary, light, plug, motion, presence (more to be added)
- Limited testing, and only with Mosquitto MQTT broker
- Secure connections and authorization with broker not yet supported

## Instructions

### Pre-requisites
- SmartThings Edge enabled hub
- SmartThings ID
- MQTT broker running on your LAN (e.g. Mosquitto)

### Getting the SmartThings Driver
The driver is available through my test channel:  https://bestow-regional.api.smartthings.com/invite/Q1jP7BqnNNlL

Enroll your hub and then from the available drivers list, install **MQTT Handler V1**

### Driver Configuration

Once available on your hub, from the Smartthings mobile app, do an Add Device / Scan nearby devices, and a new device called **MQTT Discovery** will be created in the ‘No room assigned’ room.

Open the MQTT Discovery device and go into device settings *Settings* and configure the MQTT broker IP address (IP only, no port; secure connections or authorization not yet supported).

After saving the broker IP address, return to the device Controls screen and tap the Refresh button. The driver will now connect to the MQTT broker and subscribe to the ‘smartthings/#’ MQTT topic.

### Sending MQTT Messages

SmartThings device creation and capability attribute (state) updates are achieved through publishing MQTT message to specific Topic endpoints.  

#### Topic format for device creation and state updates:

**smartthings/**\<*type*\>**/**[*nodename*/]\<*uniquename*\>**/**\<**config** | **state**\>

where:

- ‘**smartthings**’ is mandatory topic prefix
- *type* is device type (currently: switch | light | plug | momentary | motion | presence)
- *nodename* is an optional name identifying the source node \[a-zA-Z0-9_\]; no other special characters or spaces
- *uniquename* is a unique identifying name for the device; \[a-zA-Z0-9_\]; no other special characters or spaces
- ‘**config**’ indicates device creation, ‘**state**’ indicates device capability attribute update

#### Sending commands back to the device from SmartThings

SmartThings MQTT devices created by this driver can be configured to publish capability commands **TO** a chosen MQTT topic. This is configured in device Settings. Note that this is implemented only for the devices containing switches (switch, plug, light) at the moment.

#### Switch example

Use an app like mosquitto_pub to issue the following examples.

##### Create new device

mosquitto_pub -h localhost -t “smartthings/switch/myswitch/config” -m “create it!”

Note that the message content is unimportant, and Retain option is optional (unlike HA)

##### Update state of the switch

mosquitto_pub -h localhost -t “smartthings/switch/myswitch/state” -m “on”
mosquitto_pub -h localhost -t “smartthings/switch/myswitch/state” -m “off”

The message value must be one of the valid values that SmartThings expects for the specific device capability:
- switch, light, plug: on | off
- momentary: pushed | held | double | pushed_x2 | pushed_x3
- motion (motionSensor): active | inactive
- presence (presenceSensor): present | not present

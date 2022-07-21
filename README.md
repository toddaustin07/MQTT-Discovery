# MQTT-Discovery
A SmartThings Edge version of Home Assistant's MQTT Discovery feature

This driver is provides a general-purpose way to create and update basic SmartThings devices via MQTT messages. These messages can be initiated through configurable MQTT-enabled applications, or custom applications or scripts running on your home network. It is easy to set up, and requires no programming expertise to implement.

### Supported Device Types
The following device types are currently supported, but more can easily be added at community's request:
```
switch, level, momentary, light, plug, motion, contact, presence, alarm, valve
```
### Caveats
- Testing has been limited so far, and only with Mosquitto MQTT broker
- HTTP connections only (https not yet supported)

### Pre-requisites
- SmartThings Edge enabled hub
- SmartThings ID
- MQTT broker running on your LAN (e.g. Mosquitto)

## Instructions

### Getting the SmartThings Driver
The driver is available through my test channel:  https://bestow-regional.api.smartthings.com/invite/Q1jP7BqnNNlL

Enroll your hub and then from the available drivers list, install **MQTT Handler V1**

### Driver Configuration

Once available on your hub, from the Smartthings mobile app, do an Add Device / Scan nearby devices, and a new device called **MQTT Discovery** will be created in the *No room assigned* room.

Open the MQTT Discovery device and go into device *Settings* and configure the MQTT broker IP address (IP only, no port), authorization username & pw (if required), and desired Quality of Service (QoS).

After saving the device Settings, return to the device Controls screen and tap the Refresh button. The driver will now connect to the MQTT broker and subscribe to the ‘smartthings/#’ MQTT topic.

### Sending MQTT Messages

SmartThings device creation and capability attribute (state) updates are achieved through publishing MQTT message to specific Topic endpoints.  

#### Topic format for device creation and state updates:

**smartthings/**\<*type*\>**/**[*nodename*/]\<*uniquename*\>**/**\<**config** | **state**\>

where:

- ‘**smartthings**’ is mandatory topic prefix
- *type* is device type (currently: switch | level | light | plug | momentary | motion | contact | presence | alarm | valve)
- *nodename* is an optional name identifying the source node \[a-zA-Z0-9_\]; no other special characters or spaces
- *uniquename* is a unique identifying name for the device; \[a-zA-Z0-9_\]; no other special characters or spaces
- ‘**config**’ indicates device creation, ‘**state**’ indicates device capability attribute update

#### Sending updates back to MQTT from the SmartThings device

SmartThings MQTT devices *created by this driver* can be configured to publish SmartThings-initiated state changes (i.e. switch on/off) **TO** a configured MQTT topic. This is configured in device Settings.  It is highly recommended to use a top-level topic *other* than 'smartthings' to avoid feedback loops!

Also configurable on a device-by-device basis are QoS and Retention options. 

*If you have the need for other SmartThings devices to publish MQTT messages, check out my [MQTT SmartApp](https://github.com/toddaustin07/MQTT_SmartApp).*

#### Switch example

Use an app like mosquitto_pub to issue the following examples.

##### Create new device

mosquitto_pub -h localhost -t “smartthings/switch/myswitch/config” -m “create it!”

Note that the message content is unimportant, and Retain option should *not* be used (unlike HA)

##### Update state of the switch

mosquitto_pub -h localhost -t “smartthings/switch/myswitch/state” -m “on”

mosquitto_pub -h localhost -t “smartthings/switch/myswitch/state” -m “off”

The message value must be one of the valid values that SmartThings expects for the specific device capability:
- switch, light, plug (switch): on | off
- level: 0-100
- momentary: pushed | held | double | pushed_x2 | pushed_x3
- motion (motionSensor): active | inactive
- contact (contactSensor): open | closed
- presence (presenceSensor): present | not present
- alarm: off | siren | strobe | both
- valve: open | closed

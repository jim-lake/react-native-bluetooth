'use strict';

import React from 'react-native';
import EventEmitter from 'events';
import _ from 'lodash';
import { Buffer } from 'buffer';

const { NativeAppEventEmitter, NativeModules } = React;
const { BluetoothModule } = NativeModules;

const PERIPHERAL_POLL_MS = 5000;
const CHANGE_EVENT = "change";

const g_eventEmitter = new EventEmitter();
let g_isPoweredOn = false;
let g_isReady = false;
let g_connectedPeripheralCount = 0;

NativeAppEventEmitter.addListener('bluetooth.peripheral.write',_onPeripheralWrite);
NativeAppEventEmitter.addListener('bluetooth.peripheral.read',_onPeripheralRead);
NativeAppEventEmitter.addListener('bluetooth.peripheral.update_value',_onPeripheralUpdateValue);
NativeAppEventEmitter.addListener('bluetooth.central.state',_onCentralState);

function init(opts) {
  BluetoothModule.init(opts,(err) => {
    BluetoothModule.getState((err,state) => {
      _onCentralState(state,'startup');
    });

    setInterval(_checkPeripherials,PERIPHERAL_POLL_MS);
  });
}
function addListener(event,callback) {
  g_eventEmitter.on(event,callback);
}
function removeListener(event,callback) {
  g_eventEmitter.removeListener(event,callback);
}
function addChangeListener(callback) {
  g_eventEmitter.on(CHANGE_EVENT,callback);
}
function removeChangeListener(callback) {
  g_eventEmitter.removeListener(CHANGE_EVENT,callback);
}

function _onCentralState(state,tag) {
  g_isReady = true;
  const is_powered_on = !!state.isPoweredOn;
  if (g_isPoweredOn != is_powered_on) {
    g_isPoweredOn = is_powered_on;
    g_eventEmitter.emit(CHANGE_EVENT,tag);
  } else if (tag == 'startup') {
    g_eventEmitter.emit(CHANGE_EVENT,tag);
  }
}
function _onPeripheralCountUpdate(count,tag) {
  if (g_connectedPeripheralCount != count) {
    g_connectedPeripheralCount = count;
    g_eventEmitter.emit(CHANGE_EVENT,tag);
  }
}

function _onPeripheralRead(data) {
  const opts = {
    requestId: data.requestId,
    value: "1234",
  };
  BluetoothModule.respondToRequest(opts,(err) => {
    console.log("Bluetooth._onPeripheralRead: respondToRequest err:",err);
  });
}

function _onPeripheralWrite(data) {
  const { valueBase64 } = data;
  const buf = new Buffer(valueBase64,'base64');
  data.valueBuffer = buf;
  data.value = buf.toString('utf8');

  g_eventEmitter.emit("write",data);
}

function _onPeripheralUpdateValue(data) {
  const { valueBase64 } = data;
  const buf = new Buffer(valueBase64,'base64');
  data.valueBuffer = buf;
  data.value = buf.toString('utf8');

  g_eventEmitter.emit("updateValue",data);
}
function _checkPeripherials() {
  BluetoothModule.getPeripheralList((err,peripheral_list) => {
    let count = 0;
    peripheral_list.forEach((p) => {
      if (p.isConnected) {
        count++;
      } else if (!p.isConnecting) {
        BluetoothModule.connectToPeripheral(p.peripheral,(err) => {});
      }
    });
    _onPeripheralCountUpdate(count);
  });
}
function getConnectedPeripheralCount() {
  return g_connectedPeripheralCount;
}
function isReady() {
  return g_isReady;
}
function isPoweredOn() {
  return g_isPoweredOn;
}
function startScanning() {
  BluetoothModule.startScanning((err) => {
    console.log("Bluetooth.startScanning: err:",err);
  });
}
function sendValue(value,done = function() {}) {
  if (Buffer.isBuffer(value)) {
    value = value.toString('base64');
  } else {
    value = new Buffer(value,'utf8').toString('base64');
  }
  BluetoothModule.notifyWithValue(value,done);
}

export default {
  init,
  addListener,
  removeListener,
  addChangeListener,
  removeChangeListener,
  getConnectedPeripheralCount,
  isReady,
  isPoweredOn,
  startScanning,
  sendValue,
};


#import <CoreBluetooth/CoreBluetooth.h>

#import "RCTBridgeModule.h"
#import "RCTBridge.h"
#import "RCTEventDispatcher.h"

NSNumber *getTime() {
  return [NSNumber numberWithDouble:(CFAbsoluteTimeGetCurrent() - 978307200000)];
}

@interface BluetoothModule : NSObject <RCTBridgeModule>

-(void)sendEvent:(NSString *)name body:(NSDictionary *)body;

@end

@interface BluetoothResponder : NSObject <CBPeripheralManagerDelegate,CBCentralManagerDelegate,CBPeripheralDelegate>

+ (BluetoothResponder *)sharedInstanceWithOpts:(NSDictionary *)opts;
+ (BluetoothResponder *)sharedInstance;

- (void)startScanning;
- (void)stopScanning;
- (void)setDelegate:(BluetoothModule *)delegate;
- (void)respondToRequest:(NSDictionary *)opts;
- (BOOL)notifyWithValue:(NSData *)value;
- (void)connectToPeripheral:(NSString *)uuidString;
- (NSArray *)peripheralList;
- (id)isPoweredOn;

@property (atomic, strong) dispatch_queue_t centralManagerQueue;

@end


@implementation BluetoothModule

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(init:(NSDictionary *)opts callback:(RCTResponseSenderBlock)callback)
{
  id ret = [NSNull null];
  @try {
    id bluetooth = [BluetoothResponder sharedInstanceWithOpts:opts];
    [bluetooth setDelegate:self];
  } @catch(NSException *e) {
    ret = [e description];
  }
  callback(@[ret]);
}

RCT_EXPORT_METHOD(startScanning:(RCTResponseSenderBlock)callback)
{
  [[BluetoothResponder sharedInstance] startScanning];
  callback(@[[NSNull null]]);
}
RCT_EXPORT_METHOD(stopScanning:(RCTResponseSenderBlock)callback)
{
  [[BluetoothResponder sharedInstance] stopScanning];
  callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(respondToRequest:(NSDictionary *)opts callback:(RCTResponseSenderBlock)callback)
{
  [[BluetoothResponder sharedInstance] respondToRequest:opts];
  callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(notifyWithValue:(NSString *)value callback:(RCTResponseSenderBlock)callback)
{
  NSData *data = [[NSData alloc] initWithBase64EncodedString:value options:NSDataBase64DecodingIgnoreUnknownCharacters];
  BOOL ret = [[BluetoothResponder sharedInstance] notifyWithValue:data];
  callback(ret ? @[[NSNull null]] : @[@"transmit_queue_full"]);
}

RCT_EXPORT_METHOD(connectToPeripheral:(NSString *)uuidString callback:(RCTResponseSenderBlock)callback)
{
  [[BluetoothResponder sharedInstance] connectToPeripheral:uuidString];
  callback(@[[NSNull null]]);
}

RCT_EXPORT_METHOD(getPeripheralList:(RCTResponseSenderBlock)callback)
{
  NSArray *array = [[BluetoothResponder sharedInstance] peripheralList];
  callback(@[[NSNull null],array]);
}

RCT_EXPORT_METHOD(getState:(RCTResponseSenderBlock)callback)
{
  callback(@[[NSNull null],@{
    @"isPoweredOn": [[BluetoothResponder sharedInstance] isPoweredOn],
  }]);
}

- (void)sendEvent:(NSString *)name body:(NSDictionary *)body {
  [self.bridge.eventDispatcher sendAppEventWithName:name body:body];
}

@end

@implementation BluetoothResponder {
  CBPeripheralManager *_peripheralManager;
  CBCentralManager *_centralManager;
  CBMutableService *_service;
  CBMutableCharacteristic *_characteristic;
  NSMutableArray<CBPeripheral *> *_peripheralList;
  BluetoothModule *_delegate;
  NSMutableDictionary<NSString *,CBATTRequest *> *_requestMap;
}

@synthesize centralManagerQueue;

static CBUUID *g_serviceUUID = nil;
static CBUUID *g_characteristicUUID = nil;
static BluetoothResponder *g_sharedInstance = nil;

+ (BluetoothResponder *)sharedInstanceWithOpts:(NSDictionary *)opts {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    id service_uuid = [opts objectForKey:@"service_uuid"];
    id characteristic_uuid = [opts objectForKey:@"chracteristic_uuid"];
    if (service_uuid && characteristic_uuid) {
      g_serviceUUID = [CBUUID UUIDWithString:service_uuid];
      g_characteristicUUID = [CBUUID UUIDWithString:characteristic_uuid];
      g_sharedInstance = [[self alloc] init];
      NSLog(@"Init: service: %@, characteristic: %@",g_serviceUUID,g_characteristicUUID);
    } else {
      NSLog(@"Bad init");
    }
  });
  return g_sharedInstance;
}

+ (BluetoothResponder *)sharedInstance {
  return g_sharedInstance;
}

- (BluetoothResponder *)init {
  if (self = [super init]) {
    _peripheralList = [NSMutableArray new];
    _requestMap = [NSMutableDictionary new];

    CBCharacteristicProperties props = CBCharacteristicPropertyRead | CBCharacteristicPropertyNotify | CBCharacteristicPropertyWrite;
    CBAttributePermissions permissions = CBAttributePermissionsReadable | CBAttributePermissionsWriteable;

    _characteristic = [[CBMutableCharacteristic alloc] initWithType:g_characteristicUUID
      properties:props
      value:nil
      permissions:permissions];

    _peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:nil options:nil];
    _service = [[CBMutableService alloc] initWithType:g_serviceUUID primary:YES];
    _service.characteristics = @[_characteristic];

    _centralManager = [[CBCentralManager alloc] initWithDelegate:self
      queue:self.centralManagerQueue
      options:nil];
  }
  return self;
}

- (void)setDelegate:(BluetoothModule *)delegate {
  _delegate = delegate;
}

- (void)startScanning {
  [_centralManager scanForPeripheralsWithServices:@[g_serviceUUID] options:nil];
}
- (void)stopScanning {
  [_centralManager stopScan];
}

- (void)respondToRequest:(NSDictionary *)opts {
  NSString *requestId = [opts objectForKey:@"requestId"];
  NSString *value = [opts objectForKey:@"value"];
  CBATTRequest *request = [_requestMap objectForKey:requestId];
  if (request) {
    [_requestMap removeObjectForKey:requestId];
    request.value = [value dataUsingEncoding:NSUTF8StringEncoding];
    [_peripheralManager respondToRequest:request withResult:CBATTErrorSuccess];
  }
}
- (BOOL)notifyWithValue:(NSData *)value {
  return [_peripheralManager updateValue:value
    forCharacteristic:_characteristic
    onSubscribedCentrals:nil];
}
- (void)connectToPeripheral:(NSString *)uuidString {
  for(CBPeripheral *peripheral in _peripheralList) {
    if ([[peripheral.identifier UUIDString] isEqualToString:uuidString]) {
      [_centralManager connectPeripheral:peripheral options:nil];
    }
  }
}
- (NSArray *)peripheralList {
  NSMutableArray *array = [NSMutableArray new];
  for (CBPeripheral *peripheral in _peripheralList) {
    [array addObject:@{
      @"peripheral": [peripheral.identifier UUIDString],
      @"isConnected": peripheral.state == CBPeripheralStateConnected ? @TRUE : @FALSE,
      @"isConnecting": peripheral.state == CBPeripheralStateConnecting ? @TRUE : @FALSE,
    }];
  }
  return array;
}
- (id)isPoweredOn {
#if TARGET_IPHONE_SIMULATOR
  return @TRUE;
#else
  return _centralManager.state == CBCentralManagerStatePoweredOn ? @TRUE : @FALSE;
#endif
}

/********************************************************************************************/

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
  if (peripheral.state == CBPeripheralManagerStatePoweredOn) {
    [peripheral removeAllServices];
    [peripheral addService:_service];
    [peripheral startAdvertising:@{
      CBAdvertisementDataServiceUUIDsKey: @[_service.UUID]
    }];
  }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
  willRestoreState:(NSDictionary<NSString *, id> *)dict {
  NSLog(@"willRestoreState");
}
- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral
  error:(nullable NSError *)error {
  if (error) {
    NSLog(@"peripheralManagerDidStartAdvertising: Error: %@",[error localizedDescription]);
  }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
  didAddService:(CBService *)service
  error:(nullable NSError *)error {
  if (error) {
    NSLog(@"didAddService: Error: %@",[error localizedDescription]);
  }
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
  central:(CBCentral *)central
  didSubscribeToCharacteristic:(CBCharacteristic *)characteristic {
}

- (void)peripheralManager:(CBPeripheralManager *)peripheral
  central:(CBCentral *)central
  didUnsubscribeFromCharacteristic:(CBCharacteristic *)characteristic {
}


- (void)peripheralManager:(CBPeripheralManager *)peripheral
  didReceiveReadRequest:(CBATTRequest *)request {
  NSString *requestId = [[NSUUID UUID] UUIDString];
  [_requestMap setObject:request forKey:requestId];

  [_delegate sendEvent:@"bluetooth.peripheral.read" body:@{
    @"time": getTime(),
    @"requestId": requestId,
    @"central": [request.central.identifier UUIDString],
    @"offset": [NSNumber numberWithLong:request.offset],
    @"characteristic": @{
      @"UUID": [request.characteristic.UUID UUIDString],
    },
  }];
}
- (void)peripheralManager:(CBPeripheralManager *)peripheral
  didReceiveWriteRequests:(NSArray<CBATTRequest *> *)requests {
  for (CBATTRequest *request in requests) {
    NSString *valueBase64 = [request.value base64EncodedStringWithOptions:0];
    [_delegate sendEvent:@"bluetooth.peripheral.write" body:@{
      @"time": getTime(),
      @"central": [request.central.identifier UUIDString],
      @"offset": [NSNumber numberWithLong:request.offset],
      @"valueBase64": valueBase64,
      @"characteristicUUID": [request.characteristic.UUID UUIDString],
    }];
    [peripheral respondToRequest:request withResult:CBATTErrorSuccess];
  }
}

- (void)peripheralManagerIsReadyToUpdateSubscribers:(CBPeripheralManager *)peripheral {
  NSLog(@"peripheralManagerIsReadyToUpdateSubscribers");
}

/********************************************************************************************/

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  if (central.state == CBCentralManagerStatePoweredOn) {
    [central scanForPeripheralsWithServices:@[g_serviceUUID] options:nil];
  } else {
    [_peripheralList removeAllObjects];
  }
  [_delegate sendEvent:@"bluetooth.central.state" body:@{
    @"isPoweredOn": [self isPoweredOn],
  }];
}
- (void)centralManager:(CBCentralManager *)central
  willRestoreState:(NSDictionary<NSString *, id> *)dict {
}
- (void)centralManager:(CBCentralManager *)central
  didDiscoverPeripheral:(CBPeripheral *)peripheral
  advertisementData:(NSDictionary<NSString *, id> *)advertisementData
  RSSI:(NSNumber *)RSSI {

  [peripheral setDelegate:self];
  [_peripheralList addObject:peripheral];
  [_centralManager connectPeripheral:peripheral options:nil];
  [_delegate sendEvent:@"bluetooth.peripheral.discover" body:@{
    @"time": getTime(),
    @"peripheral": [peripheral.identifier UUIDString],
  }];
}
- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral {
  [peripheral discoverServices:@[g_serviceUUID]];
  [_delegate sendEvent:@"bluetooth.peripheral.connect" body:@{
    @"time": getTime(),
    @"peripheral": [peripheral.identifier UUIDString],
  }];
}

- (void)centralManager:(CBCentralManager *)central
  didFailToConnectPeripheral:(CBPeripheral *)peripheral
  error:(nullable NSError *)error {
  [_delegate sendEvent:@"bluetooth.peripheral.connect_fail" body:@{
    @"time": getTime(),
    @"error": error ? [error description] : [NSNull null],
    @"peripheral": [peripheral.identifier UUIDString],
  }];
}

- (void)centralManager:(CBCentralManager *)central
  didDisconnectPeripheral:(CBPeripheral *)peripheral
  error:(nullable NSError *)error {
  [_delegate sendEvent:@"bluetooth.peripheral.disconnect" body:@{
    @"time": getTime(),
    @"error": error ? [error description] : [NSNull null],
    @"peripheral": [peripheral.identifier UUIDString],
  }];
}

/********************************************************************************************/

- (void)peripheral:(CBPeripheral *)peripheral
  didDiscoverServices:(nullable NSError *)error {
  if (error) {
    NSLog(@"didDiscoverServices: ERROR: %@",[error localizedDescription]);
  } else {
    for (CBService *service in peripheral.services) {
      [peripheral discoverCharacteristics:nil forService:service];
    }
  }
}
- (void)peripheral:(CBPeripheral *)peripheral
  didDiscoverIncludedServicesForService:(CBService *)service
  error:(nullable NSError *)error {
}
- (void)peripheral:(CBPeripheral *)peripheral
  didDiscoverCharacteristicsForService:(CBService *)service
  error:(nullable NSError *)error {
  if (error) {
    NSLog(@"didDiscoverCharacteristicsForService: ERROR: %@",[error localizedDescription]);
  } else {
    for (CBCharacteristic *characteristic in service.characteristics) {
      [peripheral setNotifyValue:YES forCharacteristic:characteristic];
    }
  }
}
- (void)peripheral:(CBPeripheral *)peripheral
  didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic
  error:(nullable NSError *)error {
  if (error) {
    NSLog(@"didUpdateValueForCharacteristic: ERROR: %@",[error localizedDescription]);
  }

  NSString *valueBase64 = [characteristic.value base64EncodedStringWithOptions:0];
  [_delegate sendEvent:@"bluetooth.peripheral.update_value" body:@{
    @"time": getTime(),
    @"error": error ? [error description] : [NSNull null],
    @"peripheral": [peripheral.identifier UUIDString],
    @"characteristicUUID": [characteristic.UUID UUIDString],
    @"valueBase64": valueBase64,
  }];
}
 - (void)peripheral:(CBPeripheral *)peripheral
  didWriteValueForCharacteristic:(CBCharacteristic *)characteristic
  error:(nullable NSError *)error {
  if (error) {
    NSLog(@"didWriteValueForCharacteristic: ERROR: %@",[error localizedDescription]);
  }
}
- (void)peripheral:(CBPeripheral *)peripheral
  didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic
  error:(nullable NSError *)error {
  if (error) {
    NSLog(@"didUpdateNotificationStateForCharacteristic: ERROR: %@",[error localizedDescription]);
  }
}
- (void)peripheral:(CBPeripheral *)peripheral
  didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic
  error:(nullable NSError *)error {
}
- (void)peripheral:(CBPeripheral *)peripheral
  didUpdateValueForDescriptor:(CBDescriptor *)descriptor
  error:(nullable NSError *)error {
  if (error) {
    NSLog(@"didUpdateValueForDescriptor: ERROR: %@",[error localizedDescription]);
  }
}
- (void)peripheral:(CBPeripheral *)peripheral
  didWriteValueForDescriptor:(CBDescriptor *)descriptor
  error:(nullable NSError *)error {
  if (error) {
    NSLog(@"didWriteValueForDescriptor: ERROR: %@",[error localizedDescription]);
  }
}

/********************************************************************************************/


@end

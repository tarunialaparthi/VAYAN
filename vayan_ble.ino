#include <Wire.h>
#include <math.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <string.h>

// ---------------- PIN CONFIGURATION ------------------
#define SDA_PIN 21
#define SCL_PIN 22

// ---------------- MPU6050 CONFIGURATION --------------
#define MPU_ADDR_1 0x68
#define MPU_ADDR_2 0x69

uint8_t MPU_ADDR = MPU_ADDR_1;

// ---------------- SAMPLING ---------------------------
const unsigned long SAMPLE_INTERVAL = 20;
const unsigned long PRINT_INTERVAL = 1000;

// ---------------- BLE CONFIGURATION -------------------
#define BLE_DEVICE_NAME "VAYAN_ESP32"
#define SERVICE_UUID "12345678-1234-1234-1234-1234567890AB"
#define CHARACTERISTIC_UUID "ABCD1234-5678-1234-1234-1234567890AB"

BLEServer* bleServer = nullptr;
BLECharacteristic* sensorCharacteristic = nullptr;
bool bleDeviceConnected = false;

// ---------------- STEP DETECTION ---------------------
const float STEP_GYRO_THRESHOLD = 18.0;
const float STEP_ACCEL_THRESHOLD = 0.18;

const unsigned long MIN_STEP_DURATION = 40;
const unsigned long MAX_STEP_DURATION = 800;
const unsigned long STEP_REFRACTORY = 350;

// ---------------- SMALL MOVEMENT DETECTION -----------
const float SMALL_GYRO_THRESHOLD = 2.0;
const float SMALL_ACCEL_THRESHOLD = 0.025;

const int MIN_ATTEMPT_MOVEMENTS = 8;
const int MIN_DIRECTION_CHANGES = 3;

// ---------------- FoG TIMING -------------------------
const unsigned long DEFAULT_STEP_TIMEOUT = 2500;
const unsigned long TIMEOUT_MARGIN = 500;
const unsigned long FREEZING_OBSERVATION_TIME = 10000;
const int RESUME_STEPS_REQUIRED = 2;

// ---------------- CALIBRATION ------------------------
const int CALIBRATION_SAMPLES = 100;

// ---------------- SENSOR VARIABLES -------------------
float ax, ay, az;
float gx, gy, gz;

float gyroOffsetX = 0;
float gyroOffsetY = 0;
float gyroOffsetZ = 0;

float accelMagnitude = 0;
float accelDynamic = 0;
float gyroMagnitude = 0;

// ---------------- TIMING VARIABLES -------------------
unsigned long lastSampleTime = 0;
unsigned long lastPrintTime = 0;

unsigned long lastValidStepTime = 0;
unsigned long lastWalkActivityTime = 0;
unsigned long lastStepPulseTime = 0;

unsigned long stepPulseStartTime = 0;

// ---------------- STEP VARIABLES ---------------------
bool stepPulseActive = false;

float stepPeakGyro = 0;
float stepPeakAccel = 0;

unsigned long stepPulseDuration = 0;

int totalSteps = 0;

// ---------------- CADENCE VARIABLES ------------------
const int CADENCE_BUFFER_SIZE = 5;

unsigned long cadenceIntervals[CADENCE_BUFFER_SIZE];

int cadenceIndex = 0;
int cadenceCount = 0;

float averageStepInterval = 0;

// ---------------- MOVEMENT VARIABLES -----------------
int attemptedMovementCount = 0;
int directionChangeCount = 0;

float previousGx = 0;
float previousGy = 0;
float previousGz = 0;

// ---------------- STATE MACHINE ----------------------
enum MonitorState {
  IDLE,
  OBSERVING,
  WALKING,
  POSSIBLE_FREEZING
};

MonitorState currentState = IDLE;

unsigned long observationStartTime = 0;
int completedStepsInWindow = 0;

// =====================================================
// MPU6050 FUNCTIONS
// =====================================================

bool checkMPU(uint8_t address) {
  Wire.beginTransmission(address);
  return Wire.endTransmission() == 0;
}

bool initializeMPU() {

  if (checkMPU(MPU_ADDR_1)) {
    MPU_ADDR = MPU_ADDR_1;
  }
  else if (checkMPU(MPU_ADDR_2)) {
    MPU_ADDR = MPU_ADDR_2;
  }
  else {
    return false;
  }

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0x00);
  if (Wire.endTransmission() != 0) return false;

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1C);
  Wire.write(0x00);
  if (Wire.endTransmission() != 0) return false;

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1B);
  Wire.write(0x00);
  if (Wire.endTransmission() != 0) return false;

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1A);
  Wire.write(0x03);
  if (Wire.endTransmission() != 0) return false;

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x19);
  Wire.write(19);
  if (Wire.endTransmission() != 0) return false;

  return true;
}

// =====================================================
// READ RAW SENSOR DATA
// =====================================================

bool readMPU() {

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);

  if (Wire.endTransmission(false) != 0) {
    return false;
  }

  if (Wire.requestFrom(MPU_ADDR, (uint8_t)14) != 14) {
    return false;
  }

  int16_t rawAX = (Wire.read() << 8) | Wire.read();
  int16_t rawAY = (Wire.read() << 8) | Wire.read();
  int16_t rawAZ = (Wire.read() << 8) | Wire.read();

  Wire.read();
  Wire.read();

  int16_t rawGX = (Wire.read() << 8) | Wire.read();
  int16_t rawGY = (Wire.read() << 8) | Wire.read();
  int16_t rawGZ = (Wire.read() << 8) | Wire.read();

  ax = rawAX / 16384.0;
  ay = rawAY / 16384.0;
  az = rawAZ / 16384.0;

  gx = rawGX / 131.0 - gyroOffsetX;
  gy = rawGY / 131.0 - gyroOffsetY;
  gz = rawGZ / 131.0 - gyroOffsetZ;

  accelMagnitude = sqrt(
    ax * ax +
    ay * ay +
    az * az
  );

  accelDynamic = fabs(accelMagnitude - 1.0);

  gyroMagnitude = sqrt(
    gx * gx +
    gy * gy +
    gz * gz
  );

  return true;
}

// =====================================================
// GYROSCOPE CALIBRATION
// =====================================================

void calibrateGyroscope() {

  float sumX = 0;
  float sumY = 0;
  float sumZ = 0;

  Serial.println();
  Serial.println("GYROSCOPE CALIBRATION");
  Serial.println("Keep the ankle still...");

  for (int i = 0; i < CALIBRATION_SAMPLES; i++) {

    if (readMPU()) {
      sumX += gx + gyroOffsetX;
      sumY += gy + gyroOffsetY;
      sumZ += gz + gyroOffsetZ;
    }

    delay(20);
  }

  gyroOffsetX = sumX / CALIBRATION_SAMPLES;
  gyroOffsetY = sumY / CALIBRATION_SAMPLES;
  gyroOffsetZ = sumZ / CALIBRATION_SAMPLES;

  Serial.println("Calibration completed.");
}


// CADENCE FUNCTIONS


void updateCadence(unsigned long now) {

  if (lastValidStepTime > 0) {

    unsigned long interval = now - lastValidStepTime;

    if (interval >= 300 && interval <= 2500) {

      cadenceIntervals[cadenceIndex] = interval;

      cadenceIndex =
        (cadenceIndex + 1) % CADENCE_BUFFER_SIZE;

      if (cadenceCount < CADENCE_BUFFER_SIZE) {
        cadenceCount++;
      }

      unsigned long total = 0;

      for (int i = 0; i < cadenceCount; i++) {
        total += cadenceIntervals[i];
      }

      averageStepInterval =
        (float)total / cadenceCount;
    }
  }

  lastValidStepTime = now;
}

unsigned long getExpectedStepTimeout() {

  if (cadenceCount >= 2) {
    return (unsigned long)averageStepInterval
           + TIMEOUT_MARGIN;
  }

  return DEFAULT_STEP_TIMEOUT;
}

// MOVEMENT ANALYSIS


void resetMovementCounters() {

  attemptedMovementCount = 0;
  directionChangeCount = 0;

  previousGx = gx;
  previousGy = gy;
  previousGz = gz;
}

void analyseSmallMovement() {

  if (
    gyroMagnitude > SMALL_GYRO_THRESHOLD ||
    accelDynamic > SMALL_ACCEL_THRESHOLD
  ) {
    attemptedMovementCount++;
  }

  if (
    previousGx * gx < 0 &&
    fabs(gx) > SMALL_GYRO_THRESHOLD
  ) {
    directionChangeCount++;
  }

  if (
    previousGy * gy < 0 &&
    fabs(gy) > SMALL_GYRO_THRESHOLD
  ) {
    directionChangeCount++;
  }

  if (
    previousGz * gz < 0 &&
    fabs(gz) > SMALL_GYRO_THRESHOLD
  ) {
    directionChangeCount++;
  }

  previousGx = gx;
  previousGy = gy;
  previousGz = gz;
}

bool attemptedMovementDetected() {

  return (
    attemptedMovementCount >= MIN_ATTEMPT_MOVEMENTS &&
    directionChangeCount >= MIN_DIRECTION_CHANGES
  );
}


// STEP DETECTION


bool detectStepEvent(unsigned long now) {

  bool movementDetected =
    gyroMagnitude >= STEP_GYRO_THRESHOLD ||
    accelDynamic >= STEP_ACCEL_THRESHOLD;

  if (
    movementDetected &&
    !stepPulseActive &&
    (now - lastStepPulseTime >= STEP_REFRACTORY)
  ) {

    stepPulseActive = true;

    stepPulseStartTime = now;

    stepPeakGyro = gyroMagnitude;
    stepPeakAccel = accelDynamic;
  }

  if (stepPulseActive) {

    if (gyroMagnitude > stepPeakGyro) {
      stepPeakGyro = gyroMagnitude;
    }

    if (accelDynamic > stepPeakAccel) {
      stepPeakAccel = accelDynamic;
    }

    stepPulseDuration = now - stepPulseStartTime;

    if (!movementDetected) {

      stepPulseActive = false;

      if (
        stepPulseDuration >= MIN_STEP_DURATION &&
        stepPulseDuration <= MAX_STEP_DURATION
      ) {

        lastStepPulseTime = now;
        return true;
      }
    }

    if (stepPulseDuration > MAX_STEP_DURATION) {
      stepPulseActive = false;
    }
  }

  return false;
}

// =====================================================
// STATE TRANSITIONS
// =====================================================

bool smallMovementPresent() {
  return (
    gyroMagnitude > SMALL_GYRO_THRESHOLD ||
    accelDynamic > SMALL_ACCEL_THRESHOLD
  );
}

void beginObservation(unsigned long now, bool firstStepCompleted) {

  currentState = OBSERVING;
  observationStartTime = now;

  completedStepsInWindow = firstStepCompleted ? 1 : 0;

  resetMovementCounters();

  Serial.println();
  Serial.println("IDLE MOVEMENT DETECTED");
  Serial.println("10-second observation started");
}

void confirmWalking(unsigned long now) {

  currentState = WALKING;

  lastValidStepTime = now;
  lastWalkActivityTime = now;

  completedStepsInWindow = 0;

  resetMovementCounters();

  Serial.println();
  Serial.println("NORMAL WALKING CONFIRMED");
}

void processStepEvent(unsigned long now) {

  totalSteps++;
  lastWalkActivityTime = now;

  switch (currentState) {

    case IDLE:

      beginObservation(now, true);
      break;

    case OBSERVING:

      completedStepsInWindow++;
      updateCadence(now);

      if (completedStepsInWindow >= RESUME_STEPS_REQUIRED) {
        confirmWalking(now);
      }
      break;

    case WALKING:

      updateCadence(now);
      lastValidStepTime = now;
      break;

    case POSSIBLE_FREEZING:

      completedStepsInWindow++;
      updateCadence(now);

      if (completedStepsInWindow >= RESUME_STEPS_REQUIRED) {
        confirmWalking(now);
      }
      break;
  }
}

// =====================================================
// STATE MACHINE UPDATE
// =====================================================

void updateMonitorState(unsigned long now) {

  switch (currentState) {

    case IDLE:

      if (smallMovementPresent()) {
        beginObservation(now, false);
        analyseSmallMovement();
      }
      break;

    case OBSERVING:

      analyseSmallMovement();

      if (now - observationStartTime >= FREEZING_OBSERVATION_TIME) {

        if (
          attemptedMovementDetected() &&
          completedStepsInWindow < RESUME_STEPS_REQUIRED
        ) {

          currentState = POSSIBLE_FREEZING;
          completedStepsInWindow = 0;

          Serial.println();
          Serial.println("====================================");
          Serial.println("POSSIBLE FREEZING OF GAIT");
          Serial.println("Attempted leg movement detected");
          Serial.println("Fewer than 2 completed steps in 10 seconds");
          Serial.println("====================================");
        }
        else {

          currentState = IDLE;
          completedStepsInWindow = 0;

          resetMovementCounters();

          Serial.println();
          Serial.println("IDLE - NO FREEZING EVIDENCE");
        }
      }
      break;

    case WALKING:

      if (now - lastValidStepTime >= getExpectedStepTimeout()) {

        currentState = IDLE;

        lastValidStepTime = 0;
        completedStepsInWindow = 0;

        resetMovementCounters();

        Serial.println();
        Serial.println("WALKING STOPPED - IDLE");
      }
      break;

    case POSSIBLE_FREEZING:

      analyseSmallMovement();
      break;
  }
}

// =====================================================
// SERIAL MONITOR OUTPUT
// =====================================================

void printMonitorStatus() {

  Serial.println();
  Serial.println("========== VAYAN STATUS ==========");

  Serial.print("Accel (g): ");
  Serial.print(ax, 2);
  Serial.print(", ");
  Serial.print(ay, 2);
  Serial.print(", ");
  Serial.println(az, 2);

  Serial.print("Gyro (deg/s): ");
  Serial.print(gx, 2);
  Serial.print(", ");
  Serial.print(gy, 2);
  Serial.print(", ");
  Serial.println(gz, 2);

  Serial.print("Total steps: ");
  Serial.println(totalSteps);

  Serial.print("Average step interval (ms): ");
  Serial.println(averageStepInterval);

  Serial.print("Attempted movement samples: ");
  Serial.println(attemptedMovementCount);

  Serial.print("Direction changes: ");
  Serial.println(directionChangeCount);

  Serial.print("State: ");

  switch (currentState) {

    case IDLE:
      Serial.println("IDLE");
      break;

    case OBSERVING:
      Serial.println("OBSERVING - 10 SECOND WINDOW");
      break;

    case WALKING:
      Serial.println("NORMAL WALKING");
      break;

    case POSSIBLE_FREEZING:
      Serial.println("POSSIBLE FREEZING OF GAIT");
      break;
  }

  Serial.println("==================================");
}

// =====================================================
// BLE AND SENSOR DATA TRANSMISSION
// =====================================================

const char* getStateLabel() {
  switch (currentState) {
    case IDLE: return "IDLE";
    case OBSERVING: return "OBSERVING_10S";
    case WALKING: return "WALKING";
    case POSSIBLE_FREEZING: return "POSSIBLE_FREEZING";
    default: return "UNKNOWN";
  }
}

class VayanServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    bleDeviceConnected = true;
    Serial.println("Flutter app connected over BLE.");
  }

  void onDisconnect(BLEServer* server) override {
    bleDeviceConnected = false;
    Serial.println("Flutter app disconnected. Restarting BLE advertising...");
    BLEDevice::startAdvertising();
  }
};

void initializeBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);
  // A larger MTU is needed because each notification contains a JSON record.
  BLEDevice::setMTU(512);

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new VayanServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);
  sensorCharacteristic = service->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  sensorCharacteristic->addDescriptor(new BLE2902());
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("BLE ready. Device name: VAYAN_ESP32");
  Serial.println("Waiting for Flutter app connection...");
}

void sendSensorData() {
  if (!bleDeviceConnected || sensorCharacteristic == nullptr) {
    return;
  }

  // One complete JSON object per BLE notification.
  String payload = "{";
  payload += "\"timestamp_ms\":" + String(millis()) + ",";
  payload += "\"accel_x\":" + String(ax, 4) + ",";
  payload += "\"accel_y\":" + String(ay, 4) + ",";
  payload += "\"accel_z\":" + String(az, 4) + ",";
  payload += "\"gyro_x\":" + String(gx, 4) + ",";
  payload += "\"gyro_y\":" + String(gy, 4) + ",";
  payload += "\"gyro_z\":" + String(gz, 4) + ",";
  payload += "\"total_steps\":" + String(totalSteps) + ",";
  payload += "\"average_step_interval_ms\":" + String(averageStepInterval, 1) + ",";
  payload += "\"attempted_movement_count\":" + String(attemptedMovementCount) + ",";
  payload += "\"direction_change_count\":" + String(directionChangeCount) + ",";
  payload += "\"status\":\"" + String(getStateLabel()) + "\"";
  payload += "}";

  sensorCharacteristic->setValue(
    (uint8_t*)payload.c_str(),
    payload.length()
  );
  sensorCharacteristic->notify();
}

// =====================================================
// SETUP
// =====================================================

void setup() {

  Serial.begin(115200);

  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);

  delay(1000);

  Serial.println();
  Serial.println("=================================");
  Serial.println("VAYAN FoG MONITOR STARTING");
  Serial.println("ESP32 + MPU6050");
  Serial.println("=================================");

  if (!initializeMPU()) {

    Serial.println("ERROR: MPU6050 NOT DETECTED");

    while (1) {
      delay(1000);
    }
  }

  Serial.print("MPU6050 detected at address: 0x");
  Serial.println(MPU_ADDR, HEX);

  calibrateGyroscope();

  initializeBLE();

  lastSampleTime = millis();
  lastPrintTime = millis();

  Serial.println();
  Serial.println("SYSTEM READY");
  Serial.println("State logic: IDLE -> 10s OBSERVATION -> WALKING / POSSIBLE FoG");
}

// =====================================================
// MAIN LOOP
// =====================================================

void loop() {

  unsigned long now = millis();

  if (now - lastSampleTime >= SAMPLE_INTERVAL) {

    lastSampleTime += SAMPLE_INTERVAL;

    if (readMPU()) {

      bool stepDetected = detectStepEvent(now);

      if (stepDetected) {
        processStepEvent(now);
      }

      updateMonitorState(now);

      sendSensorData();
    }
  }

  if (now - lastPrintTime >= PRINT_INTERVAL) {

    lastPrintTime = now;

    printMonitorStatus();
  }
}
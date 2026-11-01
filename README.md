# VAYAN

### Early Cueing and Habitual Observation for Parkinsonian Mobility  
<p align="center">
  <strong>Monitor Movement. Identify Gait Irregularities. Support Rehabilitation.</strong>
</p>

---

## 1. About the Project

**VAYAN** is a wearable gait-monitoring and rehabilitation support prototype developed to address movement-related difficulties associated with Parkinson's disease, particularly **Freezing of Gait (FoG)**.

Parkinson's disease can affect an individual's ability to initiate movement, maintain balance and walk continuously. Freezing of Gait is a motor symptom in which a person temporarily experiences difficulty starting or continuing a walking movement.

VAYAN aims to monitor gait-related movement patterns using wearable sensors, identify possible freezing episodes and provide activity-based rehabilitation support through a dedicated mobile application.

The system integrates:

* An ESP32 microcontroller for embedded processing.
* An MPU6050 accelerometer and gyroscope for movement sensing.
* Bluetooth Low Energy (BLE) for wireless communication.
* A coin vibration motor for haptic feedback.
* A Flutter-based mobile application for monitoring and rehabilitation support.

The system is designed with an emphasis on affordability, portability and offline functionality.

---

## 2. Problem Statement

Individuals living with Parkinson's disease may experience several movement-related difficulties:

* Difficulty initiating walking.
* Reduced step consistency.
* Interrupted walking patterns.
* Freezing of Gait episodes.
* Difficulty maintaining continuous movement.

These symptoms can affect mobility, independence and everyday activities.

There is a need to explore affordable wearable systems that can monitor gait patterns, identify possible movement irregularities and support rehabilitation outside clinical environments.

---

## 3. Proposed Solution

VAYAN uses an ESP32-based wearable sensing system to monitor movement and identify patterns associated with possible Freezing of Gait.

The system follows this process:

1. The MPU6050 continuously captures acceleration and angular velocity.
2. The ESP32 processes the incoming sensor readings.
3. A step-detection algorithm monitors completed steps.
4. A state-machine-based approach classifies movement.
5. During a 10-second observation window, the system evaluates movement attempts and completed steps.
6. If repeated movement attempts occur without sufficient completed steps, the system identifies a possible freezing episode.
7. Movement information is transmitted to the Flutter mobile application through BLE.
8. The application displays activity information and provides rehabilitation recommendations.

The objective is to combine wearable movement monitoring with a patient-oriented mobile application.

---

# 4. Hardware Architecture

Hardware is the core of VAYAN. The wearable device captures movement data, processes it and communicates with the mobile application.

## 4.1 Hardware Components

| Component             | Function                                                                                              |
| --------------------- | ----------------------------------------------------------------------------------------------------- |
| ESP32                 | Main microcontroller responsible for sensor processing, movement classification and BLE communication |
| MPU6050               | 6-axis motion sensor containing a 3-axis accelerometer and 3-axis gyroscope                           |
| Coin Vibration Motor  | Provides haptic feedback through vibration                                                            |
| N-channel MOSFET      | Acts as an electronic switch to control the vibration motor                                           |
| Flyback Diode         | Protects the switching circuit from inductive voltage spikes, where applicable to the motor circuit   |                                                        |
| Supporting Components | Resistors, connecting wires                                           |

## 4.2 ESP32 – Main Processing Unit

The ESP32 acts as the brain of the wearable device.

Its responsibilities include:

* Communicating with the MPU6050 through I2C.
* Acquiring accelerometer and gyroscope readings.
* Processing movement information.
* Detecting step events.
* Monitoring movement attempts.
* Classifying movement states.
* Transmitting movement information through BLE.

The ESP32 also supports Wi-Fi, but the Flutter application's wearable communication uses BLE.

## 4.3 MPU6050 – Motion Sensing

The MPU6050 is a 6-axis motion-tracking sensor.

It contains:

**Accelerometer**

* Measures acceleration along X, Y and Z axes.
* Helps identify movement intensity and acceleration patterns.

**Gyroscope**

* Measures angular velocity along X, Y and Z axes.
* Helps identify rotational movement and changes in orientation.

The sensor communicates with the ESP32 through the I2C protocol.

### Sensor Connections

| MPU6050 Pin | ESP32 Pin |
| ----------- | --------- |
| VCC         | 3.3V      |
| GND         | GND       |
| SDA         | GPIO 21   |
| SCL         | GPIO 22   |

These are the I2C pin assignments used in the current firmware configuration.

## 4.4 Coin Vibration Motor – Haptic Feedback

The coin vibration motor is intended to provide physical vibration feedback.

It can be used to notify the wearer about movement-related events or prompts. Also, according to studies, small haptic feedback during freeze events can help few people to provide movement partially.

Since the ESP32 GPIO cannot directly supply the motor's operating current, a suitable N-channel MOSFET is used as a switching element.


## 4.5 Hardware Working Flow

```text
             MPU6050
          Accelerometer
             Gyroscope
                 |
                 | I2C
                 |
               ESP32
                 |
          Sensor Processing
                 |
           Step Detection
                 |
          Movement Analysis
                 |
          State Classification
                 |
          +------+------+
          |             |
         BLE        Vibration
          |             |
       Mobile App   Coin Motor
```

---

# 5. Embedded Firmware and Movement Detection

The ESP32 firmware is developed using Embedded C/C++ in the Arduino IDE.

## 5.1 Sensor Acquisition

The MPU6050 provides:

* Acceleration X, Y and Z.
* Gyroscope X, Y and Z.

The current firmware samples sensor data at approximately **50 Hz**, corresponding to one sample every 20 milliseconds.

## 5.2 Step Detection

The firmware analyses acceleration and gyroscope readings to identify movement patterns associated with step events.

It maintains a count of completed steps and uses this information to evaluate walking activity.

## 5.3 State-Machine-Based Movement Classification

VAYAN uses four primary movement states:

| State             | Responsibility                                                         |
| ----------------- | ---------------------------------------------------------------------- |
| IDLE              | Represents the absence of significant detected movement                |
| OBSERVING         | Monitors movement attempts during a 10-second observation window       |
| WALKING           | Indicates that sufficient completed steps have been detected           |
| POSSIBLE_FREEZING | Indicates repeated movement attempts with insufficient completed steps |


# 6. Bluetooth Low Energy (BLE) Communication

VAYAN uses Bluetooth Low Energy to establish communication between the ESP32 wearable and the Flutter mobile application.

### Communication Architecture

| Device                     | BLE Role       |
| -------------------------- | -------------- |
| ESP32                      | BLE Peripheral |
| Flutter Mobile Application | BLE Central    |


---

# 7. Flutter Mobile Application

The VAYAN mobile application is developed using **Flutter and Dart**.

It acts as the user-facing interface between the wearable device and the individual using the system.

The application is organised into three primary sections:

1. My Day
2. Doctors
3. Tomorrow

Each section has a specific responsibility.

## 7.1 My Day – Daily Activity Monitoring

The My Day page provides an overview of the user's daily movement information.

Its responsibilities include:

* Displaying the current activity status.
* Showing the number of reported discomfort episodes.
* Presenting daily movement information.
* Reflecting relevant sensor-detected activity.
* Helping the user understand their movement patterns throughout the day.

The purpose of this page is to provide a simple daily overview without requiring the user to interpret raw sensor readings.

## 7.2 Doctors – Activity Statistics and Monitoring

The Doctors page focuses on presenting activity information in a format useful for reviewing progress during medical checkups.

Its responsibilities include:

* Displaying activity statistics.
* Presenting graphical summaries of recorded information.
* Supporting monthly activity review.
* Helping communicate movement-related observations during consultations.

The page is intended to support discussions between individuals and healthcare professionals. It does not replace clinical assessment.

## 7.3 Tomorrow – Rehabilitation Recommendations

The Tomorrow page focuses on activity-based rehabilitation support.

Its responsibility is to recommend an exercise for the following day based on the user's recorded activity information.

The recommendation logic considers:

* Recorded movement activity.
* Sensor-detected episodes.
* Reported discomfort.
* Activity-related thresholds.

Based on the available information, the application selects a suitable exercise recommendation.

The page also provides:

* Recommended exercise for the next day.
* Exercise instructions.
* Visual guidance.
* Step-by-step exercise procedures.

The objective is to make rehabilitation guidance easier to access and follow.

**Important:** The exercise recommendations are prototype-generated suggestions, not medically prescribed treatment. They require review and validation by qualified healthcare professionals before clinical use.

---

# 8. Mobile Application Technologies

| Technology         | Purpose                                       |
| ------------------ | --------------------------------------------- |
| Flutter            | Cross-platform mobile application development |
| Dart               | Application programming language              |
| flutter_blue_plus  | BLE communication with ESP32                  |
| permission_handler | Managing required mobile permissions          |
| Realm              | Local data storage                            |
| qr_flutter         | QR code generation                            |
| mobile_scanner     | QR code scanning                              |

The application is designed to support local data access and reduce dependence on continuous internet connectivity.

---


# 12. Current Project Features

### Hardware and Embedded Systems

* ESP32-based wearable architecture.
* MPU6050 motion sensing.
* Accelerometer and gyroscope data acquisition.
* Step detection.
* State-machine-based movement classification.
* Experimental possible Freezing of Gait identification.
* Coin vibration motor interface.

### Wireless Communication

* BLE-based ESP32-to-mobile communication.
* Dedicated BLE service and characteristic.
* Offline-capable direct communication.

### Mobile Application

* My Day: daily activity monitoring.
* Doctors: activity statistics and monthly review.
* Tomorrow: activity-based rehabilitation recommendations.
* Exercise instructions and visual guidance.
* Local data storage.

---

# 13. Future Scope

* Improved movement classification using machine learning.
* Validation using real-world Parkinson's-related gait datasets.
* Better identification of different gait patterns.
* Personalised rehabilitation recommendations.
* More advanced haptic feedback.
* Long-term movement tracking.
* Improved patient and doctor reporting.
* Clinical evaluation and usability testing.
* Improved battery optimisation and wearable ergonomics.

---


# 15. Project Objective

The long-term objective of VAYAN is to explore how affordable embedded systems, wearable motion sensors and mobile technology can work together to support individuals experiencing Parkinson's-related gait difficulties.

By combining real-time movement monitoring with accessible rehabilitation guidance, VAYAN aims to contribute towards more accessible and patient-centred assistive technology.

---

**Developed as an academic engineering project focused on Embedded Systems, Wearable Electronics, BLE Communication, Mobile Application Development and Healthcare Technology.**

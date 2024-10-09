# Open Digital Payments Hub

## Introduction

The **Open Digital Payments Hub** is an open-source platform designed to facilitate secure and efficient financial transactions between countries. A group of countries or a region can host this hub, allowing each country to develop and register its own payment driver. Once registered, countries can perform financial transactions with other countries registered in the hub. This project includes two sample drivers as reference implementations, written in Ballerina, but countries can use a language of their preference to write their drivers.

## Features

- Facilitates cross-border financial transactions.
- Allows countries to develop and register custom drivers.
- Interaction between drivers and the hub is done via REST APIs.
- Reference drivers and mock payment networks are provided for guidance.

## Table of Contents

- [Build Instructions](#build-instructions)
  - [Building the Hub](#building-the-hub)
  - [Building the Sample Drivers](#building-the-sample-drivers)
  - [Building the Mock Payment Networks](#building-the-mock-payment-networks)
- [Run Instructions](#run-instructions)
  - [Starting the Hub](#starting-the-hub)
  - [Starting the ypay payment network](#starting-the-ypay-payment-network)
  - [Starting the drivers](#starting-the-drivers)
  - [Performing a mock transaction](#performing-a-mock-transaction)

## Build Instructions

### Building the Hub

The Digital Payments Hub is built using Ballerina. To build the hub:

1. Install [Ballerina](https://ballerina.io/learn/get-started/).
2. Clone this repository:

```bash
   git clone https://github.com/digital-payments-hub/digital-payments-hub.git
   cd digital-payments-hub
```

3. Navigate to the hub directory:

```bash
   cd payments-hub
```

4. Build the hub:

```bash
   bal build
```

5. Push the balllerina artifacts to the local repository:

```bash
   bal pack
   bal push --repository=local
```

### Building the Sample Drivers

To build the sample drivers, the common driver utils should be pushed to the local ballerina repository first:

1. Navigate to the driver utils directory:

```bash
   cd drivers/utils
```

2. Build the driver utils:

```bash
   bal build
```

3. Push the balllerina artifacts to the local repository:

```bash
   bal pack
   bal push --repository=local
```

Now the sample driver can be built.

1. Navigate to the xpay driver directory:

```bash
   cd drivers/xpay
```

2. Build the driver:

```bash
   bal build
```

The second sample driver (ypay) can be built the same way

### Building the mock payment networks

To mock a transaction between two drivers, we need 2 mock payments networks. To build the mock networks:

1. Navigate to the xpay-network directory:

```bash
   cd mock/xpay-network
```

4. Build the xpay-network:

```bash
   bal build
```

The second payment network (ypay-network) can be built the same way

## Run Instructions

### Starting the Hub

Navigate to the payments-hub directory and execute the following command

```bash
    bal run
```

### Starting the ypay payment network

Navigate to the mock/ypay-network directory and execute the following command

```bash
    bal run
```

### Starting the drivers

Navigate to the drivers/xpay and drivers/ypay directories and execute the following command

```bash
    bal run
```

### Performing a mock transaction

Navigate to the mock/xpay-network directory and execute the following command to send a mock payment request

```bash
    bal run
```

You will be able to see the transaction details in the ypay-network log, and the response will be visible in the xpay-network log.

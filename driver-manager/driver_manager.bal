// Copyright 2024 [name of copyright owner]
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ballerina/http;
import ballerina/io;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/tcp;
import ballerina/time;
import ballerina/uuid;
import ballerinax/kafka;

configurable DriverConfig[] drivers = ?;
map<DriverHttpClient> driverHttpClientMap = {};
map<string> driverNameCountryCodeMap = {};
FileEventPublisher eventPublisher = new FileEventPublisher("./driver-manager-events.log");

// Structure for driver configuration
type DriverConfig readonly & record {
    string name;
    string code;
    InboundConfig inbound;
    OutboundConfig outbound;
};

// Structure for the inbound configuration
type InboundConfig readonly & record {
    string transport;
    int port;
};

// Structure for the outbound configuration
type OutboundConfig readonly & record {
    string baseUrl;
};

type DriverResponse readonly & record {
    string destinationCode;
    string data;
};

enum EventType {
    RECEIVED_FROM_SOURCE,
    FORWARING_TO_SOURCE_DRIVER_INBOUND,
    RECEIVED_FROM_SOURCE_DRIVER_INBOUND,
    FORWARING_TO_DESTINATION_DRIVER_OUTBOUND,
    RECEIVED_FROM_DESTINATION_DRIVER_OUTBOUND,
    FORWARING__TO_SOURCE_DRIVER_RESPONSE,
    RECEIVED_FROM_SOURCE_DRIVER_RESPONSE,
    RESPONDING_TO_SOURCE
}

const DRIVER_MANAGER = "DriverManager";

public function main() returns error? {

    foreach DriverConfig driver in drivers {

        driverNameCountryCodeMap[driver.code] = driver.name;
        if ("tcp" == driver.inbound.transport) {
            check initiateNewTCPListener(driver);
        } else if ("http" == driver.inbound.transport) {
            check initiateNewHTTPListener(driver);
        } else {
            return error("Invalid transport configured for the driver.");
        }
    }
}

public function initiateNewTCPListener(DriverConfig driver) returns error? {

    DriverHttpClient driverHttpClient = check new DriverHttpClient(driver.outbound.baseUrl, driver.name);
    DriverTCPConnectionService paymentsTCPListener = new DriverTCPConnectionService(driver.name, driverHttpClient);

    string driverCountryCode = driver.code;
    string driverOutboundBaseUrl = driver.outbound.baseUrl;
    log:printInfo("Initialized http client for driver " + driverCountryCode + " at " + driverOutboundBaseUrl);
    driverHttpClientMap[driverCountryCode] = driverHttpClient;

    tcp:Listener tcpListener = check new tcp:Listener(driver.inbound.port);
    tcp:Service tcpService = service object {
        function onConnect(tcp:Caller caller) returns tcp:ConnectionService|error {
            log:printInfo("Client connected to port: " + driver.inbound.port.toString());
            return paymentsTCPListener;
        }
    };

    check tcpListener.attach(tcpService);
    check tcpListener.'start();
    runtime:registerListener(tcpListener);
    log:printInfo("Started " + driver.name + " listener on port: " + driver.inbound.port.toString());
    log:printInfo("Initialized http client for driver " + driver.name + " at " + driver.outbound.baseUrl);
}

public function initiateNewHTTPListener(DriverConfig driver) returns error? {

    DriverHttpClient driverHttpClient = check new DriverHttpClient(driver.outbound.baseUrl, driver.name);
    DriverHttpConnectionService paymentsHttpListener = new DriverHttpConnectionService(driver.name, driverHttpClient);

    string driverCountryCode = driver.code;
    string driverOutboundBaseUrl = driver.outbound.baseUrl;
    log:printInfo("Initialized http client for driver " + driverCountryCode + " at " + driverOutboundBaseUrl);
    driverHttpClientMap[driverCountryCode] = driverHttpClient;

    http:Listener httpListener = check new http:Listener(driver.inbound.port);
    http:Service httpService = service object {
        resource function post .(http:Caller caller, http:Request req) returns error? {
            log:printInfo("Client connected to HTTP service on port: " + driver.inbound.port.toString());
            check paymentsHttpListener.onRequest(caller, req);
        }
    };

    check httpListener.attach(httpService);
    check httpListener.'start();
    runtime:registerListener(httpListener);
    log:printInfo("Started " + driver.name + " HTTP listener on port: " + driver.inbound.port.toString());
    log:printInfo("Initialized http client for driver " + driver.name + " at " + driver.outbound.baseUrl);
}

function createEventJson(EventType eventType, string origin, string destination, string correlationId)
    returns json {

    string timestamp = time:utcNow().toString();
    string id = uuid:createType4AsString();

    json eventJsonObject = {
        "id": id,
        "correlationId": correlationId,
        "eventType": eventType,
        "origin": origin,
        "destination": destination,
        "eventTimestamp": timestamp,
        "status": "",
        "errorMessage": ""
    };

    return eventJsonObject;
}

public service class DriverHttpConnectionService {

    string driverName;
    DriverHttpClient driverHttpClient;

    function init(string driverName, DriverHttpClient driverHttpClient) {
        log:printInfo("Initialized new HTTP listener for " + driverName);
        self.driverName = driverName;
        self.driverHttpClient = driverHttpClient;
    }

    function onRequest(http:Caller caller, http:Request req) returns error? {

        string correlationId = uuid:createType4AsString();
        eventPublisher.publishEvent(RECEIVED_FROM_SOURCE, self.driverName, DRIVER_MANAGER, correlationId);

        // Read the request payload
        string requestData = check req.getTextPayload();
        log:printInfo("Received request data from client");

        // Send request to driver and get response
        log:printDebug("Sending request to driver : " + self.driverName);
        DriverResponse driverResponse = check self.driverHttpClient.sendInboundPayloadToDriver(requestData,
            correlationId);

        // Get destination client for the code
        log:printDebug("Destination code received from driver: " + driverResponse.destinationCode);
        DriverHttpClient destinationDriverHttpClient = driverHttpClientMap.get(driverResponse.destinationCode);
        string destinationDriverName = driverNameCountryCodeMap.get(driverResponse.destinationCode);

        // Send driver response data to destination and get response
        log:printDebug("Sending driver response to destination driver : " + destinationDriverName);
        DriverResponse destinationResponse = check destinationDriverHttpClient.sendOutboundPayloadToDriver(
            driverResponse.data, destinationDriverName, correlationId);

        // Send destination response data to driver and get response
        log:printDebug("Sending destination response to original driver : " + self.driverName);
        DriverResponse driverSecondResponse = check self.driverHttpClient.sendResponsePayloadToDriver(
            destinationResponse.data, correlationId);

        // Publish the response event and return the response
        eventPublisher.publishEvent(RESPONDING_TO_SOURCE, DRIVER_MANAGER, self.driverName, correlationId);

        // Create and send the response back to the client
        log:printDebug("Responding to origin of the payment");
        http:Response res = new;
        res.setTextPayload(driverSecondResponse.data);
        check caller->respond(res);
    }
}

public service class DriverTCPConnectionService {

    *tcp:ConnectionService;
    string driverName;
    DriverHttpClient driverHttpClient;

    function init(string driverName, DriverHttpClient driverHttpClient) {
        log:printInfo("Initialized new TCP listener for " + driverName);
        self.driverName = driverName;
        self.driverHttpClient = driverHttpClient;
    }

    function onBytes(tcp:Caller caller, readonly & byte[] data) returns byte[]|error|tcp:Error? {

        string dataString = check string:fromBytes(data);
        string correlationId = uuid:createType4AsString();

        eventPublisher.publishEvent(RECEIVED_FROM_SOURCE, self.driverName, DRIVER_MANAGER, correlationId);

        // Send request to driver and get response
        log:printDebug("Sending request to driver : " + self.driverName);
        DriverResponse driverResponse = check self.driverHttpClient.sendInboundPayloadToDriver(dataString,
            correlationId);

        // Get destination client for the code
        log:printDebug("Destination code received from driver: " + driverResponse.destinationCode);
        DriverHttpClient destinationDriverHttpClient = driverHttpClientMap.get(driverResponse.destinationCode);
        string destinationDriverName = driverNameCountryCodeMap.get(driverResponse.destinationCode);

        // Send driver response data to destination and get response
        log:printDebug("Sending driver response to destination driver : " + destinationDriverName);
        DriverResponse destinationResponse = check destinationDriverHttpClient.sendOutboundPayloadToDriver(
            driverResponse.data, destinationDriverName, correlationId);

        // Send destination response data to driver and get response
        log:printDebug("Sending destination response to original driver : " + self.driverName);
        DriverResponse driverFinalResponse = check self.driverHttpClient.sendResponsePayloadToDriver(
            destinationResponse.data, correlationId);

        eventPublisher.publishEvent(RESPONDING_TO_SOURCE, DRIVER_MANAGER, self.driverName, correlationId);
        log:printDebug("Responding to origin of the payment");
        return driverFinalResponse.data.toBytes();
    }

    function onError(tcp:Error err) {

        log:printError("An error occurred", 'error = err);
    }

    function onClose() {

        log:printInfo("Client left");
    }
}

public class DriverHttpClient {

    http:Client driverHttpClient;
    string driverName;

    function init(string driverBaseUrl, string driverName) returns error? {

        self.driverHttpClient = check new (driverBaseUrl);
        self.driverName = driverName;
    }

    function sendInboundPayloadToDriver(string payload, string correlationId)
        returns DriverResponse|error {

        http:Request request = new;
        request.setPayload(payload);
        request.setHeader("Content-Type", "text/plain");
        request.setHeader("X-Correlation-ID", correlationId);

        eventPublisher.publishEvent(FORWARING_TO_SOURCE_DRIVER_INBOUND, DRIVER_MANAGER, self.driverName, correlationId);
        http:Response response = check self.driverHttpClient->/inbound\-payload.post(request);

        string|http:HeaderNotFoundError destinationCode = response.getHeader("x-wso2-destination-code");
        string responseBody = check response.getTextPayload();
        eventPublisher.publishEvent(RECEIVED_FROM_SOURCE_DRIVER_INBOUND, self.driverName, DRIVER_MANAGER,
            correlationId);

        DriverResponse driverResponse = {
            destinationCode: destinationCode is string ? destinationCode : "N/A",
            data: responseBody
        };
        return driverResponse;
    }

    function sendOutboundPayloadToDriver(string payload, string destinationDriverName, string correlationId)
        returns DriverResponse|error {

        http:Request request = new;
        request.setPayload(payload);
        request.setHeader("Content-Type", "application/json");
        request.setHeader("X-Correlation-ID", correlationId);

        eventPublisher.publishEvent(FORWARING_TO_DESTINATION_DRIVER_OUTBOUND, DRIVER_MANAGER, destinationDriverName,
            correlationId);
        http:Response response = check self.driverHttpClient->/outbound\-payload.post(request);

        string responseBody = check response.getTextPayload();
        eventPublisher.publishEvent(RECEIVED_FROM_DESTINATION_DRIVER_OUTBOUND, destinationDriverName, DRIVER_MANAGER,
            correlationId);

        DriverResponse driverResponse = {
            destinationCode: "N/A",
            data: responseBody
        };
        return driverResponse;
    }

    function sendResponsePayloadToDriver(string payload, string correlationId)
        returns DriverResponse|error {

        http:Request request = new;
        request.setPayload(payload);
        request.setHeader("Content-Type", "application/json");
        request.setHeader("X-Correlation-ID", correlationId);

        eventPublisher.publishEvent(FORWARING__TO_SOURCE_DRIVER_RESPONSE, DRIVER_MANAGER, self.driverName,
            correlationId);
        http:Response response = check self.driverHttpClient->/response\-payload.post(request);

        string responseBody = check response.getTextPayload();
        eventPublisher.publishEvent(RECEIVED_FROM_SOURCE_DRIVER_RESPONSE, self.driverName, DRIVER_MANAGER,
            correlationId);

        DriverResponse driverResponse = {
            destinationCode: "N/A",
            data: responseBody
        };
        return driverResponse;
    }
}

public class KafkaEventPublisher {

    private final kafka:Producer kafkaPublisher;
    string topic = "payments-hub-driver-manager";

    function init() returns error? {
        self.kafkaPublisher = check new (kafka:DEFAULT_URL);
    }

    function publishEvent(EventType eventType, string origin, string destination, string correlationId) {

        string eventJson = createEventJson(eventType, origin, destination, correlationId).toString();

        kafka:Error? publishingError = self.kafkaPublisher->send({
            topic: self.topic,
            value: eventJson
        });

        if (publishingError is kafka:Error) {
            log:printError("Error occurred while publishing event", publishingError);
        } else {
            log:printDebug("Event successfully published");
        }
    }
}

public class FileEventPublisher {
    string filePath;

    function init(string filePath) {
        self.filePath = filePath;
    }

    function publishEvent(EventType eventType, string origin, string destination, string correlationId) {

        json eventJson = createEventJson(eventType, origin, destination, correlationId);
        string eventJsonString = eventJson.toString();
        string logEntry = eventJsonString + "\n";

        // Append the log entry to the file
        io:Error? publishingError = io:fileWriteString(self.filePath, logEntry, io:APPEND);

        if (publishingError is io:Error) {
            log:printError("Error occurred while publishing event", publishingError);
        } else {
            log:printDebug("Event successfully published");
        }
    }

}

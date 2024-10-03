// Copyright (c) 2024 WSO2 LLC. (https://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/task;
import ballerina/tcp;
import ballerina/time;
import ballerina/uuid;

http:Client hubClient = check new ("localhost:9090"); //ToDo: Remove
public http:Client paymentNetworkClient = check new ("localhost:9092"); //ToDo: Remove
map<http:Client> httpClientMap = {};
DriverMetadata[] metadataList = [];

# Initialize http/tcp listeners for the driver based on configurations.
#
# + driverConfig - driver configurations 
# + driverConnectionService - http/tcp connection service
# + return - error
public function initializeDriverListeners(DriverConfig driverConfig, tcp:ConnectionService|
        HTTPConnectionService driverConnectionService)
    returns error? {

    if ("tcp" == driverConfig.inbound.transport && driverConnectionService is tcp:ConnectionService) {
        check initiateNewTCPListener(driverConfig, driverConnectionService);
    } else if ("http" == driverConfig.inbound.transport && driverConnectionService is HTTPConnectionService) {
        check initiateNewHTTPListener(driverConfig, driverConnectionService);
    } else {
        return error("Invalid transport configured for the driver.");
    }
}

# Initialize http clients to communicate with the payments hub and payment network.
#
# + hubUrl - url of the payments hub  
# + paymentNetworkUrl - url of the payment network
# + return - error
public function initializeDriverHttpClients(string? hubUrl, string? paymentNetworkUrl) returns error? {

    if (hubUrl is string && paymentNetworkUrl is string) {
        hubClient = check new (hubUrl);
        paymentNetworkClient = check new (paymentNetworkUrl);
    }
}

# Start scheduled job for initializing http clients to communicate with destination drivers.
# + return - error
public function initializeDestinationDriverClients() returns error? {

    //ToDo : Make the periodic interval configurable
    task:JobId id = check task:scheduleJobRecurByFrequency(new DestinationClientInitializationJob(), 60);
    log:printInfo("Started DestinationClientInitializationJob with job id: " + id.toString());
}

# Register driver at payments hub.
#
# + driverMetadata - populated driver metadata record
# + return - error
public function registerDriverAtHub(DriverMetadata driverMetadata) returns error? {

    log:printInfo("Registering driver " + driverMetadata.driverName + " at payments hub.");
    log:printInfo("Driver info: " + driverMetadata.toString());
    DriverMetadata registerResponse = check hubClient->/payments\-hub/register.post(driverMetadata);

    // ToDo: Add error handling and retry logic
    log:printInfo("\nRegistration response from hub: " + registerResponse.toString());

}

# Send message to another driver.
#
# + countryCode - country code of the destination driver  
# + payload - request payload  
# + correlationId - correlation-id to track the transaction
# + return - response from the destination driver | error
public function sendToDestinationDriver(string countryCode, json payload, string correlationId) returns
    DestinationResponse|error {

    http:Client? destinationClient = httpClientMap[countryCode];

    if (destinationClient is http:Client) {
        http:Request request = new;
        request.setHeader("Content-Type", "application/json");
        request.setHeader("X-Correlation-ID", correlationId);
        request.setPayload(payload);
        http:Response response = check destinationClient->/transact.post(request);

        int responseStatusCode = response.statusCode;
        // string|http:HeaderNotFoundError responseCorrelationId = response.getHeader("X-Correlation-ID");
        json|http:ClientError responsePayload = response.getJsonPayload();

        // if (responseStatusCode == 200 && responseCorrelationId is string && responsePayload is json) {
        if (responseStatusCode == 200 && responsePayload is json) {
            DestinationResponse destinationResponse = {
                correlationId: correlationId,
                responsePayload: responsePayload
            };
            return destinationResponse;
        } else if (responsePayload is json) {
            log:printError("Error returned from the destination driver");
            return error(responsePayload.toString() + " CorrelationID: " + correlationId);
        } else if (responsePayload is error) {
            log:printError("Error occurred while forwarding request to the destination driver");
            return responsePayload;
        }
    } else {
        string errorMessage = "Http client for the destination " + countryCode + " not found";
        log:printError(errorMessage);
        return error(errorMessage);
    }
}

# Send request to the payment network.
#
# + payload - request payload
# + return - response as a json | error
public function sendToPaymentNetwork(json payload) returns json|error? {

    http:Request request = new;
    request.setHeader("Content-Type", "application/json");
    request.setPayload(payload);
    http:Response response = check paymentNetworkClient->/payment.post(request);
    return response.getJsonPayload();
}

# Publish event related to the transaction.
#
# + event - populated event object
public function publishEvent(Event event) {

    log:printInfo("Publishing event to payments hub.");
    json|http:ClientError eventResponse = hubClient->/payments\-hub/events.post(event.toJson());
    if (eventResponse is error) {
        log:printInfo("Error occurred when publishing event");
    } else {
        log:printInfo("\n Event published:" + event.toJsonString());
    }
}

# Get a populated event object with given parameters.
#
# + correlationId - correlation-id to track the transaction
# + eventType - type of the event. can be one of given 8 event types  
# + origin - origin of the message  
# + destination - destination of the message  
# + status - current status of the transaction  
# + errorMessage - error message if available
# + return - populated event object
public function createEvent(string correlationId, EventType eventType, string origin, string destination,
        string status, string errorMessage) returns Event {

    time:Utc utc = time:utcNow();
    string currentTimestamp = time:utcToString(utc);
    string id = uuid:createType4AsString();

    Event event = {
        id: id,
        correlationId: correlationId,
        eventType: eventType,
        origin: origin,
        destination: destination,
        eventTimestamp: currentTimestamp,
        status: status,
        errorMessage: errorMessage
    };

    return event;
}

# Get a ppopulated driver metadata record with given arguments
#
# + driverName - name of the driver  
# + countryCode - country code of the driver  
# + paymentEndpoint - payments endpoint which can be called by source drivers
# + return - populated driver metadata record
public function createDriverMetadata(string driverName, string countryCode, string paymentEndpoint)
    returns DriverMetadata {

    DriverMetadata driverMetadata = {
        driverName: driverName,
        countryCode: countryCode,
        paymentEndpoint: paymentEndpoint
    };

    return driverMetadata;
}

# Get metadata of the registered drivers at payments hub.
#
# + return - driver metadata | error
function getdriverMetadataFromHub() returns DriverMetadata[]|error {

    DriverMetadata[]|http:ClientError metadataList = hubClient->get("/payments-hub/metadata");

    if (metadataList is error) {
        log:printError("Error occurred when getting driver metadata from payments hub");
        return error("Error occurred when getting driver metadata from payments hub", metadataList);
    }
    return metadataList;
}

# Initiate a new TCP listener with the given connection service.
#
# + driver - configurations of the driver
# + driverTCPConnectionService - customized tcp connection service of the driver
# + return - error
function initiateNewTCPListener(DriverConfig driver, tcp:ConnectionService driverTCPConnectionService) returns error? {

    tcp:Listener tcpListener = check new tcp:Listener(driver.inbound.port);
    tcp:Service tcpService = service object {
        function onConnect(tcp:Caller caller) returns tcp:ConnectionService|error {
            log:printInfo("Client connected to port: " + driver.inbound.port.toString());
            return driverTCPConnectionService;
        }
    };
    check tcpListener.attach(tcpService);
    check tcpListener.'start();
    runtime:registerListener(tcpListener);
    log:printInfo("Started " + driver.name + " TCP listener on port: " + driver.inbound.port.toString());
};

# Initiate a new HTTP listener with the given connection service.
#
# + driver - configurations of the driver
# + driverHTTPConnectionService - customized http connection service of the driver
# + return - error
function initiateNewHTTPListener(DriverConfig driver, HTTPConnectionService driverHTTPConnectionService)
    returns error? {

    http:Listener httpListener = check new http:Listener(driver.inbound.port);
    http:Service httpService = service object {
        resource function post .(http:Caller caller, http:Request req) returns error? {
            log:printInfo("Client connected to HTTP service on port: " + driver.inbound.port.toString());
            check driverHTTPConnectionService.onRequest(caller, req);
        }
    };

    check httpListener.attach(httpService);
    check httpListener.'start();
    runtime:registerListener(httpListener);
    log:printInfo("Started " + driver.name + " HTTP listener on port: " + driver.inbound.port.toString());
}

# Represent HTTP Listener ConnectionService service type.
public type HTTPConnectionService distinct service object {

    public function onRequest(http:Caller caller, http:Request req) returns error?;
};

# Perioic job to initialize http clients to communicate with destination drivers.
# This job will only initialize http clients if there are any new drivers registered
# at the payments hub
class DestinationClientInitializationJob {
    *task:Job;

    public function execute() {

        DriverMetadata[]|error newMetadataList = getdriverMetadataFromHub();

        if (newMetadataList is DriverMetadata[]) {
            if (metadataList == newMetadataList) {
                log:printDebug("No change in cached destination driver metadata. " +
                        "No requirement to create new http clients.");
                return;
            }
            log:printInfo("Creating http clients for destination drivers.");
            metadataList = newMetadataList;
            httpClientMap.removeAll();
            foreach var metadata in metadataList {
                string countryCode = metadata.countryCode;
                http:Client|error destinationHttpClient = new (metadata.driverApiEndpoint);
                // Add the client to the map with countryCode as the key
                if (destinationHttpClient is http:Client) {
                    httpClientMap[countryCode] = destinationHttpClient;
                    log:printInfo("Http client for the destination " + countryCode + " created");
                } else {
                    log:printError("Error occurred while creating destination http client.",
                            destinationHttpClient);
                }
            }
        } else {
            log:printError("Error occurred while getting metadata of drivers from payment hub.", newMetadataList);
        }
    }
}

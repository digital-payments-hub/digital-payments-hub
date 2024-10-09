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

import payments_hub.models;

import ballerina/http;
import ballerina/log;

configurable int port = 9100;

public function main() {
    log:printInfo(string `Starting payments-hub on port: ${port}`);
}

service /payments\-hub on new http:Listener(port) {

    resource function post cross\-border/payments(@http:Header string Country\-Code, @http:Header string
            X\-Correlation\-ID, @http:Payload models:TransactionsRequest payload) returns json|models:ErrorResponse {

        log:printDebug(string `Received payment request payload: ${payload.toJsonString()}. CorrelationID: 
            ${X\-Correlation\-ID}`);
        json responseJson = sendPaymentRequestToTargetDriver(Country\-Code, X\-Correlation\-ID, payload);
        return responseJson;
    }

    resource function post cross\-border/accounts/look\-up(@http:Header string Country\-Code, @http:Header string
            X\-Correlation\-ID, @http:Payload models:AccountLookupRequest payload)
            returns json|models:AccountLookupResponse|models:ErrorResponse {

        // ToDo : Return lookup response
        log:printDebug(string `Received lookup request payload: ${payload.toJsonString()}. CorrelationID: 
            ${X\-Correlation\-ID}`);
        json responseJson = sendLookupRequestToTargetDriver(Country\-Code, X\-Correlation\-ID, payload);
        return responseJson;
    }

    resource function get discover() returns models:DriverRegisterModel[] {

        log:printDebug("Received discover request for all countries");
        models:DriverRegisterModel[] driverArray = driverMap.toArray();
        return driverArray;
    }

    resource function get discover/[string countryCode]() returns models:DriverRegisterModel|http:NotFound {

        log:printDebug("Received discover request for country code " + countryCode);
        models:DriverRegisterModel? discoveryData = driverMap[countryCode];
        if discoveryData is () {
            return http:NOT_FOUND;
        } else {
            return discoveryData;
        }
    }

    resource function post register(@http:Payload models:DriverRegisterModel registerPayload)
        returns models:DriverRegisterModel|http:BadRequest {

        log:printDebug("Received driver registration request");
        return registerDriver(registerPayload);
    }

    resource function get register/[string countryCode]()
        returns models:DriverRegisterModel|http:NotFound {

        log:printDebug("Received get registration data request for country code " + countryCode);
        models:DriverRegisterModel? registrationData = getDriverRegistrationData(countryCode);
        if registrationData is () {
            return http:NOT_FOUND;
        } else {
            return registrationData;
        }
    }

    resource function put register/[string countryCode](@http:Payload models:DriverRegisterModel registerPayload)
        returns models:DriverRegisterModel|http:NotFound|http:BadRequest {

        // ToDo: Implement update logic
        return registerPayload;
    }

    resource function delete register/[string countryCode]()
        returns http:NoContent|http:NotFound {

        log:printDebug("Received delete registration data request for country code " + countryCode);
        // ToDo: Implement delete logic
        return http:NO_CONTENT;
    }
}

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

// import ballerina/log;

import digitalpaymentshub/driver.utils;

configurable int port = 9090;

service /payments\-hub on new http:Listener(port) {

    map<utils:DriverMetadata> metadataMap = {};

    // resource function get metadata() returns utils:DriverMetadata[] {

    //     log:printDebug("Received metadata request for all countries");
    //     utils:DriverMetadata[] metadataArray = self.metadataMap.toArray();
    //     return metadataArray;
    // }

    // resource function get metadata/[string countryCode]() returns utils:DriverMetadata|http:NotFound {

    //     log:printDebug("Received metadata request for country code " + countryCode);
    //     utils:DriverMetadata? metadata = self.metadataMap[countryCode];
    //     if metadata is () {
    //         return http:NOT_FOUND;
    //     } else {
    //         return metadata;
    //     }
    // }

    // resource function post register(@http:Payload utils:DriverMetadata metadata) returns utils:DriverMetadata {

    //     log:printDebug("Received driver registration request");
    //     self.metadataMap[metadata.countryCode] = metadata;
    //     log:printInfo(metadata.driverName + " driver registered in payments hub with code " + metadata.countryCode);
    //     return metadata;
    // }
}

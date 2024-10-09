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

public type AccountLookupRequest record {
    string proxyType;
    string proxyValue;
    string bicCode?;
    map<string> metadata?;
};

public type AccountLookupResponse record {|
    *http:Ok;
    record {|
        Proxy proxy;
        Account account;
        map<string> metadata?;
    |} body;
|};

public type TransactionsRequest record {
    json data;
};

public type TransactionResponse record {|
    *http:Ok;
    record {|
        json data;
    |} body;
|};

public type ErrorResponse record {
    int statusCode;
    string errorCode;
    string errorDescription;
};

public type Proxy record {
    string 'type;
    string value;
};

public type Account record {
    string agentId;
    string name;
    string accountId;
};

public type Event record {

    string id;
    string correlationId;
    EventType eventType;
    string origin;
    string destination;
    string eventTimestamp;
    string status;
    string errorMessage;
};

public enum EventType {
    RECEIVED_FROM_SOURCE,
    FORWARDING_TO_DESTINATION_DRIVER,
    RECEIVED_FROM_SOURCE_DRIVER,
    FORWARDING_TO_PAYMENT_NETWORK,
    RECEIVED_FROM_PAYMENT_NETWORK,
    FORWARDING_TO_SOURCE_DRIVER,
    RECEIVED_FROM_DESTINATION_DRIVER,
    RESPONDING_TO_SOURCE
}

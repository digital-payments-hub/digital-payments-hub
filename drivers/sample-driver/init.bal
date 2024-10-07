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

import digitalpaymentshub/drivers.utils;
import digitalpaymentshub/payments_hub.models;

configurable models:DriverConfig driver = ?;
configurable models:PaymentsHubConfig payments_hub = ?;

public function main() returns error? {

    string driverGatewayUrl = driver.driver_api.gateway_url;

    models:AccountsLookUp[] accountsLookUp = [
        {'type: "MBNO", description: "Mobile Number"},
        {'type: "NIC", description: "National Identity Card Number"}
    ];
    models:DriverRegisterModel driverMetadata = utils:createDriverRegisterModel(driver.name, driver.code,
            accountsLookUp, driverGatewayUrl);
    check utils:initializeDriverListeners(driver, new DriverTCPConnectionService(driver.name));
    check utils:initializeHubClient(payments_hub.base_url);
    //todo initialize outbound client
    check utils:registerDriverAtHub(driverMetadata);
}

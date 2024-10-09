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

import yPayNetwork.models;

import ballerina/data.jsondata;
import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/financial.iso20022;

json receivedData = {
    "accountName": "",
    "originatingBank": "",
    "destinationBank": "",
    "amount": "",
    "isomsg": ""
};

# A service representing a network-accessible API
# bound to port `8300`.
service /v1/picasso\-guard/banks/nad/v2 on new http:Listener(8300) {

    # Inbound endpoint of LanakPay ISO 8583 messages.
    #
    # + caller - http caller
    # + req - http request
    # + return - return value description
    resource function get resolution/[string proxyType]/[string proxy](http:Caller caller, http:Request req)
        returns error? {

        string xBusinessMsgId = check req.getHeader("X-Business-Message-Id");
        log:printDebug(string `[YPay Payment Switch] Received a resolution request for proxy: ${proxy} of type: ${proxyType} with business message id: ${xBusinessMsgId}`);
        log:printDebug(string `[YPay Payment Switch] Received a proxy resolution message [id: ${xBusinessMsgId}].`);
        time:Utc utcTime = time:utcNow();
        string utcString = time:utcToString(utcTime);

        models:PrxyLookUpRspnCBFT response = {
            GrpHdr: {
                MsgId: xBusinessMsgId,
                CreDtTm: utcString.toString(),
                MsgSndr: {
                    Agt: {
                        FinInstnId: {
                            Othr: {
                                Id: "****MYKL"
                            }
                        }
                    }
                }
            },
            LkUpRspn: {
                OrgnlId: "",
                OrgnlPrxyRtrvl: {
                    Val: proxy,
                    Tp: proxyType
                },
                RegnRspn: {
                    PrxRspnSts: isValidProxy(proxy) ? "ACTC" : "RJCT",
                    StsRsnInf: {
                        Cd: isValidProxy(proxy) ? "U000" : "U129",
                        Prtry: ""
                    },
                    Prxy: {
                        Tp: proxyType,
                        Val: proxy
                    },
                    Regn: getAccounts(proxy)
                }
            },
            OrgnlGrpInf: {
                OrgnlMsgId: xBusinessMsgId,
                OrgnlMsgNmId: ""
            }
        };
        log:printDebug(string `[YPay Payment Switch] Responding to the proxy resolution message [id: ${xBusinessMsgId}].`, Message = response.toJson());
        check caller->respond(response);
    }

    resource function post register(http:Caller caller, http:Request req) returns error? {

        string xBusinessMsgId = check req.getHeader("X-Business-Message-Id");
        json payload = check req.getJsonPayload();
        log:printDebug(string `[YPay Payment Switch] Received a fund transfer message [id: ${xBusinessMsgId}].`, Message = payload);
        // models:FundTransfer fundTransferPayload = check jsondata:parseAsType(payload);
        iso20022:FIToFICstmrCdtTrf isoPacs008 = check jsondata:parseAsType(payload);

        receivedData = {
            "accountName": (isoPacs008.CdtTrfTxInf[0].Dbtr.Nm ?: ""),
            "originatingBank": (isoPacs008.CdtTrfTxInf[0].DbtrAcct?.Id?.Othr?.Id ?: ""),
            "destinationBank": (isoPacs008.CdtTrfTxInf[0].CdtrAgt.FinInstnId.Othr?.Id ?: ""),
            "amount": (isoPacs008.CdtTrfTxInf[0].IntrBkSttlmAmt.\#content).toString(),
            "isomsg": isoPacs008.toJson()
        };

        log:printDebug(string `[YPay Payment Switch] Fund transfer detials received [id: ${xBusinessMsgId}].`, Message = receivedData.toJson());

        models:FundTransferResponse response = {
            data: {
                businessMessageId: xBusinessMsgId,
                createdDateTime: isoPacs008.GrpHdr.CreDtTm,
                code: "U000",
                reason: "ACTC",
                registrationId: "0075800039"
            }
        };
        log:printDebug(string `[YPay Payment Switch] Responding to the fund transfer message [id: ${xBusinessMsgId}].`, Message = response.toJson());
        check caller->respond(response);
    }
}

service / on new http:Listener(5601) {
    resource function get data(http:Caller caller) returns http:ListenerError? {
        http:Response httpResponse = new;
        httpResponse.setJsonPayload(receivedData);
        httpResponse.setHeader("Access-Control-Allow-Origin", "*");
        httpResponse.setHeader("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
        check caller->respond(httpResponse);
    }
}

function getAccounts(string mobileNumber) returns models:Regn[] {

    match mobileNumber {
        "0060412341234" =>
        {
            return [
                {
                    RegnId: "0075800025",
                    DsplNm: "Bank Account",
                    Agt: {
                        FinInstnId: {
                            Othr: {
                                Id: "AIBMMYKLXXX"
                            }
                        }
                    },
                    Acct: {
                        Id: {
                            Othr: {
                                Id: "111222333444"
                            }
                        },
                        Nm: "Isabella Rivera"
                    },
                    PreAuthrsd: ""
                },
                {
                    RegnId: "0075800025",
                    DsplNm: "Bank Account",
                    Agt: {
                        FinInstnId: {
                            Othr: {
                                Id: "AIBMMYKLXXX"
                            }
                        }
                    },
                    Acct: {
                        Id: {
                            Othr: {
                                Id: "555666777888"
                            }
                        },
                        Nm: "Jordan Ramirez"
                    },
                    PreAuthrsd: ""
                }
            ];
        }
        "0060123456789" => {
            return [
                {
                    RegnId: "0092800067",
                    DsplNm: "Bank Account",
                    Agt: {
                        FinInstnId: {
                            Othr: {
                                Id: "AIBMMYKLXXX"
                            }
                        }
                    },
                    Acct: {
                        Id: {
                            Othr: {
                                Id: "331222000565"
                            }
                        },
                        Nm: "Alex Thornton"
                    },
                    PreAuthrsd: ""
                }
            ];
        }
        _ => {
            return [];
        }
    }
}

function isValidProxy(string mobileNumber) returns boolean {
    string[] vlaidNumbers = ["0060412341234", "0060123456789"];
    return vlaidNumbers.some(n => n == mobileNumber);
};

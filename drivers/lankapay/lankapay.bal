// Copyright 2024 [name of copyright owner]

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at

//     http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import digital.payments.hub.lankapay.util;

import ballerina/constraint;
import ballerina/data.jsondata;
import ballerina/http;
import ballerina/lang.'decimal as decimal0;
import ballerina/log;
import ballerinax/financial.iso20022;
import ballerinax/financial.iso8583;

service http:InterceptableService / on new http:Listener(9090) {

    # Inbound endpoint of LanakPay ISO 8583 messages.
    #
    # + caller - http caller
    # + req - http reques
    # + return - return value description
    isolated resource function post inbound_payload(http:Caller caller, http:Request req) returns error? {

        // Extract the string payload from the request and parse to iso 8583 xml
        string payload = check req.getTextPayload();
        anydata|iso8583:ISOError parsedISO8583Msg = iso8583:parse(payload);

        http:Response|error response;
        if (parsedISO8583Msg is iso8583:ISOError) {
            log:printError("Error occurred while parsing the ISO 8583 message", err = parsedISO8583Msg);
            response = error("Error occurred while parsing the ISO 8583 message: " + parsedISO8583Msg.message);
        } else {
            map<anydata> parsedISO8583Map = <map<anydata>>parsedISO8583Msg;
            string mti = <string>parsedISO8583Map[util:MTI];

            match mti {
                util:TYPE_MTI_0200 => {
                    // validate the parsed ISO 8583 message
                    iso8583:MTI_0200|error validatedMsg = constraint:validate(parsedISO8583Msg);

                    if (validatedMsg is iso8583:MTI_0200) {
                        // transform to ISO 20022 message
                        iso20022:FIToFICstmrCdtTrf|error iso20022Msg = transformMTI200ToISO20022(validatedMsg);
                        if (iso20022Msg is error) {
                            log:printError("Error while transforming to ISO 20022 message: " + iso20022Msg.message());
                            response = error("Error while transforming to ISO 20022 message: " + iso20022Msg.message());
                        } else {
                            // respond with the transformed ISO 20022 message to the driver manager
                            http:Response httpResponse = new;
                            httpResponse.setPayload(iso20022Msg.toJsonString());
                            httpResponse.setHeader(util:DESTINATION_COUNTRY_HEADER, 
                                check getDestinationCountry(getDataFromSupplementaryData(iso20022Msg.SplmtryData, 
                                    util:DESTINATION_COUNTRY_CODE)));
                            response = httpResponse;
                        }
                    } else {
                        log:printError("Error while validating incoming message: " + validatedMsg.message());
                        response = error("Error while validating: " + validatedMsg.toBalString());
                    }
                }
                _ => {
                    log:printError("MTI is not supported");
                    response = error("MTI is not supported");
                }
            }
        }
        // return response;
        check caller->respond(response);
    };

    # Transform the ISO 20022 message to ISO 8583 message.
    #
    # + caller - parameter description  
    # + req - parameter description
    # + return - return value description
    isolated resource function post response_payload(http:Caller caller, http:Request req) returns error? {

        // Extract the json payload from the request
        json payload = check req.getJsonPayload();
        iso20022:FIToFIPmtStsRpt iso20022Response = check jsondata:parseAsType(payload);
        // transform to ISO 8583 MTO 0210
        iso8583:MTI_0210|error mti0210msg = util:transformPacs002toMTI0210(iso20022Response);

        http:Response|error response;
        if mti0210msg is error {
            response = error("Error while transforming to ISO 8583 message: " + mti0210msg.message());
        } else {
            json jsonMsg = check jsondata:toJson(mti0210msg);
            string|iso8583:ISOError iso8583Msg = iso8583:generateISOMessage(jsonMsg);
            if iso8583Msg is string {
                http:Response httpResponse = new;
                httpResponse.setPayload(iso8583Msg);
                response = httpResponse;
            } else {
                response = error(iso8583Msg.message);
            }
        }
        check caller->respond(response);
    }

    isolated resource function post out (http:Caller caller, http:Request req) returns error? {}

    public function createInterceptors() returns http:Interceptor|http:Interceptor[] {
        return new util:ResponseErrorInterceptor();
    }
};

isolated function getDestinationCountry(string countryCode) returns string|error {
    match countryCode {
        "9001" => { return "MY"; }
        _ => { return error("Error while resolving destination country. Unknown country code : " + countryCode); }
    } 
};

isolated function transformMTI200ToISO20022(iso8583:MTI_0200 mti0200) returns iso20022:FIToFICstmrCdtTrf|error => {
    GrpHdr: {
        MsgId: mti0200.ProcessingCode,
        CreDtTm: mti0200.TransmissionDateTime,
        NbOfTxs: 1,
        SttlmInf: {
            SttlmMtd: "CLRG"
        }
    },
    CdtTrfTxInf: [
        {
            PmtId: {
                EndToEndId: mti0200.SystemTraceAuditNumber
            },
            IntrBkSttlmAmt: {
                \#content: check decimal0:fromString(mti0200.AmountTransaction),
                Ccy: mti0200.CurrencyCodeTransaction
            },
            ChrgBr: "CRED",
            Dbtr: {
                Nm: getDataFromField120(parseField120(mti0200.EftTlvData), "009")
            },
            DbtrAcct: {
                Id: {
                    Othr: {
                        Id: getDataFromField120(parseField120(mti0200.EftTlvData), "002")
                    }
                }
            },
            DbtrAgt: {
                FinInstnId: {
                    Othr: {
                        Id: mti0200.AcquiringInstitutionIdentificationCode
                    }
                }
            },
            CdtrAgt: {
                FinInstnId: {
                    Othr: {
                        Id: getDataFromField120(parseField120(mti0200.EftTlvData), "004")
                    }
                }
            },
            Cdtr: {
                Nm: getDataFromField120(parseField120(mti0200.EftTlvData), "010")
            }

        }
    ],
    SplmtryData: mapSupplementaryData(mti0200)
};

isolated function transformISO20022toMTI0200(iso20022:FIToFICstmrCdtTrf fiToFiCstmrCdtTrf) returns iso8583:MTI_0210 => {
    ProcessingCode: fiToFiCstmrCdtTrf.GrpHdr.MsgId, //todo
    MTI: "210",
    TransmissionDateTime: fiToFiCstmrCdtTrf.GrpHdr.CreDtTm,
    SystemTraceAuditNumber: fiToFiCstmrCdtTrf.CdtTrfTxInf[0].PmtId.EndToEndId,
    AmountTransaction: fiToFiCstmrCdtTrf.CdtTrfTxInf[0].IntrBkSttlmAmt.\#content.toString(),
    CurrencyCodeTransaction: fiToFiCstmrCdtTrf.CdtTrfTxInf[0].IntrBkSttlmAmt.Ccy,
    AcquiringInstitutionIdentificationCode: fiToFiCstmrCdtTrf.CdtTrfTxInf[0].DbtrAgt.FinInstnId.Othr?.Id ?: "",
    DateCapture: getDataFromSupplementaryData(fiToFiCstmrCdtTrf.SplmtryData, "DateCapture"),
    
    LocalTransactionDate: getDataFromSupplementaryData(fiToFiCstmrCdtTrf.SplmtryData, "LocalTransactionDate"),
    LocalTransactionTime: getDataFromSupplementaryData(fiToFiCstmrCdtTrf.SplmtryData, "LocalTransactionTime"),
    MerchantType: getDataFromSupplementaryData(fiToFiCstmrCdtTrf.SplmtryData, "MerchantType"),
    PointOfServiceConditionCode: getDataFromSupplementaryData(fiToFiCstmrCdtTrf.SplmtryData, 
        "PointOfServiceConditionCode"),
    RetrievalReferenceNumber: getDataFromSupplementaryData(fiToFiCstmrCdtTrf.SplmtryData, "RetrievalReferenceNumber"),
    ReceivingInstitutionIdentificationCode: getDataFromSupplementaryData(fiToFiCstmrCdtTrf.SplmtryData, 
        "ReceivingInstitutionIdentificationCode"),
    ResponseCode: "00",
    SettlementDate: getDataFromSupplementaryData(fiToFiCstmrCdtTrf.SplmtryData, "SettlementDate"),

    AccountIdentification1: "//businessMsgId",
    AccountIdentification2:"//businessMsgId",
    EftTlvData: fiToFiCstmrCdtTrf.CdtTrfTxInf[0].Dbtr.Nm ?: ""

};

isolated function addOptionalFields(map<string> supplementaryData, string fieldName, string? fieldValue) {
    if (fieldValue is string) {
        supplementaryData[fieldName] = fieldValue;
    }
}


isolated function getDataFromSupplementaryData(iso20022:SplmtryData[]? supplementaryData, string tag) returns string {
    if (supplementaryData != ()) {
        foreach iso20022:SplmtryData item in supplementaryData {
            if (item.Envlp.id == tag) {
                return item.Envlp.value ?: "";
            }
        }
    }
    return "";
}

isolated function mapSupplementaryData(iso8583:MTI_0200 mti0200) returns iso20022:SplmtryData[] {

    iso20022:SplmtryData[] splmtryDataArray = [];
    map<string> supplementaryData = {};
    supplementaryData["LocalTransactionTime"] = mti0200.LocalTransactionTime;
    supplementaryData["LocalTransactionDate"] = mti0200.LocalTransactionDate;
    supplementaryData["MerchantType"] = mti0200.MerchantType;
    supplementaryData["PointOfServiceConditionCode"] = mti0200.PointOfServiceConditionCode;
    supplementaryData["RetrievalReferenceNumber"] = mti0200.RetrievalReferenceNumber;
    supplementaryData["AdditionalTerminalDetails"] = mti0200.AdditionalTerminalDetails;
    addOptionalFields(supplementaryData, "SettlementDate", mti0200.SettlementDate);
    addOptionalFields(supplementaryData, "DateCapture", mti0200.DateCapture);
    addOptionalFields(supplementaryData, "PointOfServiceEntryMode", mti0200.PointOfServiceEntryMode);
    addOptionalFields(supplementaryData, "CardAccepterIdentificationCode", mti0200.CardAccepterIdentificationCode);
    addOptionalFields(supplementaryData, "CardAccepterNameLocation", mti0200.CardAccepterNameLocation);
    addOptionalFields(supplementaryData, "AccountIdentification1", mti0200.AccountIdentification1);
    addOptionalFields(supplementaryData, "MessageAuthenticationCode", mti0200.MessageAuthenticationCode);
    // process field 120
    map<string> parseField120Result = parseField120(mti0200.EftTlvData);
    foreach string tag in parseField120Result.keys() {
        supplementaryData[tag] = parseField120Result.get(tag);
    }
    // check for proxy request
    if (mti0200.ProcessingCode.startsWith("31")) {
        supplementaryData["ProxyRequest"] = "true";
    }
    // build supplementary data array
    foreach string dataElement in supplementaryData.keys() {
        iso20022:Envlp envlp = {"id": getSupplementaryDataKey(dataElement), "value": supplementaryData.get(dataElement)};
        iso20022:SplmtryData splmtryDataElement = {Envlp: envlp};
        splmtryDataArray.push(splmtryDataElement);
    }
    return splmtryDataArray;
}

isolated function parseField120(string field120) returns map<string> {

    map<string> field120Parts = {};
    int i = 0;
    while i < field120.length() {
        // i+6 < field
        string tagId = field120.substring(i, i + 3);
        int elementLength = check int:fromString(field120.substring(i + 3, i + 6));
        // i+6+elementLength < field
        string data = field120.substring(i + 6, i + 6 + elementLength);
        field120Parts[tagId] = data;
        i = i + 6 + elementLength;
    } on fail var e {
        log:printError("Error while parsing field 120: " + e.message());
    }
    return field120Parts;
}

isolated function getDataFromField120(map<string> fieldValues, string tag) returns string {

    return fieldValues[tag] ?: "";
}

final map<string> & readonly suppplementaryDataMap = {
    "002": "DestinationAccountNumbet",
    "004": "CardholderAccount",
    "005": "DestinationMemberCode",
    "006": "OriginatingMemberCode",
    "007": "DestinationCountryCode",
    "009": "DestinationAccountHoldersName",
    "010": "OriginatingAccountHoldersName",
    "011": "Particulars",
    "012": "Reference",
    "013": "TransactionCode",
    "014": "TransactionID"
};

isolated function getSupplementaryDataKey(string code) returns string? {
    if (suppplementaryDataMap.hasKey(code)) {
        return suppplementaryDataMap[code];
    }
    return code;
}

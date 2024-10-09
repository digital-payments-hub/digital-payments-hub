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

import ballerina/lang.'decimal as decimal;
import ballerina/lang.regexp;
import ballerina/log;
import ballerina/time;
import ballerinax/financial.iso20022;
import ballerinax/financial.iso8583;

import digitalpaymentshub/payments_hub.models;

final string:RegExp seperator = re `.`;

function transformMTI200ToISO20022(iso8583:MTI_0200 mti0200) returns iso20022:FIToFICstmrCdtTrf|error => {
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
                \#content: check decimal:fromString(mti0200.AmountTransaction),
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

function transformPacs002toMTI0210(iso20022:FIToFIPmtStsRpt fiToFiPmtStsRpt, iso8583:MTI_0200 originalMsg)
    returns iso8583:MTI_0210|error => {
    MTI: "0210",
    PrimaryAccountNumber: originalMsg.PrimaryAccountNumber ?: (),
    ProcessingCode: originalMsg.ProcessingCode,
    AmountTransaction: originalMsg.AmountTransaction,
    TransmissionDateTime: originalMsg.TransmissionDateTime,
    SystemTraceAuditNumber: originalMsg.SystemTraceAuditNumber,
    LocalTransactionTime: originalMsg.LocalTransactionTime,
    LocalTransactionDate: originalMsg.LocalTransactionDate,
    SettlementDate: originalMsg.SettlementDate ?: check getDate(fiToFiPmtStsRpt.GrpHdr.CreDtTm), // ME
    DateCapture: originalMsg.DateCapture ?: check getDate(fiToFiPmtStsRpt.GrpHdr.CreDtTm),
    MerchantType: originalMsg.MerchantType,
    PointOfServiceEntryMode: originalMsg.PointOfServiceEntryMode ?: (),
    PointOfServiceConditionCode: originalMsg.PointOfServiceConditionCode,
    AcquiringInstitutionIdentificationCode: originalMsg.AcquiringInstitutionIdentificationCode,
    RetrievalReferenceNumber: originalMsg.RetrievalReferenceNumber,
    AuthorizationNumber: "123456",
    ResponseCode: fiToFiPmtStsRpt.OrgnlGrpInfAndSts?.StsRsnInf?.Rsn?.Cd == "U000" ? "00" : "14",
    CardAcceptorTerminalID: originalMsg.CardAcceptorTerminalID ?: (),
    CardAcceptorIDCode: originalMsg.CardAcceptorIDCode ?: (),
    CardAcceptorNameLocation: originalMsg.CardAcceptorNameLocation ?: (),
    CurrencyCodeTransaction: originalMsg.CurrencyCodeTransaction,
    ReceivingInstitutionIdentificationCode: fiToFiPmtStsRpt.GrpHdr.SttlmInf?.SttlmAcct?.Id?.Othr?.Id ?: "9000",
    AccountIdentification1: originalMsg.AccountIdentification1 ?: fiToFiPmtStsRpt.TxInfAndSts?.InstgAgt?.FinInstnId?.Othr?.Id,
    AccountIdentification2: originalMsg.AccountIdentification2 ?: fiToFiPmtStsRpt.TxInfAndSts?.InstdAgt?.FinInstnId?.Othr?.Id,
    EftTlvData: buildDE120(originalMsg.EftTlvData, fiToFiPmtStsRpt),
    MessageAuthenticationCode: originalMsg.MessageAuthenticationCode ?: "11111111"
};

function transformToAccountLookupRequest(iso8583:MTI_0200 isomsg) returns models:AccountLookupRequest {
    map<string> field120DataElements = parseField120(isomsg.EftTlvData);
    string proxyType = getDataFromField120(field120DataElements, "011");
    string proxyValue = getDataFromField120(field120DataElements, "012");
    string bicCode = getDataFromField120(field120DataElements, "002");
    models:AccountLookupRequest accountLookupRequest = {
        proxyType: proxyType,
        proxyValue: proxyValue,
        metadata: {
            "bicCode": bicCode
        }
    };
    return accountLookupRequest;
}

function buildDE120(string? originalField, iso20022:FIToFIPmtStsRpt fiToFiPmtStsRpt) returns string {
    if (fiToFiPmtStsRpt.OrgnlGrpInfAndSts?.StsRsnInf?.Rsn?.Cd == "U000") {
        return originalField ?: "";
    }
    string accountIds = fiToFiPmtStsRpt.TxInfAndSts?.OrgnlTxRef?.CdtrAgt?.FinInstnId?.ClrSysMmbId?.MmbId ?: "";
    string accountIdsLength = accountIds.length().toString().padZero(3);
    string field017 = "017" + accountIdsLength + accountIds;
    string accountNames = fiToFiPmtStsRpt.TxInfAndSts?.OrgnlTxRef?.CdtrAgt?.FinInstnId?.Nm ?: "";
    string accountNamesLength = accountNames.length().toString().padZero(3);
    string field009 = "009" + accountNamesLength + accountNames;
    string agentIds = fiToFiPmtStsRpt.TxInfAndSts?.OrgnlTxRef?.CdtrAgt?.FinInstnId?.BICFI ?: "";
    string agentIdsLength = agentIds.length().toString().padZero(3);
    string field014 = "014" + agentIdsLength + agentIds;
    string originalFieldString = originalField ?: "";
    return originalFieldString + field017 + field009 + field014;
}

function transformMTI0800toMTI0810(iso8583:MTI_0800 mti0800) returns iso8583:MTI_0810 => {
    MTI: "810",
    TransmissionDateTime: mti0800.TransmissionDateTime,
    SystemTraceAuditNumber: mti0800.SystemTraceAuditNumber,
    SettlementDate: mti0800.SettlementDate,
    AcquiringInstitutionIdentificationCode: mti0800.AcquiringInstitutionIdentificationCode,
    AdditionalDataPrivate: mti0800.AdditionalDataPrivate,
    NetworkManagementInformationCode: mti0800.NetworkManagementInformationCode,
    NetworkManagementInformationChannelType: mti0800.NetworkManagementInformationChannelType,
    ResponseCode: "00"
};

function buildMTI0210error(iso8583:MTI_0200 mti0200, string responseCode) returns iso8583:MTI_0210 => {
    PrimaryAccountNumber: mti0200.PrimaryAccountNumber,
    ProcessingCode: mti0200.ProcessingCode,
    AmountTransaction: mti0200.AmountTransaction,
    TransmissionDateTime: mti0200.TransmissionDateTime,
    SystemTraceAuditNumber: mti0200.SystemTraceAuditNumber,
    LocalTransactionTime: mti0200.LocalTransactionTime,
    LocalTransactionDate: mti0200.LocalTransactionDate,
    MerchantType: mti0200.MerchantType,
    PointOfServiceEntryMode: mti0200.PointOfServiceEntryMode,
    PointOfServiceConditionCode: mti0200.PointOfServiceConditionCode,
    AmountTransactionFee: mti0200.AmountTransactionFee,
    AcquiringInstitutionIdentificationCode: mti0200.AcquiringInstitutionIdentificationCode,
    RetrievalReferenceNumber: mti0200.RetrievalReferenceNumber,
    CardAcceptorTerminalID: mti0200.CardAcceptorTerminalID,
    CardAcceptorIDCode: mti0200.CardAcceptorIDCode,
    CardAcceptorNameLocation: mti0200.CardAcceptorNameLocation,
    CurrencyCodeTransaction: mti0200.CurrencyCodeTransaction,
    IntegratedCircuitCardSystemRelatedData: mti0200.IntegratedCircuitCardSystemRelatedData,
    AccountIdentification1: mti0200.AccountIdentification1,
    AccountIdentification2: mti0200.AccountIdentification2,
    EftTlvData: mti0200.EftTlvData ?: "",
    MessageAuthenticationCode: mti0200.MessageAuthenticationCode,
    SettlementDate: mti0200.SettlementDate ?: "",
    DateCapture: mti0200.DateCapture ?: "",
    ReceivingInstitutionIdentificationCode: "",
    ResponseCode: responseCode
};

# Map the fields that cannot be directly mapped to ISO 20022 field to the supplementary data element.
#
# + mti0200 - ISO 8583 MTI 0200 message
# + return - ISO 20022 supplementary data array
function mapSupplementaryData(iso8583:MTI_0200 mti0200) returns iso20022:SplmtryData[] {

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
    addOptionalFields(supplementaryData, "CardAcceptorIDCode", mti0200.CardAcceptorIDCode);
    addOptionalFields(supplementaryData, "CardAcceptorNameLocation", mti0200.CardAcceptorNameLocation);
    addOptionalFields(supplementaryData, "AccountIdentification1", mti0200.AccountIdentification1);
    addOptionalFields(supplementaryData, "MessageAuthenticationCode", mti0200.MessageAuthenticationCode);
    // process field 120 and add to supplementary data
    map<string> field120DataElements = parseField120(mti0200.EftTlvData);
    foreach string tag in field120DataElements.keys() {
        supplementaryData[tag] = field120DataElements.get(tag);
    }
    // build supplementary data array
    foreach string dataElement in supplementaryData.keys() {
        iso20022:Envlp envlp = {"id": getSupplementaryDataKey(dataElement), "value": supplementaryData.get(dataElement)};
        iso20022:SplmtryData splmtryDataElement = {Envlp: envlp};
        splmtryDataArray.push(splmtryDataElement);
    }
    return splmtryDataArray;
}

# Get the value of the tag from the field 120 data elements.
#
# + tagElements - field 120 data elements
# + tag - tag to get the value
# + return - value of the tag
function getDataFromField120(map<string> tagElements, string tag) returns string {

    return tagElements[tag] ?: "";
}

# Supplementary data tag name map.
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

# Get the supplementary data key name from the tag.
#
# + code - tag id
# + return - supplementary data key name
function getSupplementaryDataKey(string code) returns string? {
    if (suppplementaryDataMap.hasKey(code)) {
        return suppplementaryDataMap[code];
    }
    return code;
}

# Add field and value to supplementary data element if the value is present.
#
# + supplementaryData - supplementary data map 
# + fieldName - iso 8583 field name
# + fieldValue - field value
function addOptionalFields(map<string> supplementaryData, string fieldName, string? fieldValue) {
    if (fieldValue is string) {
        supplementaryData[fieldName] = fieldValue;
    }
}

# Process the 120 DE of ISO 8583 and return the values as a string map.
#
# + field120 - ISO 8583 field 120
# + return - map of field 120 values
function parseField120(string? field120) returns map<string> {

    if (field120 is string) {
        map<string> field120Parts = {};
        int i = 0;
        while i < field120.length() {
            if (i + 6 > field120.length()) {
                log:printError("Error while parsing field 120: Field length is not enough to parse the next element");
                break;
            }
            string tagId = field120.substring(i, i + 3);
            int elementLength = check int:fromString(field120.substring(i + 3, i + 6));
            if (i + 6 + elementLength > field120.length()) {
                log:printError("Error while parsing field 120: Field length is not enough to parse the next element");
                break;
            }
            string data = field120.substring(i + 6, i + 6 + elementLength);
            field120Parts[tagId] = data;
            i = i + 6 + elementLength;
        } on fail var e {
            log:printError("Error while parsing field 120: " + e.message());
        }
        return field120Parts;
    }
    else {
        return {};
    }
}

# Get supplementary data value from the supplementary data array.
#
# + supplementaryData - supplementary data array
# + tag - tag to get the value
# + return - value of the tag
function getDataFromSupplementaryData(iso20022:SplmtryData[]? supplementaryData, string tag) returns string {
    if (supplementaryData != ()) {
        foreach iso20022:SplmtryData item in supplementaryData {
            if (item.Envlp.id == tag) {
                return item.Envlp.value ?: "";
            }
        }
    }
    return "";
}

# Return MMDDhhmmss format string.
#
# + utcTime - parameter description
# + return - return value description
function getDateTime(string utcTime) returns string|error {

    time:Civil civilDateTime = check getCivilDateTime(utcTime);
    return civilDateTime.month.toString().padZero(2) + civilDateTime.day.toString().padZero(2)
        + civilDateTime.hour.toString().padZero(2) + civilDateTime.minute.toString().padZero(2)
        + regexp:split(seperator, civilDateTime.second.toString())[0].padZero(2);
}

# Return hhmmss format string.
#
# + utcTime - parameter description
# + return - return value description
function getTime(string utcTime) returns string|error {

    time:Civil civilDateTime = check getCivilDateTime(utcTime);
    return civilDateTime.hour.toString().padZero(2) + civilDateTime.minute.toString().padZero(2)
        + regexp:split(seperator, civilDateTime.second.toString())[0].padZero(2);
}

# Return MMDD format string.
#
# + utcTime - parameter description
# + return - return value description
function getDate(string utcTime) returns string|error {

    time:Civil civilDateTime = check getCivilDateTime(utcTime);
    return civilDateTime.month.toString().padZero(2) + civilDateTime.day.toString().padZero(2);
}

function getCivilDateTime(string utcTime) returns time:Civil|error {
    time:Utc|time:Error utcFromString = time:utcFromString(utcTime);
    if (utcFromString is time:Utc) {
        return time:utcToCivil(utcFromString);
    } else {
        time:Civil|time:Error civilFromString = time:civilFromString(utcTime + "Z");
        if civilFromString is time:Civil {
            return civilFromString;
        }
        return error("Error while converting UTC time to Civil time", err = utcFromString);
    }
}

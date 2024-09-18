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

import ballerinax/financial.iso20022;
import ballerinax/financial.iso8583;
import ballerina/lang.regexp;
import ballerina/time;
import ballerina/http;

final string:RegExp seperator = re `.`;

public isolated function transformPacs002toMTI0210(iso20022:FIToFIPmtStsRpt fiToFiPmtStsRpt) returns iso8583:MTI_0210|error => {
    AccountIdentification1: fiToFiPmtStsRpt.TxInfAndSts?.InstgAgt?.FinInstnId?.Othr?.Id,
    MTI: "0210",
    ProcessingCode: "31xxxx",
    AmountTransaction: fiToFiPmtStsRpt.GrpHdr.TtlIntrBkSttlmAmt?.\#content.toString(),
    TransmissionDateTime: check getDateTime(fiToFiPmtStsRpt.GrpHdr.CreDtTm),
    AcquiringInstitutionIdentificationCode: fiToFiPmtStsRpt.GrpHdr.InstgAgt?.FinInstnId.toString(),
    CurrencyCodeTransaction: fiToFiPmtStsRpt.GrpHdr.TtlIntrBkSttlmAmt?.Ccy ?: "",
    DateCapture: check getDate(fiToFiPmtStsRpt.GrpHdr.CreDtTm),
    LocalTransactionTime: check getTime(fiToFiPmtStsRpt.GrpHdr.CreDtTm),
    LocalTransactionDate: check  getDate(fiToFiPmtStsRpt.GrpHdr.CreDtTm),
    EftTlvData: fiToFiPmtStsRpt.GrpHdr.SttlmInf?.SttlmMtd ?: "",
    RetrievalReferenceNumber: fiToFiPmtStsRpt.GrpHdr.SttlmInf?.SttlmAcct?.Id?.IBAN ?: "",
    MerchantType: fiToFiPmtStsRpt.GrpHdr.SttlmInf?.SttlmAcct?.Id?.Othr?.Id ?: "",
    PointOfServiceEntryMode: fiToFiPmtStsRpt.GrpHdr.SttlmInf?.SttlmAcct?.Id?.Othr?.Id,
    PointOfServiceConditionCode: fiToFiPmtStsRpt.GrpHdr.SttlmInf?.SttlmAcct?.Id?.Othr?.Id ?: "",
    ReceivingInstitutionIdentificationCode: fiToFiPmtStsRpt.GrpHdr.SttlmInf?.SttlmAcct?.Id?.Othr?.Id ?: "",
    SettlementDate: check getDate(fiToFiPmtStsRpt.GrpHdr.CreDtTm),
    ResponseCode: fiToFiPmtStsRpt.GrpHdr.SttlmInf?.SttlmAcct?.Id?.Othr?.Id ?: "",
    SystemTraceAuditNumber: fiToFiPmtStsRpt.OrgnlGrpInfAndSts?.OrgnlMsgId ?: ""
};

# Return MMDDhhmmss format string.
#
# + utcTime - parameter description
# + return - return value description
isolated function getDateTime(string utcTime) returns string|error {

    time:Civil civilDateTime = check getCivilDateTime(utcTime);
    return civilDateTime.month.toString().padZero(2) + civilDateTime.day.toString().padZero(2) 
        + civilDateTime.hour.toString().padZero(2) + civilDateTime.minute.toString().padZero(2) 
        + regexp:split(seperator, civilDateTime.second.toString())[0].padZero(2);
}

# Return hhmmss format string.
#
# + utcTime - parameter description
# + return - return value description
isolated function getTime(string utcTime) returns string|error {

    time:Civil civilDateTime = check getCivilDateTime(utcTime);
    return civilDateTime.hour.toString().padZero(2) + civilDateTime.minute.toString().padZero(2) 
        + regexp:split(seperator, civilDateTime.second.toString())[0].padZero(2);
}

# Return MMDD format string.
#
# + utcTime - parameter description
# + return - return value description
isolated function getDate(string utcTime) returns string|error {

    time:Civil civilDateTime = check getCivilDateTime(utcTime);
    return civilDateTime.month.toString().padZero(2) + civilDateTime.day.toString().padZero(2);
}

isolated function getCivilDateTime(string utcTime) returns time:Civil|error {
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

public isolated function getDestinationCountry(string countryCode) returns string|error {
    match countryCode {
        "9001" => { return "MY"; }
        _ => { return error("Error while resolving destination country. Unknown country code : " + countryCode); }
    } 
};

public service class ResponseErrorInterceptor {
    *http:ResponseErrorInterceptor;

    // The error occurred in the request-response path can be accessed by the 
    // mandatory argument: `error`. The remote function can return a response,
    // which will overwrite the existing error response.
    remote isolated function interceptResponseError(error err) returns http:BadRequest {
        // In this case, all the errors are sent as `400 BadRequest` responses with a customized
        // media type and body. Moreover, you can send different status code responses according to
        // the error type.        
        return {
            mediaType: "application/org+json",
            body: {message: err.message()}
        };
    }
}
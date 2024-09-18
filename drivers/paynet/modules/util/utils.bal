import digital.payments.hub.paynet.models;

import ballerina/http;
import ballerina/lang.regexp;
import ballerina/log;
import ballerina/mime;
import ballerina/random;
import ballerina/time;
import ballerinax/financial.iso20022;

# Call paynet proxy resolution service to resolve the proxy.
#
# + iso20022Msg - iso 20022 message
# + return - proxy lookup response or error
public isolated function getPaynetProxyResolution(iso20022:FIToFICstmrCdtTrf iso20022Msg)
    returns models:PrxyLookUpRspnCBFT|error {

    http:Client paynetClient = check new (PROXY_RESOLUTION_ENDPOINT);

    string bicCode = iso20022Msg.CdtTrfTxInf[0].DbtrAcct?.Id?.Othr?.Id ?: "";
    iso20022:SplmtryData[]? supplementaryData = iso20022Msg.SplmtryData;
    // if (supplementaryData != ()) {
    //     foreach iso20022:SplmtryData item in supplementaryData {
    //         // todo how to resolve this name conflict??
    //         if item.Envlp.id == "Particulars" {
    //             proxyType = item.Envlp.value ?: "";
    //             continue;
    //         }
    //         if item.Envlp.id == "Reference" {
    //             proxy = item.Envlp.value ?: "";
    //             continue;
    //         }
    //     }
    // }
    string proxyType = resolveProxyType(supplementaryData);
    string proxy = resolveProxy(supplementaryData);

    if (bicCode == "" || proxyType == "" || proxy == "") {
        return error("Error while resolving proxy. Required data not found");
    }

    string xBusinessMsgId = check generateXBusinessMsgId(bicCode);
    models:PrxyLookUpRspnCBFT response = check paynetClient->/[proxyType]/[proxy]({
        Accept: mime:APPLICATION_JSON,
        Authorization: "Bearer 123",
        "X-Business-Message-Id": xBusinessMsgId,
        "X-Client-Id": "123456",
        "X-Gps-Coordinates": "3.1234, 101.1234",
        "X-Ip-Address": "1"
    });
    log:printDebug("Response received from Paynet: " + response.toBalString());
    return response;
}

# Call paynet proxy registration service.
#
# + iso20022Msg - iso 20022 message
# + return - proxy lookup response or error
public isolated function postPaynetProxyRegistration(iso20022:FIToFICstmrCdtTrf iso20022Msg)
    returns models:fundTransferResponse|error {

    http:Client paynetClient = check new (PROXY_REGISTRATION_ENDPOINT);
    models:fundTransfer|error proxyRegistrationPayload = buildProxyRegistrationPayload(iso20022Msg);
    if proxyRegistrationPayload is models:fundTransfer {
        string bicCode = iso20022Msg.CdtTrfTxInf[0].DbtrAcct?.Id?.Othr?.Id ?: "";
        string xBusinessMsgId = check generateXBusinessMsgId(bicCode);
        // models:fundTransferResponse response = check paynetClient->/register.post({
        //     Accept: mime:APPLICATION_JSON,
        //     Authorization: "Bearer 123",
        //     "X-Business-Message-Id": xBusinessMsgId,
        //     "X-Client-Id": "123456",
        //     "X-Gps-Coordinates": "3.1234, 101.1234",
        //     "X-Ip-Address": "1"
        // });
        map<string> headers = {
            Accept: mime:APPLICATION_JSON,
            Authorization: "Bearer 123",
            "X-Business-Message-Id": xBusinessMsgId,
            "X-Client-Id": "123456",
            "X-Gps-Coordinates": "3.1234, 101.1234",
            "X-Ip-Address": "1"
        };
        models:fundTransferResponse response = check paynetClient->post("/register", proxyRegistrationPayload, headers);
        log:printDebug("Response received from Paynet: " + response.toBalString());
        return response;
    } else {
        log:printError("Error while building proxy registration payload: "
                + proxyRegistrationPayload.message());
        return error("Error while building proxy registration payload: "
            + proxyRegistrationPayload.message());
    }
};

isolated function generateXBusinessMsgId(string bicCode) returns string|error {

    time:Utc utcTime = time:utcNow();
    time:Civil date = time:utcToCivil(utcTime);
    string currentDate = date.year.toString() + date.month.toString().padZero(2) + date.day.toString().padZero(2);
    string originator = "O";
    string channelCode = "RB";
    int randomNumber = check random:createIntInRange(1, 99999999);
    string sequenceNumber = randomNumber.toString().padZero(8);
    return currentDate + bicCode + PROXY_RESOLUTION_ENQUIRY_TRANSACTION_CODE + originator
        + channelCode + sequenceNumber;
};

public isolated function isProxyRequest(iso20022:SplmtryData[]? supplementaryData) returns boolean {

    if (supplementaryData == ()) {
        log:printDebug("Supplementary data not found. Request will be treated as a fund transfer request");
    } else {
        return supplementaryData.some(item => item.Envlp.id == "ProxyRequest");
    }
    return false;
};

isolated function resolveProxyType(iso20022:SplmtryData[]? supplementaryData) returns string {

    if (supplementaryData != ()) {
        foreach iso20022:SplmtryData item in supplementaryData {
            // todo how to resolve this name conflict??
            if item.Envlp.id == "Particulars" {
                return item.Envlp.value ?: "";
            }
        }
    }
    return "";
};

isolated function resolveProxy(iso20022:SplmtryData[]? supplementaryData) returns string {

    if (supplementaryData != ()) {
        foreach iso20022:SplmtryData item in supplementaryData {
            // todo how to resolve this name conflict??
            if item.Envlp.id == "Reference" {
                return item.Envlp.value ?: "";
            }
        }
    }
    return "";
};

public isolated function transformPrxy004toPacs002(models:PrxyLookUpRspnCBFT prxyLookUpRspnCbft) returns iso20022:FIToFIPmtStsRpt => {
    GrpHdr: {
        MsgId: prxyLookUpRspnCbft.GrpHdr.MsgId,
        CreDtTm: prxyLookUpRspnCbft.GrpHdr.CreDtTm,
        NbOfTxs: 1,
        OrgnlBizQry: {
            MsgId: "",
            MsgNmId: prxyLookUpRspnCbft.OrgnlGrpInf.OrgnlMsgNmId,
            CreDtTm: prxyLookUpRspnCbft.OrgnlGrpInf.OrgnlCreDtTm ?: ""
        }
    },
    TxInfAndSts: {
        InstgAgt: {
            FinInstnId: {
                BICFI: prxyLookUpRspnCbft.GrpHdr.MsgSndr.Agt.FinInstnId.Othr.Id
            }
        },
        OrgnlTxRef: {
            PrvsInstgAgt1Acct: {
                Prxy: {
                    Tp: {
                        Cd: prxyLookUpRspnCbft.LkUpRspn.RegnRspn.Prxy?.Tp,
                        Prtry: prxyLookUpRspnCbft.LkUpRspn.RegnRspn.Prxy?.Val
                    },
                    Id: prxyLookUpRspnCbft.LkUpRspn.RegnRspn.Prxy?.Val ?: ""
                }
            },
            CdtrAgt: {
                FinInstnId: {
                    ClrSysMmbId: {MmbId: prxyLookUpRspnCbft.LkUpRspn.RegnRspn.Regn?.Acct?.Id?.Othr?.Id ?: ""},
                    BICFI: prxyLookUpRspnCbft.LkUpRspn.RegnRspn.Regn?.Agt?.FinInstnId?.Othr?.Id,
                    Nm: prxyLookUpRspnCbft.LkUpRspn.RegnRspn.Regn?.Acct?.Nm
                }
            },
            Cdtr: {},
            ChrgBr: "",
            Dbtr: {},
            DbtrAgt: {FinInstnId: {}},
            IntrBkSttlmAmt: {\#content: 0, Ccy: ""},
            PmtId: {EndToEndId: ""}

        }
    },
    OrgnlGrpInfAndSts: {
        OrgnlMsgId: prxyLookUpRspnCbft.OrgnlGrpInf.OrgnlMsgId,
        OrgnlMsgNmId: prxyLookUpRspnCbft.OrgnlGrpInf.OrgnlMsgNmId,
        OrgnlCreDtTm: prxyLookUpRspnCbft.OrgnlGrpInf.OrgnlCreDtTm,
        OrgnlNbOfTxs: "1",
        StsRsnInf: {
            Rsn: {
                Cd: prxyLookUpRspnCbft.LkUpRspn.RegnRspn.StsRsnInf?.Cd,
                Prtry: prxyLookUpRspnCbft.LkUpRspn.RegnRspn.StsRsnInf?.Prtry
            }
        }
    }

};

public isolated function transformFTResponsetoPacs002(models:fundTransferResponse fundTransferResponse, 
    iso20022:FIToFICstmrCdtTrf isoPacs008Msg) returns iso20022:FIToFIPmtStsRpt => {
    GrpHdr: {
        MsgId: fundTransferResponse.data.businessMessageId,
        CreDtTm: fundTransferResponse.data.createdDateTime,
        NbOfTxs: 1,
        OrgnlBizQry: {
            MsgId: isoPacs008Msg.GrpHdr.MsgId,
            MsgNmId: isoPacs008Msg.GrpHdr.MsgId,
            CreDtTm: isoPacs008Msg.GrpHdr.CreDtTm
        }
    },
    TxInfAndSts: {
        InstgAgt: {
            FinInstnId: {
                BICFI: isoPacs008Msg.CdtTrfTxInf[0].DbtrAgt.FinInstnId.Othr?.Id
            }
        }
    },
    OrgnlGrpInfAndSts: {
        OrgnlMsgId: isoPacs008Msg.CdtTrfTxInf[0].PmtId.EndToEndId,
        OrgnlMsgNmId: isoPacs008Msg.GrpHdr.MsgId,
        OrgnlCreDtTm: isoPacs008Msg.GrpHdr.CreDtTm,
        OrgnlNbOfTxs: "1",
        StsRsnInf: {
            Rsn: {
                Cd: fundTransferResponse.data.code,
                Prtry: fundTransferResponse.data.reason
            }
        }
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

public isolated function buildProxyRegistrationPayload(iso20022:FIToFICstmrCdtTrf iso20022Payload)
    returns models:fundTransfer|error => {

    data: {
        businessMessageId: check generateXBusinessMsgId(iso20022Payload.CdtTrfTxInf[0].DbtrAcct?.Id?.Othr?.Id ?: ""),
        createdDateTime: check getCurrentDateTime(),
        proxy: {
            tp: resolveProxyType(iso20022Payload.SplmtryData),
            value: resolveProxy(iso20022Payload.SplmtryData)
        },
        account: {
            id: iso20022Payload.CdtTrfTxInf[0].DbtrAcct?.Id?.Othr?.Id ?: "",
            name: iso20022Payload.CdtTrfTxInf[0].DbtrAcct?.Nm ?: "",
            tp: "CACC",
            accountHolderType: "S"
        },
        secondaryId: {
            tp: "NRIC",
            value: "94771234567"
        }
    }
};

# Return yyyy-MM-ddTHH:mm:ss.SSS format string.
#
# + return - return value description
isolated function getCurrentDateTime() returns string|error {

    time:Utc utcTime = time:utcNow();
    final string:RegExp seperator = re `.`;
    time:Civil civilDateTime = time:utcToCivil(utcTime);
    return civilDateTime.year.toString() + "-" + civilDateTime.month.toString().padZero(2) + "-"
        + civilDateTime.day.toString().padZero(2) + "T"
        + civilDateTime.hour.toString().padZero(2) + ":" + civilDateTime.minute.toString().padZero(2) + ":"
        + regexp:split(seperator, civilDateTime.second.toString())[0].padZero(2) + "."
        + regexp:split(seperator, civilDateTime.second.toString())[1].padZero(3);

}

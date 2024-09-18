import ballerina/http;
import ballerina/time;
import digital.payments.hub.paynet.models;
import ballerina/data.jsondata;

service /v1/picasso\-guard/banks/nad/v2 on new http:Listener(8086) {

    # Inbound endpoint of LanakPay ISO 8583 messages.
    #
    # + caller - http caller
    # + req - http request
    # + return - return value description
    isolated resource function get resolution/[string proxyType]/[string proxy](http:Caller caller, http:Request req) 
        returns error? {

        string xBusinessMsgId = check req.getHeader("X-Business-Message-Id");
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
                    PrxRspnSts: "ACTC",
                    StsRsnInf: {
                        Cd: "U000",
                        Prtry: ""
                    },
                    Prxy: {
                        Tp: proxyType, 
                        Val: proxy
                    },
                    Regn: {
                        RegnId: "0075800025", 
                        DsplNm: "Bank Account", 
                        Agt: {
                            FinInstnId: {
                                Othr: {
                                    Id: "****MYKL"
                                }
                            }
                        }, 
                        Acct: {
                            Id: {
                                Othr: {
                                    Id: "********0105"
                                }
                            },
                            Nm: "Bank Account"
                        }, 
                        PreAuthrsd: ""
                    }
                }
            }, 
            OrgnlGrpInf: {
                OrgnlMsgId: xBusinessMsgId, 
                OrgnlMsgNmId: ""
                }
            };
        check caller->respond(response);
    }

    isolated resource function post register(http:Caller caller, http:Request req) returns error? {
        
        json payload = check req.getJsonPayload();
        models:fundTransfer fundTransferPayload = check jsondata:parseAsType(payload);
        string xBusinessMsgId = check req.getHeader("X-Business-Message-Id");
        models:fundTransferResponse response = {
            data: {
                businessMessageId: xBusinessMsgId, 
                createdDateTime: fundTransferPayload.data.createdDateTime,
                code: "ACTC", 
                reason: "U000", 
                registrationId: "0075800039"
            }
        };
        check caller->respond(response);
    }
}


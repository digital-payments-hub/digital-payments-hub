import digital.payments.hub.paynet.models;
import digital.payments.hub.paynet.util;

import ballerina/constraint;
import ballerina/http;
import ballerina/log;
import ballerinax/financial.iso20022;

service http:InterceptableService / on new http:Listener(9091) {
    isolated resource function post outbound_payload(http:Caller caller, http:Request req) returns error? {

        // Extract the json payload from the request
        json payload = check req.getJsonPayload();
        iso20022:FIToFICstmrCdtTrf|error iso20022ValidatedMsg = constraint:validate(payload);

        http:Response|error response;
        if (iso20022ValidatedMsg is iso20022:FIToFICstmrCdtTrf) {
            iso20022:FIToFICstmrCdtTrf isoPacs008Msg = check iso20022ValidatedMsg.cloneWithType(iso20022:FIToFICstmrCdtTrf);
            // Differentiate proxy resolution and fund transfer request

            if (util:isProxyRequest(isoPacs008Msg.SplmtryData)) {
                // proxy resolution request to PayNet
                models:PrxyLookUpRspnCBFT|error paynetProxyResolution = util:getPaynetProxyResolution(isoPacs008Msg);
                if (paynetProxyResolution is error) {
                    log:printError("Error while resolving proxy: " + paynetProxyResolution.message());
                    return error("Error while resolving proxy: " + paynetProxyResolution.message());
                }
                // transform to iso 20022 response pacs 002.001.14
                iso20022:FIToFIPmtStsRpt iso20022Response = util:transformPrxy004toPacs002(paynetProxyResolution);
                // add original msg id
                iso20022Response.GrpHdr.MsgId = isoPacs008Msg.GrpHdr.MsgId;
                // log:printInfo(iso20022Response.toBalString());
                http:Response httpResponse = new;
                httpResponse.setPayload(iso20022Response.toJsonString());
                response = httpResponse;
            } else {
                // fund transfer request -- todo
                // map paynet register proxy payload

                models:fundTransferResponse|error paynetProxyRegistartionResponse = 
                    util:postPaynetProxyRegistration(isoPacs008Msg);
                if (paynetProxyRegistartionResponse is error) {
                    log:printError("Error while registering proxy: " + paynetProxyRegistartionResponse.message());
                    return error("Error while registering proxy: " + paynetProxyRegistartionResponse.message());
                }
                // transform to iso 20022 response pacs 002.001.14
                iso20022:FIToFIPmtStsRpt iso20022Response = 
                    util:transformFTResponsetoPacs002(paynetProxyRegistartionResponse, isoPacs008Msg);

                http:Response httpResponse = new;
                httpResponse.setPayload(iso20022Response.toJsonString());
                response = httpResponse;
            }
        } else {
            log:printError("Request type not supported");
            return error("Request type not supported");
        }
        // return response;
        check caller->respond(response);
    }

    public function createInterceptors() returns http:Interceptor|http:Interceptor[] {
        return new util:ResponseErrorInterceptor();
    }
}

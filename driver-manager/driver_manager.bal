import ballerina/http;

public isolated function switchToOutboundDriver(anydata iso20022Msg, string destination) returns error|http:Response {

    if (destination == "paynet") {
        
        http:Client paynetDriverClient = check new ("http://localhost:9091");
        http:Response paynetDriverResponse = check paynetDriverClient->/request.post(iso20022Msg);
        
        return paynetDriverResponse;
    }
    return error("Destination driver not found");
}

final http:Client lanakpayclient = check new ("http://localhost:9090");
final http:Client paynetclient = check new ("http://localhost:9091");


service / on new http:Listener(8085) {

    # Inbound endpoint of LanakPay ISO 8583 messages.
    #
    # + caller - http caller
    # + req - http reques
    # + return - return value description
    isolated resource function post lankapay(http:Caller caller, http:Request req) returns error? {

        string|http:ClientError iso8583msg = req.getTextPayload();
        if (iso8583msg is http:ClientError) {
            return iso8583msg;
        }
        //call lankapay
        http:Response|http:ClientError lankapayDriverInboundResponse = lanakpayclient->/request.post(iso8583msg);
        if (lankapayDriverInboundResponse is http:ClientError || isError(lankapayDriverInboundResponse)) {
            check caller -> respond(lankapayDriverInboundResponse);
        } else {
            json payload = check lankapayDriverInboundResponse.getJsonPayload();
            // call destination country driver outbound
            http:Response|http:ClientError paynetDriverInboundResponse = paynetclient->/outbound.post(payload);

            if paynetDriverInboundResponse is http:ClientError || isError(paynetDriverInboundResponse) {
                check caller->respond(paynetDriverInboundResponse);
            } else {
                // call lankapay response
                json paynetResponse = check paynetDriverInboundResponse.getJsonPayload();
                http:Response|http:ClientError lankaPayOutboundRes = lanakpayclient->/response.post(paynetResponse);
                check caller->respond(lankaPayOutboundRes);
            }
        }
    };
}

public isolated function isError(http:Response response) returns boolean{
    return response.statusCode >= 400;
}
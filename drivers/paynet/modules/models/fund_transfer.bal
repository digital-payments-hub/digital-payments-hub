public type fundTransfer record {|
    Data data;
|};

public type Data record {|
    string businessMessageId;
    string createdDateTime;
    Proxy proxy;
    Account account;
    SecondaryId secondaryId;
|};

public type Proxy record {|
    string tp;
    string value;
|}; 

public type Account record {|
    string tp;
    string id;
    string name;
    string accountHolderType;
|};

public type SecondaryId record {|
    string tp;
    string value;
|};

public type fundTransferResponse record {|
    ResposneData data;
|};

public type ResposneData record {|
    string businessMessageId;
    string createdDateTime;
    string code;
    string reason;
    string registrationId;
|};


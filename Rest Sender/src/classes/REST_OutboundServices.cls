public class REST_OutboundServices{

    //for authorization
    private String username;
    private String password;

    //for after authorization
    private String sessionId;
    private String instanceURL;

    public REST_OutboundServices(){
        List<String> usernamePassword = getCredentialsFromUser();
        if(usernamePassword[0]==null||usernamePassword[1]==null){//user does not have paramteres set, use custom setting
            usernamePassword = getCredentialsFromCustomSetting();
        }
        userName = usernamePassword[1];
        password = usernamePassword[0];
        
    }


    private  List<String> getCredentialsFromUser(){
        User u = [Select Other_Org_Password__c, Other_Org_UserName__c from User where ID = :userInfo.getUserId()];
        return new List<String>{u.Other_Org_Password__c, u.Other_Org_UserName__c};
    }

    private  List<String> getCredentialsFromCustomSetting(){
        Other_Org_Credentials__c creds = Other_Org_Credentials__c.getOrgDefaults();
        return new List<String>{creds.Other_Org_Password__c, creds.Other_Org_Username__c};
    }

    private void authorize(String username, String password){
        //returns List<String>{instance url, sessionid}
        
        HttpRequest request = new HttpRequest();
        request.setTimeout(10000);
        request.setEndpoint('https://login.salesforce.com/services/Soap/u/22.0');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'text/xml;charset=UTF-8');
        request.setHeader('SOAPAction', '""');
        request.setBody(
                '<Envelope xmlns="http://schemas.xmlsoap.org/soap/envelope/">'+
                    '<Header/>'+
                    '<Body>'+
                        '<login xmlns="urn:partner.soap.sforce.com">'+
                            '<username>' +
                                username +
                            '</username>'+
                            '<password>' +
                                password +
                            '</password>'+
                        '</login>'+
                    '</Body>'+
                '</Envelope>');
        HttpResponse res = new Http().send(request);
        
        if(res.getStatusCode()!=200){
            system.debug('Bad request: ' + res.getStatus());
        }
        else{
            Dom.XmlNode resultXML = (res.getBodyDocument().getRootElement()
              .getChildElement('Body','http://schemas.xmlsoap.org/soap/envelope/')
              .getChildElement('loginResponse','urn:partner.soap.sforce.com')
              .getChildElement('result','urn:partner.soap.sforce.com'));
            instanceURL = resultXML.getChildElement('serverUrl','urn:partner.soap.sforce.com').getText().split('/services')[0];
            sessionId = resultXML.getChildElement('sessionId','urn:partner.soap.sforce.com').getText();
        }
    }

    private HTTPResponse sendRequest(String method, String methodType, String body){
        HttpRequest req = new HttpRequest();
        req.setTimeout(100000);
        HttpResponse res = new HttpResponse();
        String restUrl = ('/services/apexrest/InboundServices?'+method);
        if(sessionId==null){//no session yet
            authorize(username, password);
        }
        req.setHeader('Content-Type','application/json');
        req.setHeader('Authorization', 'OAuth ' + sessionId);
        req.setEndpoint(instanceURL + restUrl);
        req.setMethod(methodType);
        if(body!=null){
            req.setBody(body);
        }
        res = new Http().send(req);
        if(res.getStatusCode()==440){//session timed out
            authorize(username, password);
            res = new Http().send(req);
        }
        return res;

    }

    public String ping(){
        return sendRequest('ping','GET',null).getBody();
    }


    public void upsertLeads(List<Lead> leadList){
        HTTPResponse res = sendRequest('upsertLeads','POST', JSON.serialize(cleanLeadList(leadList))); 
        syncLeadReturn((List<String>)JSON.deserialize(res.getBody(), List<String>.class));
    }

    public String updateLeadStatus(String externalId, String status){
      String body = '{"externalId":"'+externalId+'","status":'+status+'}';
      system.debug(body);
      HttpResponse res = sendRequest('updateLead','PUT', body);
      return res.getBody();
    }

    public String updateLead(Lead l){
      String body = '{"l":'+JSON.serialize(l)+'}';
      HttpResponse res = sendRequest('updateLead','PUT', body);
      return res.getBody();
    }

    @future (callout=true)
    public static void syncLeads(String leadJSON){
        REST_OutboundServices ros = new REST_OutboundServices();
        ros.upsertLeads((List<Lead>)JSON.deserialize(leadJSON, List<Lead>.class));
    }

    private List<Lead> cleanLeadList(List<Lead> toClean){
        List<Lead> returnList = new List<Lead>();
        for(Lead l : toClean){
            returnList.add(clone(l));
        }
        return returnList;//leads with the id moved to the external field
    }

    private Lead clone(Lead l){
        return new Lead(
            //here you decide which fields you want to keep synced.
            //the OOB "clone" method doesn't work well for cross-org syncing.
            //it includes fields like "isconverted" and "ownerId" which will fail 
            //because they are not writeable
            LastName = l.LastName,
            FirstName = l.FirstName,
            Email = l.Email,
            External_Id__c = l.Id,
            Phone = l.Phone,
            Company = l.Company,
            Status = l.Status
        );
    }

    private void syncLeadReturn(List<String> idMap){
        List<Lead> toSync = new List<Lead>();
        for(String s : idMap){
            List<String> ids = s.split(':');
            toSync.add(new Lead(Id = ids[0], External_Id__c = ids[1]));
        }
        update toSync;
    }
}
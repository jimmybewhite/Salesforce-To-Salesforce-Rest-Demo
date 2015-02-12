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
      String body = '{"externalId":"'+externalId+'","status":"'+status+'"}';
      system.debug(body);
      HttpResponse res = sendRequest('updateLeadStatus','PUT', body);
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
        return returnList;//leads with the id moved to the external field and nonwriteable fields removed
    }

    private Lead clone(Lead l){
        //if you use the "Clone" method, below is a way to remove the unwriteable fields from the object before sending it over
        String jsonStr = JSON.serialize(l);
        Map<String, object> testObj = (Map<String, object>)JSON.deserializeUntyped(jsonStr);
        testObj.remove('OwnerId');//not writeable
        testObj.remove('IsConverted');//not writeable
        testObj.put('External_Id__c', testObj.get('Id'));
        testObj.remove('Id');//
        Lead returnLead = (Lead)(JSON.deserialize(JSON.serialize(testObj),Lead.class));

        return returnLead;
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
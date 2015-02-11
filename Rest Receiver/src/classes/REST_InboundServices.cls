@RestResource(urlMapping='/InboundServices/*')
global with sharing class REST_InboundServices{

	@HttpGet
	global static String ping(){
		// ...salesforce.com/services/apexrest/InboundServices?ping
		return 'Connection Successful';
	}

	@HttpPost
	global static List<String> upsertLeads(){
		List<String> returnMap = new List<String>();
		String leadJSON = RestContext.request.requestBody.toString();
		List<Lead> leadsToUpsert = (List<Lead>)JSON.deserialize(leadJSON, List<Lead>.class);
		List<Database.upsertResult> results = database.upsert(leadsToUpsert, Lead.External_Id__c);
		for(integer i = 0; i< results.size(); i++){
			returnMap.add(leadsToUpsert[i].External_Id__c+':'+results[i].getId());
		}
		return returnMap;
	}

	//@HttpPut
	//global static String updateLeadStatus(String externalId, String Status){
	//	system.debug('Update lead start');
	//	Lead l = new Lead(External_Id__c = externalId, Status = status);
	//	upsert l External_Id__c;
	//	return 'Successful';
	//}

	@HttpPut
	global static String updateLead(Lead l){
		system.debug('Update lead start');
		upsert l External_Id__c;
		return 'Successful';
	}

}
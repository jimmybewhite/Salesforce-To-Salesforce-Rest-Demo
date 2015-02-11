trigger LeadSyncTrigger on Lead (after insert, after update) {
	//do not write a trigger like this! This is just an example.
	if(!(system.isFuture())){//stop recursion
		REST_OutboundServices.syncLeads(JSON.serialize(trigger.new));
	}
}
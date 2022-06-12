global with sharing class CLExpirationFlow implements Database.batchable<sobject>,Schedulable {
    global final string query;
    global CLExpirationFlow(string q){  
        query=q;
    }
    global CLExpirationFlow(){  
        
        query='Select id,opportunity__c,CL_Issuance_Date__c,UW_Started_PL_Date_time__c,Opp_Close_Date__c,Opportunity__r.StageName,Opportunity__r.Closer__c,Opportunity__r.Name,Loan_Officer__r.Email,Loan_Officer__r.Name,Underwriter__r.Email,Opportunity__r.Previous_Opportunity_stage__c,opportunity__r.Financing_type__c,Underwriter__r.Name,Loan_amount__c,Loan_Officer__c,Underwriter__c from Loan_Comparisons__c where CL_Issuance_Date__c !=null and Opportunity__r.Financing_type__c=\'APC Core\' and opportunity__r.Probability>= 80 and opportunity__r.Probability< 100 and status__c!=\'Expired\' and Opportunity__r.StageName !=\'Submitted for Commitment\' and Recordtype.name= \'Commitment Letter Request\'';
    }
    global Database.QueryLocator start(Database.BatchableContext BC){
        return Database.getQueryLocator(query);
    }
    global void execute(SchedulableContext SC) {
        database.executebatch(new CLExpirationFlow());
    }
    global  void execute(Database.BatchableContext BC,List<Loan_Comparisons__c> scope){                        
        system.debug('scope-----'+scope);
        String[] ccAddress = new String[]{};
        String[] toAddress = new String[]{};
        List<Loan_Comparisons__c> updateCommmitmentLst = new List<Loan_Comparisons__c>();
        List<Opportunity> updateOppLst = new List<Opportunity>();
        Map<Id,Loan_Comparisons__c> mapOppIdtoCommmitment = new Map<Id,Loan_Comparisons__c>();
        Map<String,EmailTemplate> mapTemplateNameToTemplate = new Map<String,EmailTemplate>();      
        List<EmailTemplate> emailTemplateList = [select Id, Subject, Name,HtmlValue, Body from EmailTemplate where name In ('Commitment Letter Set to Expire','Commitment Letter has Expired')];
        for(EmailTemplate template : emailTemplateList){
            mapTemplateNameToTemplate.put(template.Name,template);
        }
        if(scope.size() > 0){
            for(Loan_Comparisons__c commitment : scope){
                Integer noOfDays = date.valueOf(commitment.CL_Issuance_Date__c).daysBetween(date.today());
                system.debug('noOfDays----'+noOfDays);
                Date CLIssuanceDateFilter = date.newInstance(2021,12,06);
                DateTime CLIssuanceDate = commitment.CL_Issuance_Date__c;
                String CLIssuanceDatePST = CLIssuanceDate.format('yyyy-MM-dd HH:mm:ss', 'PST'); 
                if(noOfDays == 105){
                    notificationForCLExpiration(15,commitment,mapTemplateNameToTemplate);
                }
                if(noOfDays == 60){                   
                    string days;
                    if(date.valueOf(CLIssuanceDatePST) < CLIssuanceDateFilter){
                        days = '30';
                    }else{
                        days = '60';
                    }
                    notificationForCLExpiration(noOfDays,commitment,mapTemplateNameToTemplate);                           
                }else if((date.valueOf(CLIssuanceDatePST) < CLIssuanceDateFilter && noOfDays == 90) || 
                (date.valueOf(CLIssuanceDatePST) >= CLIssuanceDateFilter && noOfDays == 120)){                    
                    mapOppIdtoCommmitment.put(commitment.Opportunity__c,commitment);                    
                    ccAddress.add('underwriting@applepiecapital.com');
                    ccAddress.add('operations@applepiecapital.com');
                    ccAddress.add('megan@applepiecapital.com');
                    toAddress.add(commitment.Loan_Officer__r.Email);
                    if(commitment.Underwriter__c !=null){
                        toAddress.add(commitment.Underwriter__r.Email);                    
                    }
                    commitment.Status__c ='Expired';
                    updateCommmitmentLst.add(commitment);                   
                    EmailTemplate emailTemplate = mapTemplateNameToTemplate.get('Commitment Letter has Expired');
                    String plainBody = emailTemplate.Body;
                    String subject = emailTemplate.Subject;
                    if(!string.isBlank(subject)){                        
                        subject = subject.replace('{!Loan_comparisons__c.Opportunity__c}', commitment.Opportunity__r.Name);                                                
                    }
                    if(!string.isBlank(plainBody)){
                        plainBody = plainBody.replace('{!noOfDays}', string.valueOf(noOfDays));                        
                        plainBody = plainBody.replace('{!Loan_comparisons__c.Opportunity__c}', commitment.Opportunity__r.Name);
                        plainBody = plainBody.replace('{!Loan_comparisons__c.Opp_Close_Date__c}', string.valueOf(commitment.Opp_Close_Date__c));
                        plainBody = plainBody.replace('{!Loan_comparisons__c.Loan_amount__c}', string.valueOf(commitment.Loan_amount__c));                        
                        
                        if(commitment.Loan_Officer__c!=null){
                            plainBody = plainBody.replace('{!Loan_comparisons__c.Loan_Officer__c}', commitment.Loan_Officer__r.Name);
                        }else{
                            plainBody = plainBody.replace('{!Loan_comparisons__c.Loan_Officer__c}', '');
                        }                        
                        if(commitment.Underwriter__c!=null){
                            plainBody = plainBody.replace('{!Loan_comparisons__c.Underwriter__c}', commitment.Underwriter__r.Name);
                        }else{
                            plainBody = plainBody.replace('{!Loan_comparisons__c.Underwriter__c}', '');
                        }
                        plainBody = plainBody.replace('{!Loan_comparisons__c.CL_Issuance_Date__c}', string.valueOf(commitment.CL_Issuance_Date__c));
                        plainBody = plainBody.replace('{!Opportunity__c.Link}', URL.getSalesforceBaseUrl().toExternalForm()+'/'+commitment.Opportunity__c);
                        plainBody = plainBody.replace('{!Opportunity.Previous_Opportunity_stage__c}', commitment.Opportunity__r.StageName);
                                                                              
                    }
                    system.debug('plainBody----'+plainBody );
                    EmailNotification.customEmailAlert(emailTemplate.Id, subject, plainBody, toAddress,ccAddress, '', false, System.Label.OrgWideAddressId, '');        
                }
            }
            List<Opportunity> oppList = [Select stageName,Commitment_Submitted__c from opportunity where Id in: mapOppIdtoCommmitment.keySet()];
            for(Opportunity opp : oppList){
                opp.StageName ='Collecting Additional Items';
                opp.Commitment_Submitted__c = false;
                opp.Submitted_for_Commitment__c = null;
                updateOppLst.add(opp);
            }
            if(updateCommmitmentLst.size()>0){
                Database.SaveResult[] srList = Database.update(updateCommmitmentLst, false);
                for (Database.SaveResult sr : srList) {
                    if (!sr.isSuccess()) {
                        // Operation failed, so get all errors                
                        for(Database.Error err : sr.getErrors()) {
                            handleCustomException.LogException(err,sr.getId(),'Credit Submission','CLExpirationFlow','execute');                            
                        }
                    }
                }
            }
            if(updateOppLst.size()>0){
                Database.SaveResult[] srList = Database.update(updateOppLst, false);
                for(Integer i=0;i<srList.size();i++){
                    if (srList.get(i).isSuccess()){
                        srList.get(i).getId();

                    }else if (!srList.get(i).isSuccess()){
                        // DML operation failed
                        Database.Error error = srList.get(i).getErrors().get(0);
                        String failedDML = error.getMessage();
                        //updateOppLst.get(i);//failed record from the list
                        handleCustomException.LogException(error,updateOppLst.get(i).Id,'Opportunity','CLExpirationFlow','execute');                            
                        //system.debug('Failed ID'+arudate.get(i).Id);
                     }

                }
                /*for (Database.SaveResult sr : srList) {
                    if (!sr.isSuccess()) {
                        // Operation failed, so get all errors                
                        for(Database.Error err : sr.getErrors()) {
                            handleCustomException.LogException(err,sr.getId(),'Opportunity','CLExpirationFlow','execute');                            
                        }
                    }
                }*/
            }
            
        }   
    }
    public void notificationForCLExpiration(Integer noOfDays, Loan_Comparisons__c commitment,Map<String,EmailTemplate> mapTemplateNameToTemplate){
        String[] ccAddress = new String[]{};
        String[] toAddress = new String[]{};
        ccAddress.add('megan@applepiecapital.com');
        toAddress.add(commitment.Loan_Officer__r.Email);
        Map<String,Closer__mdt> mapLabelToCloser = new Map<String,Closer__mdt>();
        if(noOfDays == 15){           
            if(commitment.Underwriter__c!=null){
                toAddress.add(commitment.Underwriter__r.Email);
            }
            if(!string.isBlank(commitment.Opportunity__r.Closer__c)){
                List<Closer__mdt> closerDetails = [Select MasterLabel,Email__c from Closer__mdt];
                for(Closer__mdt closerDetail : closerDetails){
                    mapLabelToCloser.put(closerDetail.MasterLabel,closerDetail);
                }
                toAddress.add(mapLabelToCloser.get(commitment.Opportunity__r.Closer__c).Email__c);
            }            
        }
        EmailTemplate emailTemplate = mapTemplateNameToTemplate.get('Commitment Letter Set to Expire');
        String plainBody = emailTemplate.Body;
        String subject = emailTemplate.Subject;
        if(!string.isBlank(subject)){                        
            subject = subject.replace('{!Loan_comparisons__c.Opportunity__c}', commitment.Opportunity__r.Name);                        
            subject = subject.replace('{!days}', string.valueOf(noOfDays));                                               
        }
        system.debug('subject----'+subject);
        if(!string.isBlank(plainBody)){                        
            plainBody = plainBody.replace('{!Loan_comparisons__c.Opportunity__c}', commitment.Opportunity__r.Name);
            plainBody = plainBody.replace('{!Loan_comparisons__c.Loan_amount__c}', string.valueOf(commitment.Loan_amount__c));
            plainBody = plainBody.replace('{!days}', string.valueOf(noOfDays));                        
            if(commitment.Loan_Officer__c!=null){
                plainBody = plainBody.replace('{!Loan_comparisons__c.Loan_Officer__c}', commitment.Loan_Officer__r.Name);
            }else{
                plainBody = plainBody.replace('{!Loan_comparisons__c.Loan_Officer__c}', '');
            }                        
            if(commitment.Underwriter__c!=null){
                plainBody = plainBody.replace('{!Loan_comparisons__c.Underwriter__c}', commitment.Underwriter__r.Name);
            }else{
                plainBody = plainBody.replace('{!Loan_comparisons__c.Underwriter__c}', '');
            }
            plainBody = plainBody.replace('{!Opportunity.CloseDate}', string.valueOf(commitment.Opp_Close_Date__c));
            plainBody = plainBody.replace('{!Loan_comparisons__c.CL_Issuance_Date__c}', string.valueOf(commitment.CL_Issuance_Date__c));
            plainBody = plainBody.replace('{!Loan_comparisons__c.Link}', URL.getSalesforceBaseUrl().toExternalForm()+'/'+commitment.Id);                       
                                                                  
        }
        EmailNotification.customEmailAlert(emailTemplate.Id, subject, plainBody, toAddress,ccAddress, '', false, System.Label.OrgWideAddressId, ''); 
    }
    global void finish(Database.BatchableContext BC){
    }
}
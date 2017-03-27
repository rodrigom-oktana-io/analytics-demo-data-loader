public with sharing class WaveDataManagerController {
	
	public String Host {get;set;}
	public String RemoteSiteName { get { return 'WaveDataManager_mdapi'; } }
	public String MetadataResponse {get;set;}
	public Boolean MetadataConnectionWarning {get;set;}
	public String MetadataApiException {get;set;}

	public String selectedWaveApp { get; set; }
	public String errorMessage { get; set; }
	public String successMessage  { get; set; }
	public String warningMessage  { get; set; }
	public Id batchProcessId { get; set; }
	public Boolean monitorJobExecution { get; set; }
	public Boolean showJobStatistics { get; set; }
	public Integer batchesProcessed { get; set; }
	public Integer totalBatches { get; set; }
	public String jobStatusDsc { get; set; }
	public List<String> processingLog { get; set; }
	public Integer currentNodeIndex { get; set; }
	public String currentObjectProcessing { get; set; }
	public List<WaveApplicationObject> objectsNodes { get; set; }
	public List<Edgemart> edgemarts { get; set; }
	public boolean disabledButton { get; set; }
	private WaveMetadata metadata;
	private Map<String, String> appDescriptions; // <appName, appDesc>
	private Map<String, Integer> appIndexes; // <appName, appIndex in this.metadata.waveApplications>
	public String folderName { get; set; }
	public String dataflowName { get; set; }
	public String dataflowLabel { get; set; }
	public String emailAddress { get; set; }
	public List<WaveApplicationRow> applicationRows;
	public WaveMetadataApplication selectedAppMetadata { get; set; }
	public String dataflowDefinitionJson { get; set; }

	public WaveDataManagerController() {
		this.objectsNodes = new List<WaveApplicationObject>();
		this.processingLog = new List<String>();
		this.appDescriptions = new Map<String, String>();
		this.appIndexes = new Map<String, Integer>();
		this.emailAddress = UserInfo.getUserEmail();
		this.MetadataResponse = '';
	}

	public PageReference pageLoad()
	{
		// Get Host Domain
		Host = ApexPages.currentPage().getHeaders().get('Host');
				
		// Attempt to connect to the Metadata API
		MetadataConnectionWarning = false;
		if(!Test.isRunningTest() && !SF_MetadataUtils.checkMetadataAPIConnection())
		{
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Warning, 'Unable to connect to the Salesforce Metadata API.'));
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Warning, 'A Remote Site Setting must be created in your org before you can use this tool.'));
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Warning, 'Press the Create Remote Site Setting button to perform this step or refer to the post install step below to perform this manually.'));
			MetadataConnectionWarning = true;
			MetadataApiException = '';
			/*if(RollupService.LastMetadataAPIConnectionException!=null)
				MetadataApiException = RollupService.LastMetadataAPIConnectionException.getMessage();*/
		}

		if(applicationRows == null){
			applicationRows = WaveConfiguratorUtils.getWaveApplications('https://raw.githubusercontent.com/rodrigom-oktana-io/wave-tooling/master/WaveApplications.csv');			
			if(this.applicationRows != null){
				Integer index = 0;
	        	for(WaveApplicationRow genericApp: this.applicationRows) {
					this.appIndexes.put(genericApp.Name, index);
					this.appDescriptions.put(genericApp.Name, genericApp.Description);
					index++;
				}
	        }
		}

		return null;
	}

	public List<SelectOption> getWaveApps() {
        
        List<SelectOption> options = new List<SelectOption>();

        if(this.applicationRows != null){
        	for(WaveApplicationRow genericApp: this.applicationRows) {
				options.add(new SelectOption(genericApp.Name, genericApp.Label));
			}
        }

        return options;
    }

    public PageReference waveAppSelected(){

    	this.folderName = this.selectedWaveApp;
    	return null;
    }

    public String getAppDescription(){
    	
    	String dsc = 'No description available.';

    	if(!String.isBlank(this.selectedWaveApp) && this.appDescriptions.containsKey(this.selectedWaveApp)){
    		dsc =  this.appDescriptions.get(this.selectedWaveApp);
    	}
    	
    	return dsc;
    }

	public void resetMessages(){
		this.errorMessage = '';
		this.successMessage = '';
		this.warningMessage = '';
		this.jobStatusDsc = '';
		this.processingLog.clear();
	}

	public void installApp(){
		
		this.resetMessages();

		// Start with validations
		Boolean passedValidation = true;

		if(String.isBlank(folderName)){
			passedValidation = false;
			this.errorMessage = 'A folder/app must be specified.';
		}

		if(String.isBlank(this.dataflowName)){
			passedValidation = false;
			this.errorMessage = 'A dataflow name must be specified.';
		}

		if(String.isBlank(this.dataflowLabel)){
			passedValidation = false;
			this.errorMessage = 'A dataflow label must be specified.';
		}

		if(WaveConfiguratorUtils.folderExists(this.folderName)){
			passedValidation = false;
			this.errorMessage = 'The folder ' + this.folderName + ' already exists.';
		}

		if(WaveConfiguratorUtils.dataflowExistsByName(this.dataflowName)){
			passedValidation = false;
			this.errorMessage = 'The dataflow ' + this.dataflowName + ' already exists.';
		}

		if(!String.isBlank(this.emailAddress)){
			if(WaveConfiguratorUtils.isInvalidEmail(this.emailAddress)){
				passedValidation = false;
				this.errorMessage = 'The email address ' + this.emailAddress + ' is invalid.';
			}
		}		

		if(passedValidation){
			try {
				Integer appIndex = this.appIndexes.get(this.selectedWaveApp);
				WaveApplicationRow appRow = this.applicationRows.get(appIndex);
				// Retrieve and parse metadata
				HttpRequest req = new HttpRequest();
				req.setEndpoint(appRow.MetadataUrl);
		        req.setMethod('GET');
				Http http = new Http();
		        HTTPResponse res = http.send(req);

				String jsonMetadata = res.getBody();
				this.selectedAppMetadata = (WaveMetadataApplication)JSON.deserialize(jsonMetadata, WaveMetadataApplication.class);

				if(this.selectedAppMetadata != null && this.selectedAppMetadata.objects != null){
					
					// Edgemarts
					this.edgemarts = this.selectedAppMetadata.edgemarts;		
					
					// Dataflow Definition JSON file
					req = new HttpRequest();
					req.setEndpoint(this.selectedAppMetadata.dataflowLocation);
		        	req.setMethod('GET');
					http = new Http();
		        	HTTPResponse resDf = http.send(req);

		        	if(WaveConfiguratorUtils.checkStatus(resDf)){
						String dfDefJsonBody = resDf.getBody();
						if(String.isBlank(dfDefJsonBody)){
							throw new WaveConfiguratorException('Invalid Dataflow Definition JSON for Wave Application. Check URL: ' + selectedAppMetadata.dataflowLocation);
						}
						
						this.dataflowDefinitionJson = dfDefJsonBody;						
					}
					else {
						System.debug(resDf);

						throw new WaveConfiguratorException('Unable to retrieve Dataflow Definition JSON file for Wave Application.');							
					}

					// Create app/folder
					this.processingLog.add('Creating ' + this.folderName + ' folder/application...');
					String resFolderCreate = WaveConfiguratorUtils.insertFolder(appRow.Label, this.folderName);
					
					//If empty, no errors
					if(!String.isEmpty(resFolderCreate)) {
						this.processingLog.add(resFolderCreate);

						throw new WaveConfiguratorException('There was an error in the attempting to create the ' + this.folderName + ' folder. See log for details.');
					}

					this.processingLog.add(this.folderName + ' folder/application created successfully.');

					String folderId = WaveConfiguratorUtils.getFolderId(this.folderName);

					// Create dataflow
					// Create dataflow version
					// Link dataflow to dataflow version current id
					this.processingLog.add('Creating ' + this.dataflowName + ' dataflow...');
					
					String dataflowResponse = WaveConfiguratorUtils.createDataflow(this.dataflowName, this.dataflowLabel, folderId);

					if(dataflowResponse.contains('Error')){
						this.processingLog.add(dataflowResponse);
						throw new WaveConfiguratorException('Dataflow for ' + this.dataflowLabel + ' could not be created. Check debug logs.');
					}

					String dataflowId = dataflowResponse;					
					String versionId = WaveConfiguratorUtils.createDataflowVersion(dataflowId, this.dataflowDefinitionJson.replaceAll('<folderId>', folderId));
					WaveConfiguratorUtils.linkDataflowToVersion(dataflowId, versionId);

					this.processingLog.add('Dataflow created successfully.');
					// We leave this commented for now: UNABLE TO CREATE DASHBOARD BEFORE RUNNING DATAFLOW
					/*
					if(this.selectedAppMetadata.dashboards != null && this.selectedAppMetadata.dashboards.size() > 0){
						this.processingLog.add('Encountered ' + this.selectedAppMetadata.dashboards.size() + ' dashboards for the application.');
						
						for(String dashJsonUrl : this.selectedAppMetadata.dashboards){
							this.loadDashboard(dashJsonUrl, folderId);
						}

						this.processingLog.add('All dashboards were successfully created.');
					}
					else {
						this.processingLog.add('The application doesn\'t contain any dashboard.');
					}*/

					// Retrieve objects to process
					for(WaveMetadataApplicationObject wmaObj: this.selectedAppMetadata.objects) {
						List<WaveApplicationObject> objs = this.getObjectsToProcess(wmaObj);
						this.objectsNodes.addAll(objs);
					}

					// Check if there are objects data to load					
					if(this.objectsNodes.size() > 0){						

						// Create objects metadata if needed
						SF_MetadataUtils mdUtils = new SF_MetadataUtils();

						// Objects and fields Setup
						for(WaveApplicationObject waObj: this.objectsNodes) {
							
							this.processingLog.add('Processing ' + waObj.name + ' object metadata...');

							// Check object existence using waObj.name property					
							if(!mdUtils.objectExists(waObj.name)){
								// If object doesn't exist, create it
								this.processingLog.add(waObj.name + ' doesn\'t exists. Attempting to create it...');
								List<String> errors = mdUtils.createObject(waObj.name);
								if(errors.size() == 0){
									this.processingLog.add(waObj.name + ' object created successfully.');
								}
								else {
									this.processingLog.addAll(errors);
								}						
							}

							// Check fields existence using waObj.fields property
							for(WaveApplicationObjectField field: waObj.fields) {
								// If field doesn't exist, create it using field properties
								if(field.Name.endsWithIgnoreCase('__c') && !mdUtils.fieldExists(waObj.name, field.Name)){
									this.processingLog.add(waObj.name + '.' + field.Name + ' field doesn\'t exists. Attempting to create it...');
									SF_MetadataUtils.CustomFieldSpecification fieldSpec = new SF_MetadataUtils.CustomFieldSpecification();
									fieldSpec.ObjectName = waObj.name;
									fieldSpec.Name = field.Name;
							    	fieldSpec.Label = field.Label;
							    	fieldSpec.Type = field.Type;
									fieldSpec.ReferenceTo = field.ReferenceTo;
									fieldSpec.Length = field.Length;
									fieldSpec.Precision = field.Precision;
									fieldSpec.Scale = field.Scale;
									fieldSpec.IsExternalId = field.IsExternalId;
									fieldSpec.IsRequired = field.IsRequired;

									List<String> errors = mdUtils.createField(fieldSpec);
									if(errors.size() == 0){
										this.processingLog.add(waObj.name + '.' + field.Name + ' field created successfully.');
									}
									else {
										this.processingLog.add(waObj.name + '.' + field.Name + ' field couldn\'t be created. Reasons: ');
										this.processingLog.addAll(errors);
									}
								}
							}
						}

						// Print some message at the UI to inform that setup has succeeded
						this.processingLog.add('All needed metadata was created successfully.');						
					}					

					if(this.objectsNodes.size() > 0){
						// We start loading data for each object
						this.processingLog.add('This process can take up to 30 minutes. We will refresh status every 5 seconds.');
						this.currentNodeIndex = 0;
						this.disabledButton = true;

						// This launchs all the process of loading data to salesforce objects
						this.processCurrentObjectLoadNode();	
					}
					else {
						this.processingLog.add('There are no objects to load.');
						this.processingLog.add('Done.');
						this.successMessage = 'Application installed successfully.';
					}					
				}
			}
			catch(Exception e) {
				System.debug(e.getMessage());
				System.debug(e.getStackTraceString());
				this.errorMessage = e.getMessage();

				this.rollbackProcess();
			}
		}
	}

	public List<WaveApplicationObject> getObjectsToProcess(WaveMetadataApplicationObject wmaObj){
		List<WaveApplicationObject> listToProcess = new List<WaveApplicationObject>();
		WaveApplicationObject rootObj = new WaveApplicationObject();
		rootObj.name = wmaObj.name;
		rootObj.url = wmaObj.url;
		rootObj.additionalDataFiles = wmaObj.additionalDataFiles;
		listToProcess.add(rootObj);

		// We process the fields metadata
		IMockarooHelper iMockHelper = MockarooHelperFactory.getIMockarooHelper();
    	List<List<String>> csvMetadata = iMockHelper.getData(wmaObj.metadataUrl, false);
    	
    	if(csvMetadata.size() > 0){
			// Will extract headers
			List<String> headers = csvMetadata.remove(0);
			Map<String, Integer> fieldPositions = new Map<String, Integer>();
			
			for(Integer i = 0; i < headers.size(); i++) {
				fieldPositions.put(headers.get(i), i);
			}

			// For each row of data in the CSV
			rootObj.fields = new List<WaveApplicationObjectField>();

			for(List<String> metadataRow: csvMetadata) {
				WaveApplicationObjectField fieldMetadata = new WaveApplicationObjectField();
				fieldMetadata.Label = metadataRow.get(fieldPositions.get('Label'));
				fieldMetadata.Name = metadataRow.get(fieldPositions.get('Name'));
				fieldMetadata.Type = metadataRow.get(fieldPositions.get('Type'));
				fieldMetadata.ReferenceTo = metadataRow.get(fieldPositions.get('ReferenceTo'));
				fieldMetadata.Length = Integer.valueOf(metadataRow.get(fieldPositions.get('Length')));
				fieldMetadata.Precision = Integer.valueOf(metadataRow.get(fieldPositions.get('Precision')));
				fieldMetadata.Scale = Integer.valueOf(metadataRow.get(fieldPositions.get('Scale')));
				fieldMetadata.IsExternalId = Boolean.valueOf(metadataRow.get(fieldPositions.get('IsExternalId')));
				fieldMetadata.IsRequired = Boolean.valueOf(metadataRow.get(fieldPositions.get('IsRequired')));

				rootObj.fields.add(fieldMetadata);
			}
		}

		// We process the relations
		rootObj.relations = new List<WaveApplicationObjectRelation>();
		if(wmaObj.relations != null){			
			for(WaveMetadataApplicationObjectRelation relObj: wmaObj.relations) {
				WaveApplicationObjectRelation rel = new WaveApplicationObjectRelation();
				rel.csvColumnName = relObj.csvColumnName;
				rel.targetSObject = relObj.targetSObject;
				rel.targetSObjectLookupField = relObj.targetSObjectLookupField;
				rel.foreignKeyField = relObj.foreignKeyField;

				rootObj.relations.add(rel);
			}
		}

		// Replicate for each adittional data CSV file

		// We process the children
		if(wmaObj.children != null) {
			// Now the children objects
			for(WaveMetadataApplicationObject chObj: wmaObj.children) {
				List<WaveApplicationObject> childrenObjs = getObjectsToProcess(chObj);
				listToProcess.addAll(childrenObjs);
			}
		}

		return listToProcess;
	}

	private void processCurrentObjectLoadNode(){
		
		WaveApplicationObject currentNode = this.objectsNodes.get(this.currentNodeIndex);
		IMockarooHelper iMockHelper = MockarooHelperFactory.getIMockarooHelper();
		List<List<String>> csvData;
		
		// Check whether we are in the initial chunk of CSV data or not
		if(currentNode.currentDataIndex == 0){
			
			// We start processing the initial chunk of data
			csvData = iMockHelper.getData(currentNode.url, false);

    		if(csvData.size() > 0){
				// Will extract headers
				List<String> headers = csvData.remove(0);
				currentNode.fieldPositions = new Map<Integer, String>();
				
				for(Integer i = 0; i < headers.size(); i++) {
					currentNode.fieldPositions.put(i, headers[i]);
				}
			}

			currentObjectProcessing = currentNode.name;
		}
		else {
			String newUrl = currentNode.url.substringBeforeLast('.csv') + currentNode.currentDataIndex + '.csv';
			csvData = iMockHelper.getData(newUrl, false);
		}

		this.processingLog.add('Loading ' + csvData.size() + ' records for ' + currentNode.name + ' object...');

		// Start the batch process
		CsvDataImportBatch batchProcess = new CsvDataImportBatch(Schema.getGlobalDescribe().get(currentNode.name), csvData, currentNode.fieldPositions, currentNode.relations);
		this.batchProcessId = Database.executeBatch(batchProcess);

		// Now monitor job execution
		this.monitorJobExecution = true;
		AsyncApexJob asyncJob = [SELECT CompletedDate, JobItemsProcessed, NumberOfErrors, Status, TotalJobItems FROM AsyncApexJob WHERE Id = :this.batchProcessId];			
		this.totalBatches = asyncJob.TotalJobItems;
		this.batchesProcessed = asyncJob.JobItemsProcessed;
		this.showJobStatistics = true;
	}

	public PageReference checkObjectLoadingStatus(){
		
		if(!String.isBlank(this.batchProcessId)){

			WaveApplicationObject currentNode = this.objectsNodes.get(this.currentNodeIndex);
			List<AsyncApexJob> lstJobs = [SELECT CompletedDate, JobItemsProcessed, NumberOfErrors, Status, TotalJobItems FROM AsyncApexJob WHERE Id = :this.batchProcessId];
			
			if(lstJobs.size() > 0){

				AsyncApexJob asyncJob = lstJobs.get(0);

				if(asyncJob.Status == 'Completed'){
					if(asyncJob.NumberOfErrors > 0) {
						this.errorMessage = 'The process was interrupted due to errors while loading data for the ' + this.objectsNodes.get(this.currentNodeIndex).name + ' object. See logs for details.';
						this.currentNodeIndex = 0;
						currentNode.currentDataIndex = 0;
						this.objectsNodes.clear();
						this.jobStatusDsc = '';
						this.disabledButton = false;
					}
					else {
						// Completed entire job, inspect if there are more data files 
						// within the current node
						if(currentNode.currentDataIndex < currentNode.additionalDataFiles){
							currentNode.currentDataIndex = currentNode.currentDataIndex + 1;
							this.processCurrentObjectLoadNode();
						}
						else{
							// Entire node finished, reset currentNode.currentDataIndex
							currentNode.currentDataIndex = 0;
							
							// now check whether it was the last one
							if(this.currentNodeIndex == this.objectsNodes.size() - 1){
								
								try {
									// Now load the edgemarts
									loadAllEdgemarts();
									WaveConfiguratorUtils.sendEmail(this.emailAddress, this.dataflowLabel);
									this.processingLog.add('Done.');
									this.successMessage = 'Application installed successfully.';
								} 

								catch(Exception e) {
									this.errorMessage = e.getMessage();
									System.debug(e.getMessage());
									System.debug(e.getStackTraceString());
									
									// Rollback
									this.rollbackProcess();
								}
								finally {
									this.jobStatusDsc = '';
									this.objectsNodes.clear();
									this.currentNodeIndex = 0;
									this.disabledButton = false;
								}
							}
							else {
								// There are more nodes to process, increment index and reset
								// currentNode.currentDataIndex
								this.currentNodeIndex = this.currentNodeIndex + 1;
								this.processCurrentObjectLoadNode();
							}
						}
					}		
				}
				else if(asyncJob.Status == 'Aborted'){
					this.errorMessage = 'The process was aborted while loading data for the ' + this.objectsNodes.get(this.currentNodeIndex).name + ' object.';
					this.currentNodeIndex = 0;
					this.disabledButton = false;
					this.objectsNodes.clear();
					this.jobStatusDsc = '';
				}
				else if(asyncJob.Status == 'Failed'){
					this.errorMessage = 'The process failed while loading data for the ' + this.objectsNodes.get(this.currentNodeIndex).name + ' object.';
					this.currentNodeIndex = 0;
					this.disabledButton = false;
					this.objectsNodes.clear();
					this.jobStatusDsc = '';
				}
			}
		}		

		return null;
	}

		
	private void loadAllEdgemarts(){
		if(this.edgemarts != null){
			String folderId = WaveConfiguratorUtils.getFolderId(this.folderName);
			for(Edgemart edg : this.edgemarts){
				this.loadEdgemart(edg, folderId);
			}
		}
	}

	private void loadEdgemart(Edgemart e, String folderId){

		this.processingLog.add('Loading edgmart data for: ' + e.Label);

		WaveConfiguratorUtils.loadEdgemart(e, folderId);

        this.processingLog.add('Edgmart data loaded successfully.');
	}

	public PageReference displayMetadataResponse()
	{
		// Display the response from the client side Metadata API callout
		if(this.MetadataResponse.length()==0)
		{
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'Remote Site Setting ' + RemoteSiteName + ' has been created. Now you can continue with Wave Apps instalation.' ));
			MetadataConnectionWarning = false;
		}
		else
		{
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, this.MetadataResponse));
			MetadataConnectionWarning = true;
		}
		return null;
	}

	private void loadDashboard(String dashJsonUrl, String folderId){
		HttpRequest req = new HttpRequest();
		req.setEndpoint(dashJsonUrl);
        req.setMethod('GET');
		Http http = new Http();
        HTTPResponse res = http.send(req);

		WaveConfiguratorUtils.insertWaveDashboard(res.getBody(), folderId);
	}

	private void rollbackProcess(){
		// Delete recently created app/folder here
		String folderId = WaveConfiguratorUtils.getFolderId(this.folderName);
		WaveConfiguratorUtils.deleteFolder(folderId, UserInfo.getSessionId());

		// Delete recently created dataflow
		String dataflowId = WaveConfiguratorUtils.getDataflowIdByName(this.dataflowName);
		WaveConfiguratorUtils.deleteDataflow(dataflowId, UserInfo.getSessionId());
	}
}
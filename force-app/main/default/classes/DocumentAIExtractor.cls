public with sharing class DocumentAIExtractor {

    /**
     * @param configName             Document AI config API name or Id
     * @param contentVersionId       Used as the fileId; if blank, the latest version of contentDocumentId is used
     * @param contentDocumentId      Fallback when contentVersionId is blank
     * @param includeConfidenceScore Adds the confidence score to each extracted field
     */
    @AuraEnabled
    public static Result extract(
        String configName,
        Id contentVersionId,
        Id contentDocumentId,
        Boolean includeConfidenceScore
    ) {
        Result res = new Result();
        try {
            Id fileId = contentVersionId != null ? contentVersionId : latestVersionId(contentDocumentId);
            res.extractedDataJson = extractData(configName, fileId, includeConfidenceScore == true);
            res.success = true;
        } catch (Exception e) {
            res.errorMessage = e.getMessage();
        }
        return res;
    }

    /**
     * Calls extract-data with just the saved config and the file Id.
     * The schema and model come from the saved Document AI configuration.
     *
     * @return the extracted data as a JSON string
     */
    public static String extractData(String configName, Id contentVersionId, Boolean includeConfidenceScore) {
        if (String.isBlank(configName)) {
            throw new DocumentAIException('Document AI config name is required.');
        }
        if (contentVersionId == null) {
            throw new DocumentAIException('Content Version Id is required.');
        }

        Document_AI_Callout_Config__mdt cfg = getCalloutConfig();
        String endpoint = 'callout:' + cfg.Named_Cred_API_Name__c + '/' + cfg.API_Version__c + '/' + cfg.Extract_Data_Endpoint_Path__c;
        if (includeConfidenceScore == true) {
            endpoint += '?extractDataWithConfidenceScore=true';
        }

        Map<String, Object> payload = new Map<String, Object>{
            'idpConfigurationIdOrName' => configName,
            'files' => new List<Object>{
                new Map<String, Object>{ 'fileId' => contentVersionId }
            }
        };

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(endpoint);
        httpReq.setMethod('POST');
        httpReq.setHeader('Content-Type', 'application/json');
        httpReq.setHeader('Accept', 'application/json');
        httpReq.setTimeout(cfg.Timeout_in_Millisecond__c.intValue());
        httpReq.setBody(JSON.serialize(payload));

        HttpResponse httpRes = new Http().send(httpReq);

        // Document AI can return 201 on success, so accept the whole 2xx range
        Integer status = httpRes.getStatusCode();
        if (status < 200 || status >= 300) {
            throw new DocumentAIException('Document AI extract-data failed (HTTP ' + status + '): ' + httpRes.getBody());
        }
        return parseResponse(httpRes.getBody());
    }

    public class DocumentAIException extends Exception {}

    public class Result {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String  extractedDataJson;
        @AuraEnabled public String  errorMessage;
    }

    /** Returns the active Document_AI_Callout_Config__mdt record (named credential, API version, endpoint path, timeout). */
    @TestVisible
    private static Document_AI_Callout_Config__mdt getCalloutConfig() {
        for (Document_AI_Callout_Config__mdt cfg : Document_AI_Callout_Config__mdt.getAll().values()) {
            if (cfg.Active__c) {
                return cfg;
            }
        }
        throw new DocumentAIException('No active Document AI Callout Config record found.');
    }

    /**
     * Response shape: { "data": [ { "data": "<stringified, HTML-escaped JSON>" } ] }
     * Returns the inner extracted JSON, decoded.
     */
    @TestVisible
    private static String parseResponse(String responseBody) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> dataList = (List<Object>) parsed.get('data');
        if (dataList == null || dataList.isEmpty()) {
            throw new DocumentAIException('No data returned by Document AI.');
        }

        Object nested = ((Map<String, Object>) dataList[0]).get('data');
        if (nested instanceof String) {
            return ((String) nested).unescapeHtml4();
        }
        return JSON.serialize(nested);
    }

    private static Id latestVersionId(Id contentDocumentId) {
        if (contentDocumentId == null) {
            throw new DocumentAIException('Provide either Content Version Id or Content Document Id.');
        }
        List<ContentVersion> versions = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw new DocumentAIException('No file found for Content Document Id ' + contentDocumentId);
        }
        return versions[0].Id;
    }
}

import { LightningElement, api } from 'lwc';
import extract from '@salesforce/apex/DocumentAIExtractor.extract';

const ACCEPTED_FORMATS = ['.pdf', '.png', '.jpg', '.jpeg'];

export default class DocumentAiExtractor extends LightningElement {
    @api configName;
    @api includeConfidenceScore = false;

    acceptedFormats = ACCEPTED_FORMATS;

    contentVersionId;
    fileName;
    isLoading = false;
    errorMessage;
    rawJson;
    fieldRows = [];
    tables = [];

    get isExtractDisabled() {
        return !this.contentVersionId || this.isLoading;
    }

    get hasResult() {
        return Boolean(this.rawJson);
    }

    get fieldColumns() {
        const columns = [
            { label: 'Field', fieldName: 'name' },
            { label: 'Value', fieldName: 'value', wrapText: true }
        ];
        if (this.includeConfidenceScore) {
            columns.push({
                label: 'Confidence',
                fieldName: 'confidence',
                type: 'percent',
                typeAttributes: { maximumFractionDigits: 0 },
                initialWidth: 120
            });
        }
        return columns;
    }

    handleUploadFinished(event) {
        const file = event.detail.files[0];
        this.contentVersionId = file.contentVersionId;
        this.fileName = file.name;
        this.clearResult();
    }

    async handleExtract() {
        this.clearResult();
        this.isLoading = true;
        try {
            const result = await extract({
                configName: this.configName,
                contentVersionId: this.contentVersionId,
                contentDocumentId: null,
                includeConfidenceScore: this.includeConfidenceScore === true
            });
            if (result.success) {
                this.showResult(result.extractedDataJson);
            } else {
                this.errorMessage = result.errorMessage;
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unexpected error.';
        } finally {
            this.isLoading = false;
        }
    }

    clearResult() {
        this.errorMessage = undefined;
        this.rawJson = undefined;
        this.fieldRows = [];
        this.tables = [];
    }

    showResult(json) {
        let parsed;
        try {
            parsed = JSON.parse(json);
        } catch (e) {
            this.errorMessage = 'Could not read the extracted data.';
            this.rawJson = json;
            return;
        }
        this.rawJson = JSON.stringify(parsed, null, 2);

        const fieldRows = [];
        const tables = [];
        Object.entries(parsed).forEach(([name, node]) => {
            const { value, confidence } = unwrap(node);
            if (Array.isArray(value) && value.length && value.every(isPlainObject)) {
                tables.push(buildTable(name, value));
            } else {
                fieldRows.push({ name, value: toDisplay(value), confidence });
            }
        });
        this.fieldRows = fieldRows;
        this.tables = tables;
    }
}

// Every field is either a plain value, or { type, value, confidence_score } when confidence is on.
function unwrap(node) {
    if (isPlainObject(node) && 'value' in node) {
        const confidence = node.confidence_score ?? node.confidenceScore ?? node.confidence;
        return { value: node.value, confidence: confidence == null ? undefined : Number(confidence) };
    }
    return { value: node, confidence: undefined };
}

function isPlainObject(v) {
    return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function toDisplay(value) {
    if (value === null || value === undefined) {
        return '';
    }
    if (Array.isArray(value)) {
        return value.map(toDisplay).join('; ');
    }
    if (isPlainObject(value)) {
        if ('value' in value) {
            return toDisplay(value.value);
        }
        return Object.entries(value)
            .map(([k, v]) => `${k}: ${toDisplay(v)}`)
            .join(', ');
    }
    return String(value);
}

function buildTable(name, rows) {
    const keys = [];
    rows.forEach((row) =>
        Object.keys(row).forEach((k) => {
            if (!keys.includes(k)) {
                keys.push(k);
            }
        })
    );
    return {
        name,
        columns: keys.map((k) => ({ label: k, fieldName: k, wrapText: true })),
        rows: rows.map((row, i) => {
            const flat = { rowId: String(i) };
            keys.forEach((k) => {
                flat[k] = toDisplay(row[k]);
            });
            return flat;
        })
    };
}

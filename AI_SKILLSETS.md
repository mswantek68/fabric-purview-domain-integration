# OneLake AI Skillsets Integration

This document describes the AI skillsets enhancement that adds cognitive document processing capabilities to OneLake indexers.

## Overview

The AI skillsets integration adds intelligent document processing to your OneLake indexing pipeline, automatically extracting:

- **Language Detection**: Identifies the primary language of documents
- **Entity Recognition**: Extracts people, locations, and organizations
- **Key Phrase Extraction**: Identifies important phrases and topics
- **Sentiment Analysis**: Determines document sentiment (positive/negative/neutral)

## Architecture

```
OneLake Documents → AI Search Indexers → AI Skillsets → Enhanced Search Index
     ↓                     ↓                ↓                    ↓
[PDF, DOCX, TXT]    [Text Extraction]   [AI Processing]   [Searchable Fields]
```

## Automation Scripts

### Core Scripts

1. **`add_onelake_skillsets.ps1`**
   - Creates text-only AI skillset for reliable OneLake processing
   - Attaches skillsets to existing OneLake indexers
   - Updates index schemas with new AI fields
   - Safe to run multiple times (idempotent)

2. **`test_onelake_indexers.ps1`**
   - Validates OneLake indexer configuration
   - Checks skillset attachment and AI field mappings
   - Optionally runs indexers for testing
   - Provides comprehensive status report

3. **`postprovision_onelake_indexing.ps1`**
   - Updated to include AI skillsets in deployment automation
   - Runs after infrastructure provisioning
   - Ensures complete end-to-end automation

### Advanced Scripts (Optional)

4. **`create_ai_skillsets.ps1`**
   - Comprehensive skillset creation with multiple options
   - Supports OCR, entities, key phrases, sentiment, language detection
   - Modular design for custom skillset combinations

5. **`attach_skillsets_to_indexers.ps1`**
   - Attaches existing skillsets to indexers
   - Updates index schemas and field mappings
   - Test mode support for validation

## Current Status

✅ **Working Configuration**:
- 2 OneLake indexers with AI skillsets attached
- Text-only skillset (no OCR complexity)
- 6 AI fields per indexer: language, people, locations, organizations, keyphrases, sentiment
- Automatic hourly processing schedule

✅ **Skillsets Created**:
- `onelake-textonly-skillset`: Reliable text processing without image dependencies
- `onelake-comprehensive-skillset`: Full skillset including OCR (requires configuration)

✅ **Active Indexers**:
- `files-documents-presentations-indexer`: Processing presentation files
- `files-documents-reports-indexer`: Processing report documents

## Usage

### Quick Setup

```powershell
# Add AI skillsets to existing OneLake indexers
./scripts/add_onelake_skillsets.ps1 -AISearchName "your-ai-search-name"

# Test the configuration
./scripts/test_onelake_indexers.ps1 -AISearchName "your-ai-search-name"

# Run indexers immediately for testing
./scripts/test_onelake_indexers.ps1 -AISearchName "your-ai-search-name" -RunIndexers
```

### Automated Deployment

The AI skillsets are automatically included in the deployment pipeline via `postprovision_onelake_indexing.ps1`:

```yaml
# azure.yaml
postprovision:
  - shell: pwsh scripts/postprovision_onelake_indexing.ps1
```

## Search Fields

After AI processing, documents will have these additional searchable fields:

| Field | Type | Description | Example Values |
|-------|------|-------------|----------------|
| `language` | String | Detected language code | "en", "es", "fr" |
| `people` | Collection(String) | Person names found | ["John Smith", "Jane Doe"] |
| `locations` | Collection(String) | Place names found | ["New York", "London"] |
| `organizations` | Collection(String) | Company/org names | ["Microsoft", "Contoso"] |
| `keyphrases` | Collection(String) | Important phrases | ["artificial intelligence", "cloud computing"] |
| `sentiment` | String | Document sentiment | "positive", "negative", "neutral" |

## Example Search Queries

### REST API Queries

```http
# Search for documents mentioning specific people
GET https://your-search.search.windows.net/indexes/files-documents-reports/docs?search=*&$filter=people/any(p: p eq 'John Smith')

# Find positive sentiment documents about AI
GET https://your-search.search.windows.net/indexes/files-documents-reports/docs?search=artificial intelligence&$filter=sentiment eq 'positive'

# Search documents by organization
GET https://your-search.search.windows.net/indexes/files-documents-reports/docs?search=*&$filter=organizations/any(o: search.in(o, 'Microsoft,Contoso'))
```

### PowerShell Search Examples

```powershell
# Search for documents with specific key phrases
$searchUrl = "https://aisearchswan2.search.windows.net/indexes/files-documents-reports/docs"
$query = @{
    search = "*"
    filter = "keyphrases/any(k: search.in(k, 'machine learning,artificial intelligence'))"
    select = "metadata_storage_name,keyphrases,sentiment"
}

Invoke-RestMethod -Uri $searchUrl -Headers $headers -Body ($query | ConvertTo-Json)
```

## Troubleshooting

### Common Issues

1. **Skillset Creation Fails**
   - Verify AI Search admin key access
   - Check that AI Search service has sufficient capacity
   - Ensure proper authentication to Azure

2. **Indexer Update Fails**
   - Confirm indexers exist before attaching skillsets
   - Verify index schema supports new AI fields
   - Check for conflicting field mappings

3. **OCR Skills Not Working**
   - Use text-only skillset for OneLake (recommended)
   - OCR requires specific image processing configuration
   - OneLake primarily handles text-based documents

### Debug Commands

```powershell
# Check indexer status
az search indexer show --service-name "aisearchswan2" --name "files-documents-reports-indexer" --resource-group "AI_Related"

# View indexer execution history
az search indexer status --service-name "aisearchswan2" --name "files-documents-reports-indexer" --resource-group "AI_Related"

# List all skillsets
az search skillset list --service-name "aisearchswan2" --resource-group "AI_Related"
```

## Performance Considerations

- **Processing Time**: AI skillsets add 2-5 seconds per document
- **Capacity**: Ensure AI Search has sufficient search units for concurrent processing
- **Rate Limits**: Large document batches may hit cognitive services rate limits
- **Cost**: Each document processed incurs cognitive services charges

## Future Enhancements

- **Custom Skills**: Add domain-specific entity extraction
- **Translation**: Automatic translation for multi-language documents
- **OCR Integration**: Full image and PDF text extraction
- **Classification**: Automatic document type classification
- **Summarization**: AI-powered document summarization

## Security Notes

- AI Search uses managed identity for secure access
- Document content is processed by Azure Cognitive Services
- No data is stored outside your Azure tenant
- RBAC controls access to search indexes and skillsets

---

*This integration provides enterprise-grade AI document processing while maintaining the modular, atomic design principles of the overall solution.*

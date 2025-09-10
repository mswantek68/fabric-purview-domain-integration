#!/usr/bin/env pwsh

Write-Host "🔧 AI Foundry Chat Playground - Non-Semantic Configuration Helper" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green

# Get azd environment variables
$env:AZURE_ENV_NAME = if ($env:AZURE_ENV_NAME) { $env:AZURE_ENV_NAME } else { "swantest-ws06" }

Write-Host "🎯 📋 Configuration Values for Chat Playground (WITHOUT Semantic Search):"
Write-Host "========================================================================="
Write-Host ""

Write-Host "🎯 🔗 AI Foundry Resource:"
Write-Host "  Portal URL: https://ai.azure.com"
Write-Host ""

Write-Host "🎯 🔍 AI Search Configuration:"
Write-Host "  Search Service Name: aisearchswan2"
Write-Host "  Search Service URL: https://aisearchswan2.search.windows.net"
Write-Host "  Index Name: $env:AZURE_ENV_NAME-documents"
Write-Host ""

Write-Host "🎯 🔐 Authentication Method:"
Write-Host "  Type: System-assigned managed identity"
Write-Host "  (Choose this option in the authentication dropdown)"
Write-Host ""

Write-Host "🎯 ⚠️  IMPORTANT - Semantic Search Configuration:"
Write-Host "  Query Type: Keyword (NOT Semantic)"
Write-Host "  Semantic Search: DISABLED/OFF"
Write-Host "  Search Type: Full text search"
Write-Host ""

Write-Host "🎯 📋 Step-by-Step Instructions for Chat Playground:"
Write-Host "===================================================="
Write-Host ""

Write-Host "1. 🌐 Go to AI Foundry Portal:"
Write-Host "   URL: https://ai.azure.com"
Write-Host ""

Write-Host "2. 🎯 Navigate to your project:"
Write-Host "   - Select 'firstProject1'"
Write-Host "   - Go to 'Playgrounds' > 'Chat'"
Write-Host ""

Write-Host "3. ➕ Add Data Source:"
Write-Host "   - Click 'Add your data' or 'Add data source'"
Write-Host "   - Select 'Azure AI Search' as the data source type"
Write-Host ""

Write-Host "4. 🔧 Configure the connection:"
Write-Host "   Search service: aisearchswan2"
Write-Host "   Index name: $env:AZURE_ENV_NAME-documents"
Write-Host "   Authentication: System-assigned managed identity"
Write-Host ""

Write-Host "5. ⚠️  DISABLE Semantic Search:"
Write-Host "   - Look for 'Query type' or 'Search type' setting"
Write-Host "   - Choose 'Keyword' or 'Vector + Keyword' (NOT 'Semantic')"
Write-Host "   - Ensure semantic search is turned OFF"
Write-Host "   - Some UIs show this as a toggle switch - turn it OFF"
Write-Host ""

Write-Host "6. ✅ Test the connection:"
Write-Host "   - Click 'Test connection' or 'Validate'"
Write-Host "   - Should succeed without semantic search"
Write-Host ""

Write-Host "7. 💾 Save the configuration:"
Write-Host "   - Click 'Save' or 'Add data source'"
Write-Host "   - The data source should now appear in your chat playground"
Write-Host ""

Write-Host "8. 🧪 Test the integration:"
Write-Host "   - Ask: 'What documents do you have access to?'"
Write-Host "   - You should get responses with citations from your indexed data"
Write-Host ""

Write-Host "🎯 🚨 Troubleshooting:"
Write-Host "==================="
Write-Host ""

Write-Host "If you still get semantic search errors:"
Write-Host "1. ❌ Look for any 'Semantic search' toggles and turn them OFF"
Write-Host "2. ⚙️  Choose 'Keyword search' or 'Full text search' mode"
Write-Host "3. 🔑 If managed identity fails, try 'API key' authentication:"
Write-Host "   - Go to Azure portal > AI Search service 'aisearchswan2'"
Write-Host "   - Settings > Keys > Copy Primary admin key"
Write-Host "   - Use that key instead of managed identity"
Write-Host ""

Write-Host "Expected behavior WITHOUT semantic search:"
Write-Host "✅ Regular keyword search works"
Write-Host "✅ Citations are provided"
Write-Host "✅ Content from your indexed documents appears"
Write-Host "❌ No advanced semantic ranking (but that's OK)"
Write-Host ""

Write-Host "🎯 💡 Why this happens:"
Write-Host "======================"
Write-Host "The AI Search index was created without semantic search configuration."
Write-Host "Chat Playground defaults to semantic search, which requires special index setup."
Write-Host "Using keyword search provides the same content access without semantic features."
Write-Host ""

Write-Host "✅ Configuration helper completed!" -ForegroundColor Green
Write-Host "Use keyword search mode to avoid semantic search requirement." -ForegroundColor Green

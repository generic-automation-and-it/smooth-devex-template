#!/bin/bash
# Update an existing PR description in Azure DevOps
# Usage: update-pr.sh <pr-id> "PR Body"

set -e

if [ $# -ne 2 ]; then
    echo "Usage: update-pr.sh <pr-id> \"PR Body\""
    exit 1
fi

PR_ID="$1"
BODY="$2"

az repos pr update \
    --id "$PR_ID" \
    --description "$BODY" \
    --org https://dev.azure.com/versionequipmentmanager \
    --project "VEM-Version Equipment Manager" \
    --output json

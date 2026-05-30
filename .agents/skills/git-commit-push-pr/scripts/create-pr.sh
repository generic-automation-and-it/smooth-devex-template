#!/bin/bash
# Create a pull request in Azure DevOps with title and body
# Usage: create-pr.sh "PR Title" "PR Body" [base-branch]
# Default base branch: main

set -e

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: create-pr.sh \"PR Title\" \"PR Body\" [base-branch]"
    echo "Default base branch: main"
    exit 1
fi

TITLE="$1"
BODY="$2"
BASE_BRANCH="${3:-main}"
REPO=$(basename "$(git remote get-url origin)" .git)

az repos pr create \
    --source-branch "$(git rev-parse --abbrev-ref HEAD)" \
    --target-branch "$BASE_BRANCH" \
    --title "$TITLE" \
    --description "$BODY" \
    --org https://dev.azure.com/versionequipmentmanager \
    --project "VEM-Version Equipment Manager" \
    --repository "$REPO" \
    --output json

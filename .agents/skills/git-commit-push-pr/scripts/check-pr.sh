#!/bin/bash
# Check if a PR exists for the current branch in Azure DevOps
# Usage: check-pr.sh
# Returns: JSON with PR id and title, or empty array if no PR exists

set -e

BRANCH=$(git rev-parse --abbrev-ref HEAD)
REPO=$(basename "$(git remote get-url origin)" .git)

az repos pr list \
    --source-branch "$BRANCH" \
    --status active \
    --org https://dev.azure.com/versionequipmentmanager \
    --project "VEM-Version Equipment Manager" \
    --repository "$REPO" \
    --output json

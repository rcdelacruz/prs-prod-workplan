#!/bin/bash

# Repository Configuration Example
# Copy this file to repo-config.sh and modify as needed
# Source this file before running deploy-onprem.sh to use custom repositories

# Backend repository configuration
export BACKEND_REPO_URL="https://github.com/stratpoint-engineering/prs-backend-a.git"
export BACKEND_BRANCH="main"

# Frontend repository configuration
export FRONTEND_REPO_URL="https://github.com/stratpoint-engineering/prs-frontend-a.git"
export FRONTEND_BRANCH="main"

# Repository base directory
export REPO_BASE_DIR="/opt/prs"

# Example usage:
# 1. Copy this file: cp repo-config.example.sh repo-config.sh
# 2. Edit repo-config.sh with your repository URLs and branches
# 3. Source the config: source scripts/repo-config.sh
# 4. Run deployment: scripts/deploy-onprem.sh deploy

# Alternative: Set environment variables directly
# BACKEND_REPO_URL=https://github.com/myorg/my-backend.git scripts/deploy-onprem.sh deploy

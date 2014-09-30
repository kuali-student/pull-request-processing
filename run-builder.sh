#!/bin/bash -e
#
# run-builder.sh
#
# run the build of a specific pull request.
#
# Expected Jenkins Build Parameter Names:
# PULL_REQUEST_NUMBER
# PULL_REQUEST_COMMIT_ID
#
REPO_BASE=https://github.com/kuali-student

KS_REPO=$REPO_BASE/ks-development
KS_IMPEX_REPO=$REPO_BASE/ks-development-impex

mvn clean

mkdir -p target

mvn initialize -DfetchOpenPullRequests.target-pull-request-number=$PULL_REQUEST_NUMBER -D -DfetchOpenPullRequests.phase=initialize

# EOF
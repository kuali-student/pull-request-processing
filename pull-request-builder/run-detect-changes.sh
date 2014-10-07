#!/bin/bash -e
#
# run-detect-changes.sh
#
# Using the github api find out which modules changed and if there are sql changes to impex.
#
# Expected Jenkins Build Parameter Names:
# PULL_REQUEST_NUMBER
# PULL_REQUEST_COMMIT_ID
#

mvn clean

mkdir -p target

# This step generates files that can be used for downstream jobs for impex and unit testing.
mvn validate -DidentifyChangesInApi.target-pull-request-number=$PULL_REQUEST_NUMBER -DidentifyChangeInApi.target-pull-request-head-id=PULL_REQUEST_COMMIT_ID -DidentifyChangesInApi.phase=validate

# EOF

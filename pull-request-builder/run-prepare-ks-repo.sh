#!/usr/bin/env bash
#
# create target/ks-repo
# change the current directory to target/ks-repo
# change the current branch to pull-request-X
#
#
# Expects these environment variables to exist:
# PULL_REQUEST_NUMBER
# PULL_REQUEST_COMMIT_ID

if test -z $PULL_REQUEST_NUMBER
then
	echo "Missing PULL_REQUEST_NUMBER Variable"
	exit 1
fi

if test -z $PULL_REQUEST_COMMIT_ID
then
	echo "Missing PULL_REQUEST_COMMIT_ID Variable"
	exit 1
fi

mkdir -p target

echo "Fetching pull request $PULL_REQUEST_NUMBER head at $PULL_REQUEST_COMMIT_ID from github"
mvn validate -DfetchOpenPullRequests.target-pull-request-number=$PULL_REQUEST_NUMBER -DfetchOpenPullRequests.target-commit-id=$PULL_REQUEST_COMMIT_ID -DfetchOpenPullRequests.phase=validate -e 

cd target/ks-repo

# runs in the subshell to keep the current directory at the top level.
echo "Checkout pull-request-${PULL_REQUEST_NUMBER} branch"
git checkout pull-request-${PULL_REQUEST_NUMBER}

# EOF

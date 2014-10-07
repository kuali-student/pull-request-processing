#!/usr/bin/env bash
#
# run-builder.sh
#
# Determine if we should be running the manual impex process.
#
# Expected Jenkins Build Parameter Names:
# PULL_REQUEST_NUMBER
# PULL_REQUEST_COMMIT_ID
#

# for example set this to -Doracle.dba.password=<password>
DEBUG_DB_OPTS=

REPO_BASE=https://github.com/kuali-student

KS_REPO=$REPO_BASE/ks-development
KS_IMPEX_REPO=$REPO_BASE/ks-development-impex

PR_BRANCH="pull-request-${PULL_REQUEST_NUMBER}"

# make sure all environment variables are set
set -o nounset
# exit immediately if a pipeline returns a non-zero status
set -o errexit

if test -f target/sql-changes.dat
then
	# change detector says there are sql changes on this pull request
	
	# run the manual impex process.
	
	# first checkout the ks-repo
	mvn clean

	mkdir -p target

	echo "Fetching pull request $PULL_REQUEST_NUMBER head at $PULL_REQUEST_COMMIT_ID"
	mvn process-resources -DfetchOpenPullRequests.target-pull-request-number=$PULL_REQUEST_NUMBER -DfetchOpenPullRequests.target-commit-id=$PULL_REQUEST_COMMIT_ID -DfetchOpenPullRequests.phase=process-resources 	
	
	cd target/ks-repo

	echo "Checkout $PR_BRANCH branch"
	git checkout $PR_BRANCH	
	
	KS_REPO_PR_BRANCH_HEAD_ID=$(git log --format=%H -n 1 $PR_BRANCH)
	echo "$PR_BRANCH at commit id: $KS_REPO_PR_BRANCH_HEAD_ID"
	
	# set the pom versions
	## This will use the Fusion Tag Mojo
	mvn process-resources -Ppull-request -Dfusion.tag.phase=process-resources -Dfusion.tag.pull-request-number-property=PULL_REQUEST_NUMBER -N -e 
	
	# ideally this would work but if not then do a full build
	# once development is building properly try switching this back.
	# mvn clean install -Psql-only,impex-only
	
	mvn clean install -DskipTests -Pskip-all-wars
	
	# move back up to the pull-request-builder directory
	cd ../..
	
	bash -e ./run-setup-impex-repo.sh
	
	
else
	echo "No SQL Changes Detected so Skipping Manual Impex Process"
fi


# EOF
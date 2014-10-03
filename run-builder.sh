#!/bin/bash -e
#
# run-builder.sh
#
# Determine if we should be running the manual impex process.
#
# Expected Jenkins Build Parameter Names:
# PULL_REQUEST_NUMBER
# PULL_REQUEST_COMMIT_ID
#
DEBUG_DB_OPTS=-Doracle.dba.password=X12p42Rs

REPO_BASE=https://github.com/kuali-student

KS_REPO=$REPO_BASE/ks-development
KS_IMPEX_REPO=$REPO_BASE/ks-development-impex

PR_BRANCH="pull-request-${PULL_REQUEST_NUMBER}"

if test -f target/sql-changes.dat
then
	# change detector says there are sql changes on this pull request
	
	# run the manual impex process.
	
	# first checkout the ks-repo
	mvn clean

	mkdir -p target

	echo "Fetching pull request $PULL_REQUEST_NUMBER head at $PULL_REQUEST_COMMIT_ID"
	mvn initialize -DfetchOpenPullRequests.target-pull-request-number=$PULL_REQUEST_NUMBER -DfetchOpenPullRequests.target-commit-id=$PULL_REQUEST_COMMIT_ID -DfetchOpenPullRequests.phase=initialize	
	
	cd target/ks-repo

	echo "Checkout $PR_BRANCH branch"
	git checkout $PR_BRANCH	
	
	# set the pom versions
	## This will use the Fusion Tag Mojo
	mvn initialize -Dfusion.tag.phase=initialize -Dfusion.tag.pull-request-number-property=PULL_REQUEST_NUMBER -N
	
	# ideally this would work but if not then do a full build
	# once development is building properly try switching this back.
	# mvn clean install -Psql-only,impex-only
	
	mvn clean install -DskipTests -Pskip-all-wars
	
	# move back up to the target directory
	cd ..
	
	# next checkout the ks-impex-repo

	git clone --depth=1 $KS_IMPEX_REPO ./ks-impex-repo	

	cd ks-impex-repo
	
	# if the pull request branch exists use it otherwise create it.
	$(git branch -r | grep $PR_BRANCH)
	R=$?
	
	if test 0 -eq $R
	then
		# branch exists remotely
		git checkout -b $PR_BRANCH origin/$PR_BRANCH
	else
		# branch does not exist remotely
		git checkout -b $PR_BRANCH
	fi
	
	# setup the pom versions.
	mvn initialize -Ppull-request -Dfusion.tag.phase=initialize -Dfusion.tag.pull-request-number-property=PULL_REQUEST_NUMBER -Dfusion.tag.pull-request-number=$PULL_REQUEST_NUMBER -N -e
	
	# this only works on my local
	mvn initialize -Plocal,source-db $DEBUG_DB_OPTS -N -e 
	mvn generate-resources -Pdump,local $DEBUG_DB_OPTS -N -e
	mvn process-resources -Pimpexscm -N
	
	git add .
	
	git commit -a -m'Commit Impex Changes for pull-request-$PULL_REQUEST_NUMBER'
	
	echo "IMPEX_BRANCH=$PR_BRANCH" > pull-request-branch.dat
	
	# we want to push $PR_BRANCH to the upstream.
	

else
	echo "No SQL Changes Detected so Skipping Manual Impex Process"
fi


# EOF
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

# for example set this to -Doracle.dba.password=<password>
DEBUG_DB_OPTS=

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
	mvn process-resources -DfetchOpenPullRequests.target-pull-request-number=$PULL_REQUEST_NUMBER -DfetchOpenPullRequests.target-commit-id=$PULL_REQUEST_COMMIT_ID -DfetchOpenPullRequests.phase=process-resources -Dgit-workflow.fetchDepth=4	
	
	cd target/ks-repo

	echo "Checkout $PR_BRANCH branch"
	git checkout $PR_BRANCH	
	
	KS_REPO_PR_BRANCH_HEAD_ID=$(git log --format=%H -n 1 $PR_BRANCH)
	echo "$PR_BRANCH at commit id: $KS_REPO_PR_BRANCH_HEAD_ID"
	
	# set the pom versions
	## This will use the Fusion Tag Mojo
	mvn process-resources -Dfusion.tag.phase=process-resources -Dfusion.tag.pull-request-number-property=PULL_REQUEST_NUMBER -N
	
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
		echo "Branch $PR_BRANCH exists in the origin so checkout a local branch pointing at the existing one."
		git checkout -b $PR_BRANCH origin/$PR_BRANCH
		
	else
		# branch does not exist remotely
		
		echo "Branch $PR_BRANCH does not exist remotely so create it from master."
		git checkout -b $PR_BRANCH
		
		echo "Setup the pom versions to $PR_BRANCH"
		
		# setup the pom versions.
		mvn process-resources -Ppull-request -Dfusion.tag.phase=process-resources -Dfusion.tag.pull-request-number-property=PULL_REQUEST_NUMBER -Dfusion.tag.pull-request-number=$PULL_REQUEST_NUMBER -N -e
	
	fi
	
	
	# run local manual impex process
	
	# this loads in all of the -sql module artifacts
	mvn initialize -Plocal,source-db $DEBUG_DB_OPTS -N -e
	
	# this creates the .mpx and .xml files from the source database 
	mvn generate-resources -Pdump,local $DEBUG_DB_OPTS -N -e
	
	# this moves the created .mpx and .xml files back under the src/main/resources directory.
	mvn process-resources -Pimpexscm -N
	
	# we want to add all newly generated files
	git add src/main/resources
	
	git commit -a -m'Commit Impex Changes for pull-request-$PULL_REQUEST_NUMBER\n\nFor pull-request commit id: $KS_REPO_PR_BRANCH_HEAD_ID'
	
	# move back up to the pull-request-builder directory
	cd ../..
	
	# update the ks-impex-repo $PR_BRANCH into github.
	mvn process-resources -Dpush-db-changes.phase=process-resources  -Dpush-db-changes.pull-request-branch-name=$PR_BRANCH
	

else
	echo "No SQL Changes Detected so Skipping Manual Impex Process"
fi


# EOF
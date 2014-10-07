Kuali Student Pull Request Processing 
=====================================

These artifacts contain both the pom configuration aswell as shell scripts used
in the Kuali Student Pull Request Processing Process.

There are three phases handled here:
1. Github Pull Request Changed notifications
2. On each pull request build, unit test, manual impex, run smoke test aft's
3. On verified Sign off and step 2 is passing merge to the stable branch.


For the initial conversion the full aft suite will still run on the stable branch 
only.  Later we can use the module change detector to find a better subset of tests
to run.



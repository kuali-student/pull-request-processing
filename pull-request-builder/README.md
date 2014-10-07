Pull Request Builder
====================

This project is a thin maven project that is setup with the 
git-workflow-maven-plugin configured for processing individual pull requests
against the kuali-student development repository.

The ci.kuali.org jenkins job will checkout this project and then configure the 
various build scripts which will take build parameters and take care of the 
various build steps for verifying pull requests.

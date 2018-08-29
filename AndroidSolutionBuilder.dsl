// this map need to me matching the BUILD_STACK choice parameter options
def nodeParameterMap=[:]
nodeParameterMap.put('Docker on Ubuntu 16.04 - LTS Stack','adocker')
nodeParameterMap.put('Android on Ubuntu 16.04 - LTS Stack','aci-ssd')

def AGENT_NODE = nodeParameterMap[BUILD_STACK]



def jobPrefix = "$SOLUTION_NAME" + "/" + "$SOLUTION_NAME"

def jobDashboard = "$SOLUTION_NAME" + "/" + "Dashboard"
def jobDevPR = "$SOLUTION_NAME" + "/" + "1_DevPR"
def jobBuild = "$SOLUTION_NAME" + "/" + "2_Build"
def jobDeployment = "$SOLUTION_NAME" + "/" + "3A_QA"
def jobPromotion = "$SOLUTION_NAME" + "/" + "3B_QA_Promotion"
def jobPublishing = "$SOLUTION_NAME" + "/" + "4_Publish"


folder("$SOLUTION_NAME") {
  displayName("$SOLUTION_NAME")
  description("Folder for $SOLUTION_NAME")
}

// create Dashboard overview
dashboardView(jobDashboard) {
  	jobs {
        regex(/.*/)
    }
  
    columns {
        status()
        weather()
      	name()
      	lastSuccess()
      	lastFailure()
      	lastDuration()
        buildButton()
    }
  
    topPortlets {
        jenkinsJobsList {
        }
    }
  
    bottomPortlets {
        buildStatistics()
    }
}

// create QA_Promotion Job
freeStyleJob(jobPromotion) {
  	
    parameters {
        stringParam('SOURCE_PROJECT', '', '')
      	stringParam('SOURCE_BUILD_NUMBER', '', '')
        stringParam('PROMOTION_RECEIPIENTS', PROMOTION_RECEIPIENTS, '')
    }

  	properties{
		    promotions{
			      promotion {
                name('Deploy to Google')
                icon('star-gold')
                conditions {
                    manual('')
                }
              
                actions {
                    downstreamParameterized {
                        trigger(jobPublishing) {
                            parameters {
                                predefinedProp("SOURCE_PROJECT", '$SOURCE_PROJECT')
                                predefinedProp("SOURCE_BUILD_NUMBER", '$SOURCE_BUILD_NUMBER')
                            }
                        }
                    }
                }
            }
		    }
	  }
  
    steps {
      	shell('echo "INFORM ABOUT NEW BUILD - awaiting promotion!"')
        shell('echo "SEND EMAIL"')
        shell('echo "CREATE JIRA ISSUE"')
    }  
  
    publishers {
        extendedEmail {
            recipientList("$PROMOTION_RECEIPIENTS")
            defaultSubject('Request for Promotion of ' + "$SOLUTION_NAME")
            defaultContent('A build #${SOURCE_BUILD_NUMBER} of project <b>' + "$SOLUTION_NAME" + '</b> was successful and a new version was created.<br><br>Check $BUILD_URL and promote version to be uploaded to the Store.')
            contentType('text/html')
            triggers {
                beforeBuild()
                always {
                    sendTo {
                        recipientList()
                    }
                }
            }
        }
    }
}

// create Publish Job
freeStyleJob(jobPublishing) {
  	description("<h2>Be aware to configure the Post-build Action: Upload Android APK to Google Play Step.</h2>Job configuration (Recent Changes) might be updated whenever a build is about to be promoted.")
  
    parameters {
        stringParam('SOURCE_PROJECT', '', '')
      	stringParam('SOURCE_BUILD_NUMBER', '', '')
    }

    steps {
        copyArtifacts('$SOURCE_PROJECT') {
            targetDirectory('$SOURCE_PROJECT')
            flatten()
            fingerprintArtifacts(true)
            buildSelector {
                buildNumber('$SOURCE_BUILD_NUMBER')
            }
        }
    }
  
    publishers {
    	androidApkUpload {
          	apkFilesPattern("**/*.apk")
            deobfuscationFilesPattern("**/mapping.txt")
          	googleCredentialsId("$GOOGLE_SERVICE_ACCOUNT")
        }
    }
}

// create QA Job
freeStyleJob(jobDeployment) {
  	description("<h2>Be aware to configure the Post-build Action: Apperian EASE Plugin Step</h2>")
    parameters {
        stringParam('SOURCE_PROJECT', '', '')
      	stringParam('SOURCE_BUILD_NUMBER', '', '')
    }

    steps {
        copyArtifacts('$SOURCE_PROJECT') {
            targetDirectory('$SOURCE_PROJECT')
            flatten()
            fingerprintArtifacts(true)
            buildSelector {
                buildNumber('$SOURCE_BUILD_NUMBER')
            }
        }
    }

	// Base Init of Apperian Publishing
    configure { project ->
        project / publishers << 'org.jenkinsci.plugins.ease.EaseRecorder' {
            uploads {
                org.jenkinsci.plugins.ease.EaseUpload {
                    versionNotes('Build #$SOURCE_BUILD_NUMBER at $BUILD_TIMESTAMP')
                }
            }
        }
    }
}

// create Build Job
pipelineJob(jobBuild) {
  	parameters {
        stringParam('AGENT_NODE', AGENT_NODE, '')
      	stringParam('DOCKER_IMAGE', DOCKER_IMAGE, '')
        booleanParam('SKIP_CHECKOUT', (SKIP_CHECKOUT == 'true'), '')
      	stringParam('GIT_REPOSITORY', GIT_REPOSITORY, '')
        credentialsParam('GIT_CREDENTIALS') {
          defaultValue(GIT_CREDENTIALS)
        }
      	booleanParam('GIT_UPDATE_SUBMODULES', (GIT_UPDATE_SUBMODULES == 'true'), '')
        stringParam('GIT_BRANCH', GIT_BRANCH, '')
        stringParam('GIT_TAG', GIT_TAG, '')
        stringParam('GIT_COMMIT', GIT_COMMIT_SHA, '')
        stringParam('GRADLE_TASK', GRADLE_TASK, '')
        stringParam('ARCHIVE_INCLUDE', ARCHIVE_INCLUDE, '')
        stringParam('ARCHIVE_EXCLUDE', ARCHIVE_EXCLUDE, '')
        stringParam('DEPLOYMENT_JOB', jobDeployment, '')
        stringParam('PROMOTION_JOB', jobPromotion, '')
      	booleanParam('IS_PR_BUILD', false, '')
    }
  
    properties {
      	// allow any project in this folder being able to copy artifacts from Build job
        copyArtifactPermission {
            // Comma-separated list of projects that can copy artifacts of this project.
            projectNames("$SOLUTION_NAME" + ".*")
        }
    }

    definition {
        cps {
            if (AGENT_NODE == 'aci-ssh') {
                script(readFileFromWorkspace('android-stock/Jenkinsfile'))
            } else {
                script(readFileFromWorkspace('android-docker/Jenkinsfile'))
                sandbox()
            }
        }
    }
}

// create Dev_PR Job
pipelineJob(jobDevPR) {
  	parameters {
        stringParam('AGENT_NODE', AGENT_NODE, '')
      	stringParam('DOCKER_IMAGE', DOCKER_IMAGE, '')
        booleanParam('SKIP_CHECKOUT', (SKIP_CHECKOUT == 'true'), '')
      	stringParam('GIT_REPOSITORY', GIT_REPOSITORY, '')
        credentialsParam('GIT_CREDENTIALS') {
          defaultValue(GIT_CREDENTIALS)
        }
      	booleanParam('GIT_UPDATE_SUBMODULES', (GIT_UPDATE_SUBMODULES == 'true'), '')
        stringParam('GRADLE_TASK', GRADLE_TASK, '')
      	booleanParam('IS_PR_BUILD', true, '')
    }
  
    properties {
        githubProjectProperty {
          	projectUrlStr(GIT_REPOSITORY)
        }
    }

    triggers {
        githubPullRequests {
          	triggerMode("CRON")
          	spec("*/5 * * * *")
          	preStatus(true)
          	cancelQueued(false)
          	abortRunning(false)
          	skipFirstRun(false)
          	events {
              	Open()
              	nonMergeable {
					skip(true)
				}
            }
            repoProviders {
              githubPlugin {
                // Old trigger behaviour when connection resolved first from global settings and then used locally.
                cacheConnection(true)
                // Allow disable registering hooks even if it specified in global settings.
                manageHooks(true)
                // ADMIN, PUSH or PULL repository permission required for choosing connection from `GitHub Plugin` `GitHub Server Configs`.
                repoPermission("ADMIN")
              }
            }
        }
    }
  
    definition {
        cps {
            if (AGENT_NODE == 'aci-ssh') {
                script(readFileFromWorkspace('android-stock/JenkinsfilePR'))
            } else {
                script(readFileFromWorkspace('android-docker/JenkinsfilePR'))
                sandbox()
            }
        }
    }
}
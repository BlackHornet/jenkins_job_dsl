// this map need to me matching the BUILD_STACK choice parameter options
def nodeParameterMap=[:]
nodeParameterMap.put('Xcode 9.4.x, on macOS 10.13','xcode_1013')

def AGENT_NODE = nodeParameterMap[BUILD_STACK]



def jobPrefix = "$SOLUTION_NAME" + "/" + "$SOLUTION_NAME"

def jobDashboard = "$SOLUTION_NAME" + "/" + "Dashboard"
def jobDevPR = "1_" + jobPrefix + "_DevPR"
def jobBuild = "2_" + jobPrefix + "_Build"
def jobDeployment = "3A_" + jobPrefix + "_QA"
def jobPromotion = "3B_" + jobPrefix + "_QA_Promotion"
def jobPublishing = "4_" + jobPrefix + "_Publish"


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
    }

    properties{
    promotions{
      promotion {
            name('Deploy to Apple')
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
}

// create Publish Job
freeStyleJob(jobPublishing) {
    description("<h2>Be aware to configure the Post-build Action: Upload IPA to Apple AppStore Step.</h2>Job configuration (Recent Changes) might be updated whenever a build is about to be promoted.")

    label('xcode_1013')

    wrappers {
        credentialsBinding {
            usernamePassword('ITUNES_USERNAME', 'ITUNES_PASSWORD', '${ITUNES_CREDENTIALS}')
        }
    }
  
    parameters {
        stringParam('SOURCE_PROJECT', '', '')
        stringParam('SOURCE_BUILD_NUMBER', '', '')
        credentialsParam('ITUNES_CREDENTIALS') {
          defaultValue(ITUNES_CREDENTIALS)
        }
    }

    steps {
        copyArtifacts('$SOURCE_PROJECT') {
            flatten()
            targetDirectory('$SOURCE_BUILD_NUMBER')
            fingerprintArtifacts(true)
            buildSelector {
                buildNumber('$SOURCE_BUILD_NUMBER')
            }
        }
        shell('"/Applications/Xcode.app/Contents/Applications/Application Loader.app/Contents/Frameworks/ITunesSoftwareService.framework/Support/altool" --validate-app -f "$WORKSPACE/$SOURCE_BUILD_NUMBER/Application.ipa" -u $ITUNES_USERNAME -p $ITUNES_PASSWORD')
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
            flatten()
            targetDirectory('$SOURCE_BUILD_NUMBER')
            fingerprintArtifacts(true)
            buildSelector {
                buildNumber('$SOURCE_BUILD_NUMBER')
            }
        }
    }

  // Base Init of Apperian Publishing
    configure { project ->
        project / publishers << 'org.jenkinsci.plugins.ease.EaseRecorder' {
            
        }
    }
}

// create Build Job
pipelineJob(jobPrefix + "_Build") {
    parameters {
        stringParam('AGENT_NODE', AGENT_NODE, '')
        booleanParam('SKIP_CHECKOUT', (SKIP_CHECKOUT == 'true'), '')
        stringParam('GIT_REPOSITORY', GIT_REPOSITORY, '')
        credentialsParam('GIT_CREDENTIALS') {
          defaultValue(GIT_CREDENTIALS)
        }
        booleanParam('GIT_UPDATE_SUBMODULES', (GIT_UPDATE_SUBMODULES == 'true'), '')
        stringParam('GIT_BRANCH', GIT_BRANCH, '')
        stringParam('GIT_TAG', GIT_TAG, '')
        stringParam('GIT_COMMIT', GIT_COMMIT_SHA, '')
        stringParam('ARCHIVE_INCLUDE', ARCHIVE_INCLUDE, '')
        stringParam('DEPLOYMENT_JOB', jobDeployment, '')
        stringParam('PROMOTION_JOB', jobPromotion, '')
        booleanParam('IS_PR_BUILD', false, '')

        stringParam('XCODE_SCHEMA', XCODE_SCHEMA, '')
        stringParam('PROJECT_PATH', PROJECT_PATH, '')
        stringParam('XCODE_CONFIGURATION', XCODE_CONFIGURATION, '')
        stringParam('XCODE_TARGET', XCODE_TARGET, '')
        stringParam('DEVELOPMENT_TEAMID', DEVELOPMENT_TEAMID, '')
        stringParam('IPA_EXPORT_METHOD', IPA_EXPORT_METHOD, '')
        stringParam('KEYCHAIN_NAME', KEYCHAIN_NAME, '')
        stringParam('PROVISIONING_PROFILE_APPID', PROVISIONING_PROFILE_APPID, '')
        stringParam('PROVISIONING_PROFILE_UUID', PROVISIONING_PROFILE_UUID, '')
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
          script(readFileFromWorkspace('ios-stock/Jenkinsfile'))
          sandbox()
        }
    }
}

// create Dev_PR Job
pipelineJob(jobDevPR) {
    parameters {
        stringParam('AGENT_NODE', AGENT_NODE, '')
        booleanParam('SKIP_CHECKOUT', (SKIP_CHECKOUT == 'true'), '')
        stringParam('GIT_REPOSITORY', GIT_REPOSITORY, '')
        credentialsParam('GIT_CREDENTIALS') {
          defaultValue(GIT_CREDENTIALS)
        }
        booleanParam('GIT_UPDATE_SUBMODULES', (GIT_UPDATE_SUBMODULES == 'true'), '')
        booleanParam('IS_PR_BUILD', true, '')

        stringParam('PROJECT_PATH', PROJECT_PATH, '')
        stringParam('XCODE_CONFIGURATION', XCODE_CONFIGURATION, '')
        stringParam('XCODE_TARGET', XCODE_TARGET, '')
        stringParam('DEVELOPMENT_TEAMID', DEVELOPMENT_TEAMID, '')
        stringParam('KEYCHAIN_NAME', KEYCHAIN_NAME, '')
        stringParam('PROVISIONING_PROFILE_APPID', PROVISIONING_PROFILE_APPID, '')
        stringParam('PROVISIONING_PROFILE_UUID', PROVISIONING_PROFILE_UUID, '')
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
          script(readFileFromWorkspace('ios-stock/JenkinsfilePR'))
          sandbox()
        }
    }
}
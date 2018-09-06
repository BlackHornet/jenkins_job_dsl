// this map need to me matching the BUILD_STACK choice parameter options
def nodeParameterMap=[:]
nodeParameterMap.put('Xcode 9.4.x, on macOS 10.13','xcode_1013')

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
    
    if (AUTHORIZATION_ID.trim() != '') {
        authorization {
            permissionAll(AUTHORIZATION_ID)
        }
    }
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
                name('Deploy to Apple')
                icon('star-gold')
                conditions {
                    manual('')
                    downstream(false, '$SOURCE_PROJECT')
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
        shell("""
xcode_contents=`xcode-select -p`
cd "${xcode_contents}/../Applications/Application Loader.app/Contents/Frameworks/ITunesSoftwareService.framework/Support/"
./altool --validate-app -f "$WORKSPACE/$SOURCE_BUILD_NUMBER/Application.ipa" -u $ITUNES_USERNAME -p $ITUNES_PASSWORD --output-format xml
if [ "$?" -eq 0 ]; then
    ./altool --upload-app -f "$WORKSPACE/$SOURCE_BUILD_NUMBER/Application.ipa" -u $ITUNES_USERNAME -p $ITUNES_PASSWORD --output-format xml
fi
""")
    }
  
    publishers {
        wsCleanup {
            deleteDirectories(true)
        }
    }
}

// create QA Job
freeStyleJob(jobDeployment) {
    description("<h2>Be aware to configure the Post-build Action: Apperian EASE Plugin Step</h2>")

    wrappers {
        credentialsBinding {
            usernamePassword('ACCOUNT_USERNAME', 'ACCOUNT_PASSWORD', '${DEPLOYMENT_ACCOUNT}')
        }
    }

    parameters {
        stringParam('SOURCE_PROJECT', '', '')
        stringParam('SOURCE_BUILD_NUMBER', '', '')
        credentialsParam('DEPLOYMENT_ACCOUNT') {
          defaultValue(QA_DEPLOYMENT_ACCOUNT)
        }
    }

    steps {
        copyArtifacts('$SOURCE_PROJECT') {
            targetDirectory('$SOURCE_PROJECT')
            includePatterns('**/*.ipa')
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
                'org.jenkinsci.plugins.ease.EaseUpload' {
                    prodEnv('EUROPE')
                    username('$ACCOUNT_USERNAME')
                    password('$ACCOUNT_PASSWORD')
                    versionNotes('Automated build #$SOURCE_BUILD_NUMBER created at $BUILD_TIMESTAMP')
                }
            }
        }
    }
  
    publishers {
        wsCleanup {
            deleteDirectories(true)
        }
    }
}

// create Build Job
pipelineJob(jobBuild) {
    parameters {
        stringParam('AGENT_NODE', AGENT_NODE, '')
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
        credentialsParam('KEYCHAIN_PASSWORD_CREDENTIALS') {
          defaultValue(KEYCHAIN_PASSWORD_CREDENTIALS)
        }
        stringParam('PROVISIONING_PROFILE_APPID', PROVISIONING_PROFILE_APPID, '')
        stringParam('PROVISIONING_PROFILE_UUID', PROVISIONING_PROFILE_UUID, '')
        credentialsParam('DEVELOPER_PROFILE') {
          defaultValue(DEVELOPER_PROFILE)
        }
    }
  
    properties {
        // allow any project in this folder being able to copy artifacts from Build job
        copyArtifactPermission {
            // Comma-separated list of projects that can copy artifacts of this project.
            projectNames("$SOLUTION_NAME" + ".*")
        }

        githubProjectProperty {
            // Enter the URL for the GitHub hosted project (without the tree/master or tree/branch part).
            projectUrlStr("$GIT_REPOSITORY")
        }
    }

    triggers {
        githubBranches {
            triggerMode("CRON")
            spec("*/5 * * * *")
            cancelQueued(false)
            abortRunning(false)
            skipFirstRun(false)
            events {
                hashChanged()
                restriction {
                    matchCriteriaStr('master')
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
          script(readFileFromWorkspace('ios-stock/Jenkinsfile'))
          sandbox()
        }
    }
}

// create Dev_PR Job
pipelineJob(jobDevPR) {
    parameters {
        stringParam('AGENT_NODE', AGENT_NODE, '')
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
        credentialsParam('KEYCHAIN_PASSWORD_CREDENTIALS') {
          defaultValue(KEYCHAIN_PASSWORD_CREDENTIALS)
        }
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
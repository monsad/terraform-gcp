#!/bin/bash

if [ -z "$BITBUCKET_BUILD_NUMBER" ]; then
  echo "Script stopped. It can only be launched in the pipeline."
  exit 1
fi

# Define CommitType
declare -A CommitType
CommitType=( ["hash"]=""
             ["subject"]=""
             ["body"]=""
             ["committerDate"]="" )

# Define ValueOf function
ValueOf() {
    local -n array=$1
    local key=$2
    echo "${array[$key]}"
}

# Find betaUpdateArg
betaUpdateArg=""
for arg in "$@"; do
    if [[ "$arg" == "--isBetaUpdate="* ]]; then
        betaUpdateArg="${arg#*=}"
        break
    fi
done

# Set isBetaUpdate
isBetaUpdate=false
if [ "$betaUpdateArg" == "true" ]; then
    isBetaUpdate=true
fi

# Set MAIN_BRANCH
if [ "$isBetaUpdate" == true ]; then
    MAIN_BRANCH='dev'
else
    MAIN_BRANCH='master'
fi

# Define COMMIT_PHRASES
declare -A COMMIT_PHRASES
COMMIT_PHRASES=( ["BREAKING_CHANGE"]="BREAKING CHANGE"
                 ["BREAKING_CHANGE_SIGN"]="!"
                 ["FEATURE"]="feat"
                 ["FIX"]="fix" )

# Define VersionChangeKey
VersionChangeKey=""
for key in "${!COMMIT_PHRASES[@]}"; do
    if [ "$key" != "BREAKING_CHANGE_SIGN" ]; then
        VersionChangeKey="$key"
        break
    fi
done

# Define runCommand function
runCommand() {
    local command=$1
    eval "$command"
}

#!/bin/bash

getCommitTypeFromSubject() {
    local subject=$1
    echo "$subject" | cut -d':' -f1
}

updateVersion() {
    local currentVersion=$1
    local versionChangeKey=$2
    local mainVersion
    local betaVersion

    IFS='-' read -ra versionParts <<< "$currentVersion"
    mainVersion="${versionParts[0]}"
    betaVersion="${versionParts[1]}"

    if [ "$isBetaUpdate" == true ]; then
        local newBetaVersion=$((betaVersion + 1))
        echo "${mainVersion}-${newBetaVersion}"
    else
        IFS='.' read -ra mainVersionParts <<< "$mainVersion"
        major="${mainVersionParts[0]}"
        minor="${mainVersionParts[1]}"
        patch="${mainVersionParts[2]}"

        case $versionChangeKey in
            ${COMMIT_PHRASES[BREAKING_CHANGE]})
                echo "$((major + 1)).0.0"
                ;;
            ${COMMIT_PHRASES[FEATURE]})
                echo "${major}.$((minor + 1)).0"
                ;;
            ${COMMIT_PHRASES[FIX]})
                echo "${major}.${minor}.$((patch + 1))"
                ;;
            *)
                echo "$currentVersion"
                ;;
        esac
    fi
}

# Rest of#!/bin/bash

getFileContentFromMainBranch() {
    local filePath=$1
    local defaultContent=${2:-''}
    
    fileListString=$(git ls-tree -r $MAIN_BRANCH --name-only)
    fileList=($fileListString)
    resolvedFilePath=$(echo "$filePath" | sed 's/\.\.\///')
    isFileExist=false

    for file in "${fileList[@]}"; do
        if [ "$file" == "$resolvedFilePath" ]; then
            isFileExist=true
            break
        fi
    done

    if [ "$isFileExist" == true ]; then
        git show ${MAIN_BRANCH}:${resolvedFilePath}
    else
        echo "$defaultContent"
    fi
}

getCurrentVersionFromNPM() {
    packageName='@wskz_3/wskz-front'

    output=$(npm view $packageName versions --json 2>/dev/null)
    if [ $? -eq 0 ]; then
        versions=($(echo "$output" | jq -r '.[]'))
        currentVersion=${versions[-1]}

        if [ "$isBetaUpdate" == true ]; then
            preCurrentVersion=${versions[-2]}
            mainPreCurrentVersion=$(echo "$preCurrentVersion" | cut -d'-' -f1)
            mainCurrentVersion=$(echo "$currentVersion" | cut -d'-' -f1)

            if [ "$mainCurrentVersion" != "$currentVersion" ]; then
                echo "$currentVersion"
            elif [ "$mainPreCurrentVersion" == "$mainCurrentVersion" ]; then
                echo "$preCurrentVersion"
            fi
        else
            echo "$currentVersion"
        fi
    else
        echo "0.0.0"
    fi
}

updateProjectVersion() {
    local versionChangeKey=$1

    if [ -n "$versionChangeKey" ]; then
        versionFilePath="../package.json"
        versionFileStringContent=$(getFileContentFromMainBranch "$versionFilePath" '{"version": "0.0.0"}')
        versionFileContent=$(echo "$versionFileStringContent" | jq '.')
        currentVersion=$(getCurrentVersionFromNPM)
        newVersion=$(updateVersion "$currentVersion" "$versionChangeKey")
        versionFileContent=$(echo "$versionFileContent" | jq ".version=\"$newVersion\"")
        echo "$versionFileContent" | jq '.' > "$(dirname $0)/$versionFilePath"
        git add "$(dirname $0)/$(echo $versionFilePath | sed 's/\.\.\///')"
        echo "$newVersion"
    else
        echo "null"
    fi
}

isBreakingChangeCommit() {
    local subject=$1
    local body=$2
    
    echo "$body" | grep -q "${COMMIT_PHRASES[BREAKING_CHANGE]}"
}



#!/bin/bash

getCommitTypeFromSubject() {
    local subject=$1
    echo "$subject" | grep -q "${COMMIT_PHRASES[BREAKING_CHANGE_SIGN]}"
}

isFeatureCommit() {
    local subject=$1
    local body=$2
    getCommitTypeFromSubject "$subject" | grep -q "${COMMIT_PHRASES[FEATURE]}" && !isBreakingChangeCommit "$subject" "$body"
}

isFixCommit() {
    local subject=$1
    local body=$2
    getCommitTypeFromSubject "$subject" | grep -q "${COMMIT_PHRASES[FIX]}" && !isBreakingChangeCommit "$subject" "$body"
}

getVersionChangeKey() {
    local subject=$1
    local body=$2

    if isBreakingChangeCommit "$subject" "$body"; then
        echo "${COMMIT_PHRASES[BREAKING_CHANGE]}"
    elif isFeatureCommit "$subject" "$body"; then
        echo "${COMMIT_PHRASES[FEATURE]}"
    elif isFixCommit "$subject" "$body"; then
        echo "${COMMIT_PHRASES[FIX]}"
    else
        echo "null"
    fi
}

coloredLog() {
    local versionChangeKey=$1
    shift
    case $versionChangeKey in
        ${COMMIT_PHRASES[BREAKING_CHANGE]})
            echo -e "\e[35m$@\e[37m"
            ;;
        ${COMMIT_PHRASES[FEATURE]})
            echo -e "\e[32m$@\e[37m"
            ;;
        ${COMMIT_PHRASES[FIX]})
            echo -e "\e[34m$@\e[37m"
            ;;
    esac
}

isDaylightSavingTime() {
    local now=$(date +"%s")
    local year=$(date +"%Y")
    local jan=$(date -d "$year-01-01" +"%s")
    local jul=$(date -d "$year-07-01" +"%s")
    local timezone_offset=$(date +"%z" | sed 's/00/0/') # Adjust the timezone offset as needed

    [ "$now" -lt "$jul" ] && [ "$now" -ge "$jan" ] && [ "$timezone_offset" == "+0200" ]
}

generateMarkdownChangelogContent() {
    local newVersion=$1
    declare -A changes
    # Assuming changes is an associative array containing CommitType data
    local project=${BITBUCKET_REPO_FULL_NAME:-''}

    local changesString=""
    for versionChangeKey in "${!changes[@]}"; do
        local commitsString=""
        for commit in "${changes[$versionChangeKey]}"; do
            local hash=${commit[hash]}
            local subject=${commit[subject]}
            local body=${commit[body]}
            local committerDate=${commit[committerDate]}

            # Date formatting logic here

            commitsString+="* ${subject} - ${dateFormatted} ${timeFormatted}\n${body}\n"
        done
        changesString+="\n\n<details><summary>${versionChangeKey^^}:</summary>\n${commitsString}</details>"
    done

    # Final markdown content
    echo -e "# Changelog\n\n## ${newVersion}\n${changesString}"
}

#!/bin/bash

# Set environment variables
pipelineUuid=${BITBUCKET_PIPELINE_UUID:-''}
MAIN_BRANCH='main' # Change to the appropriate branch name
COMMIT_PHRASES=(
    "FIX"
    "FEATURE"
    "BREAKING_CHANGE"
)
VERSION_FILE='../package.json'  # Update the path as needed
CHANGELOG_FILE='../CHANGELOG.md'  # Update the path as needed

# Function to get the latest version tag
getLatestVersionTag() {
    local versionPattern="^v([0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?)$"
    local tags=$(git tag -l)
    local latestVersionTag=$(echo "$tags" | grep -E "$versionPattern" | sort -V -r | head -n 1)
    echo "$latestVersionTag"
}

# Function to update version and changelog
updateVersionAndChangelog() {
    local latestVersionTag=$(getLatestVersionTag)
    local lastUpdateVersionRef=${latestVersionTag:-'HEAD'}
    local lastUpdateVersionCommit=$(git rev-parse "$lastUpdateVersionRef")
    local lastMainCommit=$(git rev-parse "$MAIN_BRANCH")

    logOptions=(
        "--from=$lastUpdateVersionCommit"
        "--to=$lastMainCommit"
        "--format=hash:%H,subject:%s,body:%b,committerDate:%cd"
    )

    IFS=$'\n' read -ra log <<< "$(git log "${logOptions[@]}")"

    declare -A changelog=(
        ["${COMMIT_PHRASES[0]}"]=""
        ["${COMMIT_PHRASES[1]}"]=""
        ["${COMMIT_PHRASES[2]}"]=""
    )

    echo -e "\e[47m\e[30mFILES FROM \e[44m\e[30m FIXES \e[42m\e[30m FEATURES \e[45m\e[30m BREAKING CHANGES \e[47m\e[30mCOMMITS\e[0m\e[37m"

    for commitInfo in "${log[@]}"; do
        IFS=',' read -ra commit <<< "$commitInfo"
        commitHash=${commit[0]}
        commitSubject=${commit[1]}
        commitBody=${commit[2]}

        versionChangeKey=${COMMIT_PHRASES[2]}

        if [[ "$commitSubject" == *"${COMMIT_PHRASES[1]}"* ]]; then
            versionChangeKey=${COMMIT_PHRASES[1]}
        elif [[ "$commitSubject" == *"${COMMIT_PHRASES[0]}"* ]]; then
            versionChangeKey=${COMMIT_PHRASES[0]}
        fi

        if [ -n "$versionChangeKey" ]; then
            diff=$(git diff --name-only "${commitHash}^..${commitHash}")
            IFS=$'\n' read -ra files <<< "$diff"

            for file in "${files[@]}"; do
                echo -e "\e[41m\e[30m$versionChangeKey \e[0m\e[37m$file"
                changelog["$versionChangeKey"]+="$file "
            done
        fi
    done

    isChangesExist=false
    versionChangeKey=null

    for key in "${!changelog[@]}"; do
        if [ -n "${changelog[$key]}" ]; then
            versionChangeKey=$key
            isChangesExist=true
            break
        fi
    done

    echo -e "\e[41m\e[30mPROJECT UPDATE VERSION TYPE: ${versionChangeKey:-not update} \e[0m\e[37m"

    if [ "$isChangesExist" = true ]; then
        npmToken=${NPM_TOKEN:-''}
        if [ -z "$npmToken" ]; then
            echo "NPM_TOKEN is not set."
            exit 1
        fi

        echo "//registry.npmjs.org/:_authToken=${npmToken}" > .npmrc

        newVersion=$(updateProjectVersion "$versionChangeKey")

        if [ -n "$newVersion" ]; then
            changelogContent=$(getFileContentFromMainBranch "$CHANGELOG_FILE")
            newChangelogContent=$(generateMarkdownChangelogContent "$newVersion" "${changelog[@]}")"$changelogContent"
            echo -e "$newChangelogContent" > "$(dirname $0)/$CHANGELOG_FILE"
            isChangesExist=true
            git add "$(dirname $0)/$(echo $CHANGELOG_FILE | sed 's/\.\.\///')"

            if [ "$isChangesExist" = true ]; then
                git commit -m "chore: Update project version and generate changelog, [skip ci]" --no-verify
                git pull origin "$MAIN_BRANCH"
                git push origin "$MAIN_BRANCH"

                runCommand "npm run build"
                runCommand "npm publish --access private"

                git addTag "v$newVersion"
                git pushTags "origin"
            fi
        fi
    fi
}

# Execute the updateVersionAndChangelog function
updateVersionAndChangelog || { echo "An error occurred."; exit 1; }


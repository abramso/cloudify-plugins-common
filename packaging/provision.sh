#!/bin/bash -e

SUDO=""

function install_dependencies(){
    echo "## Installing necessary dependencies"

    if  which yum; then
        sudo yum -y install python-devel gcc openssl git libxslt-devel libxml2-devel
        SUDO="sudo"
    elif which apt-get; then
        sudo apt-get update &&
        sudo apt-get -y install build-essential python-dev
        SUDO="sudo"
    else
        echo 'probably windows machine'
        return
    fi
    curl --silent --show-error --retry 5 https://bootstrap.pypa.io/get-pip.py | sudo python &&
    sudo pip install pip==7.1.2 --upgrade
}

function install_wagon(){
    echo "## installing wagon"
    $SUDO pip install wagon==0.3.0
}

function wagon_create_package(){
    echo "## wagon create package"
    $SUDO wagon create -s https://$GITHUB_USERNAME:$GITHUB_PASSWORD@github.com/cloudify-cosmo/$PLUGIN_NAME/archive/$PLUGINS_TAG_NAME.tar.gz -r --validate -v -f
}

function upload_to_s3() {
    ###
    # This will upload both the artifact and md5 files to the relevant bucket.
    # Note that the bucket path is also appended the version.
    ###
    # no preserve is set to false only because preserving file attributes is not yet supported on Windows.

    echo "## uploading wgn and md5 files to s3"
    file=$(basename $(find . -type f -name "$1"))
    date=$(date +"%a, %d %b %Y %T %z")
    acl="x-amz-acl:public-read"
    content_type='application/x-compressed'
    string="PUT\n\n$content_type\n$date\n$acl\n/$AWS_S3_BUCKET/$AWS_S3_PATH/$file"
    signature=$(echo -en "${string}" | openssl sha1 -hmac "${AWS_ACCESS_KEY}" -binary | base64)
    curl -v -X PUT -T "$file" \
      -H "Host: $AWS_S3_BUCKET.s3.amazonaws.com" \
      -H "Date: $date" \
      -H "Content-Type: $content_type" \
      -H "$acl" \
      -H "Authorization: AWS ${AWS_ACCESS_KEY_ID}:$signature" \
      "https://$AWS_S3_BUCKET.s3.amazonaws.com/$AWS_S3_PATH/$file"
}

function print_params(){

    declare -A params=( ["VERSION"]=$VERSION ["PRERELEASE"]=$PRERELEASE ["BUILD"]=$BUILD \
                        ["CORE_TAG_NAME"]=$CORE_TAG_NAME ["PLUGINS_TAG_NAME"]=$PLUGINS_TAG_NAME \
                        ["AWS_S3_BUCKET"]=$AWS_S3_BUCKET ["AWS_S3_PATH"]=$AWS_S3_PATH \
                        ["PLUGIN_NAME"]=$PLUGIN_NAME \
                        ["GITHUB_USERNAME"]=$GITHUB_USERNAME ["AWS_ACCESS_KEY_ID"]=$AWS_ACCESS_KEY_ID)
    for param in "${!params[@]}"
    do
            echo "$param - ${params["$param"]}"
    done
}


# VERSION/PRERELEASE/BUILD must be exported as they is being read as an env var by the cloudify-agent-packager
export VERSION="3.3.1"
export PRERELEASE="sp"
export BUILD="310"
CORE_TAG_NAME="3.3.1"
PLUGINS_TAG_NAME="1.3.1"

#env Variables
GITHUB_USERNAME=$1
GITHUB_PASSWORD=$2
AWS_ACCESS_KEY_ID=$3
AWS_ACCESS_KEY=$4
PLUGIN_NAME=$5
AWS_S3_BUCKET="gigaspaces-repository-eu"
AWS_S3_PATH="org/cloudify3/${VERSION}/${PRERELEASE}-RELEASE"




print_params
install_dependencies &&
install_wagon &&
wagon_create_package &&
md5sum=$(md5sum -t *.wgn) && echo $md5sum > ${md5sum##* }.md5 &&
[ -z ${AWS_ACCESS_KEY} ] || upload_to_s3 "*.wgn" && upload_to_s3 "*.md5"

#!/bin/bash

function __besman_init() {
    __besman_echo_white "initializing"
    export ASSESSMENT_TOOL_NAME="counterfit"
    export ASSESSMENT_TOOL_TYPE="dast"
    export ASSESSMENT_TOOL_VERSION="0.0.1"
    export ASSESSMENT_TOOL_PLAYBOOK="besman-$ASSESSMENT_TOOL_NAME-$ASSESSMENT_TOOL_VERSION-playbook.sh"
    
    local steps_file_name="besman-$ASSESSMENT_TOOL_NAME-$ASSESSMENT_TOOL_VERSION-steps.ipynb"
    export BESMAN_STEPS_FILE_PATH="$BESMAN_PLAYBOOK_DIR/$steps_file_name"

    local var_array=("BESMAN_COUNTERFIT_LOCAL_PATH" "BESMAN_COUNTERFIT_BRANCH" "BESMAN_COUNTERFIT_URL" "BESMAN_ARTIFACT_NAME" "BESMAN_ASSESSMENT_DATASTORE_DIR" "BESMAN_ARTIFACT_VERSION" "BESMAN_ARTIFACT_URL" "BESMAN_ENV_NAME" "BESMAN_LAB_TYPE" "BESMAN_LAB_NAME" "BESMAN_ASSESSMENT_DATASTORE_URL")

    local flag=false
    for var in "${var_array[@]}"; do
        if [[ ! -v $var ]]; then
            __besman_echo_yellow "$var is not set"
            __besman_echo_no_colour ""
            flag=true
        fi
    done
    
    __besman_check_url_valid $BESMAN_ARTIFACT_URL
    if [ xx"$?" != xx"0" ]; then
       __besman_echo_red "Create the model repository on github/gitlab and try again."
       __besman_echo_red "Make the the following files available in repository."
       __besman_echo_red "   1. $BESMAN_ARTIFACT_NAME.h5"
       __besman_echo_red "   2. $BESMAN_ARTIFACT_NAME.npz"
       __besman_echo_red "   3. $BESMAN_ARTIFACT_NAME.py"
       return 1
    fi

    [[ ! -d $BESMAN_COUNTERFIT_LOCAL_PATH ]] && __besman_echo_red "counterfit not found at $BESMAN_COUNTERFIT_LOCAL_PATH" && flag=true

    if [[ $flag == true ]]; then
        return 1
    else
        export DETAILED_REPORT_PATH="$BESMAN_ASSESSMENT_DATASTORE_DIR/models/$BESMAN_ARTIFACT_NAME/$ASSESSMENT_TOOL_TYPE/$BESMAN_ARTIFACT_NAME-$ASSESSMENT_TOOL_VERSION-$ASSESSMENT_TOOL_TYPE-detailed-report.json"
        export SUMMARY_REPORT_PATH="$BESMAN_ASSESSMENT_DATASTORE_DIR/models/$BESMAN_ARTIFACT_NAME/$ASSESSMENT_TOOL_TYPE/$BESMAN_ARTIFACT_NAME-$ASSESSMENT_TOOL_VERSION-$ASSESSMENT_TOOL_TYPE-summary-report.json"
	export OSAR_PATH="$BESMAN_ASSESSMENT_DATASTORE_DIR/models/$BESMAN_ARTIFACT_NAME/$BESMAN_ARTIFACT_NAME-osar.json"
        __besman_fetch_steps_file "$steps_file_name" || return 1
	__besman_fetch_source && return 1
        return 0
    fi
}

function __besman_execute() {
    local duration

    # Isolating the steps file for better use
    mkdir -p "$BESMAN_DIR/tmp/steps"
    __besman_echo_yellow "Launching steps file"
    cp "$BESMAN_STEPS_FILE_PATH" "$BESMAN_DIR/tmp/steps"
    SECONDS=0

    while true; do
      read -p "Running playbook on cloud? (y/n):" clinput
      if [ xx"$clinput" == xx"y" ];then
        if [[ ! -z $(command -v jupyter) ]];then
          [[ ! -f  $HOME/.jupyter/jupyter_notebook_config.py ]] && jupyter notebook --generate-config 2>&1>/dev/null
          [[ -f  $HOME/.jupyter/jupyter_notebook_config.py ]] && sed -i "s/# c.ServerApp.ip = 'localhost'/c.ServerApp.ip = '0.0.0.0'/g" $HOME/.jupyter/jupyter_notebook_config.py
          [[ -f  $HOME/.jupyter/jupyter_notebook_config.py ]] && sed -i "s/# c.ServerApp.open_browser = False/c.ServerApp.open_browser = False/g" $HOME/.jupyter/jupyter_notebook_config.py
        fi
        __besman_echo_cyan "Since playbook is executing on cloud so please follow below steps to execute the steps playbook."
	__besman_echo_cyan "   1. Open a separate terminal using ssh to the cloud instance."
        __besman_echo_cyan "   2. Stop and start the jupyter notebook again on the jupyter server."
        __besman_echo_cyan "   3. Capture the jupter notebook token from the screen."
        __besman_echo_cyan "   4. Enable the jupyter notebook port (usaually port 8888) on security group /firewall settings of cloud provider."
        __besman_echo_cyan "   5. Make sure the instance firewall also allowing port of jupter notebook (usually 8888) is allowed."
        __besman_echo_cyan "   6. Open the jupyter notebook ui on the browser using the instance public IP and port number used (usually 8888)."
        __besman_echo_cyan "   7. Enter the token copied above into the UI and connect."
        __besman_echo_cyan "   8. Upload the steps playbook i.e $BESMAN_DIR/tmp/steps/ to the jupyter notebook ui"
        __besman_echo_cyan "   9. Follow the notebook steps in playbook and press \"y\" for below prompt after executing all playbook steps sucessfully."
	break;
      elif [ xx"$clinput" == xx"n" ];then
         jupyter notebook "$BESMAN_DIR/tmp/steps"
         break;
      else
         __besman_echo_yellow "No a valid input. Please press \"y\" or \"n\" only."
      fi
    done 
    while true; do
        read -p "Playbook execution completed? (y/n):" userinput

	if [ xx"$userinput" == xx"y" ];then
           break;
	else
	  __besman_echo_red "Steps playbook need to be completed before proceed."
	fi
    done

    [[ ! -f $BESMAN_COUNTERFIT_LOCAL_PATH/counterfit/targets/$BESMAN_ARTIFACT_NAME.py ]] && __besman_echo_red "$BESMAN_ARTIFACT_NAME.py is required. Please follow the steps in jupyter playbook closely and copy the file to $BESMAN_COUNTERFIT_LOCAL_PATH/counterfit/targets/ folder from the model repository." && return 1
    [[ ! -f $BESMAN_COUNTERFIT_LOCAL_PATH/counterfit/targets/$BESMAN_ARTIFACT_NAME/$BESMAN_ARTIFACT_NAME.npz ]] && __besman_echo_red "$BESMAN_ARTIFACT_NAME.npz is required. Please follow the steps in jupyter playbook and copy file to $BESMAN_COUNTERFIT_LOCAL_PATH/counterfit/targets/$BESMAN_ARTIFACT_NAME/ folder from the model repository." && return 1
    [[ ! -f $BESMAN_COUNTERFIT_LOCAL_PATH/counterfit/targets/$BESMAN_ARTIFACT_NAME/$BESMAN_ARTIFACT_NAME.h5 ]] && __besman_echo_red "$BESMAN_ARTIFACT_NAME.h5 is required. please follow steps in jupyter notebook closely  and copy the file to  $BESMAN_COUNTERFIT_LOCAL_PATH/counterfit/targets/$BESMAN_ARTIFACT_NAME/ folder from the model repository." && return 1

    local attack_id=$(cat $BESMAN_DIR/tmp/attack_id)

    [[ -z $attack_id ]] && __besman_echo_red "Could not find attack_id, please complete the assessment steps of counterfit" && return 1

    export COUNTERFIT_ATTACKID=$attack_id

    # echo "attack id = $COUNTERFIT_ATTACKID"
    # source ~/.bashrc

    # [[ -z $COUNTERFIT_ATTACKID ]] && __besman_echo_red "Attack Id is not set. Required. Please set it and try again." && return 1

    [[ ! -f $BESMAN_COUNTERFIT_LOCAL_PATH/counterfit/targets/results/${COUNTERFIT_ATTACKID}/run_summary.json ]] && __besman_echo_red "Counterfit result file not found. Execute the playbook to generate the results first." && flag="true"

    duration=$SECONDS

    export EXECUTION_DURATION=$duration
    if [[ ! -f $BESMAN_COUNTERFIT_LOCAL_PATH/counterfit/targets/results/${COUNTERFIT_ATTACKID}/run_summary.json ]]; then
        export PLAYBOOK_EXECUTION_STATUS=failure
        return 1
    else
        export PLAYBOOK_EXECUTION_STATUS=success
        return 0
    fi

    rm -rf "$BESMAN_DIR/tmp/steps"
}

function __besman_prepare() {
    __besman_echo_yellow "preparing data"
    EXECUTION_TIMESTAMP=$(date)
    export EXECUTION_TIMESTAMP
    
    source ~/.bashrc
    [[ ! -d $BESMAN_ASSESSMENT_DATASTORE_DIR/models/$BESMAN_ARTIFACT_NAME/dast ]] && mkdir -p $BESMAN_ASSESSMENT_DATASTORE_DIR/models/$BESMAN_ARTIFACT_NAME/dast
    cp -f $BESMAN_COUNTERFIT_LOCAL_PATH/counterfit/targets/results/${COUNTERFIT_ATTACKID}/run_summary.json $SUMMARY_REPORT_PATH
    [[ ! -f $SUMMARY_REPORT_PATH ]] && __besman_echo_red "Could not find report @ $SUMMARY_REPORT_PATH" && return 1

    __besman_generate_osar
}


function __besman_publish() {
    __besman_echo_yellow "Pushing to datastore"
    cd "$BESMAN_ASSESSMENT_DATASTORE_DIR"

    git add models/$BESMAN_ARTIFACT_NAME/*
    git commit -m "Added SAST and OSAR reports for $BESMAN_ARTIFACT_NAME"
    git push origin main

    [[ -d $BESMAN_ARTIFACT_NAME ]] && rm -rf $BESMAN_ARTIFACT_NAME
}

function __besman_cleanup() {
    local var_array=("ASSESSMENT_TOOL_NAME" "ASSESSMENT_TOOL_TYPE" "ASSESSMENT_TOOL_VERSION" "ASSESSMENT_TOOL_PLAYBOOK" "BESMAN_STEPS_FILE_PATH" "DETAILED_REPORT_PATH" "OSAR_PATH" "EXECUTION_TIMESTAMP" "EXECUTION_DURATION")

    for var in "${var_array[@]}"; do
        if [[ -v $var ]]; then
            unset "$var"
        fi
    done
    [[ -f $BESMAN_DIR/tmp/attack_id ]] && rm "$BESMAN_DIR/tmp/attack_id"
    sed -i "/export COUNTERFIT_ATTACKID=/d" ~/.bashrc

    [[ -v $COUNTERFIT_ATTACKID ]] && unset $COUNTERFIT_ATTACKID
    [[ -d $BESMAN_ARTIFACT_NAME ]] && rm -rf $BESMAN_ARTIFACT_NAME
}

function __besman_launch() {
    __besman_echo_yellow "Starting playbook"
    local flag=1

    __besman_init
    flag=$?

    if [[ $flag == 0 ]]; then
        __besman_execute
        flag=$?
    else
        __besman_cleanup
        return
    fi

    if [[ $flag == 0 ]]; then
        __besman_prepare
        __besman_publish
        __besman_cleanup
    else
        __besman_cleanup
        return
    fi
}

function __besman_fetch_steps_file() {
    echo "Fetching steps file"
    local steps_file_name=$1
    local steps_file_url="https://raw.githubusercontent.com/$BESMAN_PLAYBOOK_REPO/$BESMAN_PLAYBOOK_REPO_BRANCH/playbooks/$steps_file_name"
    __besman_check_url_valid "$steps_file_url" || return 1

    if [[ ! -f "$BESMAN_STEPS_FILE_PATH" ]]; then
        touch "$BESMAN_STEPS_FILE_PATH"
        __besman_secure_curl "$steps_file_url" >>"$BESMAN_STEPS_FILE_PATH"
        [[ "$?" != "0" ]] && echo "Failed to fetch from $steps_file_url" && return 1
    fi
    echo "Done fetching"
}

function __besman_fetch_source() {
    __besman_echo_no_colour "Fetching model files"

    git clone --quiet $BESMAN_ARTIFACT_URL
    [[ ! -d $BESMAN_ARTIFACT_NAME ]] && __besman_echo_red "Not able to download the model repository." && return 1
    #rm -rf $BESMAN_ARTIFACT_NAME
}

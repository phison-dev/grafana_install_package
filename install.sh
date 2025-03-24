#!/bin/bash

#### LOG File
LOG_FILE="/var/log/grafana_install.log"

#### Get Current Path, do not contains specical charactor
GRAFANA_INSTALL_DIR=$(dirname "$(readlink -f "$0")")
if [[ $GRAFANA_INSTALL_DIR == *[' ''!''?'@#\$%^\&*()+]* ]]; then
    echo -e "$(date +%F\ %T) : Folder directory has specical character, please do not used specical character to naming folder"
    exit 1
fi

#### Grafana Related
GRAFANA_LISTEN_PORT_ON_HOST=3000
VERSION_TAG=GIP_1.4.0
GRAFANA_DOWNLOAD_LINK="https://github.com/phison-dev/grafana_install_package_v2/releases/download/$VERSION_TAG/grafana.tar"
OTEL_DOWNLOAD_LINK="https://github.com/phison-dev/grafana_install_package_v2/releases/download/$VERSION_TAG/otel.tar"
TEMPO_DOWNLOAD_LINK="https://github.com/phison-dev/grafana_install_package_v2/releases/download/$VERSION_TAG/tempo.tar"

#### Docker configure
DOCKER_NETWORK="phison-network"
DOCKER_COMPOSE_FILE="$GRAFANA_INSTALL_DIR/grafana-compose.yaml"
DOCKER_CONFIG_ENV="$GRAFANA_INSTALL_DIR/grafana-config.env"
DOCKER_IMAGE_ENV="$GRAFANA_INSTALL_DIR/grafana-image.env"
DOCKER_COMPOSE_CLI="docker compose --env-file $DOCKER_CONFIG_ENV --env-file $DOCKER_IMAGE_ENV --file $DOCKER_COMPOSE_FILE"
# Initialization function
function init() {
    check_root
    check_log_exist
}

#### Check whether the executing user is Root user
function check_root() {
    if [ "$(id -u)" != "0" ]; then
        msg1="Please execute this script with root privileges."
        msg2="Grafana not installed, Exited."
        echo -e "$(date +%F\ %T) : [error] $msg1"
        echo -e "$(date +%F\ %T) : [error] $msg2"
        exit 1
    else
        echo -e "$(date +%F\ %T) : [isunfo] Confirm that script is started by the root user."
    fi
}

#### Print log and to log file
function LOG() {
    logLevel=$1
    logMsg=$2
    echo -e "$(date +%F\ %T) : [$logLevel] $logMsg" >> "$LOG_FILE" 2>&1
    echo -e "$(date +%F\ %T) : [$logLevel] $logMsg"
}

#### Check if the folder and file exists
function check_log_exist() {
    if [ ! -f "$LOG_FILE" ]; then
        /usr/bin/touch "$LOG_FILE"
    fi
}

function ask_question() {
    local question="$1"
    local result

    read -p "$question (Yes/No): " answer
    answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
    if [ "$answer" = "yes" ] || [ "$answer" = "y" ]; then
        result=0
    elif [ "$answer" = "no" ] || [ "$answer" = "n" ]; then
        result=1
    else
        echo "(Yes/No)。"
        result=$(ask_question "$question")
    fi

    echo "$result"
}

#### Docker compose ####
function dc_startup() {
    $DOCKER_COMPOSE_CLI up -d
    result=$?

    LOG "info" "Startup Grafana services."
    if [[ "$result" -eq 0 ]]; then
        install_finished
    else
        LOG "error" "Failed start Grafana Service $($DOCKER_COMPOSE_CLI up -d)."
    fi
}

function dc_stop() {
    remove_image=$1
    service_list=($($DOCKER_COMPOSE_CLI ps --services))

    ## If service list not empty, means docker compose can identify Grafana
    if [ ${#service_list[@]} -ne 0 ]; then
        if [[ "$remove_image" == "rmi" ]];then
            LOG "info" "Stop Grafana services and remove inuse docker images."
            $($DOCKER_COMPOSE_CLI down --remove-orphans --rmi all)	
        else
            LOG "info" "Stop Grafana services by docker compose."
            $($DOCKER_COMPOSE_CLI down --remove-orphans)
        fi

        result=$?
        if [[ "$result" -ne 0 ]]; then
		    LOG "error" "Failed stop Grafana Service"
        fi
    fi
    
    ## Check by name
    LOG "info" "Check docker container by name."
    while IFS= read -r line; do
        CID=$(docker ps -a -q -f name=$line)
        if [ ! -z $CID ]; then
            LOG "info" "Remove container $line."
            docker rm -f $line > /dev/null 2>&1
        fi
    done < <(cat $DOCKER_COMPOSE_FILE | grep container_name | awk '{print $2}')
}

#### Create phison-network
function create_docker_network() {
    docker network ls | grep -q $DOCKER_NETWORK
    result=$?
    if [[ "$result" -ne 0 ]]; then
        LOG "info" "Create docker network $DOCKER_NETWORK."
        docker network create "$DOCKER_NETWORK" >> /dev/null

        result=$?
        if [[ "$result" -eq 0 ]]; then
            subnet=$(docker network inspect $DOCKER_NETWORK | jq -r '.[0].IPAM.Config[0].Subnet')
            LOG "info" "Success create $DOCKER_NETWORK with subnet $subnet."
        else
            LOG_AND_EXIT "info" "Failed create $DOCKER_NETWORK with subnet $subnet." "1"
        fi
    fi
}

#### Docker relate ####
function config_docker() {
    LOG "info" "Config docker /etc/docker/daemon.json"
    if [[ -d /etc/docker ]]; then
        if [[ ! -f /etc/docker/daemon.json ]]; then
            cp "$GRAFANA_INSTALL_DIR"/config/docker/daemon.json /etc/docker/daemon.json
        fi
    fi
}

#### Normal install
#### Pull docker image from docherhub
function pull_docker_image() {

	while IFS= read -r line; do
		LOG "info" "Docker start loading image: $line"
        CID=$(docker load -i $GRAFANA_INSTALL_DIR/$line)
    done < <(ls $GRAFANA_INSTALL_DIR | grep tar | awk '{print $1}')
}

#### After startup
function install_finished() {
    LOG "info" "http://localhost:$GRAFANA_LISTEN_PORT_ON_HOST"
    LOG "info" "http://127.0.0.1:$GRAFANA_LISTEN_PORT_ON_HOST"

    IFS=' ' read -r -a ip_array <<< "$(hostname -I)"
    for ip_addr in "${ip_array[@]}"; do
        LOG "info" "http://$ip_addr:$GRAFANA_LISTEN_PORT_ON_HOST"
    done
}

#### Uninstall ####
function uninstall() {    
    local upgrade_image="$1"
	
	if [[ "$upgrade_image" == "upgrade" ]]; then
		LOG "info" "Unstall Grafana-related services."
		dc_stop
		while IFS= read -r line; do
			LOG "info" "Remove image id: $line."
			docker rmi -f $line 
		done < <(docker image ls | grep -e grafana -e opentelemetry-collector | awk '{print $3}')		
	else
		## Ask if remove docker image
		msg="Do you want to remove Grafana docker image ?"
		result=$(ask_question "$msg")

		if [[ "$result" -eq 0 ]]; then
			rm_image=TRUE
		else
			return 1
		fi
		LOG "info" "Remove docker image that Grafana used: $rm_image."

		## Start uninstall
		if [ "$rm_image" == "TRUE" ]; then
			dc_stop "rmi"
		else
			dc_stop
		fi
	fi
    LOG "info" "Finish uninstall Grafana."
}

function download_package(){
	wget $GRAFANA_DOWNLOAD_LINK -O grafana.tar
	wget $TEMPO_DOWNLOAD_LINK -O tempo.tar
	wget $OTEL_DOWNLOAD_LINK -O otel.tar
	LOG "info" "Finish download Grafana-related image"
}

# Function to display menu options
function display_menu() {
    echo "Select an option:"
    printf "%-40s %-40s\n" " 0) Download Grafana Packages" "Download Grafana-related docker packages."
    printf "%-40s %-40s\n" " 1) Install Grafana" "Install Grafana-related packages."
    printf "%-40s %-40s\n" " 2) Upgrade Grafana all services" "Upgrade Grafana to the previous installation package version."
    printf "%-40s %-40s\n" " 3) Start Grafana all services" "Startup Grafana-related service."
    printf "%-40s %-40s\n" " 4) Stop Grafana all services" "Stop Grafana-related service."
    printf "%-40s %-40s\n" " 5) Restart Grafana all services" "Restart Grafana-related service."
    printf "%-40s %-40s\n" " 6) Uninstall Grafana all services" "Stop and uninstall Grafana-related packages."
    printf "%-40s %-40s\n" " 7) Exit Script" "Exit."
}

# Function to handle user selection
function handle_selection() {
    local selectAction=$1
    case "$selectAction" in
		0)
            download_package
            ;;
        1)
            ## Stop Grafana container if docker cli exist
            if command -v docker &> /dev/null; then
                LOG "info" "Docker CLI exists, stopping Grafana container."
                dc_stop
            fi

            ## Docker config
            config_docker
            create_docker_network
            pull_docker_image
            dc_startup
            ;;
        2)
            uninstall "upgrade"
            pull_docker_image
            dc_startup
            ;;
        3)
            dc_startup
            ;;
        4)
            dc_stop
            ;;
        5)
            dc_stop
            sleep 5
            dc_startup
            ;;
        6)
            uninstall
            ;;
        7)
            LOG "Exiting script."
            exit 0
            ;;
        *)
            LOG "warning" "$selectAction: invalid selection."
            ;;
    esac
}

function main() {
    init
    display_menu
    read -r -p "Option: " selectAction
    until [[ "$selectAction" =~ ^[0-9]$|10$ ]]; do
        LOG "warning" "$selectAction: invalid selection."
        read -r -p "Option: " selectAction
        printf "\n"
    done
    handle_selection "$selectAction"
}


MODE="cli"

#### Start main
LOG "info" "Grafana install in $MODE mode."
main

# Grafana_Install_Package

## Getting started
This is about the docker installation packages related to Grafana, Tempo, and Otel. Please follow the instructions below for installation

## Installation
Please place this folder at the same hierarchy as Pro Suite and execute the following command:
```
sudo ./install.sh
```
## Installation Options
0. Install Grafana-related packages.
1. Upgrade Grafana to the previous installation package version.
>Note : Need to download the latest version and overwrite this local folder.
2. Startup Grafana-related service.
3. Stop Grafana-related service.
4. Restart Grafana-related service.
>Note : If you need to update the newest grafana dashboard, you can download latest version dashboard from ***./config/grafana*** and overwrite the local files before restarting the service
5. Stop and uninstall Grafana-related packages.
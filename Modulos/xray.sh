#!/bin/bash
# EDIT: @TURBONET2023
# github: https://github.com/PhoenixxZ2023/NEW-SSHPLUS

#定时任务北京执行时间(0~23)
BEIJING_UPDATE_TIME=3

#记录最开始运行脚本的路径
BEGIN_PATH=$(pwd)

#安装方式, 0为全新安装, 1为保留xray配置更新
INSTALL_WAY=0

#定义操作变量, 0为否, 1为是
HELP=0
REMOVE=0
CHINESE=0
V2RAY_MODE=0  # Novo: 0 para XRay (padrão), 1 para V2Ray

BASE_SOURCE_PATH="https://multi.netlify.app"

UTIL_PATH="/etc/xray_util/util.cfg"  # Ajustado para xray_util
UTIL_CFG="$BASE_SOURCE_PATH/xray_util/util_core/util.cfg"  # Ajustado para xray_util

BASH_COMPLETION_SHELL="$BASE_SOURCE_PATH/xray"  # Ajustado para xray

CLEAN_IPTABLES_SHELL="$BASE_SOURCE_PATH/xray_util/global_setting/clean_iptables.sh"  # Ajustado para xray_util

# Novo link do go.sh hospedado no GitHub
GO_SH_URL="https://raw.githubusercontent.com/PhoenixxZ2023/NEW-SSHPLUS/main/Modulos/go.sh"

#Centos 临时取消别名
[[ -f /etc/redhat-release && -z $(echo $SHELL|grep zsh) ]] && unalias -a

[[ -z $(echo $SHELL|grep zsh) ]] && ENV_FILE=".bashrc" || ENV_FILE=".zshrc"

#######color code########
RED="31m"
GREEN="32m"
YELLOW="33m"
BLUE="36m"
FUCHSIA="35m"

colorEcho(){
    COLOR=$1
    echo -e "\033[${COLOR}${@:2}\033[0m"
}

#######get params#########
while [[ $# > 0 ]];do
    key="$1"
    case $key in
        --remove)
        REMOVE=1
        ;;
        -h|--help)
        HELP=1
        ;;
        -k|--keep)
        INSTALL_WAY=1
        colorEcho ${BLUE} "keep config to update\n"
        ;;
        --zh)
        CHINESE=1
        colorEcho ${BLUE} "安装中文版..\n"
        ;;
        --v2ray)  # Novo parâmetro para forçar V2Ray
        V2RAY_MODE=1
        colorEcho ${BLUE} "Installing V2Ray instead of XRay\n"
        ;;
        *)
                # unknown option
        ;;
    esac
    shift # past argument or value
done
#############################

help(){
    echo "bash xray.sh [-h|--help] [-k|--keep] [--remove] [--v2ray]"
    echo "  -h, --help           Show help"
    echo "  -k, --keep           keep the config.json to update"
    echo "      --remove         remove xray (or v2ray with --v2ray)"
    echo "      --v2ray          install V2Ray instead of XRay"
    echo "                       no params to new install XRay"
    return 0
}

removeXRay() {
    # Definir variáveis com base no modo (XRay ou V2Ray)
    if [[ $V2RAY_MODE == 1 ]]; then
        KEY="v2ray"
        CONFIG_PATH="/etc/v2ray"
        LOG_PATH="/var/log/v2ray"
        GO_PARAM=""
    else
        KEY="xray"
        CONFIG_PATH="/etc/xray"
        LOG_PATH="/var/log/xray"
        GO_PARAM="--xray"
    fi

    # Parar e desativar o serviço
    systemctl stop $KEY >/dev/null 2>&1
    systemctl disable $KEY >/dev/null 2>&1

    # Remover usando go.sh
    bash <(curl -L -s "$GO_SH_URL") --remove $GO_PARAM >/dev/null 2>&1

    # Limpar arquivos de configuração e logs
    rm -rf $CONFIG_PATH >/dev/null 2>&1
    rm -rf $LOG_PATH >/dev/null 2>&1

    # Limpar regras de iptables
    bash <(curl -L -s $CLEAN_IPTABLES_SHELL)

    # Remover utilitários
    pip uninstall xray_util -y >/dev/null 2>&1
    rm -rf /usr/share/bash-completion/completions/$KEY >/dev/null 2>&1
    rm -rf /etc/bash_completion.d/$KEY.bash >/dev/null 2>&1
    rm -rf /usr/local/bin/$KEY >/dev/null 2>&1
    rm -rf /etc/xray_util >/dev/null 2>&1

    # Remover tarefas cron
    crontab -l | sed "/$KEY/d" > crontab.txt
    crontab crontab.txt >/dev/null 2>&1
    rm -f crontab.txt >/dev/null 2>&1

    # Reiniciar serviço cron
    if [[ ${PACKAGE_MANAGER} == 'dnf' || ${PACKAGE_MANAGER} == 'yum' ]]; then
        systemctl restart crond >/dev/null 2>&1
    else
        systemctl restart cron >/dev/null 2>&1
    fi

    # Limpar variáveis de ambiente
    sed -i "/$KEY/d" ~/$ENV_FILE
    source ~/$ENV_FILE

    colorEcho ${GREEN} "Uninstalled $KEY successfully!"
}

closeSELinux() {
    # Desativar SELinux
    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        setenforce 0
    fi
    if command -v getenforce >/dev/null && [ "$(getenforce)" = "Enforcing" ]; then
        colorEcho ${YELLOW} "SELinux is still enforcing. Forcing disable."
        setenforce 0
        if [ $? -ne 0 ]; then
            colorEcho ${RED} "Failed to disable SELinux. This may cause permission issues."
        fi
    fi
}

checkSys() {
    # Verificar se é root
    [ $(id -u) != "0" ] && { colorEcho ${RED} "Error: You must be root to run this script"; exit 1; }

    if [[ `command -v apt-get` ]]; then
        PACKAGE_MANAGER='apt-get'
    elif [[ `command -v dnf` ]]; then
        PACKAGE_MANAGER='dnf'
    elif [[ `command -v yum` ]]; then
        PACKAGE_MANAGER='yum'
    else
        colorEcho $RED "Not support OS!"
        exit 1
    fi
}

installDependent() {
    if [[ ${PACKAGE_MANAGER} == 'dnf' || ${PACKAGE_MANAGER} == 'yum' ]]; then
        ${PACKAGE_MANAGER} install socat crontabs bash-completion which -y
    else
        ${PACKAGE_MANAGER} update
        ${PACKAGE_MANAGER} install socat cron bash-completion ntpdate -y
    fi

    # Instalar python3 e pip
    source <(curl -sL https://python3.netlify.app/install.sh)
    if ! command -v pip >/dev/null 2>&1; then
        colorEcho ${RED} "Failed to install pip. Please install Python and pip manually."
        exit 1
    fi
}

updateProject() {
    # Verificar se o pip está instalado
    [[ ! $(type pip 2>/dev/null) ]] && colorEcho $RED "pip not installed!" && exit 1

    # Limpar instalações anteriores
    if [[ ${INSTALL_WAY} == 0 ]]; then
        colorEcho ${BLUE} "Cleaning up previous installations..."
        rm -rf /usr/bin/xray /usr/bin/v2ray /usr/local/bin/xray /usr/local/bin/v2ray >/dev/null 2>&1
    fi

    # Instalar ou atualizar xray_util
    pip install -U xray_util

    if ! pip show xray_util >/dev/null 2>&1; then
        colorEcho ${RED} "Failed to install xray_util. Please check your pip installation and try again."
        exit 1
    fi

    # Configurar utilitários
    if [[ -e $UTIL_PATH ]]; then
        [[ -z $(cat $UTIL_PATH|grep lang) ]] && echo "lang=en" >> $UTIL_PATH
    else
        mkdir -p /etc/xray_util
        curl $UTIL_CFG > $UTIL_PATH
    fi

    [[ $CHINESE == 1 ]] && sed -i "s/lang=en/lang=zh/g" $UTIL_PATH

    # Criar links simbólicos
    rm -f /usr/local/bin/xray >/dev/null 2>&1
    ln -s $(which xray-util) /usr/local/bin/xray
    if [[ $V2RAY_MODE == 1 ]]; then
        rm -f /usr/local/bin/v2ray >/dev/null 2>&1
        ln -s $(which xray-util) /usr/local/bin/v2ray
    fi

    # Remover scripts de autocompletar antigos
    [[ -e /etc/bash_completion.d/xray.bash ]] && rm -f /etc/bash_completion.d/xray.bash
    [[ -e /usr/share/bash-completion/completions/xray.bash ]] && rm -f /usr/share/bash-completion/completions/xray.bash

    # Atualizar scripts de autocompletar
    curl $BASH_COMPLETION_SHELL > /usr/share/bash-completion/completions/xray
    if [[ $V2RAY_MODE == 1 ]]; then
        curl $BASH_COMPLETION_SHELL > /usr/share/bash-completion/completions/v2ray
    fi
    if [[ -z $(echo $SHELL|grep zsh) ]]; then
        source /usr/share/bash-completion/completions/xray
        [[ $V2RAY_MODE == 1 ]] && source /usr/share/bash-completion/completions/v2ray
    fi

    # Instalar núcleo XRay (ou V2Ray, se especificado)
    if [[ ${INSTALL_WAY} == 0 ]]; then
        if [[ $V2RAY_MODE == 1 ]]; then
            bash <(curl -L -s "$GO_SH_URL")
        else
            bash <(curl -L -s "$GO_SH_URL") --xray
        fi
        if [[ $? -ne 0 ]]; then
            colorEcho ${RED} "Failed to install using go.sh. Please check your network or the script at $GO_SH_URL."
            exit 1
        fi
    fi
}

timeSync() {
    if [[ ${INSTALL_WAY} == 0 ]]; then
        colorEcho ${BLUE} "Time Synchronizing..."
        if [[ `command -v ntpdate` ]]; then
            ntpdate pool.ntp.org
        elif [[ `command -v chronyc` ]]; then
            chronyc -a makestep
        fi

        if [[ $? -eq 0 ]]; then 
            colorEcho ${GREEN} "Time Sync Success"
            colorEcho ${GREEN} "Now: `date -R`"
        else
            colorEcho ${YELLOW} "Time synchronization failed. This may cause issues with network requests."
        fi
    fi
}

profileInit() {
    # Limpar variáveis de ambiente antigas
    [[ $(grep xray ~/$ENV_FILE) ]] && sed -i '/xray/d' ~/$ENV_FILE
    [[ $(grep v2ray ~/$ENV_FILE) ]] && sed -i '/v2ray/d' ~/$ENV_FILE
    source ~/$ENV_FILE

    # Configurar codificação Python
    [[ -z $(grep PYTHONIOENCODING=utf-8 ~/$ENV_FILE) ]] && echo "export PYTHONIOENCODING=utf-8" >> ~/$ENV_FILE && source ~/$ENV_FILE

    # Criar nova configuração
    [[ ${INSTALL_WAY} == 0 ]] && xray new
}

installFinish() {
    cd ${BEGIN_PATH}
    [[ ${INSTALL_WAY} == 0 ]] && WAY="install" || WAY="update"
    colorEcho ${GREEN} "XRay ${WAY} success!\n"

    if [[ ${INSTALL_WAY} == 0 ]]; then
        clear
        echo -e "\n\033[1;32mXRAY INSTALADO COM SUCESSO !\033[0m"
        xray info
        echo -e "Por favor insira o comando 'xray' para gerenciar XRay\n"
    fi
}

main() {
    [[ ${HELP} == 1 ]] && help && return
    [[ ${REMOVE} == 1 ]] && removeXRay && return
    [[ ${INSTALL_WAY} == 0 ]] && colorEcho ${BLUE} "new install XRay\n"

    checkSys
    installDependent
    closeSELinux
    timeSync
    updateProject
    profileInit
    installFinish
}

main

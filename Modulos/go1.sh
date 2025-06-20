#!/bin/bash
# EDIT: Adaptado para XRay por Grok
# Acessível como https://multi.netlify.app/go.sh (original), modificado para XRay
# MODIFICAÇÃO: VLESS + XTLS por padrão em novas instalações.

# Códigos de retorno:
# 0: Sucesso
# 1: Erro de sistema
# 2: Erro de aplicativo
# 3: Erro de rede

# Argumentos CLI
proxy=''
help=''
force=''
check=''
remove=''
version=''
xsrc_root='/tmp/xray'
extract_only=''
local=''
local_install=''
error_if_uptodate=''

cur_ver=""
new_ver=""
zipfile="/tmp/xray/xray.zip"
xray_running=0

cmd_install=""
cmd_update=""
software_updated=0
key="Xray"
key_lower="xray"
repos="XTLS/Xray-core"

systemctl_cmd=$(command -v systemctl 2>/dev/null)

####### Códigos de cores #######
red="31m"      # Erro
green="32m"    # Sucesso
yellow="33m"   # Aviso
blue="36m"     # Info

#########################
while [[ $# > 0 ]]; do
    case "$1" in
        -p|--proxy)
        proxy="-x ${2}"
        shift
        ;;
        -h|--help)
        help="1"
        ;;
        -f|--force)
        force="1"
        ;;
        -c|--check)
        check="1"
        ;;
        --remove)
        remove="1"
        ;;
        --version)
        version="$2"
        shift
        ;;
        --extract)
        xsrc_root="$2"
        shift
        ;;
        --extractonly)
        extract_only="1"
        ;;
        -l|--local)
        local="$2"
        local_install="1"
        shift
        ;;
        --errifuptodate)
        error_if_uptodate="1"
        ;;
        *)
        ;;
    esac
    shift
done

colorEcho(){
    echo -e "\033[${1}${@:2}\033[0m" 1>& 2
}

archAffix(){
    case "$(uname -m)" in
      'i386' | 'i686')
        machine='32'
        ;;
      'amd64' | 'x86_64')
        machine='64'
        ;;
      'armv5tel')
        machine='arm32-v5'
        ;;
      'armv6l')
        machine='arm32-v6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || machine='arm32-v5'
        ;;
      'armv7' | 'armv7l')
        machine='arm32-v7a'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || machine='arm32-v5'
        ;;
      'armv8' | 'aarch64')
        machine='arm64-v8a'
        ;;
      'mips')
        machine='mips32'
        ;;
      'mipsle')
        machine='mips32le'
        ;;
      'mips64')
        machine='mips64'
        ;;
      'mips64le')
        machine='mips64le'
        ;;
      'ppc64')
        machine='ppc64'
        ;;
      'ppc64le')
        machine='ppc64le'
        ;;
      'riscv64')
        machine='riscv64'
        ;;
      's390x')
        machine='s390x'
        ;;
        *)
        echo "Erro: Arquitetura não suportada."
        exit 1
        ;;
    esac
    return 0
}

zipRoot() {
    unzip -lqq "$1" | awk -e '
        NR == 1 {
            prefix = $4;
        }
        NR != 1 {
            prefix_len = length(prefix);
            cur_len = length($4);
            for (len = prefix_len < cur_len ? prefix_len : cur_len; len >= 1; len -= 1) {
                sub_prefix = substr(prefix, 1, len);
                sub_cur = substr($4, 1, len);
                if (sub_prefix == sub_cur) {
                    prefix = sub_prefix;
                    break;
                }
            }
            if (len == 0) {
                prefix = "";
                nextfile;
            }
        }
        END {
            print prefix;
        }
    '
}

downloadXRay(){
    rm -rf /tmp/xray
    mkdir -p /tmp/xray
    download_link="https://github.com/$repos/releases/download/${new_ver}/Xray-linux-${machine}.zip"
    colorEcho ${blue} "Baixando XRay: ${download_link}"
    curl ${proxy} -L -H "Cache-Control: no-cache" -o ${zipfile} ${download_link}
    if [ $? != 0 ]; then
        colorEcho ${red} "Falha no download! Verifique a rede ou tente novamente."
        return 3
    fi
    if ! unzip -t "$zipfile" >/dev/null 2>&1; then
        colorEcho ${red} "Arquivo baixado não é um ZIP válido. Verifique a rede ou tente novamente."
        return 3
    fi
    return 0
}

installSoftware(){
    component=$1
    if [[ -n `command -v $component` ]]; then
        return 0
    fi
    getPMT
    if [[ $? -eq 1 ]]; then
        colorEcho ${red} "O gerenciador de pacotes não é APT, YUM ou ZYPPER. Instale ${component} manualmente."
        return 1
    fi
    if [[ $software_updated -eq 0 ]]; then
        colorEcho ${blue} "Atualizando repositórios"
        $cmd_update
        software_updated=1
    fi
    colorEcho ${blue} "Instalando ${component}"
    $cmd_install $component
    if [[ $? -ne 0 ]]; then
        colorEcho ${red} "Falha ao instalar ${component}. Instale manualmente."
        return 1
    fi
    return 0
}

getPMT(){
    if [[ -n `command -v apt-get` ]]; then
        cmd_install="apt-get -y -qq install"
        cmd_update="apt-get -qq update"
    elif [[ -n `command -v yum` ]]; then
        cmd_install="yum -y -q install"
        cmd_update="yum -q makecache"
    elif [[ -n `command -v zypper` ]]; then
        cmd_install="zypper -y install"
        cmd_update="zypper ref"
    else
        return 1
    fi
    return 0
}

normalizeVersion() {
    if [ -n "$1" ]; then
        case "$1" in
            v*)
                echo "$1"
            ;;
            *)
                echo "v$1"
            ;;
        esac
    else
        echo ""
    fi
}

getVersion(){
    if [[ -n "$version" ]]; then
        new_ver="$(normalizeVersion "$version")"
        return 4
    else
        ver="$(/usr/bin/xray/xray -version 2>/dev/null)"
        [[ -z $ver ]] && ver="$(/usr/bin/xray/xray version 2>/dev/null)"
        retval=$?
        cur_ver="$(normalizeVersion "$(echo "$ver" | head -n 1 | cut -d " " -f2)")"
        tag_url="https://api.github.com/repos/$repos/releases/latest"
        new_ver="$(normalizeVersion "$(curl ${proxy} -H "Accept: application/json" -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:74.0) Gecko/20100101 Firefox/74.0" -s "${tag_url}" --connect-timeout 10| grep 'tag_name' | cut -d\" -f4)")"
        if [[ $? -ne 0 ]] || [[ $new_ver == "" ]]; then
            colorEcho ${red} "Falha ao obter informações de versão. Verifique a rede ou tente novamente."
            return 3
        elif [[ $retval -ne 0 ]]; then
            return 2
        elif [[ $new_ver != $cur_ver ]]; then
            return 1
        fi
        return 0
    fi
}

stopXray(){
    colorEcho ${blue} "Desligando serviço XRay."
    if [[ -n "${systemctl_cmd}" ]] && { [[ -f "/lib/systemd/system/xray.service" ]] || [[ -f "/etc/systemd/system/xray.service" ]]; }; then
        if ${systemctl_cmd} is-active --quiet xray; then
            ${systemctl_cmd} stop xray
            if [[ $? -ne 0 ]]; then
                colorEcho ${yellow} "Falha ao desligar serviço XRay."
                return 2
            fi
        else
            colorEcho ${yellow} "Serviço XRay não está em execução."
        fi
    else
        colorEcho ${yellow} "Serviço XRay não instalado."
    fi
    return 0
}

startXray(){
    if [ -n "${systemctl_cmd}" ] && [[ -f "/lib/systemd/system/xray.service" || -f "/etc/systemd/system/xray.service" ]]; then
        ${systemctl_cmd} start xray
    fi
    if [[ $? -ne 0 ]]; then
        colorEcho ${yellow} "Falha ao iniciar serviço XRay."
        return 2
    fi
    return 0
}

installXRay(){
    mkdir -p /etc/xray /var/log/xray && \
    unzip -oj "$1" "$2xray" "$2geoip.dat" "$2geosite.dat" -d /usr/bin/xray && \
    chmod +x /usr/bin/xray/xray || {
        colorEcho ${red} "Falha ao copiar binários e recursos do XRay."
        return 1
    }

    # Bloco modificado para VLESS + XTLS por padrão
    if [ ! -f /etc/xray/config.json ]; then
        # Pede ao usuário o domínio, que é essencial para o TLS/XTLS
        local DOMAIN=""
        while [[ -z "$DOMAIN" ]]; do
          colorEcho ${yellow} "Para VLESS + XTLS, é necessário um nome de domínio."
          read -p "Por favor, digite seu domínio: " DOMAIN
          if [[ -z "$DOMAIN" ]]; then
            colorEcho ${red} "O domínio não pode ser vazio."
          fi
        done

        # Gera um certificado auto-assinado para o domínio informado
        colorEcho ${blue} "Gerando certificado TLS para o domínio: ${DOMAIN}..."
        /usr/bin/xray/xray cert --domain "$DOMAIN" --name "Xray" --organization "Xray" --expire 3650d --ca >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            colorEcho ${red} "Falha ao gerar o certificado."
            return 1
        fi
        mv cert.pem /etc/xray/xray.crt
        mv key.pem /etc/xray/xray.key
        
        # Gera uma porta e um UUID
        local port="443"
        local uuid="$(cat '/proc/sys/kernel/random/uuid')"

        # Cria o config.json já com VLESS + XTLS-Vision
        cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
          "alpn": [
            "h2",
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/xray/xray.crt",
              "keyFile": "/etc/xray/xray.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
        colorEcho ${green} "Configuração VLESS + XTLS-Vision criada com sucesso!"
        colorEcho ${blue} "Domínio: ${DOMAIN}"
        colorEcho ${blue} "Porta: ${port}"
        colorEcho ${blue} "UUID: ${uuid}"
        colorEcho ${blue} "Flow: xtls-rprx-vision"
    fi
}

installInitScript(){
    if [[ -e /.dockerenv ]]; then
        return
    fi
    if [[ ! -f "/etc/systemd/system/xray.service" && ! -f "/lib/systemd/system/xray.service" ]]; then
        cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=XRay Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/bin/xray/xray run -c /etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable xray.service
    fi
}

Help(){
    cat - 1>& 2 << EOF
./go1.sh [-h] [-c] [--remove] [-p proxy] [-f] [--version vx.y.z] [-l file]
  -h, --help            Mostrar ajuda
  -p, --proxy           Baixar via proxy, ex.: -p socks5://127.0.0.1:1080
  -f, --force           Forçar instalação
  --version             Instalar versão específica, ex.: --version v1.8.4
  -l, --local           Instalar de arquivo local
  --remove              Remover XRay instalado
  -c, --check           Verificar atualizações
EOF
}

remove(){
    if [[ -n "${systemctl_cmd}" ]] && [[ -f "/etc/systemd/system/xray.service" ]]; then
        if pgrep "xray" > /dev/null ; then
            stopXray
        fi
        systemctl disable xray.service
        rm -rf "/usr/bin/xray" "/etc/systemd/system/xray.service"
        if [[ $? -ne 0 ]]; then
            colorEcho ${red} "Falha ao remover XRay."
            return 0
        else
            colorEcho ${green} "XRay removido com sucesso."
            colorEcho ${blue} "Se necessário, remova arquivos de configuração e log manualmente."
            return 0
        fi
    elif [[ -n "${systemctl_cmd}" ]] && [[ -f "/lib/systemd/system/xray.service" ]]; then
        if pgrep "xray" > /dev/null ; then
            stopXray
        fi
        systemctl disable xray.service
        rm -rf "/usr/bin/xray" "/lib/systemd/system/xray.service"
        if [[ $? -ne 0 ]]; then
            colorEcho ${red} "Falha ao remover XRay."
            return 0
        else
            colorEcho ${green} "XRay removido com sucesso."
            colorEcho ${blue} "Se necessário, remova arquivos de configuração e log manualmente."
            return 0
        fi
    else
        colorEcho ${yellow} "XRay não encontrado."
        return 0
    fi
}

checkUpdate(){
    echo "Verificando atualizações."
    version=""
    getVersion
    retval="$?"
    if [[ $retval -eq 1 ]]; then
        colorEcho ${blue} "Nova versão ${new_ver} encontrada para XRay. (Versão atual: ${cur_ver})"
    elif [[ $retval -eq 0 ]]; then
        colorEcho ${blue} "Nenhuma atualização. Versão atual é ${new_ver}."
    elif [[ $retval -eq 2 ]]; then
        colorEcho ${yellow} "XRay não instalado."
        colorEcho ${blue} "A versão mais recente para XRay é ${new_ver}."
    fi
    return 0
}

main(){
    [[ "$help" == "1" ]] && Help && return
    [[ "$check" == "1" ]] && checkUpdate && return
    [[ "$remove" == "1" ]] && remove && return

    local arch=$(uname -m)
    archAffix

    if [[ $local_install -eq 1 ]]; then
        colorEcho ${yellow} "Instalando XRay via arquivo local. Certifique-se de que é um pacote XRay válido."
        new_ver=local
        rm -rf /tmp/xray
        zipfile="$local"
    else
        installSoftware "curl" || return $?
        getVersion
        retval="$?"
        if [[ $retval == 0 ]] && [[ "$force" != "1" ]]; then
            colorEcho ${blue} "Versão mais recente ${cur_ver} já instalada."
            if [ -n "${error_if_uptodate}" ]; then
                return 10
            fi
            return
        elif [[ $retval == 3 ]]; then
            return 3
        else
            colorEcho ${blue} "Instalando XRay ${new_ver} em ${arch}"
            downloadXRay || return $?
        fi
    fi

    local ziproot="$(zipRoot "${zipfile}")"
    installSoftware unzip || return $?

    if [ -n "${extract_only}" ]; then
        colorEcho ${blue} "Extraindo pacote XRay para ${xsrc_root}."
        if unzip -o "${zipfile}" -d ${xsrc_root}; then
            colorEcho ${green} "XRay extraído para ${xsrc_root%/}${ziproot:+/${ziproot%/}}."
            return 0
        else
            colorEcho ${red} "Falha ao extrair XRay."
            return 2
        fi
    fi

    if pgrep "xray" > /dev/null ; then
        xray_running=1
        stopXray
    fi
    installXRay "${zipfile}" "${ziproot}" || return $?
    installInitScript "${zipfile}" "${ziproot}" || return $?
    if [[ ${xray_running} -eq 1 ]]; then
        colorEcho ${blue} "Reiniciando serviço XRay."
        startXray
    fi
    colorEcho ${green} "XRay ${new_ver} instalado."
    rm -rf /tmp/xray
    return 0
}

main

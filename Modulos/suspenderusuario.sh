#!/bin/bash
# blockssh.sh - BLOQUEAR / DESBLOQUEAR / LISTAR BLOQUEADOS (SSHPlus)

set -u
shopt -s extglob

BOLD="\033[1m"
RESET="\033[0m"
BLUE="\033[1;34m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
WHITE="\033[1;37m"

ttl()  { echo -e "${BLUE}${BOLD}${*^^}${RESET}"; }
ok()   { echo -e "${GREEN}${BOLD}${*^^}${RESET}"; }
warn() { echo -e "${YELLOW}${BOLD}${*^^}${RESET}"; }
err()  { echo -e "${RED}${BOLD}${*^^}${RESET}"; }

DB_USERS="/root/usuarios.db"
PASS_DIR="/etc/SSHPlus/senha"
BLOCK_FILE="/root/bloqueado"

# garante arquivo de bloqueados
init_block_file() {
  touch "$BLOCK_FILE" >/dev/null 2>&1 || true
  chmod 600 "$BLOCK_FILE" >/dev/null 2>&1 || true
}

# valida nome (simples e seguro)
valid_user_name() {
  [[ "${1:-}" =~ ^[a-zA-Z0-9._-]{1,32}$ ]]
}

user_exists() {
  id "$1" >/dev/null 2>&1
}

is_root_like() {
  [[ "$1" == "root" ]]
}

# adiciona ao arquivo sem duplicar
blockfile_add() {
  local u="$1"
  init_block_file
  grep -qxF "$u" "$BLOCK_FILE" 2>/dev/null || echo "$u" >> "$BLOCK_FILE"
}

# remove do arquivo
blockfile_del() {
  local u="$1"
  init_block_file
  grep -vxF "$u" "$BLOCK_FILE" > "${BLOCK_FILE}.tmp" 2>/dev/null && mv -f "${BLOCK_FILE}.tmp" "$BLOCK_FILE"
}

list_users_table() {
  echo -e "\E[44;1;37m USUÁRIO         SENHA         LIMITE        VALIDADE \E[0m"
  echo ""

  awk -F: '$3>=1000 {print $1}' /etc/passwd \
    | grep -Ev '^(nobody|ubuntu|lxd)$' \
    | grep -viE 'polkitd|system-' \
    | sort \
    | while read -r u; do

      # limite
      if [[ -f "$DB_USERS" ]] && grep -qE "^${u}[[:space:]]+" "$DB_USERS"; then
        lim="$(awk -v user="$u" '$1==user{print $2; exit}' "$DB_USERS")"
      else
        lim="1"
      fi

      # senha (se existir)
      if [[ -f "$PASS_DIR/$u" ]]; then
        senha="$(cat "$PASS_DIR/$u" 2>/dev/null || echo "Null")"
      else
        senha="Null"
      fi

      # validade
      exp="$(chage -l "$u" 2>/dev/null | awk -F': ' '/^Account expires/ {print $2; exit}')"
      if [[ -z "${exp:-}" || "$exp" == "never" ]]; then
        validade="${YELLOW}NUNCA${RESET}"
      else
        exp_epoch="$(date -d "$exp" +%s 2>/dev/null || echo 0)"
        now_epoch="$(date +%s)"
        if [[ "$exp_epoch" -eq 0 || "$now_epoch" -ge "$exp_epoch" ]]; then
          validade="${RED}VENCEU${RESET}"
        else
          dias=$(( (exp_epoch - now_epoch) / 86400 ))
          validade="${WHITE}${dias}${WHITE} ${WHITE}DIAS${RESET}"
        fi
      fi

      printf "%b %-14s %b %-12s %b %-11s %b %s\n" \
        "${YELLOW}" "$u" \
        "${WHITE}" "$senha" \
        "${WHITE}" "$lim" \
        "${GREEN}" "$validade"

      echo -e "\033[0;34m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
    done
}

do_block() {
  clear
  ttl "BLOQUEAR USUÁRIO"
  echo ""

  list_users_table
  echo ""

  echo -ne "${GREEN}${BOLD}DIGITE O NOME DO USUÁRIO PARA BLOQUEAR:${WHITE} ${RESET}"
  read -r lock

  if ! valid_user_name "${lock:-}"; then
    echo ""; err "USUÁRIO INVÁLIDO!"
    echo -ne "${YELLOW}${BOLD}ENTER PARA VOLTAR...${RESET}"; read -r
    return 0
  fi
  if is_root_like "$lock"; then
    echo ""; err "NÃO É PERMITIDO BLOQUEAR ROOT!"
    echo -ne "${YELLOW}${BOLD}ENTER PARA VOLTAR...${RESET}"; read -r
    return 0
  fi
  if ! user_exists "$lock"; then
    echo ""; err "USUÁRIO NÃO EXISTE!"
    echo -ne "${YELLOW}${BOLD}ENTER PARA VOLTAR...${RESET}"; read -r
    return 0
  fi

  if passwd -l "$lock" >/dev/null 2>&1; then
    blockfile_add "$lock"
    echo ""; ok "USUÁRIO BLOQUEADO COM SUCESSO!"
  else
    echo ""; err "FALHA AO BLOQUEAR (PASSWD -L)."
  fi

  echo -ne "${YELLOW}${BOLD}ENTER PARA VOLTAR...${RESET}"; read -r
}

do_unblock() {
  clear
  ttl "DESBLOQUEAR USUÁRIO"
  echo ""

  init_block_file
  if [[ -s "$BLOCK_FILE" ]]; then
    warn "USUÁRIOS BLOQUEADOS:"
    echo -e "${WHITE}$(cat "$BLOCK_FILE")${RESET}"
  else
    warn "NENHUM USUÁRIO BLOQUEADO REGISTRADO."
  fi
  echo ""

  echo -ne "${GREEN}${BOLD}DIGITE O NOME DO USUÁRIO PARA DESBLOQUEAR:${WHITE} ${RESET}"
  read -r unlock

  if ! valid_user_name "${unlock:-}"; then
    echo ""; err "USUÁRIO INVÁLIDO!"
    echo -ne "${YELLOW}${BOLD}ENTER PARA VOLTAR...${RESET}"; read -r
    return 0
  fi
  if is_root_like "$unlock"; then
    echo ""; err "ROOT NÃO PRECISA SER DESBLOQUEADO AQUI."
    echo -ne "${YELLOW}${BOLD}ENTER PARA VOLTAR...${RESET}"; read -r
    return 0
  fi
  if ! user_exists "$unlock"; then
    echo ""; err "USUÁRIO NÃO EXISTE!"
    echo -ne "${YELLOW}${BOLD}ENTER PARA VOLTAR...${RESET}"; read -r
    return 0
  fi

  if passwd -u "$unlock" >/dev/null 2>&1; then
    blockfile_del "$unlock"
    echo ""; ok "USUÁRIO DESBLOQUEADO COM SUCESSO!"
  else
    echo ""; err "FALHA AO DESBLOQUEAR (PASSWD -U)."
  fi

  echo -ne "${YELLOW}${BOLD}ENTER PARA VOLTAR...${RESET}"; read -r
}

do_list_blocked() {
  clear
  ttl "USUÁRIOS BLOQUEADOS"
  echo ""

  init_block_file
  if [[ -s "$BLOCK_FILE" ]]; then
    cat "$BLOCK_FILE"
  else
    err "NENHUM USUÁRIO BLOQUEADO ENCONTRADO."
  fi

  echo ""
  echo -ne "${YELLOW}${BOLD}ENTER PARA VOLTAR...${RESET}"; read -r
}

# ===== MENU =====
op=""
while [[ "$op" != "0" ]]; do
  clear
  echo -e "\E[44;1;37m             BLOQUEAR USUÁRIO SSH             \E[0m"
  echo ""
  echo -e "${BLUE}${BOLD}[01]${RESET} ${WHITE}➩ ${YELLOW}${BOLD}BLOQUEAR USUÁRIO${RESET}"
  echo -e "${BLUE}${BOLD}[02]${RESET} ${WHITE}➩ ${YELLOW}${BOLD}DESBLOQUEAR USUÁRIO${RESET}"
  echo -e "${BLUE}${BOLD}[03]${RESET} ${WHITE}➩ ${YELLOW}${BOLD}LISTAR USUÁRIOS BLOQUEADOS${RESET}"
  echo -e "${BLUE}${BOLD}[00]${RESET} ${WHITE}➩ ${YELLOW}${BOLD}SAIR${RESET}"
  echo ""

  echo -ne "${GREEN}${BOLD}ESCOLHA UMA OPÇÃO:${WHITE} ${RESET}"
  read -r op

  case "$op" in
    1|01) do_block ;;
    2|02) do_unblock ;;
    3|03) do_list_blocked ;;
    0|00) exit 0 ;;
    *) echo ""; err "OPÇÃO INVÁLIDA!"; sleep 1 ;;
  esac
done

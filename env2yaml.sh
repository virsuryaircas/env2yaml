#!/usr/bin/env bash
# ─────────────────────────────────────────────
#  env2yaml.sh — Convert .env to Kubernetes
#                ConfigMap or Secret YAML
# ─────────────────────────────────────────────

set -euo pipefail

# ── Colors ──────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
WHITE='\033[0;97m'
GRAY='\033[0;90m'

# ── Banner ───────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}  ███████╗███╗   ██╗██╗   ██╗██████╗ ██╗   ██╗ █████╗ ███╗   ███╗██╗     ${RESET}"
echo -e "${BOLD}${CYAN}  ██╔════╝████╗  ██║██║   ██║╚════██╗╚██╗ ██╔╝██╔══██╗████╗ ████║██║     ${RESET}"
echo -e "${BOLD}${CYAN}  █████╗  ██╔██╗ ██║██║   ██║ █████╔╝ ╚████╔╝ ███████║██╔████╔██║██║     ${RESET}"
echo -e "${BOLD}${CYAN}  ██╔══╝  ██║╚██╗██║╚██╗ ██╔╝██╔═══╝   ╚██╔╝  ██╔══██║██║╚██╔╝██║██║     ${RESET}"
echo -e "${BOLD}${CYAN}  ███████╗██║ ╚████║ ╚████╔╝ ███████╗   ██║   ██║  ██║██║ ╚═╝ ██║███████╗${RESET}"
echo -e "${BOLD}${CYAN}  ╚══════╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝${RESET}"
echo ""
echo -e "${GRAY}  .env → Kubernetes ConfigMap / Secret YAML Generator${RESET}"
echo -e "${GRAY}  ─────────────────────────────────────────────────────${RESET}"
echo ""

# ── Usage check ──────────────────────────────
if [[ $# -lt 1 ]]; then
  echo -e "${RED}  ✘ Usage:${RESET} ${WHITE}env2yaml.sh <path-to-.env-file>${RESET}"
  echo -e "${GRAY}  Example: env2yaml.sh .env${RESET}"
  echo ""
  exit 1
fi

ENV_FILE="$1"

if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${RED}  ✘ File not found:${RESET} ${WHITE}${ENV_FILE}${RESET}"
  echo ""
  exit 1
fi

# ── Prompt helpers ───────────────────────────
ask() {
  local prompt="$1"
  local default="$2"
  local answer
  printf "${BOLD}${WHITE}  %s${RESET}${GRAY} [default: %s]${RESET}${WHITE}: ${RESET}" "$prompt" "$default" >&2
  read -r answer
  echo "${answer:-$default}"
}

# ── Collect inputs ───────────────────────────
echo -e "${BLUE}  ❯ Resource Configuration${RESET}"
echo -e "${GRAY}  ──────────────────────────${RESET}"
echo ""

RES_NAME=$(ask "Resource name" "my-app-config")
NAMESPACE=$(ask "Namespace" "default")

echo ""
echo -e "${BLUE}  ❯ Output Type${RESET}"
echo -e "${GRAY}  ──────────────────────────${RESET}"
echo ""
echo -e "  ${WHITE}1${RESET}${GRAY})${RESET} ${CYAN}ConfigMap${RESET}   ${GRAY}— plain key/value data${RESET}"
echo -e "  ${WHITE}2${RESET}${GRAY})${RESET} ${YELLOW}Secret${RESET}      ${GRAY}— base64 encoded data${RESET}"
echo ""
printf "${BOLD}${WHITE}  Choose [1/2]${RESET}${GRAY} [default: 1]${RESET}${WHITE}: ${RESET}" >&2
read -r TYPE_CHOICE
TYPE_CHOICE="${TYPE_CHOICE:-1}"

case "$TYPE_CHOICE" in
  1) KIND="ConfigMap" ;;
  2) KIND="Secret" ;;
  *)
    echo ""
    echo -e "${YELLOW}  ⚠ Invalid choice — defaulting to ConfigMap${RESET}"
    KIND="ConfigMap"
    ;;
esac

# ── Parse .env file ──────────────────────────
declare -a KEYS
declare -a VALS

while IFS= read -r line || [[ -n "$line" ]]; do
  # Skip comments and blank lines
  [[ "$line" =~ ^[[:space:]]*#.*$ || -z "${line// }" ]] && continue

  # Must contain =
  [[ "$line" != *=* ]] && continue

  key="${line%%=*}"
  val="${line#*=}"

  # Trim whitespace from key
  key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # Trim whitespace from value
  val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # Strip surrounding double quotes and unescape inner escaped quotes
  if [[ "${val:0:1}" == '"' && "${val: -1}" == '"' ]]; then
    val="${val:1:${#val}-2}"
    val="${val//\\\"/\"}"
  # Strip surrounding single quotes
  elif [[ "${val:0:1}" == "'" && "${val: -1}" == "'" ]]; then
    val="${val:1:${#val}-2}"
  fi

  # Final trim after stripping quotes
  val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  [[ -z "$key" ]] && continue

  KEYS+=("$key")
  VALS+=("$val")
done < "$ENV_FILE"

VAR_COUNT="${#KEYS[@]}"

if [[ $VAR_COUNT -eq 0 ]]; then
  echo ""
  echo -e "${YELLOW}  ⚠ No variables found in ${ENV_FILE}${RESET}"
  echo ""
  exit 1
fi

# ── base64 helper ────────────────────────────
b64() {
  # Works on both Linux (base64) and macOS (base64)
  if command -v base64 &>/dev/null; then
    printf '%s' "$1" | base64 | tr -d '\n'
  else
    printf '%s' "$1" | openssl base64 | tr -d '\n'
  fi
}

# ── Needs quoting? (ConfigMap) ────────────────
needs_quote() {
  return 0  # Always quote all ConfigMap values
}

# ── Build YAML ────────────────────────────────
OUTPUT_FILE="${RES_NAME}.yaml"

{
  echo "apiVersion: v1"
  echo "kind: ${KIND}"
  echo "metadata:"
  echo "  name: ${RES_NAME}"
  echo "  namespace: ${NAMESPACE}"

  if [[ "$KIND" == "Secret" ]]; then
    echo "type: Opaque"
  fi

  echo "data:"

  for i in "${!KEYS[@]}"; do
    k="${KEYS[$i]}"
    v="${VALS[$i]}"

    if [[ "$KIND" == "Secret" ]]; then
      encoded=$(b64 "$v")
      echo "  ${k}: ${encoded}"
    else
      if needs_quote "$v"; then
        escaped="${v//\"/\\\"}"
        echo "  ${k}: \"${escaped}\""
      else
        echo "  ${k}: ${v}"
      fi
    fi
  done
} > "$OUTPUT_FILE"

# ── Summary ───────────────────────────────────
echo ""
echo -e "${GRAY}  ─────────────────────────────────────────────${RESET}"
echo ""
echo -e "${GREEN}  ✔ Done!${RESET}"
echo ""
echo -e "  ${GRAY}File     ${RESET}${WHITE}${OUTPUT_FILE}${RESET}"
echo -e "  ${GRAY}Kind     ${RESET}${WHITE}${KIND}${RESET}"
echo -e "  ${GRAY}Name     ${RESET}${WHITE}${RES_NAME}${RESET}"
echo -e "  ${GRAY}Namespace${RESET}${WHITE}${NAMESPACE}${RESET}"
echo -e "  ${GRAY}Variables${RESET}${WHITE}${VAR_COUNT}${RESET}"

if [[ "$KIND" == "Secret" ]]; then
  echo ""
  echo -e "  ${YELLOW}⚠ Values are base64 encoded (not encrypted).${RESET}"
  echo -e "  ${GRAY}  Use RBAC and Sealed Secrets / external vaults in production.${RESET}"
fi

echo ""
echo -e "${GRAY}  ─────────────────────────────────────────────${RESET}"
echo ""

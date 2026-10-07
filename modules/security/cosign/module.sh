# shellcheck shell=bash
# Signs the pushed image with a Cosign key pair of the project
# (templates/scripts/sign-image.sh) and, with a deployment module, checks the
# signature before production (verify-image.sh).  Signatures stay in the
# image's registry; the public Sigstore services are not used.

module_secrets() {
  require_image_module
  ask_local COSIGN_KEY_FILE "Cosign private key (empty: generate one)" ""
  ask_secret COSIGN_PASSWORD "Password of the Cosign key" "$(random_password)"
}

cosign_key() {
  local file
  file=$(value COSIGN_KEY_FILE)
  printf '%s' "${file:-$DEVOPS_KEYS/cosign.key}"
}

# The key is generated on this machine with the same pinned Cosign.
module_prepare() {
  local key cosign
  key=$(cosign_key)
  [[ -f $key ]] && return 0
  [[ -z $(value COSIGN_KEY_FILE) ]] || die "COSIGN_KEY_FILE $key does not exist"
  cosign=$(sh "$DEVOPS_HOME/templates/scripts/tool.sh" cosign) \
    || die "Could not download Cosign"
  mkdir -p "$DEVOPS_KEYS"
  COSIGN_PASSWORD=$(require_value COSIGN_PASSWORD) "$cosign" generate-key-pair \
    --output-key-prefix "${key%.key}" > /dev/null
  log_ok "Generated the Cosign key pair $key (.pub)"
}

module_env() {
  local key
  key=$(cosign_key)
  if [[ -f $key ]]; then
    pipeline_secret COSIGN_KEY_B64 "$(base64 < "$key" | tr -d '\n')"
    pipeline_var COSIGN_PUBLIC_KEY_B64 "$(base64 < "${key%.key}.pub" | tr -d '\n')"
  else
    pipeline_secret COSIGN_KEY_B64 ''
    pipeline_var COSIGN_PUBLIC_KEY_B64 ''
  fi
  pipeline_secret COSIGN_PASSWORD "$(value COSIGN_PASSWORD)"
}

module_stages() {
  shell_stage 78 cd sign-image "sh \"\$DEVOPS_SCRIPTS/sign-image.sh\""
  if [[ " $MODULES " == *" deploy/"* ]]; then
    shell_stage 89 prod verify-image "sh \"\$DEVOPS_SCRIPTS/verify-image.sh\""
  fi
}

module_urls() {
  printf '  %-12s public key %s\n' Cosign "$(cosign_key | sed 's/\.key$/.pub/')"
}

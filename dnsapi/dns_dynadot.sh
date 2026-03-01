#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dynadot_info='dynadot.com
Site: dynadot.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_dynadot
Options:
 DYNADOT_Key Key
 DYNADOT_Secret API Secret
Issues: github.com/acmesh-official/acme.sh/issues/???
'

# Dynadot API Documentation (V2.0.0)
# https://www.dynadot.com/domain/api-document

DYNADOT_Api="https://api.dynadot.com"
#DYNADOT_Api="https://api-sandbox.dynadot.com"
########  Public functions #####################

#Usage: dns_dynadot_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dynadot_add() {
  #fulldomain=$1
  fulldomain=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  txtvalue=$2
  _info "Using dynadnot dns api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  DYNADOT_Key="${DYNADOT_Key:-$(_readaccountconf_mutable DYNADOT_Key)}"
  DYNADOT_Secret="${DYNADOT_Secret:-$(_readaccountconf_mutable DYNADOT_Secret)}"
  if [ -z "$DYNADOT_Key" ] || [ -z "$DYNADOT_Secret" ]; then
    DYNADOT_Key=""
    DYNADOT_Secret=""
    _err "Dynadot key and username must be present."
    return 1
  fi
  _saveaccountconf_mutable DYNADOT_Key "$DYNADOT_Key"
  _saveaccountconf_mutable DYNADOT_Secret "$DYNADOT_Secret"
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  #_subdomain="${fulldomain%.$_domain}"
  _subdomain="${fulldomain%."$_domain"}"

  _info "Adding txt record to subdomain $_subdomain"

  while true; do
    _dynadot_rest POST "/restful/v2/domains/$_domain/records" "{\"dns_main_list\": [{}], \"sub_list\": [{\"sub_host\": \"$_subdomain\", \"record_type\": \"txt\", \"record_value1\": \"$txtvalue\" }], \"ttl\": 60, \"add_dns_to_current_setting\": true}"
    if _contains "$response" "try again later" >/dev/null; then
      _debug "system busy. try again in 1min"
      sleep 1m
      continue
    elif _contains "$response" "\"message\":\"Success\"" >/dev/null; then
      _info "Added, OK"
      return 0
    else
      _err "Adding txt record error."
      return 1
    fi
  done

  #  if _dynadot_rest POST "/restful/v2/domains/$_domain/records" "{\"dns_main_list\": [{}], \"sub_list\": [{\"sub_host\": \"$_subdomain\", \"record_type\": \"txt\", \"record_value1\": \"$txtvalue\" }], \"ttl\": 60, \"add_dns_to_current_setting\": true}"; then
  #    if _contains "$response" "\"message\":\"Success\"" >/dev/null; then
  #      _info "Added, OK"
  #      return 0
  #    else
  #      _err "Adding txt record error."
  #      return 1
  #    fi
  #  else
  #    _err "Adding txt record error."
  #  fi
}

dns_dynadot_rm() {
  #fulldomain=$1
  fulldomain=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  txtvalue=$2
  _info "Using dynadnot dns api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  DYNADOT_Key="${DYNADOT_Key:-$(_readaccountconf_mutable DYNADOT_Key)}"
  DYNADOT_Secret="${DYNADOT_Secret:-$(_readaccountconf_mutable DYNADOT_Secret)}"
  if [ -z "$DYNADOT_Key" ] || [ -z "$DYNADOT_Secret" ]; then
    DYNADOT_Key=""
    DYNADOT_Secret=""
    _err "Dynadot key and username must be present."
    return 1
  fi
  _saveaccountconf_mutable DYNADOT_Key "$DYNADOT_Key"
  _saveaccountconf_mutable DYNADOT_Secret "$DYNADOT_Secret"
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  #_subdomain="${fulldomain%.$_domain}"
  _subdomain="${fulldomain%."$_domain"}"

  _debug "Getting txt records"
  _debug _domain "$_domain"

  _dynadot_rest GET "/restful/v2/domains/$_domain/records"
  if printf "%s" "$response" | grep \"error\" >/dev/null; then
    _err "Error"
    return 1
  fi

  _main_domains=$(echo "$response" | _egrep_o '"main_domains":\[[^]]+\]' | cut -d: -f2- | sed 's/"value":/"record_value1":/g')
  _sub_domains=$(echo "$response" | _egrep_o '"sub_domains":\[[^]]*\]' | cut -d: -f2-)
  _sub_domains_filtered=$(echo "$_sub_domains" | sed -E "s/\{\"sub_host\":\"$_subdomain\",\"record_type\":\"txt\",\"value\":\"$txtvalue\"\},?//g; s/,]/]/g" | sed 's/"value":/"record_value1":/g')

  # fallback as main domain cannot be empty
  if [ -z "$_main_domains" ]; then
    _main_domains='[{"record_type":"txt","record_value1":"no-records"}]'
  fi
  # empty subdomain
  _sub_domains_filtered=${_sub_domains_filtered:-[]}

  json_output=$(printf '{"dns_main_list":%s,"sub_list":%s,"ttl":60}' "$_main_domains" "$_sub_domains_filtered")

  _info "updating records"

  while true; do
    _dynadot_rest POST "/restful/v2/domains/$_domain/records" "$json_output"
    if _contains "$response" "try again later" >/dev/null; then
      _debug "system busy. try again in 1min"
      sleep 1m
      continue
    elif _contains "$response" "\"message\":\"Success\"" >/dev/null; then
      _info "sucessfully removed txt record"
      sleep 1m
      return 0
    else
      _err "updating txt record error."
      return 1
    fi
  done

  #  if _dynadot_rest POST "/restful/v2/domains/$_domain/records" $json_output; then
  #    if _contains "$response" "\"message\":\"Success\"" >/dev/null; then
  #      _info "sucessfully removed txt record"
  #      return 0
  #    else
  #      _err "updating txt record error."
  #      return 1
  #    fi
  #  else
  #    _err "updating txt record error."
  #  fi
}

####################  Private functions below ##################################

_dynadot_rest() {
  method=$1
  path="$2"
  data="$3"
  _debug "$path"

  xRequestId=$(uuidgen)
  xSignature=$(printf '%s\n%s\n%s\n%s' "$DYNADOT_Key" "$path" "$xRequestId" "$data" | openssl dgst -sha256 -hmac "$DYNADOT_Secret" -binary | openssl base64 -e -A)

  export _H1="Content-Type: application/json"
  export _H2="Accept: application/json"
  export _H3="Authorization: Bearer $DYNADOT_Key"
  export _H4="X-Request-ID: $xRequestId"
  export _H5="X-Signature: $xSignature"

  if [ "$method" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$DYNADOT_Api$path" "" "$method")"
  else
    response="$(_get "$DYNADOT_Api$path")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $response"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_get_root() {
  domain=$1
  i=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi
    if ! _dynadot_rest GET "/restful/v2/domains/$h/search"; then
      return 1
    fi
    if _contains "$response" "\"domain_name\":\"$h\"" >/dev/null; then
      _domain=$h
      return 0
    fi
    i=$(_math "$i" + 1)
  done
  return 0
}

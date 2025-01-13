#!/bin/bash
## change to "bin/sh" when necessary

##############  CLOUDFLARE CREDENTIALS  ##############
# @auth_email           - The email used to login 'https://dash.cloudflare.com'
# @auth_method          - Set to "global" for Global API Key or "token" for Scoped API Token
# @auth_key             - Your API Token or Global API Key
# @zone_identifier      - Can be found in the "Overview" tab of your domain
# -------------------------------------------------- #
auth_email=""
auth_method="token"
auth_key=""
zone_identifier=""

#############  DNS RECORD CONFIGURATION  #############
# @record_names         - Records you want to be synced, seperated by spaces
# @ttl                  - DNS TTL (seconds), can be set between (30 if enterprise) 60 and 86400 seconds, or 1 for Automatic
# @proxy                - Set the proxy to true or false
# -------------------------------------------------- #
record_names=""
ttl=3600
proxy="false"

###############  SCRIPT CONFIGURATION  ###############
# @log_header_name      - Header name used for logs
# @auto_create          - If set to true, the record will be created when record does not exist. 
# @last_ipv4_info       - If configured, only when current ip is different from last stored one, it will update dns record. 
# -------------------------------------------------- #
log_header_name="DDNS Updater_v4 $$"
auto_create="true"
last_ipv4_info=""

#############  WEBHOOKS CONFIGURATION  ###############
# @slackchannel         - Slack Channel #example
# @slackuri             - URI for Slack WebHook "https://hooks.slack.com/services/xxxxx"
# @discorduri           - URI for Discord WebHook "https://discordapp.com/api/webhooks/xxxxx"
# -------------------------------------------------- #
slackchannel=""
slackuri=""
discorduri=""

################################################
## Discord, Slack function
################################################
sendDiscord(){
  if [[ $discorduri != "" ]]; then
    curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
        --data-raw "{
            \"content\": \"$1\"
        }" $discorduri
  fi
}

sendSlack(){
  if [[ $slackuri != "" ]]; then
    curl -L -X POST $slackuri \
        --data-raw "{
            \"channel\": \"$slackchannel\",
            \"text\": \"$1\"
        }"
  fi
}

###########################################
## Check if we have a public IP
###########################################
ipv4_regex='([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\.([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])'
if [[ $1 != "" ]]; then
  # Use first parameter ip
  ip=$1
else
  # Attempt to get the ip from other websites.
  ip=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com)
fi

# Use regex to check for proper IPv4 format.
if [[ ! $ip =~ ^$ipv4_regex$ ]]; then
  logger -s "$log_header_name: Failed to find a valid IP."
  exit 2
fi

################################################
## Check if the ip is same with stored last_ip
################################################
if [[ $last_ipv4_info != "" ]]; then
  if [[ -e $last_ipv4_info ]]; then
    read last_ip last_result < $last_ipv4_info
    if [[ $ip == $last_ip && $last_result == "success" ]]; then
        echo "$log_header_name: The IP ($ip) is same with last one. exit. (Last IP in file: $last_ipv4_info)"
        exit 0
    fi
  else
    echo "$ip" > $last_ipv4_info
  fi
fi

###########################################
## Check and set the proper auth header
###########################################
if [[ "${auth_method}" == "global" ]]; then
  auth_header="X-Auth-Key:"
else
  auth_header="Authorization: Bearer"
fi

for record_name in $record_names; do

  ###########################################
  ## Seek for the A record
  ###########################################
  logger "$log_header_name: Check Initiated"
  record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=A&name=$record_name" \
                        -H "X-Auth-Email: $auth_email" \
                        -H "$auth_header $auth_key" \
                        -H "Content-Type: application/json")

  ###########################################
  ## Check if the domain has an A record
  ###########################################
  if [[ $record == *"\"count\":0"* ]]; then
    if $auto_create; then
      new_record=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records" \
          -H "X-Auth-Email: $auth_email" \
          -H "$auth_header $auth_key" \
          -H "Content-Type: application/json" \
          --data "{\"comment\":\"shell auto_create\",\"name\":\"$record_name\",\"type\":\"A\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy}")
      logger "$log_header_name: IP ($ip) for ${record_name} is created."
      continue
    else
      logger -s "$log_header_name: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
      exit 1
    fi
  fi

  ###########################################
  ## Get existing IP
  ###########################################
  old_ip=$(echo "$record" | sed -E 's/.*"content":"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/')

  # Make sure the extracted IPv4 address is valid
  if [[ ! $old_ip =~ ^$ipv4_regex$ ]]; then
      logger -s "$log_header_name: Unable to extract existing IPv4 address from DNS record ($record_name). $record"
      exit 1
  fi

  # Compare if they're the same
  if [[ $ip == $old_ip ]]; then
    logger "$log_header_name: IP ($ip) for ${record_name} has not changed."
    continue
  fi

  ###########################################
  ## Set the record identifier from result
  ###########################################
  record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

  ###########################################
  ## Change the IP@Cloudflare using the API
  ###########################################
  update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
                      -H "X-Auth-Email: $auth_email" \
                      -H "$auth_header $auth_key" \
                      -H "Content-Type: application/json" \
                      --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":${proxy}}")

  ###########################################
  ## Report the status
  ###########################################
  case "$update" in
  *"\"success\":false"*)
    echo -e "$log_header_name: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update" | logger -s 
    sendDiscord "$log_header_name Failed: $record_name: $record_identifier ($ip)."
    sendSlack "$log_header_name Failed: $record_name: $record_identifier ($ip)."
    exit 1;;
  *)
    logger "$log_header_name: $ip $record_name DDNS updated."
    sendDiscord "$log_header_name: $record_name's new IPv4 Address is $ip."
    sendSlack "$log_header_name: $record_name's new IPv4 Address is $ip."
    ;;
  esac
done
echo "$ip success" > $last_ipv4_info
exit 0

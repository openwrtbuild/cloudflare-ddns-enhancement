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
# @static_IPv6_mode     - Useful if you are using EUI-64 IPv6 address with SLAAC IPv6 suffix token. (Privacy Extensions)
#                       + Or some kind of static IPv6 assignment from DHCP server configuration, etc
#                       + If set to false, the IPv6 address will be acquired from external services
# @last_notable_hexes   - Used with `static_IPv6_mode`. Configure this to target what specific IPv6 address to search for
#                       + E.g. Your global primary IPv6 address is 2404:6800:4001:80e::59ec:ab12:34cd, then
#                       + You can put values (i.e. static suffixes) such as "34cd", "ab12:34cd" and etc
# @log_header_name      - Header name used for logs
# @auto_create          - If set to true, the record will be created when record does not exist. 
# @last_ipv6_info       - If configured, only when current ip is different from last stored one, it will update dns record. 
# -------------------------------------------------- #
static_IPv6_mode="false"
last_notable_hexes="ffff:ffff"
log_header_name="DDNS Updater_v6 $$"
auto_create="true"
last_ipv6_info=""

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

################################################
## Finding our IPv6 address
################################################
# Regex credits to https://stackoverflow.com/a/17871737
ipv6_regex="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"

if [[ $1 != "" ]]; then
    ip=$1
else
    if $static_IPv6_mode; then
        # Test whether 'ip' command is available
        if { command -v "ip" &>/dev/null; }; then
            ip=$(ip -6 -o addr show scope global primary -deprecated | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$")
        else
            # Fall back to 'ifconfig' command
            ip=$(ifconfig | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$")
        fi
    else
        # Use external services to discover our system's preferred IPv6 address
        ip=$(curl -s -6 https://api64.ipify.org || curl -s -6 https://ipv6.icanhazip.com)
    fi
fi

# Check point: Make sure the collected IPv6 address is valid
if [[ ! $ip =~ ^$ipv6_regex$ ]]; then
    logger -s "$log_header_name: Failed to find a valid IPv6 address."
    exit 1
fi

################################################
## Check if the ip is same with stored last_ip
################################################
if [[ $last_ipv6_info != "" ]]; then
    if [[ -e $last_ipv6_info ]]; then
        read last_ip last_result < $last_ipv6_info
        if [[ $ip == $last_ip && $last_result == "success" ]]; then
            echo "$log_header_name: The IP ($ip) is same with last one. exit. (Last IP in file: $last_ipv6_info)"
            exit 0
        fi
    else
        echo "$ip" > $last_ipv6_info
    fi
fi

################################################
## Check and set the proper auth header
################################################
if [[ "${auth_method}" == "global" ]]; then
    auth_header="X-Auth-Key:"
else
    auth_header="Authorization: Bearer"
fi

for record_name in $record_names; do
    ################################################
    ## Seek for the AAAA record
    ################################################
    logger "$log_header_name: Check Initiated"
    record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=AAAA&name=$record_name" \
        -H "X-Auth-Email: $auth_email" \
        -H "$auth_header $auth_key" \
        -H "Content-Type: application/json")
    
    ################################################
    ## Check if the domain has an AAAA record
    ################################################
    if [[ $record == *"\"count\":0"* ]]; then
        if $auto_create; then
            new_record=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records" \
                -H "X-Auth-Email: $auth_email" \
                -H "$auth_header $auth_key" \
                -H "Content-Type: application/json" \
                --data "{\"comment\":\"shell auto_create\",\"name\":\"$record_name\",\"type\":\"AAAA\",\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy}")
            logger "$log_header_name: IP ($ip) for ${record_name} is created."
            continue
        else
            logger -s "$log_header_name: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
            exit 1
        fi
    fi
    
    ################################################
    ## Get existing IP
    ################################################
    old_ip=$(echo "$record" | sed -E 's/.*"content":"'${ipv6_regex}'".*/\1/')
    
    # Make sure the extracted IPv6 address is valid
    if [[ ! $old_ip =~ ^$ipv6_regex$ ]]; then
        logger -s "$log_header_name: Unable to extract existing IPv6 address from DNS record ($record_name). $record"
        exit 1
    fi
    
    # Compare if they're the same
    if [[ $ip == $old_ip ]]; then
        logger "$log_header_name: IP ($ip) for ${record_name} has not changed."
        continue
    fi
    
    ################################################
    ## Set the record identifier from result
    ################################################
    record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')
    
    ################################################
    ## Change the IP@Cloudflare using the API
    ################################################
    update=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
        -H "X-Auth-Email: $auth_email" \
        -H "$auth_header $auth_key" \
        -H "Content-Type: application/json" \
        --data "{\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy}")
    
    ################################################
    ## Report the status
    ################################################
    case "$update" in
    *"\"success\":false"*)
        echo -e "$log_header_name: $ip $record_name DDNS failed for $record_identifier ($ip). DUMPING RESULTS:\n$update" | logger -s
        sendDiscord "$log_header_name Failed: $record_name: $record_identifier ($ip)."
        sendSlack "$log_header_name Failed: $record_name: $record_identifier ($ip)."
        exit 1
        ;;
    *)
        logger "$log_header_name: $ip $record_name DDNS updated."
        sendDiscord "$log_header_name: $record_name's new IPv6 Address is $ip."
        sendSlack "$log_header_name: $record_name's new IPv6 Address is $ip."
        ;;
    esac
done
echo "$ip success" > $last_ipv6_info
exit 0

#!/bin/bash

# Set variables
SCRIPT_DIR="/root/Origin_Check"
LOG_FILE="$SCRIPT_DIR/events.log"
CSV_FILE="$SCRIPT_DIR/origin_pool.csv"
APACHE_CONF="/etc/apache2/sites-enabled/000-default-le-ssl.conf"
TMP_RESULTS="/tmp/origin_results.tmp"
STOP_SIGNAL="/tmp/origin_check_stop_signal"
LOCK_FILE="/tmp/origin_check.lock"
APACHE_CHANGED=false

# Using flock to acquire a lock on the lock file to prevent concurrency
exec 200>"$LOCK_FILE"
flock -n 200 || exit 1

# Export necessary variables
export SCRIPT_DIR LOG_FILE CSV_FILE APACHE_CONF TMP_RESULTS STOP_SIGNAL

# Log message function
log_message() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> "$LOG_FILE"
}

# Check for stop signal
check_stop_signal() {
    if [ -f "$STOP_SIGNAL" ]; then
        log_message "Script execution skipped due to stop signal"
        exit 0
    fi
}

# Function to trim the log file
trim_log_file() {
    if [ -f "$LOG_FILE" ]; then
        total_lines=$(wc -l < "$LOG_FILE")
        if [ "$total_lines" -gt 5000 ]; then
            lines_to_discard=$((total_lines - 5000))
            sed -i "1,${lines_to_discard}d" "$LOG_FILE"
            log_message "events.log trimmed to 5000 lines"
        fi
    fi
}

# Function to process RPC endpoints
process_rpc_endpoint() {
    local url=$1
    response=$(curl -s -m 5 -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$url")
    if [[ -z "$response" || "$response" =~ "<html>" ]]; then
        echo "$url,Invalid Response" >> "$TMP_RESULTS"
    else
        block_height=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(int(data['result'], 0))
except (json.JSONDecodeError, KeyError):
    print('ERROR: Invalid Response')
")
        if [[ "$block_height" =~ ^[0-9]+$ ]]; then
            echo "$url,$block_height" >> "$TMP_RESULTS"
        else
            echo "$url,Invalid Response" >> "$TMP_RESULTS"
        fi
    fi
}

# Function to process WSS endpoints
process_wss_endpoint() {
    local url=$1
    python3 - << END >> "$TMP_RESULTS" 2>&1
import websocket
import json

try:
    ws = websocket.create_connection("$url")
    request = {
        "jsonrpc": "2.0",
        "method": "eth_blockNumber",
        "params": [],
        "id": 1
    }
    ws.send(json.dumps(request))
    response = ws.recv()
    data = json.loads(response)
    if 'result' in data:
        block_height = int(data['result'], 16)
        print(f"$url,{block_height}")
    else:
        print(f"$url,Invalid Response")
    ws.close()
except Exception as e:
    print(f"$url,Invalid Response")
END
}

# Function to read endpoints from CSV and process them
read_and_process_endpoints() {
    tail -n +2 "$CSV_FILE" | while IFS=, read -r network type enabled_0x_prefix url health_status block_height; do
        if [ -n "$url" ]; then
            if [[ "$url" =~ ^http ]]; then
                process_rpc_endpoint "$url" &
            elif [[ "$url" =~ ^wss ]]; then
                process_wss_endpoint "$url" &
            fi
        fi
    done
    sleep 8
}

# Function to update block heights and health status

update_block_heights_and_health_status() {
    declare -A block_heights
    declare -A health_status

    # Read TMP_RESULTS and store in associative arrays
    while IFS=, read -r url result; do
        log_message "Processing result: $url, $result"
        if [[ "$result" =~ ^[0-9]+$ ]]; then
            block_heights["$url"]=$result
            health_status["$url"]="Active"
        else
            block_heights["$url"]="Invalid Response"
            health_status["$url"]="Inactive"
        fi
    done < "$TMP_RESULTS"

    # Calculate max heights for each category
    max_height_mainnet_rpc=0
    max_height_mainnet_0xrpc=0
    max_height_mainnet_wss=0
    max_height_mainnet_0xwss=0
    max_height_apothem_rpc=0
    max_height_apothem_0xrpc=0
    max_height_apothem_wss=0
    max_height_apothem_0xwss=0

    for url in "${!block_heights[@]}"; do
        new_height=${block_heights["$url"]}
        if [ "$new_height" != "Invalid Response" ]; then
            network=$(grep "$url" "$CSV_FILE" | cut -d',' -f1)
            type=$(grep "$url" "$CSV_FILE" | cut -d',' -f2)
            enabled_0x_prefix=$(grep "$url" "$CSV_FILE" | cut -d',' -f3)

            case "$network" in
                "Mainnet")
                    if [ "$type" == "RPC" ]; then
                        if [ "$new_height" -gt "$max_height_mainnet_rpc" ]; then
                            max_height_mainnet_rpc=$new_height
                        fi
                        if [ "$enabled_0x_prefix" == "Y" ]; then
                            if [ "$new_height" -gt "$max_height_mainnet_0xrpc" ]; then
                                max_height_mainnet_0xrpc=$new_height
                            fi
                        fi
                    elif [ "$type" == "WSS" ]; then
                        if [ "$new_height" -gt "$max_height_mainnet_wss" ]; then
                            max_height_mainnet_wss=$new_height
                        fi
                        if [ "$enabled_0x_prefix" == "Y" ]; then
                            if [ "$new_height" -gt "$max_height_mainnet_0xwss" ]; then
                                max_height_mainnet_0xwss=$new_height
                            fi
                        fi
                    fi
                    ;;
                "Apothem")
                    if [ "$type" == "RPC" ]; then
                        if [ "$new_height" -gt "$max_height_apothem_rpc" ]; then
                            max_height_apothem_rpc=$new_height
                        fi
                        if [ "$enabled_0x_prefix" == "Y" ]; then
                            if [ "$new_height" -gt "$max_height_apothem_0xrpc" ]; then
                                max_height_apothem_0xrpc=$new_height
                            fi
                        fi
                    elif [ "$type" == "WSS" ]; then
                        if [ "$new_height" -gt "$max_height_apothem_wss" ]; then
                            max_height_apothem_wss=$new_height
                        fi
                        if [ "$enabled_0x_prefix" == "Y" ]; then
                            if [ "$new_height" -gt "$max_height_apothem_0xwss" ]; then
                                max_height_apothem_0xwss=$new_height
                            fi
                        fi
                    fi
                    ;;
            esac
        fi

        log_message "max_height_mainnet_rpc = $max_height_mainnet_rpc"
        log_message "max_height_mainnet_0xrpc = $max_height_mainnet_0xrpc"
        log_message "max_height_mainnet_wss = $max_height_mainnet_wss"
        log_message "max_height_mainnet_0xwss = $max_height_mainnet_0xwss"
        log_message "max_height_apothem_rpc = $max_height_apothem_rpc"
        log_message "max_height_apothem_0xrpc = $max_height_apothem_0xrpc"
        log_message "max_height_apothem_wss = $max_height_apothem_wss"
        log_message "max_height_apothem_0xwss = $max_height_apothem_0xwss"

    done

    # Prepare updated CSV content in a temporary file
    TMP_CSV=$(mktemp) || { log_message "Failed to create temporary file"; return 1; }

    # Preserve header line
    head -n 1 "$CSV_FILE" > "$TMP_CSV"

    # Read original CSV file from the second line onward and update based on block heights
    tail -n +2 "$CSV_FILE" | while IFS=, read -r network type enabled_0x_prefix url old_health_status current_height; do
        if [ "$url" != "endpoint_URL" ]; then
            new_height=${block_heights["$url"]}
            log_message "Updating URL: $url with new height: $new_height"
            
            if [ "$new_height" != "Invalid Response" ]; then
                case "$network" in
                    "Mainnet")
                        if [[ "$type" =~ "RPC" ]]; then
                            if [[ "$enabled_0x_prefix" == "Y" ]]; then
                                max_height="$max_height_mainnet_0xrpc"
                                log_message "max_height_mainnet_0xrpc = $max_height_mainnet_0xrpc"
                            else
                                max_height="$max_height_mainnet_rpc"
                                log_message "max_height_mainnet_rpc = $max_height_mainnet_rpc"
                            fi
                        elif [[ "$type" =~ "WSS" ]]; then
                            if [[ "$enabled_0x_prefix" == "Y" ]]; then
                                max_height="$max_height_mainnet_0xwss"
                                log_message "max_height_mainnet_0xwss = $max_height_mainnet_0xwss"
                            else
                                max_height="$max_height_mainnet_wss"
                                log_message "max_height_mainnet_wss = $max_height_mainnet_wss"
                            fi
                        fi
                        ;;
                    "Apothem")
                        if [[ "$type" =~ "RPC" ]]; then
                            if [[ "$enabled_0x_prefix" == "Y" ]]; then
                                max_height="$max_height_apothem_0xrpc"
                                log_message "max_height_apothem_0xrpc = $max_height_apothem_0xrpc"
                            else
                                max_height="$max_height_apothem_rpc"
                                log_message "max_height_apothem_rpc = $max_height_apothem_rpc"
                            fi
                        elif [[ "$type" =~ "WSS" ]]; then
                            if [[ "$enabled_0x_prefix" == "Y" ]]; then
                                max_height="$max_height_apothem_0xwss"
                                log_message "max_height_apothem_0xwss = $max_height_apothem_0xwss"
                            else
                                max_height="$max_height_apothem_wss"
                                log_message "max_height_apothem_wss = $max_height_apothem_wss"
                            fi
                        fi
                        ;;
                esac

                if [ "$((max_height - new_height))" -le 4 ]; then
                    new_health_status="Active"
                else
                    new_health_status="Inactive"
                fi

                log_message "max_height = $max_height"
                log_message "new_height = $new_height"
                log_message "new_health_status = $new_health_status"
                cmd="$network,$type,$enabled_0x_prefix,$url,$new_health_status,$new_height"
                log_message "Executing command: echo \"$cmd\""
                echo "$cmd" >> "$TMP_CSV"
                # echo "$network,$type,$enabled_0x_prefix,$url,$new_health_status,$new_height" >> "$TMP_CSV"
            else
                log_message "max_height = $max_height"
                log_message "new_height = $new_height"
                new_health_status="Inactive"
                log_message "new_health_status = $new_health_status"
                cmd="$network,$type,$enabled_0x_prefix,$url,Inactive,Invalid Response"
                log_message "Executing command: echo \"$cmd\""
                echo "$cmd" >> "$TMP_CSV"
                # echo "$network,$type,$enabled_0x_prefix,$url,Inactive,Invalid Response" >> "$TMP_CSV"
            fi

            if [ "$new_health_status" == "Active" ]; then
                log_message "Calling add_balancer_member with url=$url network=$network type=$type enabled_0x_prefix=$enabled_0x_prefix" 
                add_balancer_member "$url" "$network" "$type" "$enabled_0x_prefix"
            else
                log_message "Calling remove_balancer_member with url=$url"
                remove_balancer_member "$url"
            fi
        fi
    done

    # Replace original CSV file with the updated content
    mv "$TMP_CSV" "$CSV_FILE" || { log_message "Failed to replace CSV file"; return 1; }

    APACHE_CHANGED=true
}

# Function to add a balancer member
add_balancer_member() {
    local url=$1
    local network=$2
    local type=$3
    local enabled_0x_prefix=$4

    # Read the file into an array
    mapfile -t lines < "$APACHE_CONF"

    # Determine the correct insertion sections based on inputs
    case "$network-$type-$enabled_0x_prefix" in
        "Mainnet-RPC-Y")
            sections=("# Add Mainnet RPC here" "# Add Mainnet 0xRPC here")
            ends=("# END Mainnet RPC cluster" "# END Mainnet 0xRPC cluster")
            ;;
        "Mainnet-RPC-N")
            sections=("# Add Mainnet RPC here")
            ends=("# END Mainnet RPC cluster")
            ;;
        "Mainnet-WSS-Y")
            sections=("# Add Mainnet WSS here" "# Add Mainnet 0xWSS here")
            ends=("# END Mainnet WSS cluster" "# END Mainnet 0xWSS cluster")
            ;;
        "Mainnet-WSS-N")
            sections=("# Add Mainnet WSS here")
            ends=("# END Mainnet WSS cluster")
            ;;
        "Apothem-RPC-Y")
            sections=("# Add Apothem RPC here" "# Add Apothem 0xRPC here")
            ends=("# END Apothem RPC cluster" "# END Apothem 0xRPC cluster")
            ;;
        "Apothem-RPC-N")
            sections=("# Add Apothem RPC here")
            ends=("# END Apothem RPC cluster")
            ;;
        "Apothem-WSS-Y")
            sections=("# Add Apothem WSS here" "# Add Apothem 0xWSS here")
            ends=("# END Apothem WSS cluster" "# END Apothem 0xWSS cluster")
            ;;
        "Apothem-WSS-N")
            sections=("# Add Apothem WSS here")
            ends=("# END Apothem WSS cluster")
            ;;
        *)
            echo "Invalid parameters"
            return 1
            ;;
    esac

    # Check if URL already exists
    if grep -q "$url" "$APACHE_CONF"; then
        echo "URL already exists in the configuration"
        return 0
    fi

    # Initialize new_content variable
    new_content=""
    inside_section=false

    for line in "${lines[@]}"; do
        for i in "${!sections[@]}"; do
            section_start=${sections[$i]}
            section_end=${ends[$i]}
            
            if [[ "$line" == *"$section_start"* ]]; then
                inside_section=true
            elif [[ "$line" == *"$section_end"* ]]; then
                if $inside_section; then
                    new_content+="        BalancerMember \"$url\""$'\n'
                fi
                inside_section=false
            fi
        done
        new_content+="$line"$'\n'
    done

    # Trim trailing newlines
    new_content=$(echo "$new_content" | sed '/^$/d')

    # Write the new content back to the file without adding extra newline characters
    echo -n "$new_content" > "$APACHE_CONF"

    APACHE_CHANGED=true
}

# Function to remove a balancer member
remove_balancer_member() {
    local url=$1

    # Check if the URL exists in the Apache configuration file
    if grep -qF "BalancerMember \"$url\"" "$APACHE_CONF"; then
        # Temporarily store lines excluding the ones with the URL to remove
        grep -vF "BalancerMember \"$url\"" "$APACHE_CONF" > "$APACHE_CONF.tmp"
        
        # Replace the original configuration file with the temporary one
        mv "$APACHE_CONF.tmp" "$APACHE_CONF"
        
        # Set a flag indicating that the Apache configuration file has been changed
        APACHE_CHANGED=true
    fi
}

# Function to reload Apache if changes were made
reload_apache_if_changed() {
    if $APACHE_CHANGED; then
        # systemctl reload apache2
        log_message "Apache2 reloaded due to changes in BalancerMember section"
    fi
}

# Main script execution
cd "$SCRIPT_DIR" || exit
check_stop_signal
log_message "Starting Endpoint check script"
rm -f "$TMP_RESULTS"
read_and_process_endpoints
update_block_heights_and_health_status
reload_apache_if_changed
trim_log_file
# Release the lock
flock -u 200

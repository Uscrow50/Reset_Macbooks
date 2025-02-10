#!/bin/zsh

# Define the flag file location
flagFile="/var/tmp/reset_flag"

# Check if the flag file exists
if [ -f "$flagFile" ]; then
    echo "The reset process has already been completed. Exiting..."
    exit 0
fi

# Jamf Pro server URL
jamfProURL="https://jamfserver.jamfcloud.com"

# Securely retrieve credentials
apiUsername="username"
apiPassword="password"

# Get the current Mac's serial number
serialNumber=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/ {print $4}')

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq not found, attempting to install..."
    curl -fsSL https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64 -o /usr/local/bin/jq
    chmod +x /usr/local/bin/jq
    if [ $? -ne 0 ]; then
        echo "jq installation failed. Exiting..."
        exit 1
    fi
else
    echo "jq already installed."
fi

# Obtain an authentication token
authResponse=$( /usr/bin/curl --silent --request POST \
    --url "$jamfProURL/api/v1/auth/token" \
    --header "Accept: application/json" \
    --header "Content-Type: application/json" \
    --user "$apiUsername:$apiPassword" )

# Extract token using jq
token=$(echo "$authResponse" | jq -r '.token')

# Verify token retrieval
if [[ -z "$token" || "$token" == "null" ]]; then
    echo "Failed to obtain authentication token. Exiting..."
    exit 1
fi

# Get the computer ID using the correct filter (hardware.serialNumber)
computerResponse=$( /usr/bin/curl --silent \
    --header "Authorization: Bearer $token" \
    --header "Accept: application/json" \
    --url "$jamfProURL/api/v1/computers-inventory?filter=hardware.serialNumber%3D%3D$serialNumber" )

echo "Raw API response: $computerResponse"  # Debugging output

computerID=$(echo "$computerResponse" | jq -r '.results[0].id')

# Verify computer ID retrieval
if [[ -z "$computerID" || "$computerID" == "null" ]]; then
    echo "Failed to retrieve computer ID for serial number $serialNumber. Exiting..."
    exit 1
fi

echo "Computer ID retrieved: $computerID"

# Send EraseDevice command (using the erase method from Script 2)
response=$( /usr/bin/curl --silent \
    --header "Authorization: Bearer $token" \
    --header "Content-Type: application/json" \
    --request POST \
    --url "$jamfProURL/api/v1/computer-inventory/$computerID/erase" \
    --data '{
        "pin": "00000"
    }')

echo "Response: $response"

# Expire the token after use
/usr/bin/curl --silent \
    --header "Authorization: Bearer $token" \
    --request POST \
    --url "$jamfProURL/api/v1/auth/invalidate-token"

echo "API token invalidated."

exit 0

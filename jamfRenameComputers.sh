#!/bin/bash
# ----------------------------------------------------------------------
# Script Name:    jamfRenameComputers.sh
# Description:    Sets the name of the computer to "First Last - Model - Asset Tag."
# Author:         @mtbhuskies
# Created on:     10/08/2024
# Version:        1.0
# ----------------------------------------------------------------------
# Usage:          Add the script in Jamf Pro, assign to a policy triggered weekly or on an as-needed basis (e.g., login, enrollment, etc.). Ensure "Collect Inventory" is enabled.
# Example:        N/A
# ----------------------------------------------------------------------
# Environment:    Jamf Pro, Jamf Pro API Access (Read)
# Dependencies:   Jamf Pro, Jamf Pro API, Jamf binary
# ----------------------------------------------------------------------
# Revision History:
#   Date          Author          Description
#   10/08/24      @mtbhuskies     Initial release
# ----------------------------------------------------------------------

# Set variables for Jamf Pro API access
jamfURL="https://domain.jamfcloud.com"
apiUser="apiRead"
apiPass="apiPassword"

# Encode the username and password in Base64
basicAuth=$(echo -n "${apiUser}:${apiPass}" | base64)

# Get the Bearer token using Basic Auth
bToken=$(curl -sk -X POST "${jamfURL}/api/v1/auth/token" \
-H "accept: application/json" \
-H "Authorization: Basic ${basicAuth}" | awk '/token/{print $3}' | tr -d '"'',')
echo "Bearer token is $bToken"

# Get the currently logged-in user (active console user)
lastLoggedInUser=$(stat -f%Su /dev/console)

# Get the real name of the user with first and last name separated properly
realName=$(dscl . -read /Users/"$lastLoggedInUser" RealName | tail -n 1)

# Escape apostrophes for safety and ensure spaces are handled properly
sanitizedRealName=$(echo "$realName" | sed "s/'//g")

# Get the user-friendly model name of the computer (e.g., MacBook Pro, MacBook Air)
modelName=$(system_profiler SPHardwareDataType | awk -F': ' '/Model Name/ {print $2}')

# Get the serial number of the computer
serialNumber=$(system_profiler SPHardwareDataType | awk '/Serial Number/ { print $4 }')

# Retrieve the computer ID using the serial number
computerID=$(curl -X 'GET' "$jamfURL/JSSResource/computers/serialnumber/$serialNumber" \
	-H "Authorization: Bearer $bToken" \
	-H "Accept: application/xml" | xmllint --xpath "string(//id)" -)

echo "Computer ID is $computerID"

# Retrieve the asset tag using the computer ID
assetTag=$(curl -X 'GET' "$jamfURL/JSSResource/computers/id/$computerID" \
	-H "Authorization: Bearer $bToken" \
	-H "Accept: application/xml" | xmllint --xpath "string(//asset_tag)" -)

echo "Asset Tag is $assetTag"

# Generate the new computer name
computerName="${sanitizedRealName// / } - ${modelName} - ${assetTag}"

# Set the new computer name locally
scutil --set ComputerName "$computerName"
scutil --set HostName "$computerName"
scutil --set LocalHostName "$computerName"

# Set the computer name in Jamf
/usr/local/bin/jamf setComputerName -name "$computerName"
/usr/local/bin/jamf recon

# Invalidate the token after the script finishes
curl -X POST "$jamfURL/uapi/auth/invalidateToken" \
-H "Authorization: Bearer $bToken" \
-H "Accept: application/json"

echo "Computer name has been changed to $computerName"

exit 0
#!/bin/bash
#
#
# Script to help populate the bluexscrt file
#
#
# Ricardo Martins - Blue Chip Portugal © 2023-2024
#######################################################################################

Version=0.1.5

####  START:FUNCTION - Target DC and List all VSI in the POWERVS DC and Get VSI Name and ID  ####
dc_vsi_list() {
        sh -c '/usr/local/bin/ibmcloud pi ws tg '$1 2>> $log_file
    # List all VSI in this POWERVS DC and Get VSI Name and ID #
        sh -c '/usr/local/bin/ibmcloud pi ins ls | awk {'\''print $1" "$2'\''} | tail -n +2' > $vsi_list_id_tmp 2>> $log_file
        vsi_id=$(cat $vsi_list_id_tmp | grep -wi $vsi | awk {'print $1'})
        cat $vsi_list_id_tmp | awk {'print $2'} > $vsi_list_tmp
}
####  END:FUNCTION - Target DC and List all VSI in the POWERVS DC and Get VSI Name and ID  ####
####  START:FUNCTION - Check if VSI exists and Get VSI IP and IASP NAME if exists  ####
check_VSI_exists() {
	echo "" > $job_log

	# Convert 'wsnames' string to an array
	IFS=':' read -r -a wsnames_array <<< "$wsnames"

	# Convert 'allws' string to an array
	read -r -a allws_array <<< "$allws"

	# Initialize an associative array to map workspace abbreviations to full names
	declare -A wsmap
	# Populate the wsmap with dynamic values from allws and wsnames_array
	for i in "${!allws_array[@]}"; do
		wsmap[${allws_array[i]}]="${wsnames_array[i]}"
	done

	found=0
	for ws in "${allws_array[@]}"
	do
		shortnamecrn="${!ws}"
		full_ws_name="${wsmap[$ws]}" # Get the full workspace name from the map
		echo "`date +%Y-%m-%d_%H:%M:%S` - Searching for VSI in $full_ws_name..." >> $log_file
		dc_vsi_list "$shortnamecrn"
		vsi_cloud_name=$(cat $vsi_list_tmp | grep -wi $vsi | awk {'print $1'})
		if grep -qie ^$vsi$ $vsi_list_tmp
		then
			echo "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_cloud_name was found in $full_ws_name..." >> $log_file
			echo "`date +%Y-%m-%d_%H:%M:%S` - VSI to Capture: $vsi_cloud_name" >> $log_file
		else
			echo "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi not found in $full_ws_name!" >> $log_file
		fi
	done
	if [ "$found" -eq 0 ]
	then
		abort "$(date +%Y-%m-%d_%H:%M:%S) - VSI $vsi_cloud_name not found in any of the workspaces available in bluexscrt file!"
	fi
}
####  END:FUNCTION - Check if VSI exists and Get VSI IP and IASP NAME if exists  ####

while true
do
	read -p "File Name: " file_name
	if [ -f $file_name ]; then
		echo "File name $file_name exists. This file will be overwritten!"
		read -p "Are you sure? (Y/N) " continue
		if [[ $continue == "Y" ]] || [[ $continue == "y" ]]
		then
			break
		fi
	else
		break
	fi
done

read -s -p "APIKEY: " apikey
echo ""
read -p "Resource Group: " resource_grp
read -s -p "COS Access Key: " acckey
echo ""
read -s -p "COS Secret Key: " scrtkey
echo ""
read -p "Region: " region
read -p "Bucket Name: " bucket
read -p "VSI User: " vsi_user
echo ""
while true
do
	read -p "SSH Key Full Path: " ssh_key_path
	echo ""
	if [ ! -f $ssh_key_path ]
	then
		echo "File name $ssh_key_path does not exists!"
		read -p "Are you sure you want to use this file ? (Y/N) " continue
		if [[ $continue == "Y" ]] || [[ $continue == "y" ]]
		then
			echo ""
			echo "Don't forget to create ssh key named $ssh_key_path !"
			sleep 3
			echo ""
			break
		fi
	else
		break
	fi
done

echo "APIKEY: "$apikey
echo "Resource Group: "$resource_grp
echo "Region: "$region
echo "COS Access Key: "$acckey
echo "COS Secret Key: "$scrtkey
echo "Bucket Name: "$bucket
echo "VSI User: "$vsi_user
echo "SSH Key Full Path: "$ssh_key_path

echo ""
echo "Checking IBM Cloud credentials and getting Workspaces..."
echo ""

/usr/local/bin/ibmcloud login --apikey $apikey -r $region -g $resource_grp
/usr/local/bin/ibmcloud pi ws ls
ret=$?
#echo $ret
if [ $ret -eq 1 ]
then
	echo "    FAILED - Oops something went wrong!... Check messages above this line..."
	echo ""
	exit 0
fi
wsnames=$(/usr/local/bin/ibmcloud pi ws ls | awk '{$1=$2="";print $0":"}' | sed -r "s/^\s+//g" | tail -n +2)
wsids=$(/usr/local/bin/ibmcloud pi ws ls | awk {'print $2'}| tail -n +2)
wsids=$(echo $wsids | sed 's/[[:space:]]/@/g')
crns=$(/usr/local/bin/ibmcloud pi ws ls | awk {'print $1'}| tail -n +2)
crns=$(echo $crns | sed 's/[[:space:]]/@/g')
wsnames=$(echo $wsnames | sed 's/\:[[:space:]]/:/g')

#echo "WSNAMES: "$wsnames
#echo "CRNS: "$crns
#echo "WSID: "$wsids
echo ""
IFS=':' read -r -a wsnames_array <<< "$wsnames"
IFS='@' read -r -a crns_array <<< "$crns"
IFS='@' read -r -a wsids_array <<< "$wsids"
#declare -A wsmap
index=0
for i in "${wsnames_array[@]}"
do
	full_ws_name=$i # Get the full workspace name from the map
	read -p "Enter Shortname for Workspace $i : " ws_short_name
	allws=${allws}" "$ws_short_name
	crn[$index]=$ws_short_name" "${crns_array[$index]}
	wsid[$index]=$ws_short_name"ID "${wsids_array[$index]}
	echo "ALLWS:   "$allws
	echo "CRN:   "${crn[$index]}
	echo "WSID:   "${wsid[$index]}
	echo ""
	index=$((index + 1))
done

read -p "Do you want to add now the LPARs? (Y/N)? " ask_lpar
if [[ $ask_lpar=="Y" ]] || [[ $ask_lpar=="y" ]]
then
	index=0
	add_more="Y"
	while [[ "$add_more" == "Y" || "$add_more" == "y" ]]
	do
		read -p "LPAR$index Name ? (as is in IBM Cloud) " lpar[$index]

fi
### Building $HOME/$file_name file

echo "APYKEY $apikey" > $HOME/$file_name
for crn_print in "${crn[@]}"
do
	echo $crn_print >> $HOME/$file_name
done
echo "" >> $HOME/$file_name
echo "ACCESSKEY $acckey" >> $HOME/$file_name
echo "SECRETKEY $scrtkey" >> $HOME/$file_name

echo "BUCKETNAME $bucket" >> $HOME/$file_name
echo "REGION $region" >> $HOME/$file_name
echo "" >> $HOME/$file_name
echo "ALLWS $allws" >> $HOME/$file_name
echo "WSNAMES $wsnames" >> $HOME/$file_name
echo "" >> $HOME/$file_name
echo "VSI_USER $vsi_user" >> $HOME/$file_name
echo "" >> $HOME/$file_name
echo "SSHKEYPATH $ssh_key_path" >> $HOME/$file_name
echo "" >> $HOME/$file_name
for wsid_print in "${wsid[@]}"
do
	echo $wsid_print >> $HOME/$file_name
done
echo "" >> $HOME/$file_name
echo "RESOURCE_GRP $resource_grp" >> $HOME/$file_name
chmod 600 $HOME/$file_name

read -p "Do you want to add now the LPARs? (Y/N)? " ask_lpar
if [[ $ask_lpar=="Y" ]] || [[ $ask_lpar=="y" ]]
then
	index=0
	add_more="Y"
	while [[ "$add_more" == "Y" || "$add_more" == "y" ]]
	do
		read -p "LPAR$index Name ? (as is in IBM Cloud) " lpar[$index]

	done
fi

### Updating bluexport.conf file

oldbluexscrt=$(cat $HOME/bluexport.conf | grep bluexscrt | awk {'print $2'})
newbluexscrt=$HOME/$file_name
read -p "Do you want to update bluexport.conf with $file_name (Y/N) " use_file
if [[ $use_file=="Y" ]] || [[ $use_file=="y" ]]
then
	echo "Updating file $HOME/bluexport.conf..."
	sed -i "s|$oldbluexscrt|$newbluexscrt|g" $HOME/bluexport.conf
	echo "Done!"
else
	echo "If you want to use this file $HOME/$file_name as your bluexscrt file, don't forget to update $HOME/bluexport.conf file"
fi

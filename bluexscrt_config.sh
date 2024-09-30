#!/bin/bash

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
read -p "SSH Key Full Path: " ssh_key_path
echo ""


echo "APIKEY: "$apikey
echo "Resource Group: "$resource_grp
echo "Region: "$region
echo "COS Access Key: "$acckey
echo "COS Secret Key: "$scrtkey
echo "Bucket Name: "$bucket
echo "VSI User: "$vsi_user
echo "SSH Key Full Path: "$ssh_key_path

/usr/local/bin/ibmcloud login --apikey $apikey -r $region -g $resource_grp
wsnames=$(/usr/local/bin/ibmcloud pi ws ls | awk '{$1=$2="";print $0":"}' | sed -r "s/^\s+//g" | tail -n +2)
wsids=$(/usr/local/bin/ibmcloud pi ws ls | awk {'print $2'}| tail -n +2)
wsids=$(echo $wsids | sed 's/[[:space:]]/@/g')
crns=$(/usr/local/bin/ibmcloud pi ws ls | awk {'print $1'}| tail -n +2)
crns=$(echo $crns | sed 's/[[:space:]]/@/g')
wsnames=$(echo $wsnames | sed 's/\:[[:space:]]/:/g')

echo "WSNAMES: "$wsnames
echo "CRNS: "$crns
echo "WSID: "$wsids

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

echo "APYKEY $apikey" > zzzz.blu
for crn_print in "${crn[@]}"
do
	echo $crn_print >> zzzz.blu
done
echo "" >> zzzz.blu
echo "ACCESSKEY $acckey" >> zzzz.blu
echo "SECRETKEY $scrtkey" >> zzzz.blu
echo "BUCKETNAME $bucket" >> zzzz.blu
echo "REGION $region" >> zzzz.blu
echo "" >> zzzz.blu
echo "ALLWS $allws" >> zzzz.blu
echo "WSNAMES $wsnames" >> zzzz.blu
echo "" >> zzzz.blu
echo "VSI_USER $vsi_user" >> zzzz.blu
echo "" >> zzzz.blu
echo "SSHKEYPATH $ssh_key_path" >> zzzz.blu
echo "" >> zzzz.blu
for wsid_print in "${wsid[@]}"
do
	echo $wsid_print >> zzzz.blu
done
echo "" >> zzzz.blu
echo "RESOURCE_GRP $resource_grp" >> zzzz.blu

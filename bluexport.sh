#!/bin/bash
#
# Capture IBM Cloud POWERVS IBM i VSI and Export to COS or/and Image Catalog
#
# Version 3.x now supports the creation, update, delete and list Snapshots.
#
# Usage for changing secret file:	./bluexport.sh -chscrt bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new
#
# Usage to view secret file in use:	./bluexport.sh -viewscrt
#
# Usage for all volumes:		./bluexport.sh -a VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single
# Usage for excluding volumes:		./bluexport.sh -x volumes_name_to_exclude VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single
# Usage for monitoring job:		./bluexport.sh -j VSI_NAME IMAGE_NAME
#
# Usage to create a snapshot:		./bluexport.sh -snapcr VSI_NAME SNAPSHOT_NAME 0|["DESCRIPTION"] 0|[VOLUMES(Comma separated list)]
# Usage to update a snapshot:		./bluexport.sh -snapupd VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|["DESCRIPTION"]
# Usage to delete snapshot:		./bluexport.sh -snapdel VSI_NAME SNAPSHOT_NAME
# Usage to list all snapshot
#        in all Workspaces:		./bluexport.sh -snaplsall
#
# Usage to create a volume clone:   	./bluexport.sh -vclone VOLUME_CLONE_NAME BASE_NAME LPAR_NAME True|False True|False STORAGE_TIER ALL|(Comma seperated Volumes name list to clone)"
# Usage to delete a volume clone:	./bluexport.sh -vclonedel VOLUME_CLONE_NAME
# Usage to list all volume clones
#        in all Workspaces:		./bluexport.sh -vclonelsall
#
# Example:  ./bluexport.sh -a vsiprd vsiprd_img image-catalog daily            ---- Includes all Volumes and exports to COS and image catalog
# Example:  ./bluexport.sh -x ASP2_ vsiprd vsiprd_img both monthly             ---- Excludes Volumes with ASP2_ in the name and exports to image catalog and COS
# Example:  ./bluexport.sh -x "ASP2_ IASPname" vsiprd vsiprd_img both monthly  ---- Excludes Volumes with ASP2_ and IASPname in the name and exports to image catalog and COS
#
# Note: Reocurrence "hourly" only permits captures to image-catalog
#
# Capture IBM Cloud POWERVS VSI and Export to COS or/and Image Catalog and Snapshots
#
# Ricardo Martins - Blue Chip Portugal © 2023-2024
########################################################################################

       #####  START:CODE  #####

Version=3.2.15
log_file=$(cat $HOME/bluexport.conf | grep -w "log_file" | awk {'print $2'})
bluexscrt=$(cat $HOME/bluexport.conf | grep -w "bluexscrt" | awk {'print $2'})
end_log_file='==== END ========= $timestamp ========='
if [[ $1 != "-chscrt" ]] && [[ $1 != "-viewscrt" ]] && [[ $1 != "-v" ]] && [[ $1 != "-h" ]]
then
	####  START: Constants Definition  #####
	capture_time=`date +%Y-%m-%d_%H%M`
	capture_date=`date +%Y-%m-%d`
	capture_hour=`date "+%H"`
	flagj=0
	job_log=$(cat $HOME/bluexport.conf | grep -w "job_log" | awk {'print $2'})
	job_test_log=$(cat $HOME/bluexport.conf | grep -w "job_test_log" | awk {'print $2'})
	job_id=$(cat $HOME/bluexport.conf | grep -w "job_id" | awk {'print $2'})
	job_log_short=$(cat $HOME/bluexport.conf | grep -w "job_log_short" | awk {'print $2'})
	job_monitor=$(cat $HOME/bluexport.conf | grep -w "job_monitor" | awk {'print $2'})
	vsi_list_id_tmp=$(cat $HOME/bluexport.conf | grep -w "vsi_list_id_tmp" | awk {'print $2'})
	vsi_list_tmp=$(cat $HOME/bluexport.conf | grep -w "vsi_list_tmp" | awk {'print $2'})
	volumes_file=$(cat $HOME/bluexport.conf | grep -w "volumes_file" | awk {'print $2'})
	single=0
	vsi_user=$(cat $bluexscrt | grep "VSI_USER" | awk {'print $2'})
	####  END: Constants Definition  #####

	####  START: Check if Config File exists  ####
	if [ ! -f $bluexscrt ]
	then
		echo "" >> $log_file
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
		echo "`date +%Y-%m-%d_%H:%M:%S` - Config file $bluexscrt Missing!! Aborting!..." >> $log_file
		echo "==== END ========= $timestamp =========" >> $log_file
		echo "" >> $log_file
		exit 0
	fi
	####  END: Check if Config File exists  ####

	####  START: Get Cloud Config Data  #####
	resource_grp=$(cat $bluexscrt | grep -w "RESOURCE_GRP" | awk {'print $2'})
	accesskey=$(cat $bluexscrt | grep -w "ACCESSKEY" | awk {'print $2'})
	secretkey=$(cat $bluexscrt | grep -w "SECRETKEY" | awk {'print $2'})
	bucket=$(cat $bluexscrt | grep -w "BUCKETNAME" | awk {'print $2'})
	apikey=$(cat $bluexscrt | grep -w "APYKEY" | awk {'print $2'})
	sshkeypath=$(cat $bluexscrt | grep -w "SSHKEYPATH" | awk {'print $2'})

	   ### START: Dynamically create a variable with the name of the workspace ###
	read -r -a workspaces <<< $(grep "^ALLWS" "$bluexscrt" | cut -d ' ' -f2-) # Read the ALLWS line from bluexscrt file and create an array of workspace names
	for ws in "${workspaces[@]}" # Loop through the array of workspace names
	do
	    crn=$(grep "^$ws " "$bluexscrt" | awk '{print $2}') # For each workspace, find its corresponding CRN
	    declare "$ws=$crn" # Dynamically create a variable with the name of the workspace and assign the CRN as its value
	done
	   ### END: Dynamically create a variable with the name of the workspace ###

	region=$(cat $bluexscrt | grep "REGION" | awk {'print $2'})
	allws=$(grep '^ALLWS' $bluexscrt | cut -d' ' -f2-)
	wsnames=$(grep '^WSNAMES' $bluexscrt | cut -d' ' -f2-)
	####  END: Get Cloud Config Data  #####
fi

       #####  START: FUNCTIONS  #####

#### START:FUNCTION - Help  ####
help() {
	echo ""
	echo "Capture IBM Cloud POWERVS IBM i VSI and Export to COS or/and Image Catalog"
	echo "Version 3.x now supports the creation, update, delete and list Snapshots."
	echo ""
	echo "Changing secret file:		./bluexport.sh -chscrt bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
	echo ""
	echo "View secret file in use:	./bluexport.sh -viewscrt"
	echo ""
	echo "Usage for all volumes:		./bluexport.sh -a VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echo ""
	echo "Usage for excluding volumes:	./bluexport.sh -x volumes_name_to_exclude VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echo ""
	echo "Usage for monitoring job:	./bluexport.sh -j VSI_NAME IMAGE_NAME"
	echo ""
	echo "Usage to create a snapshot:	./bluexport.sh -snapcr VSI_NAME SNAPSHOT_NAME 0|[DESCRIPTION] 0|[VOLUMES(Comma separated list)]"
	echo ""
	echo "Usage to update a snapshot:	./bluexport.sh -snapupd VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[DESCRIPTION]"
	echo ""
	echo "Usage to delete snapshot:	./bluexport.sh -snapdel VSI_NAME SNAPSHOT_NAME"
	echo ""
	echo "Usage to list all snapshot"
	echo " in all Workspaces:		./bluexport.sh -snaplsall"
	echo ""
	echo "Usage to create a volume clone:	./bluexport.sh -vclone VOLUME_CLONE_NAME BASE_NAME LPAR_NAME True|False True|False STORAGE_TIER ALL|(Comma seperated Volumes name list to clone)"
	echo ""
	echo "Usage to delete a volume clone:	./bluexport.sh -vclonedel VOLUME_CLONE_NAME"
	echo ""
	echo "Usage to list all volume clones"
	echo " in all Workspaces:		./bluexport.sh -vclonelsall"
	echo ""
	echo "Example:  ./bluexport.sh -a vsiprd vsiprd_img image-catalog daily ---- Includes all Volumes and exports to COS and image catalog"
	echo "Example:  ./bluexport.sh -x ASP2_ vsiprd vsiprd_img both monthly    ---- Excludes Volumes with ASP2_ in the name and exports to image catalog and COS"
	echo 'Example:  ./bluexport.sh -x "ASP2_ IASPname" vsiprd vsiprd_img both monthly    ---- Excludes Volumes with ASP2_ and IASPname in the name and exports to image catalog and COS'
	echo ""
	echo "Flag t before a or x makes it a test and do not makes the capture"
	echo "Example:  ./bluexport.sh -tx ASP2_ vsiprd vsiprd_img both single ---- Does not makes the export"
	echo ""
	echo "Ricardo Martins - Blue Chip Portugal © 2023-2024"
	echo ""
}
#### END:FUNCTION - Help  ####

#### START:FUNCTION - Finish log file when aborting  ####
abort() {
	echo $1 >> $log_file
	timestamp=$(date +%F" "%T" "%Z)
	eval echo $end_log_file >> $log_file
	exit 0
}
#### END:FUNCTION - Finish log file when aborting  ####

#### START:FUNCTION - Check if image-catalog and Cloud Object has images from last time and deleted it ####
delete_previous_img() {
	img_id_old=$(/usr/local/bin/ibmcloud pi img ls | grep -wi $vsi | grep $old_img | awk {'print $1'})
	img_name_old=$(/usr/local/bin/ibmcloud pi img ls | grep -wi $vsi | grep $old_img | awk {'print $2'})
	objstg_img=$(/usr/local/bin/ibmcloud cos list-objects-v2 --bucket $bucket | grep -wi $vsi | grep $old_img | awk {'print $1'})
	today_img=$(/usr/local/bin/ibmcloud cos list-objects-v2 --bucket $bucket | grep -wi $vsi | grep $capture_date | awk {'print $1'})
	if [ ! $img_id_old ]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - There is no Image from $old_img - Nothing to delete in image catalog." >> $log_file
	else
		echo "`date +%Y-%m-%d_%H:%M:%S` - == Deleting from image catalog image name $img_name_old - image ID $img_id_old - from day $old_img... ==" >> $log_file
		sh -c '/usr/local/bin/ibmcloud pi img del '$img_id_old 2>> $log_file | tee -a $log_file
	fi
	if [ ! $objstg_img ]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - No image from previous export to delete in Object Storage." >> $log_file
	else
		if [ ! $today_img ]
		then
			echo "`date +%Y-%m-%d_%H:%M:%S` - == Something went wrong... Today's image is not in Bucket $bucket. Keeping ( Not deleted ) image name $objstg_img from day $old_img... ==" >> $log_file
		else
			echo "`date +%Y-%m-%d_%H:%M:%S` - == Deleting from Bucket $bucket, image name $objstg_img from day $old_img... ==" >> $log_file
			sh -c '/usr/local/bin/ibmcloud cos object-delete --bucket '$bucket' --key '$objstg_img' --force' 2>> $log_file | tee -a $log_file
		fi
	fi
}
#### END:FUNCTION - Check if image-catalog as images from last saturday and deleted it ####

####  START:FUNCTION - Target DC and List all VSI in the POWERVS DC and Get VSI Name and ID  ####
dc_vsi_list() {
	sh -c '/usr/local/bin/ibmcloud pi ws tg '$1 2>> $log_file
    # List all VSI in this POWERVS DC and Get VSI Name and ID #
	sh -c '/usr/local/bin/ibmcloud pi ins ls | awk {'\''print $1" "$2'\''} | tail -n +2' > $vsi_list_id_tmp 2>> $log_file
	vsi_id=$(cat $vsi_list_id_tmp | grep -wi $vsi | awk {'print $1'})
	cat $vsi_list_id_tmp | awk {'print $2'} > $vsi_list_tmp
}
####  END:FUNCTION - Target DC and List all VSI in the POWERVS DC and Get VSI Name and ID  ####

####  START:FUNCTION - Monitor Capture and Export Job  ####
job_monitor() {
    # Get Capture & Export Job ID #
	echo "`date +%Y-%m-%d_%H:%M:%S` - Job log in file $job_log" >> $log_file
	if [ $flagj -eq 1 ]
	then
		job=$(sh -c '/usr/local/bin/ibmcloud pi job ls | grep -B7 '$capture_name' | grep "Job ID" | awk {'\''print $3'\''}' 2>> $log_file | tee -a $log_file)
	else
		job=$(cat $job_id | grep "Job ID " | awk {'print $3'})
	fi
    # Check Capture & Export Job Status #
	echo "Job Monitoring of VM Capture "$capture_name" - Job ID:" $job >> $job_log
	while true
	do
		sh -c '/usr/local/bin/ibmcloud pi job get '$job 1> $job_monitor 2>>$job_log | tee -a $log_file
		job_status=$(cat $job_monitor | grep "State " | awk {'print $2'})
		message=$(cat $job_monitor |grep "Message" | cut -f 2- -d ' ')
		operation=$(cat $job_monitor |grep "Message" | cut -f 2- -d ' '| sed 's/::/ /g' | awk {'print $3'})
		if [[ $job_status == "completed" ]]
		then
			if [[ $destination == "cloud-storage" ]]
			then
				echo "`date +%Y-%m-%d_%H:%M:%S` - Image Capture and Export of $vsi to Bucket $bucket Completed !!" >> $log_file
			elif [[ $destination == "both" ]]
			then
				echo "`date +%Y-%m-%d_%H:%M:%S` - Image Capture and Export of $vsi to Image Catalog Completed !!" >> $log_file
				echo "`date +%Y-%m-%d_%H:%M:%S` - Image Capture and Export of $vsi to Bucket $bucket Completed !!" >> $log_file
			else
				echo "`date +%Y-%m-%d_%H:%M:%S` - Image Capture and Export of $vsi to Image Catalog Completed !!" >> $log_file
			fi
			if [ $single -eq  0 ]
			then
				delete_previous_img
			fi
			echo "`date +%Y-%m-%d_%H:%M:%S` - Finished Successfully!!" >> $job_log
			job_log_perm=$job_log_short"_"$capture_name".log"
			cp $job_log $job_log_perm
			abort "`date +%Y-%m-%d_%H:%M:%S` - Finished Successfully!!"
		elif [[ $job_status == "" ]]
		then
			echo "`date +%Y-%m-%d_%H:%M:%S` - FAILED Getting Job ID or no Job Running!" >> $log_file
			abort "`date +%Y-%m-%d_%H:%M:%S` - Check file $job_monitor for more details."
		elif [[ $job_status == "failed" ]]
		then
			echo "`date +%Y-%m-%d_%H:%M:%S` - Job ID "$job" Status:" ${job_status^^} >> $log_file
			echo "`date +%Y-%m-%d_%H:%M:%S` - Message:" $message >> $log_file
			abort "`date +%Y-%m-%d_%H:%M:%S` - Job Failed, check message!!"
		else
			if [[ $operation != $operation_before ]]
			then
				echo "`date +%Y-%m-%d_%H:%M:%S` - Job ID "$job" Status:" ${job_status^^} >> $log_file
				echo "`date +%Y-%m-%d_%H:%M:%S` - Message:" $message >> $log_file
				echo "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Operation Change... Operation Running Now:" ${operation^^} >> $log_file
				echo "`date +%Y-%m-%d_%H:%M:%S` - Running "${operation^^}"... Sleeping 60 seconds..." >> $job_log
				sleep 60
				operation_before=$operation
			else
				echo "`date +%Y-%m-%d_%H:%M:%S` - Still Running "${operation^^}"... Sleeping 60 seconds..." >> $job_log
				sleep 60
			fi
		fi
	done
}
####  END:FUNCTION - Monitor Capture and Export Job  ####

####  START:FUNCTION - Login in IBM Cloud  ####
cloud_login() {
	/usr/local/bin/ibmcloud login --apikey $apikey -r $region -g $resource_grp 2>> $log_file | tee -a $log_file
}
####  END:FUNCTION - Login in IBM Cloud  ####

####  START:FUNCTION - Get IASP name  ####
get_IASP_name() {
	if [ $test -eq 0 ]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - Getting $vsi IASP Name..." >> $log_file
		vsi_ip=$(cat $bluexscrt | grep -wi $vsi | awk {'print $2'})
		if ping -c1 -w3 $vsi_ip &> /dev/null
		then
			echo "`date +%Y-%m-%d_%H:%M:%S` - Ping VSI $vsi OK." >> $log_file
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Cannot ping VSI $vsi with IP $vsi_ip ! Aborting..."
		fi
		ssh -q -i $sshkeypath $vsi_user@$vsi_ip exit
		if [ $? -eq 255 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Unable to SSH to $vsi and not able to get IASP status! Try STRTCPSVR *SSHD on the $vsi VSI. Aborting..."
		else
			iasp_name=$(ssh -i $sshkeypath $vsi_user@$vsi_ip 'ls -l / | grep " IASP"' | awk {'print $9'})
			if [[ $iasp_name == "" ]]
			then
				echo "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi doesn't have IASP or it is Varied OFF" >> $log_file
			else
				echo "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi IASP Name: $iasp_name" >> $log_file
			fi
		fi
	else
		echo "`date +%Y-%m-%d_%H:%M:%S` - Running in test mode, skipping get_IASP_name." >> $log_file
	fi
}
####  END:FUNCTION - Get IASP name  ####

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
#			echo "`date +%Y-%m-%d_%H:%M:%S` - VSI to Capture: $vsi_cloud_name" >> $log_file
			if [ $flagj -eq 0 ]
			then
				echo "`date +%Y-%m-%d_%H:%M:%S` - VSI to Capture: $vsi_cloud_name" >> $log_file
				get_IASP_name
			fi
			found=1
			break
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

####  START:FUNCTION Flush ASPs and IASP Memory to Disk  ####
flush_asps() {
	if [ $test -eq 0 ]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - Flushing Memory to Disk for SYSBAS..." >> $log_file
		ssh -T -i $sshkeypath $vsi_user@$vsi_ip 'system "CHGASPACT ASPDEV(*SYSBAS) OPTION(*FRCWRT)"' >> $log_file | tee -a $log_file
		if [[ $iasp_name != "" ]]
		then
			echo "`date +%Y-%m-%d_%H:%M:%S` - Flushing Memory to Disk for $iasp_name ..." >> $log_file
			ssh -T -i $sshkeypath $vsi_user@$vsi_ip 'system "CHGASPACT ASPDEV('$iasp_name') OPTION(*FRCWRT)"' >> $log_file | tee -a $log_file
		fi
	else
		echo "`date +%Y-%m-%d_%H:%M:%S` - Flushing Memory to Disk for SYSBAS..." >> $log_file
		if [[ $iasp_name != "" ]]
		then
			echo "`date +%Y-%m-%d_%H:%M:%S` - Flushing Memory to Disk for $iasp_name ..." >> $log_file
		fi
	fi
}
####  END:FUNCTION Flush ASPs and IASP Memory to Disk  ####

####  START:FUNCTION - Do the Snapshot Create  ####
do_snap_create() {
	flush_asps
	echo "`date +%Y-%m-%d_%H:%M:%S` - == Executing Snapshot $snap_name of Instance $vsi with volumes $volumes_to_echo" >> $log_file
	snap_cr_cmd="/usr/local/bin/ibmcloud pi ins snap cr $vsi_id --name $snap_name $description $flag_volumes $volumes_to_snap"
	eval $snap_cr_cmd 2>> $log_file
	if [ $? -eq 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	else
		echo "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Snapshot $snap_name to reach 100%..." >> $log_file
		snap_percent=0
		while [ $snap_percent -lt 100 ]
		do
			snap_percent_before=$snap_percent
			sleep 10
			snap_percent=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name | awk {'print $7'})
			if [[ "$snap_percent" == "" ]]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
			fi
			if [[ "$snap_percent" != "$snap_percent_before" ]]
			then
				if [[ "$snap_percent" == "100" ]]
				then
					echo "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name reached 100% - Done!" >> $log_file
				else
					echo "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name at $snap_percent%" >> $log_file
				fi
			fi
		done
	fi
}
####  END:FUNCTION - Do the Snapshot Create  ####

####  START:FUNCTION - Do the Snapshot Update  ####
do_snap_update() {
	echo "`date +%Y-%m-%d_%H:%M:%S` - == Executing Snapshot $snap_name Update $new_name_echo" >> $log_file
	snap_id=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name | awk {'print $1'})
	snap_upd_cmd="/usr/local/bin/ibmcloud pi ins snap upd $snap_id $description $new_name"
	eval $snap_upd_cmd 2>> $log_file
	if [ $? -eq 0 ]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name updated $new_name_echo $new_description_echo - Done!" >> $log_file
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi
}
####  END:FUNCTION - Do the Snapshot Update  ####

####  START:FUNCTION - Do the Snapshot Delete  ####
do_snap_delete() {
	echo "`date +%Y-%m-%d_%H:%M:%S` - == Executing Snapshot $snap_name Delete" >> $log_file
	snap_id=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name | awk {'print $1'})
	/usr/local/bin/ibmcloud pi ins snap del $snap_id 2>> $log_file
	if [ $? -eq 0 ]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Snapshot $snap_name deletion to reach 100%..." >> $log_file
		snap_percent=0
		while [ $snap_percent -lt 100 ]
		do
			snap_percent_before=$snap_percent
			sleep 5
			snap_percent=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name | awk {'print $7'})
			if [[ $snap_percent == "" ]]
			then
				snap_percent=100
			fi
			if [[ "$snap_percent" != "$snap_percent_before" ]]
			then
				if [ $snap_percent -eq 100 ]
				then
					echo "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name Deleted. - Done!" >> $log_file
				else
					echo "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name deletion at $snap_percent%" >> $log_file
				fi
			fi
		done
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi
}
####  END:FUNCTION - Do the Snapshot Delete  ####

####  START:FUNCTION - Do the Volume Clone Execute ####
do_volume_clone_execute() {
	flush_asps
	echo "`date +%Y-%m-%d_%H:%M:%S` - == Executing Volume Clone with name $vclone_name ..." >> $log_file
	/usr/local/bin/ibmcloud pi vol cl ex $vclone_id --name $base_name --replication-enabled=$replication --rollback-prepare=$rollback --target-tier $target_tier 2>> $log_file
	if [ $? -eq 0 ]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Volume Clone $vclone_name execution to finish..." >> $log_file
		vcloneex_percent=0
		while [ $vcloneex_percent -lt 100 ]
		do
			vcloneex_percent_before=$vcloneex_percent
			sleep 5
			vcloneex_percent=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Percent Completed:" | awk {'print $3'})
			if [[ "$vcloneex_percent" != "$vcloneex_percent_before" ]]
			then
				if [ $vcloneex_percent -eq 100 ]
				then
					echo "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone $vclone_name Done and ready to be used!" >> $log_file
				else
					echo "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone $vclone_name execution at $vcloneex_percent%" >> $log_file
				fi
			fi
		done
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi
}
####  END:FUNCTION -  Do the Volume Clone Execute ####

####  START:FUNCTION - Do the Volume Clone Start ####
do_volume_clone_start() {
	echo "`date +%Y-%m-%d_%H:%M:%S` - == Starting Volume Clone with name $vclone_name ..." >> $log_file
	vclone_id=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Volume Clone Request ID:" | awk {'print $5'})
	/usr/local/bin/ibmcloud pi vol cl st $vclone_id 2>> $log_file
	if [ $? -eq 0 ]
	then
		vclone_start_action=$(/usr/local/bin/ibmcloud pi vol cl get $vclone_id | grep "Action" | awk {'print $2'})
		vclone_start_status=$(/usr/local/bin/ibmcloud pi vol cl get $vclone_id | grep "Status" | awk {'print $2'})
		if [[ "$vclone_start_action" == "start" ]] && [[ "$vclone_start_status" == "available" ]]
		then
			echo "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone $vclone_name Started and ready to execute..." >> $log_file
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
		fi
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi

}
####  END:FUNCTION -  Do the Volume Clone Start ####

####  START:FUNCTION - Do the Volume Clone ####
do_volume_clone() {
	echo "`date +%Y-%m-%d_%H:%M:%S` - == Creating Volume Clone Request with name $vclone_name ..." >> $log_file
	/usr/local/bin/ibmcloud pi vol cl cr --name $vclone_name --volumes $volumes_to_clone 2>> $log_file
	if [ $? -eq 0 ]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Volume Clone Request $vclone_name creation to finish..." >> $log_file
		vclone_percent=0
		while [ $vclone_percent -lt 100 ]
		do
			vclone_percent_before=$vclone_percent
			sleep 5
			vclone_percent=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Percent Completed:" | awk {'print $3'})
			if [[ "$vclone_percent" != "$vclone_percent_before" ]]
			then
				if [ $vclone_percent -eq 100 ]
				then
					echo "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name Done!" >> $log_file
				else
					echo "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name creation at $vclone_percent%" >> $log_file
				fi
			fi
		done
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi
}
####  END:FUNCTION -  Do the Volume Clone ####

####  START:FUNCTION  Check if VSI ID exists in bluexscrt file  ####
vsi_id_bluexscrt() {
	vsi_id=`cat $bluexscrt | grep -wi $vsi | awk {'print $3'}`
	if [[ $vsi_id == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - VSI ID missing or VSI Name $vsi doesn't exist in $bluexscrt file, please insert it there..."
	fi
}
####  END:FUNCTION  Check if VSI ID exists in bluexscrt file  ####

       ####  END - FUNCTIONS  ####

####  START: Iniciate Log and Validate Arguments  ####
timestamp=$(date +%F" "%T" "%Z)
echo "==== START ======= $timestamp =========" >> $log_file

if [ $# -eq 0 ]
then
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - No arguments supplied!!"
fi

case $1 in
   -h | --help)
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - Help requested!!"
    ;;

   -j)
	if [ $# -lt 3 ]
	then
		echo "Flag -j selected, but Arguments Missing!! Syntax: bluexport.sh -j VSI_NAME IMAGE_NAME"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but Arguments Missing!! Syntax: bluexport.sh -j VSI_NAME IMAGE_NAME"
	fi
	vsi=$2
	capture_name=${3^^}
	echo "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, watching only the Job Status for Capture Image $capture_name! Logging at $HOME/bluexport_j_"$capture_name".log" >> $log_file
	timestamp=$(date +%F" "%T" "%Z)
	echo "==== END ========= $timestamp =========" >> $log_file
	flagj=1
	log_file="$HOME/bluexport_j_"$capture_name".log"
	echo "" > $log_file
	timestamp=$(date +%F" "%T" "%Z)
	echo "==== START ======= $timestamp =========" >> $log_file
	cloud_login
	check_VSI_exists
	job_monitor
    ;;

   -a | -ta)
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	destination=$4
	capture_img_name=${3^^}
	capture_name=$capture_img_name"_"$capture_time
	if [[ $5 == "hourly" ]]
	then
		if [[ $destination == "both" ]] || [[ $destination == "cloud-storage" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Destination $destination is not valid with hourly parameter!! Only image-catalog is possible."
		fi
		old_img=$(date --date '1 hour ago' "+_%H")
		capture_name=$capture_img_name"_"$capture_hour
	elif [[ $5 == "daily" ]]
	then
		old_img=$(date --date '1 day ago' "+%Y-%m-%d")
	elif [[ $5 == "weekly" ]]
	then
		old_img=$(date --date '1 week ago' "+%Y-%m-%d")
	elif [[ $5 == "monthly" ]]
	then
		old_img=$(date --date '1 month ago' "+%Y-%m-%d")
	elif [[ $5 == "single" ]]
	then
		single=1
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Reocurrence must be daily or weekly or monthly or single!"
	fi
	if [[ $1 == "-ta" ]]
	then
		test=1
		echo "`date +%Y-%m-%d_%H:%M:%S` - Flag -t selected. Logging at "$job_test_log >> $log_file
		echo "`date +%Y-%m-%d_%H:%M:%S` - Testing only!! No Capture will be done!" >> $log_file
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== END ========= $timestamp =========" >> $log_file
		log_file=$job_test_log
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
	else
		test=0
	fi
	vsi=$2
	vsi_id_bluexscrt
	echo "`date +%Y-%m-%d_%H:%M:%S` - Starting Capture&Export for VSI Name: $vsi ..." >> $log_file
	echo "`date +%Y-%m-%d_%H:%M:%S` - Capture Name: $capture_name" >> $log_file
	echo "`date +%Y-%m-%d_%H:%M:%S` - Export Destination: $destination" >> $log_file
	if [[ $destination == "both" ]] || [[ $destination == "image-catalog" ]] || [[ $destination == "cloud-storage" ]]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is valid." >> $log_file
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is NOT valid!"
	fi
	volumes_cmd="/usr/local/bin/ibmcloud pi ins vol ls $vsi_id | tail -n +2"
    ;;

   -x | -tx)
	if [ $# -lt 6 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	capture_img_name=${4^^}
	capture_name=$capture_img_name"_"$capture_time
	if [[ $6 == "hourly" ]]
	then
		if [[ $destination == "both" ]] || [[ $destination == "cloud-storage" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Destination $destination is not valid with hourly parameter!! Only image-catalog is possible."
		fi
		old_img=$(date --date '1 hour ago' "+%H")
		capture_name=$capture_img_name"_"$capture_hour
	elif [[ $6 == "daily" ]]
	then
		old_img=$(date --date '1 day ago' "+%Y-%m-%d")
	elif [[ $6 == "weekly" ]]
	then
		old_img=$(date --date '1 week ago' "+%Y-%m-%d")
	elif [[ $6 == "monthly" ]]
	then
		old_img=$(date --date '1 month ago' "+%Y-%m-%d")
	elif [[ $6 == "single" ]]
	then
		single=1
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Reocurrence must be daily or weekly or monthly or single!"
	fi
	if [[ $1 == "-tx" ]]
	then
		test=1
		echo "`date +%Y-%m-%d_%H:%M:%S` - Flag -t selected. Logging at "$job_test_log >> $log_file
		echo "`date +%Y-%m-%d_%H:%M:%S` - Testing only!! No Capture will be done!" >> $log_file
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== END ========= $timestamp =========" >> $log_file
		log_file=$job_test_log
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
	else
		test=0
	fi
	IFS=' ' read -r -a exclude_names <<< "$2"
	exclude_grep_opts=""
	for name in "${exclude_names[@]}"
	do
		exclude_grep_opts+=" | grep -v $name"
	done
	echo "`date +%Y-%m-%d_%H:%M:%S` - Volumes Name to exclude: ${exclude_names[*]}" >> $log_file
	vsi=$3
	vsi_id_bluexscrt
	echo "`date +%Y-%m-%d_%H:%M:%S` - Starting Capture&Export for VSI Name: $vsi ..." >> $log_file
	echo "`date +%Y-%m-%d_%H:%M:%S` - Capture Name: $capture_name" >> $log_file
	destination=$5
	echo "`date +%Y-%m-%d_%H:%M:%S` - Export Destination: $destination" >> $log_file
	if [[ $destination == "both" ]] || [[ $destination == "image-catalog" ]] || [[ $destination == "cloud-storage" ]]
	then
		echo "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is valid!" >> $log_file
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is NOT valid!"
	fi
	volumes_cmd="/usr/local/bin/ibmcloud pi ins vol ls $vsi_id $exclude_grep_opts | tail -n +2"
    ;;

  -chscrt)
	if [ $# -lt 2 ]
	then
		echo "Arguments Missing!! Syntax: bluexport.sh $1 bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
	fi
	new_scrt=$2
	sed -i -e "s|bluexscrt $bluexscrt|bluexscrt $new_scrt|g" $HOME/bluexport.conf
	abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file change to $new_scrt !"
    ;;

  -viewscrt)
	scrt_in_use=$(cat $HOME/bluexport.conf | grep bluexscrt | awk {'print $2'})
	echo "Secret file in use is $scrt_in_use"
	abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file in use is $scrt_in_use"
    ;;

  -snapcr)
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 LPAR_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|[Comma separated Volumes name list to snap]"
	fi
	vsi=$2
	vsi_id_bluexscrt
	test=0
	snap_name=$3
	snap_name_exists=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name)
	if [[ "$snap_name_exists" != "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Already exists one Snapshot with name $snap_name, please choose a diferent name or use flag -snapupd to change the name."
	fi
	description=$4
	if [ -n "$description" ] && [ "$description" -eq "$description" ] 2>/dev/null
	then
		if [ $4 -eq 0 ]
		then
			description=""
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Argument DESCRIPTION must be 0 or a phrase inside quotes!! Syntax: bluexport.sh $1 LPAR_NAME SNAPSHOT_NAME 0|[\"DESCRIPTION\"] 0|[VOLUMES - Comma separated Volumes name list to snap]"
		fi
	else
		description="--description \""$description"\""
	fi
	volumes_to_snap=$5
	if [ -n "$volumes_to_snap" ] && [ "$volumes_to_snap" -eq "$volumes_to_snap" ] 2>/dev/null
	then
		if [ $5 -eq 0 ]
		then
			flag_volumes=""
			volumes_to_snap=""
			volumes_to_echo="ALL"
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Argument VOLUMES must be 0 or comma separated names or IDs!! Syntax: bluexport.sh $1 LPAR_NAME SNAPSHOT_NAME 0|[\"DESCRIPTION\"] 0|[VOLUMES - Comma separated Volumes name list to snap]"
		fi
	else
		flag_volumes="--volumes"
		volumes_to_echo=$volumes_to_snap
		volumes_to_snap="--volumes "$volumes_to_snap
	fi
	echo "`date +%Y-%m-%d_%H:%M:%S` - === Starting Snapshot $snap_name of VSI $vsi with volumes: $volumes_to_echo !" >> $log_file
	cloud_login
	check_VSI_exists
	do_snap_create
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished Snapshot $snap_name of VSI $vsi with volumes: $volumes_to_echo !"
    ;;

  -snapupd)
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
	fi
	test=0
	flagj=1
	vsi=$2
	vsi_id_bluexscrt
	snap_name=$3
	desc=$5
	sname=$4
	if ([ -n "$desc" ] && [ "$desc" -eq "$desc" ] && [ -n "$sname" ] && [ "$sname" -eq "$sname" ])2>/dev/null
	then
		if [ $4 -eq 0 ] && [ $5 -eq 0 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - You must pass at least one flag, DESCRIPTION or NEW_SNAPSHOT_NAME!..."
		fi
	fi
	echo "`date +%Y-%m-%d_%H:%M:%S` - === Starting Snapshot $snap_name Update !" >> $log_file
	cloud_login
	snap_name_exists=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name)
	if [[ "$snap_name_exists" == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Snapshot with name $snap_name does not exist, please choose a diferent name or use flag -snapcr to create one."
	fi
	description=$5
	if [ -n "$description" ] && [ "$description" -eq "$description" ] 2>/dev/null
	then
		if [ $5 -eq 0 ]
		then
			description=""
			new_description_echo=""
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Argument DESCRIPTION must be 0 or a phrase inside quotes!! Syntax:  bluexport.sh $1 VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
		fi
	else
		description="--description \""$description"\""
		new_description_echo="with new Description \"$5\""
	fi
	new_snap_name=$4
	if [ -n "$new_snap_name" ] && [ "$new_snap_name" -eq "$new_snap_name" ] 2>/dev/null
	then
		if [ $4 -eq 0 ]
		then
			new_name_echo=""
			new_name="--name \""$snap_name"\""
		else
			abort "`date +%Y-%m-%d_%H:%M:%S` - Argument NEW_SNAPSHOT_NAME must be 0 or a name!! Syntax:  bluexport.sh $1 VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
		fi
	else
		if [[ "$new_snap_name" == "$snap_name" ]]
		then
			new_name_echo=""
		else
			new_name_echo="with new Name "$new_snap_name
			snap_name_new=$new_snap_name
			new_name="--name \""$new_snap_name"\""
		fi
	fi
	check_VSI_exists
	do_snap_update
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished Snapshot $snap_name Update $new_name_echo !"
    ;;

  -snapdel)
	if [ $# -lt 3 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
	test=0
	flagj=1
#	vsi_name=$2
	vsi=$2
	vsi_id_bluexscrt
	snap_name=$3
#	vsi_ws=$(cat $bluexscrt | grep $vsi_name | awk {'print $4'})
#	vsi_ws_id=$(cat $bluexscrt | grep -m 1 $vsi_ws | awk {'print $2'})
#	vsi_id=$(cat $bluexscrt | grep $vsi_name | awk {'print $3'})
	echo "`date +%Y-%m-%d_%H:%M:%S` - === Starting Snapshot Delete $snap_name from VSI $vsi_name !" >> $log_file
	cloud_login
	check_VSI_exists
#	/usr/local/bin/ibmcloud pi ws tg $vsi_ws_id
	snap_name_exists=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name)
#	snap_name_exists=$(/usr/local/bin/ibmcloud pi ins snap ls $vsi_id | grep -w $snap_name)
	if [[ "$snap_name_exists" == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Snapshot with name $snap_name does not exist, please choose a diferent name or use flag -snapcr to create one."
	fi
	do_snap_delete
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished -  Snapshot $snap_name Deleted!"
    ;;

   -snaplsall)
	test=0
	echo "`date +%Y-%m-%d_%H:%M:%S` - === Starting Listing all Snapshot in all Workspaces !" >> $log_file
	cloud_login

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

	for ws in "${allws_array[@]}"
	do
		crn=$(grep "^$ws " "$bluexscrt" | awk '{print $2}')
		full_ws_name="${wsmap[$ws]}" # Get the full workspace name from the map
		echo "`date +%Y-%m-%d_%H:%M:%S` - === Listing Snapshots at Workspace $full_ws_name :" | tee -a $log_file
		/usr/local/bin/ibmcloud pi ws tg $crn 2>> $log_file | tee -a $log_file
		/usr/local/bin/ibmcloud pi ins snap ls 2>> $log_file | tee -a $log_file
	done
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Finished Listing all Snapshots in all Workpsaces"
    ;;

   -vclonelsall)
	test=0
	echo "`date +%Y-%m-%d_%H:%M:%S` - === Starting Listing all Volume Clones in all Workspaces !" >> $log_file
	cloud_login

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

	for ws in "${allws_array[@]}"
	do
		crn=$(grep "^$ws " "$bluexscrt" | awk '{print $2}')
		full_ws_name="${wsmap[$ws]}" # Get the full workspace name from the map
		echo "`date +%Y-%m-%d_%H:%M:%S` - === Listing Volume Clones at Workspace $full_ws_name :" | tee -a $log_file
		/usr/local/bin/ibmcloud pi ws tg $crn 2>> $log_file | tee -a $log_file
		/usr/local/bin/ibmcloud pi vol cl ls 2>> $log_file | tee -a $log_file
	done
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Finished Listing all Volume Clones in all Workpsaces"
    ;;

   -vclone)
	if [ $# -lt 8 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VOLUME_CLONE_NAME BASE_NAME LPAR_NAME (Replication)True|False (Rollback)True|False TARGET_STORAGE_TIER ALL|VOLUMES(Comma seperated Volumes name or IDs list to clone)"
	fi
	test=0
	vclone_name=$2
	base_name=$3
	vsi=$4
	replication=$5
	rollback=$6
	target_tier=$7
	volumes_to_clone=$8
	if [[ "$replication" != "True" ]] && [[ "$replication" != "False" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Replication value must be True or False...!"
	fi
	if [[ "$rollback" != "True" ]] && [[ "$rollback" != "False" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Rollback value must be True or False...!"
	fi
	if [[ "$target_tier" != "tier0" ]] && [[ "$target_tier" != "tier1" ]] && [[ "$target_tier" != "tier3" ]] && [[ "$target_tier" != "tier5k" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Target Tier must be tier0 or tier1 or tier3 or tier5k...!"
	fi
	cloud_login
	vclone_name_exists=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -w $vclone_name)
	if [[ "$vclone_name_exists" != "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone with name $vclone_name already exists, please choose a diferent name!"
	fi
	check_VSI_exists
	vsi_id=$(/usr/local/bin/ibmcloud pi ins ls | grep -wi $vsi | awk {'print $1'})
	if [[ "$volumes_to_clone" == "ALL" ]]
	then
		volumes_to_clone=$(/usr/local/bin/ibmcloud pi ins get $vsi_id | grep Volumes | sed -z 's/ //g' | sed -z 's/Volumes//g')
	fi
	echo "`date +%Y-%m-%d_%H:%M:%S` - === Starting the 3 processes of Volume Clone $vclone_name" >> $log_file
	echo "`date +%Y-%m-%d_%H:%M:%S` - This is the list of volumes that will be cloned: $volumes_to_clone" >> $log_file
	do_volume_clone
	do_volume_clone_start
	do_volume_clone_execute
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished -  Volume Clone $vclone_name !"
    ;;

   -vclonedel)
	if [ $# -lt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VOLUME_CLONE_NAME"
	fi
	test=0
	vclone_name=$2
	cloud_login
	vclone_name_exists=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -w $vclone_name)
	if [[ "$vclone_name_exists" == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone with name $vclone_name doesn't exists, please choose a diferent name!"
	fi
	echo "`date +%Y-%m-%d_%H:%M:%S` - === Trying to Delete Volume Clone with name $vclone_name" >> $log_file
	vclone_id=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Volume Clone Request ID:" | awk {'print $5'})
	/usr/local/bin/ibmcloud pi vol cl del $vclone_id
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Deleted Volume Clone with name $vclone_name !"
    ;;

   -v | --version)
	echo "  ### bluexport by Ricardo Martins - Blue Chip Portugal © 2023-2024"
	echo "  ### Version: $Version"
	abort "`date +%Y-%m-%d_%H:%M:%S` - Version requested!!"
    ;;

    *)
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -a or -x Missing or invalid Flag!"
    ;;
esac
####  END: Iniciate Log and Validate Arguments  ####

cloud_login
check_VSI_exists

####  START: Get Volumes to capture  ####
eval $volumes_cmd > $volumes_file | tee -a $log_file
volumes=$(cat $volumes_file | awk {'print $1'} | tr '\n' ',' | sed 's/,$//')
volumes_name=$(cat $volumes_file | awk {'print $2'} | tr '\n' ' ')
echo "`date +%Y-%m-%d_%H:%M:%S` - Volumes ID Captured: $volumes" >> $log_file
echo "`date +%Y-%m-%d_%H:%M:%S` - Volumes Name Captured: $volumes_name" >> $log_file
####  END: Get Volumes to capture  ####

####  START: Flush ASPs and IASP Memory to Disk  ####
flush_asps
####  END: Flush ASPs and IASP Memory to Disk  ####

####  START: Make the Capture and Export  ####
if [[ $destination == "image-catalog" ]]
then
	echo "`date +%Y-%m-%d_%H:%M:%S` - == Executing Capture to image catalog cloud command... ==" >> $log_file
	if [ $test -eq 1 ]
	then
		echo "/usr/local/bin/ibmcloud pi ins cap cr $vsi_id --destination $destination --name $capture_name --volumes \"$volumes\"" >> $log_file
	else
		rm $job_id
		/usr/local/bin/ibmcloud pi ins cap cr $vsi_id --destination $destination --name $capture_name --volumes "$volumes" 2>> $log_file | tee -a $log_file $job_id
	fi
else
	echo "`date +%Y-%m-%d_%H:%M:%S` - == Executing Capture and Export cloud command... ==" >> $log_file
	if [ $test -eq 1 ]
	then
		echo "/usr/local/bin/ibmcloud pi ins cap cr $vsi_id --destination $destination --name $capture_name --volumes \"$volumes\" --access-key $accesskey --secret-key $secretkey --region $region --image-path $bucket" >> $log_file
	else
		rm $job_id
		/usr/local/bin/ibmcloud pi ins cap cr $vsi_id --destination $destination --name $capture_name --volumes "$volumes" --access-key $accesskey --secret-key $secretkey --region $region --image-path $bucket 2>> $log_file | tee -a $log_file $job_id
	fi
fi
####  END: Make the Capture and Export  ####

####  START: Job Monitoring  ####
if [ $test -eq 0 ]
then
	echo "`date +%Y-%m-%d_%H:%M:%S` - => Iniciating Job Monitorization..." >> $log_file
else
	echo "`date +%Y-%m-%d_%H:%M:%S` - => Iniciating Job Monitorization..." >> $log_file
	abort "`date +%Y-%m-%d_%H:%M:%S` - Test Finished!"
fi

job_monitor
####  END: Job Monitoring  ####

       #####  END:CODE  #####

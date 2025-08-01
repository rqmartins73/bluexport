#!/bin/bash
#
# Capture IBM Cloud POWERVS VSI and Export to COS or/and Image Catalog and Snapshots
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
# Usage to list all Captured
# images in all Workspaces:             ./bluexport.sh -imglsall
#
# Usage to create a volume clone:   	./bluexport.sh -vclone VOLUME_CLONE_NAME BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) STORAGE_TIER ALL|(Comma seperated Volumes name list to clone)"
# Usage to delete a volume clone:	./bluexport.sh -vclonedel VOLUME_CLONE_NAME
# Usage to list all volume clones
#        in all Workspaces:		./bluexport.sh -vclonelsall
#
# Usage to change volume tier:          ./bluexport.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO
#
# Example:  ./bluexport.sh -a vsiprd vsiprd_img image-catalog daily            ---- Includes all Volumes and exports to COS and image catalog
# Example:  ./bluexport.sh -x ASP2_ vsiprd vsiprd_img both monthly             ---- Excludes Volumes with ASP2_ in the name and exports to image catalog and COS
# Example:  ./bluexport.sh -x "ASP2_ iASPname" vsiprd vsiprd_img both monthly  ---- Excludes Volumes with ASP2_ and iASPname in the name and exports to image catalog and COS
#
# Note: Reocurrence "hourly" and "daily" only permits captures to image-catalog
#
#
# Ricardo Martins - Blue Chip Portugal - 2023-2025
########################################################################################

       #####  START:CODE  #####

Version=3.7.7-24-gc1a862b
log_file=$(cat $HOME/bluexport.conf | grep -w "log_file" | awk {'print $2'})
bluexscrt=$(cat $HOME/bluexport.conf | grep -w "bluexscrt" | awk {'print $2'})
end_log_file='==== END ========= $timestamp ========='

#### START:FUNCTION - Echo to log file and screen  ####
echoscreen() {
	if [ -t 1 ]
	then
		echo $1
	fi
	if [[ $2 == "1" ]]
	then
		echo $1 >> $log_file
	fi
}
#### END:FUNCTION - Echo to log file and screen  ####

if [[ $1 != "-chscrt" ]] && [[ $1 != "-viewscrt" ]] && [[ $1 != "-v" ]] && [[ $1 != "--version" ]] && [[ $1 != "-h" ]] && [[ $1 != "--help" ]] && [[ $1 != "-help" ]] && [[ $1 != "" ]]
then
	####  START: Check if Config File exists  ####
	if [ ! -f $bluexscrt ]
	then
		echoscreen ""
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
		echo "Flags Used: $@" >> $log_file
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Config file $bluexscrt Missing!! Aborting!..." "1"
		echo "==== END ========= $timestamp =========" >> $log_file
		echoscreen ""
		exit 0
	fi
####  END: Check if Config File exists  ####
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
	operid_file=$(cat $HOME/bluexport.conf | grep -w "operid_file" | awk {'print $2'})
	vsi_list_id_tmp=$(cat $HOME/bluexport.conf | grep -w "vsi_list_id_tmp" | awk {'print $2'})
	vsi_list_tmp=$(cat $HOME/bluexport.conf | grep -w "vsi_list_tmp" | awk {'print $2'})
	volumes_file=$(cat $HOME/bluexport.conf | grep -w "volumes_file" | awk {'print $2'})
	vol_ch_tier=$(cat $HOME/bluexport.conf | grep -w "vol_ch_tier" | awk {'print $2'})
	vol_failed_tst=$(cat $HOME/bluexport.conf | grep -w "vol_failed_tst" | awk {'print $2'})
	snap_retention=$(cat $HOME/bluexport.conf | grep -w "snap_retention" | awk {'print $2'})
	iasp_names_file=$(cat $HOME/bluexport.conf | grep -w "iasp_names_file" | awk {'print $2'})
	single=0
	vsi_user=$(cat $bluexscrt | grep -w "VSI_USER" | awk {'print $2'})
	####  END: Constants Definition  #####

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

	region=$(cat $bluexscrt | grep -w "REGION" | awk {'print $2'})
	allws=$(grep '^ALLWS' $bluexscrt | cut -d' ' -f2-)
	wsnames=$(grep '^WSNAMES' $bluexscrt | cut -d' ' -f2-)
	####  END: Get Cloud Config Data  #####
	echoscreen ""
	echoscreen "   ### Logging at $log_file" ""
	echoscreen ""
fi

       #####  START: FUNCTIONS  #####

#### START:FUNCTION - Help  ####
help() {
	echoscreen ""
	echoscreen "Capture IBM Cloud POWERVS IBM i VSI and Export to COS or/and Image Catalog and Snapshots"
	echoscreen "Version 3.x now supports the creation, update, delete and list Snapshots."
	echoscreen ""
	echoscreen "Changing secret file:		./bluexport.sh -chscrt bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
	echoscreen ""
	echoscreen "View secret file in use:	./bluexport.sh -viewscrt"
	echoscreen ""
	echoscreen "Usage for all volumes:		./bluexport.sh -a VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echoscreen ""
	echoscreen "Usage for excluding volumes:	./bluexport.sh -x volumes_name_to_exclude VSI_Name_to_Capture Capture_Image_Name both|image-catalog|cloud-storage hourly|daily|weekly|monthly|single"
	echoscreen ""
	echoscreen "Usage for monitoring job:	./bluexport.sh -j VSI_NAME IMAGE_NAME"
	echoscreen ""
	echoscreen "Usage to create a snapshot:	./bluexport.sh -snapcr VSI_NAME SNAPSHOT_NAME 0|[DESCRIPTION] 0|[VOLUMES(Comma separated list)]"
	echoscreen ""
	echoscreen "Usage to update a snapshot:	./bluexport.sh -snapupd VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[DESCRIPTION]"
	echoscreen ""
	echoscreen "Usage to delete snapshot:	./bluexport.sh -snapdel VSI_NAME SNAPSHOT_NAME"
	echoscreen ""
	echoscreen "Usage to list all snapshot"
	echoscreen " in all Workspaces:		./bluexport.sh -snaplsall"
	echoscreen ""
	echoscreen "Usage to list all Captured"
	echoscreen " images in all Workspaces:      ./bluexport.sh -imglsall"
	echoscreen ""
	echoscreen "Usage to create a volume clone:	./bluexport.sh -vclone VOLUME_CLONE_NAME BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) STORAGE_TIER ALL|(Comma seperated Volumes name list to clone)"
	echoscreen ""
	echoscreen "Usage to delete a volume clone:	./bluexport.sh -vclonedel VOLUME_CLONE_NAME"
	echoscreen ""
	echoscreen "Usage to list all volume clones"
	echoscreen " in all Workspaces:		./bluexport.sh -vclonelsall"
	echoscreen ""
	echoscreen "Usage to change volume tier:    ./bluexport.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	echoscreen ""
	echoscreen "Example:  ./bluexport.sh -a vsiprd vsiprd_img image-catalog daily ---- Includes all Volumes and exports to COS and image catalog"
	echoscreen "Example:  ./bluexport.sh -x ASP2_ vsiprd vsiprd_img both monthly    ---- Excludes Volumes with ASP2_ in the name and exports to image catalog and COS"
	echoscreen 'Example:  ./bluexport.sh -x "ASP2_ iASPname" vsiprd vsiprd_img both monthly    ---- Excludes Volumes with ASP2_ and iASPname in the name and exports to image catalog and COS'
	echoscreen ""
	echoscreen "Flag t before a or x makes it a test and do not makes the capture"
	echoscreen "Example:  ./bluexport.sh -tx ASP2_ vsiprd vsiprd_img both single ---- Does not makes the export"
	echoscreen ""
	echoscreen "Note: Reocurrence \"hourly\" and \"daily\" only permits captures to image-catalog"
	echoscreen ""
	echoscreen "Ricardo Martins - Blue Chip Portugal - 2023-2025"
	echoscreen ""
}
#### END:FUNCTION - Help  ####

#### START:FUNCTION - Finish log file when aborting  ####
abort() {
	echo $1 >> $log_file
	if [ -t 1 ]
	then
		echo ""
		echo "   ### $1"
		echo ""
	fi
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
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - There is no Image from $old_img - Nothing to delete in image catalog." "1"
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Deleting from image catalog image name $img_name_old - image ID $img_id_old - from day $old_img... ==" "1"
		sh -c '/usr/local/bin/ibmcloud pi img del '$img_id_old 2>> $log_file | tee -a $log_file
	fi
	if [ ! $objstg_img ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - No image from previous export to delete in Object Storage." "1"
	else
		if [ ! $today_img ]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Something went wrong... Today's image is not in Bucket $bucket. Keeping ( Not deleted ) image name $objstg_img from day $old_img... ==" "1"
		else
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Deleting from Bucket $bucket, image name $objstg_img from day $old_img... ==" "1"
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
	if [[ $vsi_id == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Instance $vsi exists in your bluexscrt file, but do not exists on IBM Cloud. Please update bluexscrt file!"
	fi
	cat $vsi_list_id_tmp | awk {'print $2'} > $vsi_list_tmp
}
####  END:FUNCTION - Target DC and List all VSI in the POWERVS DC and Get VSI Name and ID  ####

####  START:FUNCTION - Monitor Capture and Export Job  ####
job_monitor() {
    # Get Capture & Export Job ID #
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Job log in file $job_log" "1"
	if [ $flagj -eq 1 ]
	then
		operid=$(cat $operid_file | grep -w $capture_name | awk {'print $2'})
		job=$(sh -c '/usr/local/bin/ibmcloud pi job ls | grep -B2 -A7 '$operid' | grep "Job ID" | awk {'\''print $3'\''}' 2>> $log_file | tee -a $log_file)
	else
		job=$(cat $job_id | grep "Job ID " | awk {'print $3'})
		if [[ $job == "" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Capturing instance $vsi has Failed, see log file!"
		fi
		operid=$(/usr/local/bin/ibmcloud pi job ls | grep -A7 $job | grep "Job ID" | awk {'print $3'})
		echo $capture_name" "$operid >> $operid_file
	fi
    # Check Capture & Export Job Status #
	echo "Job Monitoring of VM Capture "$capture_name" - Job ID:" $job >> $job_log
	while true
	do
		sh -c '/usr/local/bin/ibmcloud pi job get '$job 1> $job_monitor 2>>$job_log | tee -a $log_file
		job_status=$(cat $job_monitor | grep "State " | awk {'print $2'})
		message=$(cat $job_monitor |grep "Message" | cut -f 2- -d ' ')
		operation=$(cat $job_monitor |grep "Progress" | awk {'print $2'})
		if [[ $job_status == "completed" ]]
		then
			if [[ $destination == "cloud-storage" ]]
			then
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image Capture and Export of $vsi to Bucket $bucket Completed !!" "1"
			elif [[ $destination == "both" ]]
			then
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image Capture and Export of $vsi to Image Catalog Completed !!" "1"
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image Capture and Export of $vsi to Bucket $bucket Completed !!" "1"
			else
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Image Capture and Export of $vsi to Image Catalog Completed !!" "1"
			fi
			if [ $single -eq  0 ] && [ $flagj -ne 1 ]
			then
				delete_previous_img
			fi
			echo "`date +%Y-%m-%d_%H:%M:%S` - Finished Successfully!!" >> $job_log
			job_log_perm=$job_log_short"_"$capture_name".log"
			cp $job_log $job_log_perm
			if [ $flagj -eq 1 ] && [ -t 1 ]
			then
				echoscreen ""
				echoscreen "   ### Log files used:"
				echoscreen "   ### $log_file"
				echoscreen "   ### $job_log"
				echoscreen "   ### $job_monitor"
				echoscreen "   ### $job_log_perm"
				echoscreen ""
			fi
			abort "`date +%Y-%m-%d_%H:%M:%S` - Finished Successfully!!"
		elif [[ $job_status == "" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - FAILED Getting Job ID or no Job Running!" "1"
			abort "`date +%Y-%m-%d_%H:%M:%S` - Check file $job_monitor for more details."
		elif [[ $job_status == "failed" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Job ID $job Status: ${job_status^^}" "1"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Message: $message" "1"
			abort "`date +%Y-%m-%d_%H:%M:%S` - Job Failed, check message!!"
		else
			if [[ $operation != $operation_before ]]
			then
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Job ID $job Status: ${job_status^^}" "1"
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Message: $message" "1"
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Operation Change... Operation Running Now: ${operation^^}" "1"
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

####  START:FUNCTION - Get iASP name  ####
get_iASP_name() {
	if [ $test -eq 0 ]
	then
		vsi_ip=$(cat $bluexscrt | grep -wi $vsi | awk {'print $2'})
		vsi_status=$(/usr/local/bin/ibmcloud pi ins get $vsi_id | grep -m1 Status | awk {'print $2'})
		shutoff=0
		if [[ $vsi_status != "SHUTOFF" ]]
		then
			if ping -c1 -w3 $vsi_ip &> /dev/null
			then
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi is in Status: $vsi_status" "1"
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Ping VSI $vsi at IP $vsi_ip OK." "1"
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Getting $vsi iASP Names..." "1"
			else
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi is in Status: $vsi_status!" "1"
				abort "`date +%Y-%m-%d_%H:%M:%S` - Cannot ping VSI $vsi with IP $vsi_ip ! Aborting..."
			fi
		else
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi is in Status: $vsi_status" "1"
			shutoff=1
			return
		fi
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Trying to ssh into VSI $vsi..." "1"
		ssh -T -q -i $sshkeypath $vsi_user@$vsi_ip exit
		if [ $? -eq 255 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Unable to SSH to $vsi and not able to get iASP status! Try STRTCPSVR *SSHD on the $vsi VSI. Aborting..."
		else
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - ssh into VSI $vsi succeded..." "1"
			cmd="system 'WRKCFGSTS CFGTYPE(*DEV) CFGD(*ASP)'"
			iasp_name=$(ssh -T -i $sshkeypath $vsi_user@$vsi_ip $cmd | tail -n+4 | head -n-1 | awk {'print $1":"$3'})
			echo "" > $iasp_names_file
			for line in $iasp_name
			do
				line_status=$(echo $line | cut -d ":" -f2-)
				if [[ $line_status == "AVAILABLE" ]]
				then
					echo $line | cut -d: -f1 >> $iasp_names_file
				fi
			done
			iasp_names=$(cat $iasp_names_file)
			if [[ $iasp_names == "" ]]
			then
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi doesn't have iASPs or are Varied OFF... Moving on..." "1"
			else
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi iASP Names: $iasp_names" "1"
			fi
		fi
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Running in test mode, skipping get iASP name." "1"
	fi
}
####  END:FUNCTION - Get iASP name  ####

####  START:FUNCTION - Check if VSI exists in secret file and Get VSI IP and iASP NAME if exists  ####
check_locally_VSI_exists() {

	echo "" > $job_log
	vsi_exists=$(cat $bluexscrt | grep -wi $vsi)
	if [[ $vsi_exists != "" ]]
	then
		vsiwsshort=$(cat $bluexscrt | grep -wi $vsi | awk {'print $4'})
		shortnamecrn=$(cat $bluexscrt | grep -wi $vsiwsshort | awk {'print $2'})
		dc_vsi_list "$shortnamecrn"
		vsi_cloud_name=$(cat $vsi_list_tmp | grep -wi $vsi | awk {'print $1'})
		wsshortlist=$(cat $bluexscrt | grep -w ALLWS)
		wsposition=$(echo "$wsshortlist" | tr " " "\n" | grep -n "$vsiwsshort" | cut -d: -f1)
		full_ws_name=$(cat $bluexscrt | grep -w WSNAMES | sed -z 's/:/ /g'|awk {'print $'$wsposition''})
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI $vsi_cloud_name was found in $full_ws_name..." "1"
		if [ $flagj -eq 0 ]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - VSI to Capture: $vsi_cloud_name" "1"
			get_iASP_name
		fi
	else
		echoscreen ""
		echoscreen "   ### VSI $vsi not found in any of the workspaces available in bluexscrt file!"
		echoscreen ""
		exit 0
	fi
}
####  END:FUNCTION - Check if VSI exists in secret file and Get VSI IP and iASP NAME if exists  ####

####  START:FUNCTION Flush ASPs and iASP Memory to Disk  ####
flush_asps() {
	if [ $test -eq 0 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flushing Memory to Disk for SYSBAS..." "1"
		ssh -T -i $sshkeypath $vsi_user@$vsi_ip 'system "CHGASPACT ASPDEV(*SYSBAS) OPTION(*FRCWRT)"' >> $log_file | tee -a $log_file
		if [[ $iasp_name != "" ]]
		then
			#########
			for iasp_name in $iasp_names
			do
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flushing Memory to Disk for $iasp_name ..." "1"
				ssh -T -i $sshkeypath $vsi_user@$vsi_ip 'system "CHGASPACT ASPDEV('$iasp_name') OPTION(*FRCWRT)"' >> $log_file | tee -a $log_file
			done
			#########
		fi
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flushing Memory to Disk for SYSBAS..." "1"
		if [[ $iasp_name != "" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flushing Memory to Disk for $iasp_name ..." "1"
		fi
	fi
}
####  END:FUNCTION Flush ASPs and iASP Memory to Disk  ####

####  START:FUNCTION - Do the Snapshot Create  ####
do_snap_create() {
	flush_asps
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Snapshot $snap_name of Instance $vsi with volumes $volumes_to_echo" "1"
	snap_cr_cmd="/usr/local/bin/ibmcloud pi ins snap cr $vsi_id --name $snap_name $description $flag_volumes $volumes_to_snap"
	eval $snap_cr_cmd 2>> $log_file
	if [ $? -eq 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	else
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Snapshot $snap_name to reach 100%..." "1"
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
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name reached 100% - Done!" "1"
				else
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name at $snap_percent%" "1"
				fi
			fi
		done
	fi
}
####  END:FUNCTION - Do the Snapshot Create  ####

####  START:FUNCTION - Do the Snapshot Update  ####
do_snap_update() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Snapshot $snap_name Update $new_name_echo" "1"
	snap_id=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name | awk {'print $1'})
	snap_upd_cmd="/usr/local/bin/ibmcloud pi ins snap upd $snap_id $description $new_name"
	eval $snap_upd_cmd 2>> $log_file
	if [ $? -eq 0 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name updated $new_name_echo $new_description_echo - Done!" "1"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - FAILED - Oops something went wrong!... Check the log above this line..."
	fi
}
####  END:FUNCTION - Do the Snapshot Update  ####

####  START:FUNCTION - Do the Snapshot Delete  ####
do_snap_delete() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Snapshot $snap_name Delete" "1"
	snap_id=$(/usr/local/bin/ibmcloud pi ins snap ls | grep -w $snap_name | awk {'print $1'})
	/usr/local/bin/ibmcloud pi ins snap del $snap_id 2>> $log_file
	if [ $? -eq 0 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Snapshot $snap_name deletion to reach 100%..." "1"
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
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name Deleted. - Done!" "1"
				else
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Snapshot $snap_name deletion at $snap_percent%" "1"
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
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Volume Clone with name $vclone_name ..." "1"
	/usr/local/bin/ibmcloud pi vol cl ex $vclone_id --name $base_name --replication-enabled=$replication --rollback-prepare=$rollback --target-tier $target_tier 2>> $log_file
	if [ $? -eq 0 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Volume Clone $vclone_name execution to finish..." "1"
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
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone $vclone_name Done and ready to be used!" "1"
				else
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone $vclone_name execution at $vcloneex_percent%" "1"
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
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Starting Volume Clone with name $vclone_name ..." "1"
	vclone_id=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Volume Clone Request ID:" | awk {'print $5'})
	/usr/local/bin/ibmcloud pi vol cl st $vclone_id 2>> $log_file
	if [ $? -eq 0 ]
	then
		vclone_start_action=$(/usr/local/bin/ibmcloud pi vol cl get $vclone_id | grep "Action" | awk {'print $2'})
		vclone_start_status=$(/usr/local/bin/ibmcloud pi vol cl get $vclone_id | grep "Status" | awk {'print $2'})
		if [[ "$vclone_start_action" == "start" ]] && [[ "$vclone_start_status" == "available" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone $vclone_name Started and ready to execute..." "1"
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
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Creating Volume Clone Request with name $vclone_name ..." "1"
	/usr/local/bin/ibmcloud pi vol cl cr --name $vclone_name --volumes $volumes_to_clone 2>> $log_file
	if [ $? -eq 0 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Waiting for Volume Clone Request $vclone_name creation to finish..." "1"
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
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name Done!" "1"
				else
					echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone Request $vclone_name creation at $vclone_percent%" "1"
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
	vsi_ws=$(cat $bluexscrt | grep -i $vsi | awk {'print $4'})
	vsi_ws_id=$(cat $bluexscrt | grep -m 1 $vsi_ws | awk {'print $2'})
	vsi_id=$(cat $bluexscrt | grep -i $vsi | awk {'print $3'})
}
####  END:FUNCTION  Check if VSI ID exists in bluexscrt file  ####

####  START:FUNCTION  Change Instance Volumes Tier  ####
vchtier() {
	if [[ $volumes == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - There are no volumes with any of these words \"${volchtier_names[*]}\" in instance $vsi_cloud_name"
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes ID to be changed to tier $tier: $volumes" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes Name to be changed to tier $tier: $volumes_name" "1"
	volumes_ids=$(echo $volumes | sed -z 's/,/\n/g')
	echo "" > $vol_ch_tier
	failed_vol=""
	same_tier=0
	for vol in $volumes_ids
	do
		vol_name=$(cat $volumes_file | grep $vol | awk {'print $2'})
		echoscreen "Changing volume $vol_name with Volume ID $vol to tier $tier" "1"
		/usr/local/bin/ibmcloud pi vol act $vol --target-tier $tier 2>&1 | tee -a $log_file | tee $vol_failed_tst
		failed_vol_temp=$(cat $vol_failed_tst | grep "current storage tier")
		if [[ $failed_vol_temp == "" ]]
		then
			cat $vol_failed_tst >> $vol_ch_tier
		else
			same_tier=1
		fi
	done
	failed_vol=$(cat $vol_ch_tier | grep -B2 Failed | grep Performing | awk {'print $5'})
	if [[ $failed_vol != "" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Some volumes Failed to change tier!" "1"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Try changing the tier manually with the following commands..." "1"
		for vol in $failed_vol
		do
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - /usr/local/bin/ibmcloud pi vol act $vol --target-tier $tier" "1"
		done
		abort "`date +%Y-%m-%d_%H:%M:%S` - Tier change finished, but there was errors! Please check the log above to see the errors..."
	fi
	if [ $same_tier -eq 1 ]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Some volumes were already in tier $tier, no action done on those volumes!" "1"
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - Tier change finished successfuly!"

}
####  END:FUNCTION  Change Instance Volumes Tier  ####

####  START:FUNCTION  Export to COS an existent Image  ####
export_img() {
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
}
####  END:FUNCTION  Export to COS an existent Image  ####

####  START:FUNCTION  Delete Image from image-catalog  ####
delete_img() {
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
}
####  END:FUNCTION  Export to COS an existent Image  ####

#################  GRS Code  ####################

####  START:FUNCTION  Create Volume Group  ####
create_vg() {
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting Create $vg_flag_echo $vg_name" "1"
	echoscreen ""
	test=0
	flagj=1
	vsi_id_bluexscrt
	cloud_login
	check_locally_VSI_exists
	volumes_to_GRS=$(/usr/local/bin/ibmcloud pi ins vol ls $vsi_id | tail -n +2 | awk {'print $1'} | sed -z 's/\n/,/g' | sed 's/.$//')
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
	volumes_rep=$(echo $volumes_to_GRS | sed -z 's/,/\n/g')
	index=0
	fail=0
	all_good=0
	while [ $all_good -eq 0 ]
	do
		for volume in $volumes_rep
		do
			tmp_vol=$(/usr/local/bin/ibmcloud pi vol get $volume | grep -we "Replication Enabled" -we "Name" -we "ID")
			ret=$?
			if [ $ret -ne 0 ]
			then
				abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
			fi
			is_vol_rep_enabled=$(echo $tmp_vol | awk {'print $7'})
			vol_name=$(echo $tmp_vol | awk {'print $4'})
			vol_id=$(echo $tmp_vol | awk {'print $2'})
			if [[ "$is_vol_rep_enabled" != "true" ]]
			then
				fail=1
				vol_not_rep_enabled[$index]=$vol_name
				vol_id_not_rep_enabled[$index]=$vol_id
				index=$((index + 1))
			fi
		done
		all_good=1
		if [ $fail -eq 1 ]
		then
			echoscreen ""
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Create $vg_flag_echo $vg_name can not continue because the following volumes are not replication enabled" "1"	
			for i in ${vol_not_rep_enabled[@]}
			do
				echoscreen "$i" "1"
			done
			read -p "Do you want to enable replication on these volumes (Y/N) ? " enable_rep
			if [[ "$enable_rep" == "Y" ]] || [[ "$enable_rep" == "y" ]]
			then
				echoscreen ""
				echoscreen "OK, let's try enable the replication on the volumes..." "1"
				echoscreen ""
				index=0
				for i in ${vol_not_rep_enabled[@]}
				do
					echoscreen "Enabling replication on volume $i" "1"
					/usr/local/bin/ibmcloud pi vol act ${vol_id_not_rep_enabled[$index]} --replication-enabled=True
					index=$((index + 1))
					ret=$?
					if [ $ret -ne 0 ]
					then
						abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
					fi
					echoscreen ""
				done
				fail=0
				all_good=0
				echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Now waiting one minute for the volumes to update..." "1"
				sleep 60
			fi
		fi
	done
	if [ $fail -eq 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - If you still want to create a $vg_flag_echo, please enable replication on the volumes listed above!..."
	fi
	echoscreen ""
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - All good with the volumes, now creating $vg_flag_echo $vg_name" "1"
	/usr/local/bin/ibmcloud pi vg cr $vg_flag $vg_name --member-volume-ids "$volumes_to_GRS"
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
	vgcsg_ready=""
	while [[ "$vgcsg_ready" != "available" ]]
	do
		sleep 5
		vgcsg_ready=$(/usr/local/bin/ibmcloud pi vg ls | grep -w $vg_name | awk {'print $5'})
		ret=$?
		if [ $ret -ne 0 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
		fi
		if [[ "$vgcsg_ready" == "available" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - $vg_flag_echo $vg_name created!... Done!" "1"
		else
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - $vg_flag_echo $vg_name still $vgcsg_ready" "1"
		fi
		if [[ "$vgcsg_ready" == "error" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - $vg_flag_echo $vg_name still $vgcsg_ready" "1"
			abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
		fi
	done
	vg_id=$(/usr/local/bin/ibmcloud pi vg ls | grep -w $vg_name | awk {'print $1'})
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
	copy_sts="inconsistent_copying"	
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Checking state of the Consistency Group, please wait..." "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Copy Status: $copy_sts" "1"
	error=0
	while [[ "$copy_sts" == "inconsistent_copying" ]] || [[ "$copy_sts" == "updating" ]]
	do
		if [ $error -eq 5 ]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong with the VG Creation... Check in IBM Cloud CLI the possibles reasons."
		fi
		sleep 40
		copy_sts=$(/usr/local/bin/ibmcloud pi vg sd $vg_id | grep -w "State:" | awk {'print $2'})
		#ret=$?
		if [[ $copy_sts == "" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line... Retrying..."
			error=$((error+1))
		fi
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Percentage by Volumes:"
		/usr/local/bin/ibmcloud pi vg rcr $vg_id | grep rcrel | awk {'print $1" "$4" "$11"%"'}
		# ret=$?
		# if [ $ret -ne 0 ]
		# then
			# abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
		# fi
		if [[ "$copy_sts" == "consistent_copying" ]]
		then
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Copy Status: $copy_sts" "1"
			echoscreen "`date +%Y-%m-%d_%H:%M:%S` - $vg_flag_echo $vg_name ready to be onboarded in the DR site!" "1"
		fi
	done
}
####  END:FUNCTION  Create Volume Group  ####

####  START:FUNCTION  Onboarding auxiliary Volumes  ####
onboard_aux_vol() {
# ./bluexport.sh -onboard LPAR_NAME
	test=0
	flagj=1
	vsi_id_bluexscrt
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting onboarding volumes for LPAR $vsi" "1"
	echoscreen ""
	cloud_login
	check_locally_VSI_exists
	volumes_to_GRS=$(/usr/local/bin/ibmcloud pi ins vol ls $vsi_id | tail -n +2 | awk {'print $1'} | sed -z 's/\n/,/g' | sed 's/.$//')
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
	aux_volumes_to_onboard=$(/usr/local/bin/ibmcloud pi ins vol ls $vsi_id --json | grep -w '"auxVolumeName":' | awk {'print $2'} | sed -z 's/\"//g'| sed -z 's/,//g')
	index=0
	for i in $aux_volumes_to_onboard
	do
		aux_volumes[$index]=$i
		index=$((index + 1))
	done
	volume_name_to_onboard=$(/usr/local/bin/ibmcloud pi ins vol ls $vsi_id --json | grep -w '"name":' | awk {'print $2'} | sed -z 's/\"//g'| sed -z 's/,//g')
	index=0
	for i in $volume_name_to_onboard
	do
		volume_name[$index]=$i
		index=$((index + 1))
	done
	index=0
	for volume in ${aux_volumes[@]}
	do
		if [[ "$volume" == "" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Onboarding can not continue because volume $volume_name[$index] do not have an auxiliary volume!..."
		fi
		index=$((index + 1))
	done
	aux_vol_to_onboard=$(echo ${aux_volumes[@]}| sed -z 's/ /,/g')
	/usr/local/bin/ibmcloud pi ws tg $target_ws_crn
	/usr/local/bin/ibmcloud pi vol on cr --auxiliary-volumes $aux_vol_to_onboard --source-crn $vsi_ws_id
	ret=$?
	if [ $ret -ne 0 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` -     FAILED - Oops something went wrong!... Check messages above this line..."
	fi
	# Testar o status do onboard com o onboard_id=$(/usr/local/bin/ibmcloud pi vol on ls | grep ${aux_volumes[0]} | awk {'print $1'})
	# onboard_status=$(/usr/local/bin/ibmcloud pi vol on ls | grep $onboard_id | awk {'print $2'})
	# onboard_status=""
	#while true
	#do
	#	onboard_previous_status=$onboard_status
	#	onboard_status=$(/usr/local/bin/ibmcloud pi vol on ls | grep $onboard_id | awk {'print $2'})
	#	if [[ "$onboard_status" != "$onboard_previous_status" ]]
	#	then
	#		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Onboard Request Status is $onboard_status !" "1"
	#	elif [[ "$onboard_status" == "SUCCESS" ]]
	#	then
	#		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Onboard Request done!" "1"
	#		break
	#	fi
	#done
}
####  END:FUNCTION  Onboarding auxiliary Volumes  ####

####  START:FUNCTION  Stop Volume Group  ####
stop_vg() {
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
}
####  END:FUNCTION  Stop Volume Group  ####

####  START:FUNCTION  Start Volume Group  ####
start_vg() {
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
}
####  END:FUNCTION  Start Volume Group  ####

       ####  END - FUNCTIONS  ####

####  START: Iniciate Log and Validate Arguments  ####
timestamp=$(date +%F" "%T" "%Z)
echo "==== START ======= $timestamp =========" >> $log_file
echo "Flags Used: $@" >> $log_file

if [ $# -eq 0 ]
then
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - No arguments supplied!!"
fi


case $1 in
   -h | --help | -help)
	help
	abort "`date +%Y-%m-%d_%H:%M:%S` - Help requested!!"
    ;;

   -j)
	if [ $# -lt 3 ]
	then
		echoscreen "Flag -j selected, but Arguments Missing!! Syntax: bluexport.sh -j VSI_NAME IMAGE_NAME"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but Arguments Missing!! Syntax: bluexport.sh -j VSI_NAME IMAGE_NAME"
	fi
	if [ $# -gt 3 ]
	then
		echoscreen "Flag -j selected, but too many arguments!! Syntax: bluexport.sh -j VSI_NAME IMAGE_NAME"
		abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, but too many arguments!! Syntax: bluexport.sh -j VSI_NAME IMAGE_NAME"
	fi
	vsi=$2
	capture_name=${3^^}
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flag -j selected, watching only the Job Status for Capture Image $capture_name! Logging at $HOME/bluexport_j_$capture_name.log" "1"
	timestamp=$(date +%F" "%T" "%Z)
	echo "==== END ========= $timestamp =========" >> $log_file
	flagj=1
	log_file="$HOME/bluexport_j_"$capture_name".log"
	echoscreen "" "1"
	timestamp=$(date +%F" "%T" "%Z)
	echo "==== START ======= $timestamp =========" >> $log_file
	echo "Flags Used: $@" >> $log_file
	cloud_login
	check_locally_VSI_exists
	job_monitor
    ;;

   -a | -ta)
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	if [ $# -gt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	destination=$4
	capture_img_name=${3^^}
	capture_name=$capture_img_name"_"$capture_time
	if [[ $5 == "hourly" ]] || [[ $5 == "daily" ]]
	then
		if [[ $destination == "both" ]] || [[ $destination == "cloud-storage" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Destination $destination is not valid with hourly and daily parameter!! Only image-catalog is possible."
		fi
		if [[ $5 == "hourly" ]]
		then
			old_img=$(date --date '1 hour ago' "+_%H")
			capture_name=$capture_img_name"_"$capture_hour
		fi
		if [[ $5 == "daily" ]]
		then
			old_img=$(date --date '1 day ago' "+%Y-%m-%d")
		fi
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - Reocurrence must be weekly or monthly or single!"
	fi
	if [[ $1 == "-ta" ]]
	then
		test=1
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flag -t selected. Logging at $job_test_log" "1"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Testing only!! No Capture will be done!" "1"
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== END ========= $timestamp =========" >> $log_file
		log_file=$job_test_log
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
		echo "Flags Used: $@" >> $log_file
	else
		test=0
	fi
	vsi=$2
	vsi_id_bluexscrt
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting Capture&Export for VSI Name: $vsi ..." "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Capture Name: $capture_name" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination: $destination" "1"
	if [[ $destination == "both" ]] || [[ $destination == "image-catalog" ]] || [[ $destination == "cloud-storage" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is valid." "1"
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
	if [ $# -gt 6 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 EXCLUDE_NAME VSI_NAME IMAGE_NAME EXPORT_LOCATION [daily|weekly|monthly|single]"
	fi
	capture_img_name=${4^^}
	capture_name=$capture_img_name"_"$capture_time
	if [[ $6 == "hourly" ]] || [[ $6 == "daily" ]]
	then
		if [[ $destination == "both" ]] || [[ $destination == "cloud-storage" ]]
		then
			abort "`date +%Y-%m-%d_%H:%M:%S` - Destination $destination is not valid with hourly and daily parameter!! Only image-catalog is possible."
		fi
		if [[ $6 == "hourly" ]]
		then
			old_img=$(date --date '1 hour ago' "+%H")
			capture_name=$capture_img_name"_"$capture_hour
		fi
		if [[ $6 == "daily" ]]
		then
			old_img=$(date --date '1 day ago' "+%Y-%m-%d")
		fi
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
		abort "`date +%Y-%m-%d_%H:%M:%S` - Reocurrence must be weekly or monthly or single!"
	fi
	if [[ $1 == "-tx" ]]
	then
		test=1
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Flag -t selected. Logging at $job_test_log" "1"
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Testing only!! No Capture will be done!" "1"
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== END ========= $timestamp =========" >> $log_file
		log_file=$job_test_log
		timestamp=$(date +%F" "%T" "%Z)
		echo "==== START ======= $timestamp =========" >> $log_file
		echo "Flags Used: $@" >> $log_file
	else
		test=0
	fi
	IFS=' ' read -r -a exclude_names <<< "$2"
	exclude_grep_opts=""
	for name in "${exclude_names[@]}"
	do
		exclude_grep_opts+=" | grep -v $name"
	done
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes Name to exclude: ${exclude_names[*]}" "1"
	vsi=$3
	vsi_id_bluexscrt
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Starting Capture&Export for VSI Name: $vsi ..." "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Capture Name: $capture_name" "1"
	destination=$5
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination: $destination" "1"
	if [[ $destination == "both" ]] || [[ $destination == "image-catalog" ]] || [[ $destination == "cloud-storage" ]]
	then
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is valid!" "1"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Export Destination $destination is NOT valid!"
	fi
	volumes_cmd="/usr/local/bin/ibmcloud pi ins vol ls $vsi_id $exclude_grep_opts | tail -n +2"
    ;;

  -vchtier)
	tier="tier$4"
	test=0
	flagj=1
	if [ $# -lt 4 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	fi
	if [ $# -gt 4 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO"
	fi
	IFS=' ' read -r -a volchtier_names <<< "$3"
	volchtier_grep_opts=""
	volchtier_grep_opts=" | grep"
	for name in "${volchtier_names[@]}"
	do
		volchtier_grep_opts+=" -e $name"
	done
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Common Name of Volumes to change to tier $tier: ${volchtier_names[*]}" "1"
	vsi=$2
	vsi_id_bluexscrt
	volumes_cmd="/usr/local/bin/ibmcloud pi ins vol ls $vsi_id $volchtier_grep_opts | tail -n +1"
	cloud_login
	check_locally_VSI_exists
	eval $volumes_cmd > $volumes_file | tee -a $log_file
	volumes=$(cat $volumes_file | awk {'print $1'} | tr '\n' ',' | sed 's/,$//')
	volumes_name=$(cat $volumes_file | awk {'print $2'} | tr '\n' ' ')
#exit 0
	vchtier
	;;

  -chscrt)
	if [ $# -lt 2 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
	fi
	if [ $# -gt 2 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 bluexscrt_file_name - Use the full path ex: /home/user/bluexscrt_new"
	fi
	new_scrt=$2
	sed -i -e "s|bluexscrt $bluexscrt|bluexscrt $new_scrt|g" $HOME/bluexport.conf
	abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file change to $new_scrt !"
    ;;

  -viewscrt)
    if [ $# -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1"
	fi
	scrt_in_use=$(cat $HOME/bluexport.conf | grep bluexscrt | awk {'print $2'})
	abort "`date +%Y-%m-%d_%H:%M:%S` - Secret file in use is $scrt_in_use"
    ;;

  -snapcr)
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 LPAR_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|[Comma separated Volumes name list to snap]"
	fi
	if [ $# -gt 5 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 LPAR_NAME SNAPSHOT_NAME 0|\"DESCRIPTION\" 0|[Comma separated Volumes name list to snap]"
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
		flag_volumes="--volumes "
		volumes_to_echo=$volumes_to_snap
#		volumes_to_snap="--volumes "$volumes_to_snap
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Snapshot $snap_name of VSI $vsi with volumes: $volumes_to_echo !" "1"
	cloud_login
	check_locally_VSI_exists
	do_snap_create
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished Snapshot $snap_name of VSI $vsi with volumes: $volumes_to_echo !"
    ;;

  -snapupd)
	if [ $# -lt 5 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
	fi
	if [ $# -gt 5 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 VSI_NAME SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|[\"DESCRIPTION\"]"
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
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Snapshot $snap_name Update !" "1"
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
	check_locally_VSI_exists
	do_snap_update
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished Snapshot $snap_name Update $new_name_echo !"
    ;;

  -snapdel)
	if [ $# -lt 3 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
	if [ $# -gt 3 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
	test=0
	flagj=1
	vsi=$2
	vsi_id_bluexscrt
	snap_name=$3
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Snapshot Delete $snap_name from VSI $vsi !" "1"
	cloud_login
	/usr/local/bin/ibmcloud pi ws tg $vsi_ws_id
	snap_name_exists=$(/usr/local/bin/ibmcloud pi ins snap ls $vsi_id | grep -w $snap_name)
	if [[ "$snap_name_exists" == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Snapshot with name $snap_name does not exist, please choose a diferent name or use flag -snapcr to create one."
	fi
	do_snap_delete
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully finished -  Snapshot $snap_name Deleted!"
    ;;

   -snaplsall)
    if [ $# -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1"
	fi
	test=0
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Listing all Snapshot in all Workspaces !" "1"
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
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Listing Snapshots at Workspace $full_ws_name :" "1"
		/usr/local/bin/ibmcloud pi ws tg $crn 2>> $log_file | tee -a $log_file
		/usr/local/bin/ibmcloud pi ins snap ls 2>> $log_file | tee -a $log_file
		echoscreen "" "1"
	done
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Finished Listing all Snapshots in all Workpsaces"
    ;;

   -imglsall)
	if [ $# -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1"
	fi
	test=0
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Listing all Captured Images in all Workspaces !" "1"
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
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Listing Captured Images at Workspace $full_ws_name :" "1"
		/usr/local/bin/ibmcloud pi ws tg $crn 2>> $log_file | tee -a $log_file
		/usr/local/bin/ibmcloud pi img ls 2>> $log_file | tee -a $log_file
		echoscreen "" "1"
	done
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Finished Listing all Captured Images in all Workpsaces"
    ;;

   -vclonelsall)
    if [ $# -gt 1 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 VSI_NAME SNAPSHOT_NAME"
	fi
	test=0
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting Listing all Volume Clones in all Workspaces !" "1"
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
		echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Listing Volume Clones at Workspace $full_ws_name :" "1"
		/usr/local/bin/ibmcloud pi ws tg $crn 2>> $log_file | tee -a $log_file
		/usr/local/bin/ibmcloud pi vol cl ls 2>> $log_file | tee -a $log_file
		echoscreen "" "1"
	done
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Finished Listing all Volume Clones in all Workpsaces"
    ;;

   -vclone)
	if [ $# -lt 8 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments Missing!! Syntax: bluexport.sh $1 VOLUME_CLONE_NAME BASE_NAME LPAR_NAME (Replication)True|False (Rollback)True|False TARGET_STORAGE_TIER ALL|VOLUMES(Comma seperated Volumes name or IDs list to clone)"
	fi
	if [ $# -gt 8 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 VOLUME_CLONE_NAME BASE_NAME LPAR_NAME (Replication)True|False (Rollback)True|False TARGET_STORAGE_TIER ALL|VOLUMES(Comma seperated Volumes name or IDs list to clone)"
	fi
	test=0
	vclone_name=$2
	base_name=$3
	vsi=$4
	vsi_id_bluexscrt
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
	/usr/local/bin/ibmcloud pi ws tg $vsi_ws_id
	if [[ "$volumes_to_clone" == "ALL" ]]
	then
		volumes_to_clone=$(/usr/local/bin/ibmcloud pi ins get $vsi_id | grep Volumes | sed -z 's/ //g' | sed -z 's/Volumes//g')
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Starting the 3 processes of Volume Clone $vclone_name" "1"
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - This is the list of volumes that will be cloned: $volumes_to_clone" "1"
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
	if [ $# -gt 2 ] 
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 VOLUME_CLONE_NAME"
	fi
	test=0
	vclone_name=$2
	cloud_login
	vclone_name_exists=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -w $vclone_name)
	if [[ "$vclone_name_exists" == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Volume Clone with name $vclone_name doesn't exists, please choose a diferent name!"
	fi
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - === Trying to Delete Volume Clone with name $vclone_name" "1"
	vclone_id=$(/usr/local/bin/ibmcloud pi vol cl ls | grep -A6 $vclone_name | grep "Volume Clone Request ID:" | awk {'print $5'})
	/usr/local/bin/ibmcloud pi vol cl del $vclone_id
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Deleted Volume Clone with name $vclone_name !"
    ;;

   -expimg)
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
    ;;

   -createvg)
	if [ $# -gt 4 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 LPAR_NAME -vg VG_NAME"
	fi
	if [ $# -lt 4 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments missing!! Syntax: bluexport.sh $1 LPAR_NAME -vg VG_NAME"
	fi
	flagvg=$3
	if [[ "$flagvg" == "-vg" ]]
	then
		vg_flag="--volume-group-name"
		vg_flag_echo="Volume Group"
	else
		abort "`date +%Y-%m-%d_%H:%M:%S` - Argument 3 must be -vg"
	fi
	vsi=$2
	vg_name=$4
	create_vg
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Create $vg_flag_echo $vg_name !"
    ;;

   -onboard)
	if [ $# -gt 3 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh $1 LPAR_NAME SHORT_NAME_TARGET_WS"
	fi
	if [ $# -lt 3 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Arguments missing!! Syntax: bluexport.sh $1 LPAR_NAME SHORT_NAME_TARGET_WS"
	fi
	vsi=$2
	target_short_ws=$3
	target_ws_crn=$(cat $bluexscrt | grep -w $target_short_ws | head -n1 | awk {'print $2'})
	if [[ "$target_ws_crn" == "" ]]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Workspace with Shortname $target_short_ws does not exist in $bluexscrt file... Aborting!..."
	fi
	onboard_aux_vol
	abort "`date +%Y-%m-%d_%H:%M:%S` - === Successfully Onboarded LPAR $vsi !"
    ;;

   -crgrs)
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
    ;;

   -failover)
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
    ;;

   -failback)
	abort "`date +%Y-%m-%d_%H:%M:%S` - Under construction!!"
    ;;

   -v | --version)
    if [ $# -gt 1 ]
	then
		abort "`date +%Y-%m-%d_%H:%M:%S` - Too many arguments!! Syntax: bluexport.sh -v | --version"
	fi
    echoscreen ""
	echoscreen "  ### bluexport by Ricardo Martins - Blue Chip Portugal - 2023-2025"
	abort "`date +%Y-%m-%d_%H:%M:%S` - Version: $Version"
    ;;

    *)
	if [ -t 1 ]
	then
		help
	fi
	abort "`date +%Y-%m-%d_%H:%M:%S` - Flag -a or -x Missing or invalid Flag!"
    ;;
esac
####  END: Iniciate Log and Validate Arguments  ####

cloud_login
check_locally_VSI_exists

####  START: Get Volumes to capture  ####
eval $volumes_cmd > $volumes_file | tee -a $log_file
volumes=$(cat $volumes_file | awk {'print $1'} | tr '\n' ',' | sed 's/,$//')
volumes_name=$(cat $volumes_file | awk {'print $2'} | tr '\n' ' ')
echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes ID Captured: $volumes" "1"
echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Volumes Name Captured: $volumes_name" "1"
####  END: Get Volumes to capture  ####

####  START: Flush ASPs and iASP Memory to Disk  ####
if [ $shutoff -eq 0 ]
then
	flush_asps
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - Skipping Flushing Memory to Disk..." "1"
fi

####  END: Flush ASPs and iASP Memory to Disk  ####

####  START: Make the Capture and Export  ####
if [[ $destination == "image-catalog" ]]
then
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Capture to image catalog cloud command... ==" "1"
	if [ $test -eq 1 ]
	then
		echoscreen "/usr/local/bin/ibmcloud pi ins cap cr $vsi_id --destination $destination --name $capture_name --volumes \"$volumes\"" "1"
	else
		rm $job_id
		/usr/local/bin/ibmcloud pi ins cap cr $vsi_id --destination $destination --name $capture_name --volumes "$volumes" 2>> $log_file | tee -a $log_file $job_id
	fi
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - == Executing Capture and Export cloud command... ==" "1"
	if [ $test -eq 1 ]
	then
		echoscreen "/usr/local/bin/ibmcloud pi ins cap cr $vsi_id --destination $destination --name $capture_name --volumes \"$volumes\" --access-key $accesskey --secret-key $secretkey --region $region --image-path $bucket" "1"
	else
		rm $job_id
		/usr/local/bin/ibmcloud pi ins cap cr $vsi_id --destination $destination --name $capture_name --volumes "$volumes" --access-key $accesskey --secret-key $secretkey --region $region --image-path $bucket 2>> $log_file | tee -a $log_file $job_id
	fi
fi
####  END: Make the Capture and Export  ####

####  START: Job Monitoring  ####
if [ $test -eq 0 ]
then
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - => Iniciating Job Monitorization..." "1"
else
	echoscreen "`date +%Y-%m-%d_%H:%M:%S` - => Iniciating Job Monitorization..." "1"
	abort "`date +%Y-%m-%d_%H:%M:%S` - Test Finished!"
fi

job_monitor
####  END: Job Monitoring  ####

       #####  END:CODE  #####

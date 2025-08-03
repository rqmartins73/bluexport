#!/bin/bash
#
#
# Script to help populate the bluexscrt file
#
#
# Ricardo Martins - Blue Chip Portugal © 2024-2024
#######################################################################################

Version=0.3.2

vsi_name_id_tmp_file="$HOME/vsi_name_file.tmp"
flag=$1

if [ $# -eq 1 ] && [[ $flag != "-v" ]] && [[ $flag != "-addlpar" ]] && [[ $flag != "-dellpar" ]] && [[ $flag != "-updlpars" ]]
then
	echo " ### Wrong Syntax!!..."
	echo " ### Options:"
	echo " ### To see the version  ---  ./bluexscrt_config.sh -v"
	echo " ### To add an LPAR to the secrets file  ---   ./bluexscrt_config.sh -addlpar"
	echo " ### To delete an LPAR from the secrets file  ---   ./bluexscrt_config.sh -dellpar"
	echo " ### Automatically updated the existent LPARs in the secret file with new ID if different  ---   ./bluexscrt_config.sh -updlpars"
	echo ""
	exit 0
fi

if [[ $flag == "-v" ]]
then
	echo ""
	echo "   ####  Welcome to your bluexport secrets file configuration helper version $Version"
	echo "   ####  by Ricardo Martins - Blue Chip Portugal - 2024-2024"
	echo ""
	exit 0
fi

#### START:FUNCTION - Ping LPAR  ####
ping_lpar() {

	if ping -c7 -W3 $1 &> /dev/null
	then
		ping="OK"
	else
		ping=""
	fi
}
#### END:FUNCTION - Ping LPAR  ####

#### START:FUNCTION - Create VSI User  ####
	### Create VSI User and prepare ssh login credentials
create_vsi_user() {
echo ""
echo "   #### Now let's take care of the LPAR user and prepare it to be able to login into the LPAR..."
echo ""
read -p "Do you want to create the user $vsi_user and/or its environment in the LPARs now (Y/N) " lpar_user
if [[ "$lpar_user" == "Y" ]] || [[ "$lpar_user" == "y" ]]
then
	echo ""
	echo "OK, let's go then..."
	echo ""
	usr_folder="/home/${vsi_user^^}"
	usr_folder_ssh="$usr_folder/.ssh"
	auth_keys_path="$usr_folder_ssh/authorized_keys"
	pub_ssh_key_path="$ssh_key_path.pub"
	pub_ssh_key=$(cat $pub_ssh_key_path)
	len=${#vsi_name[@]}
	for (( i=0; i<$len; i++ ))
	do
		echo " ## LPAR ${vsi_name[$i]} with IP ${vsi_ip[$i]}:"
		echo ""
		ping_lpar "${vsi_ip[$i]}"
		if [[ "$ping" == "OK" ]]
		then
			read -p "Do you want to create the user $vsi_user in LPAR ${vsi_name[$i]} (Y/N) " crt_user
			if [[ "$crt_user" == "Y" ]] || [[ "$crt_user" == "y" ]]
			then
				echo ""
				echo "To create the user in ${vsi_name[$i]} you will have to provide a user name with permissions to create users and able to ssh into ${vsi_name[$i]}..."
				echo ""
				read -p "${vsi_name[$i]} User Name: " usr_name
				echo ""
				echo "If you have an ssh key for user $usr_name, please supply full path... if you don't leave it blank and just hit <ENTER>"
				read -p "$usr_name SSH Key: " usr_name_sshkey
				if [[ "$usr_name_sshkey" == "" ]]
				then
					sshkey=""
				else
					sshkey="-i $usr_name_sshkey"
				fi
				echo "Testing ssh connection to LPAR ${vsi_name[$i]} with IP ${vsi_ip[$i]} with user $usr_name"
				ssh $sshkey -o ConnectTimeout=1 -o ConnectionAttempts=1 $usr_name@${vsi_ip[$i]} exit 0
				ret=$?
				if [ $ret -ne 0 ]
				then
					echo "    FAILED - Oops something went wrong!... Check messages above this line..."
					echo ""
					continue
				fi
				echo "Checking if user $vsi_user exists in LPAR ${vsi_name[$i]}, please wait..."
				lpar_user_exists=$(ssh $sshkey $usr_name@${vsi_ip[$i]} 'system "DSPUSRPRF USRPRF('$vsi_user')"'| head -n 1 | awk {'print $1'})
				if [[ "$lpar_user_exists" == "" ]] #&& [ $ret -eq 0 ]
				then
					read -p "Do you want to create the user $vsi_user environment in LPAR ${vsi_name[$i]} (Y/N) " crt_user_env
					if [[ "$crt_user_env" == "Y" ]] || [[ "$crt_user_env" == "y" ]]
					then
						echo "Creating user profile $vsi_user in LPAR ${vsi_name[$i]}, please wait..."
						ssh $sshkey $usr_name@${vsi_ip[$i]} 'system "CRTUSRPRF USRPRF('$vsi_user') PASSWORD(*NONE) USRCLS(*USER) INLMNU(*SIGNOFF) SPCAUT(*ALLOBJ *JOBCTL)"'
						echo "Preparing user $vsi_user environment in LPAR ${vsi_name[$i]}, please wait..."
						ssh $sshkey $usr_name@${vsi_ip[$i]} 'mkdir '$usr_folder ';chmod 755 '$usr_folder ';mkdir '$usr_folder_ssh';chmod 700 '$usr_folder_ssh';echo "'$pub_ssh_key'">>'$auth_keys_path';chmod 600 '$auth_keys_path';chown -R '$vsi_user' '$usr_folder';exit 0'
						ret=$?
						if [ $ret -ne 0 ]
						then
							echo "    FAILED - Oops something went wrong!... Check messages above this line..."
							echo ""
							continue
						fi
						echo ""
						echo "User $vsi_user environment in LPAR ${vsi_name[$i]} prepared!"
						echo "Testing credentials and environment, please wait..."
						ssh $sshkey $usr_name@${vsi_ip[$i]} 'exit 0'
						ret=$?
						if [ $ret -ne 0 ]
						then
							echo "    FAILED - Oops something went wrong!... Check messages above this line..."
							echo ""
							continue
						fi
						echo ""
						echo "Test done! Successfully ssh logged in in LPAR ${vsi_name[$i]} with user $vsi_user! All good to go!"
						echo ""
					else
						echo ""
						echo "  ## Don't forget to create user $vsi_user environment in LPAR ${vsi_name[$i]} ..."
						echo "     You will need to create ${vsi_user^^} home folder, .ssh folder and put your public ssh key in file authorized_keys under .ssh"
						echo "     and don't forget to change folder and file permissions."
						echo ""
					fi
				else
					echo "   ## User $vsi_user already exists in LPAR ${vsi_name[$i]} ..."
					read -p "Do you still want to create the user $vsi_user environment in LPAR ${vsi_name[$i]} (Y/N) " crt_user_env
					if [[ "$crt_user_env" == "Y" ]] || [[ "$crt_user_env" == "y" ]]
					then
						echo "Preparing user $vsi_user environment in LPAR ${vsi_name[$i]}, please wait..."
						ssh $sshkey $usr_name@${vsi_ip[$i]} 'mkdir '$usr_folder ';chmod 755 '$usr_folder ';mkdir '$usr_folder_ssh';chmod 700 '$usr_folder_ssh';echo "'$pub_ssh_key'">>'$auth_keys_path';chmod 600 '$auth_keys_path';chown -R '$vsi_user' '$usr_folder';exit 0'
						ret=$?
						if [ $ret -ne 0 ]
						then
							echo "    FAILED - Oops something went wrong!... Check messages above this line..."
							echo ""
							continue
						fi
						echo ""
						echo "User $vsi_user environment in LPAR ${vsi_name[$i]} prepared!"
						echo "Testing credentials and environment, please wait..."
						ssh $sshkey $usr_name@${vsi_ip[$i]} 'exit 0'
						ret=$?
						if [ $ret -ne 0 ]
						then
							echo "    FAILED - Oops something went wrong!... Check messages above this line..."
							echo ""
							continue
						fi
						echo ""
						echo "Test done! Successfully ssh logged in in LPAR ${vsi_name[$i]} with user $vsi_user! All good to go!"
						echo ""
					else
						echo ""
						echo "  ## Don't forget to create user $vsi_user environment in LPAR ${vsi_name[$i]} ..."
						echo "     You will need to create $vsi_user home folder, .ssh folder and put your pubic ssh key in file authorized_keys under .ssh"
						echo "     and don't forget to change foler and file permissions."
						echo ""
					fi
					echo ""
#exit 0
				fi
			else
				echo ""
				echo "  ## Don't forget to create user $vsi_user in LPAR ${vsi_name[$i]} ..."
				echo ""
			fi
		else
			echo "  ## LPAR ${vsi_name[$i]} with IP ${vsi_ip[$i]} not reachable!..."
			echo "  ## Please confirm the IP is correct, or if the LPAR is IPLed."
			echo "  ## you can change the IP in file $file_name."
			echo ""
		fi
	echo ""
	echo "Moving on to the next LPAR..."
	echo ""
	done
	echo "No more LPARs in listed."
	echo ""
	echo "Done!"
else
	echo "  ## Don't forget to create user $vsi_user and update file authorized_keys in each LPAR!..."
fi
}
#### END:FUNCTION - Create VSI User  ####

if [[ $flag == "-dellpar" ]]
then
	echo ""
	echo "   ####  Welcome to your bluexport secrets file configuration helper version $Version"
	echo ""
	echo "So, you want to delete an LPAR from the secrets file?!..."
	echo "OK, let's go..."
	echo ""
	bluexscrt=$(cat $HOME/bluexport.conf | grep bluexscrt | awk {'print $2'})
	vsi_user=$(cat $bluexscrt | grep VSI_USER | awk {'print $2'})
	ssh_key_path=$(cat $bluexscrt | grep SSHKEYPATH | awk {'print $2'})
	existent_lpars=$(cat $bluexscrt | grep LPAR | awk {'print $1'})
	while [[ "$ok" != "y" ]] && [[ "$ok" != "Y" ]]
	do
		echo $existent_lpars
		read -p "From the list above, enter LPAR name to delete: " vsi_name
		read -p "Is this name $vsi_name correct? (y/n) " ok
		exists=$(cat $bluexscrt | grep -w $vsi_name | awk {'print $1'})
		if [[ $exists == "" ]]
		then
			echo ""
			echo "### LPAR with that name $vsi_name do not exists!"
			echo ""
			ok="n"
		fi
	done
	grep -v $vsi_name $bluexscrt > .tmp && mv .tmp $bluexscrt
	lpar_lines=$(grep "LPAR" $bluexscrt | wc -l)
	count=1
	lpars=$(grep "LPAR" $bluexscrt | awk {'print $1'})
	for lpar in $lpars
	do
		lpar_num=$(grep $lpar $bluexscrt | awk {'print $5'} | sed -z 's/LPAR//g')
		lpar_num_full=$(grep $lpar $bluexscrt | awk {'print $5'})
		if [ $lpar_num -ne $count ]
		then
			sed -i 's/'$lpar_num_full'/'LPAR$count'/g' $bluexscrt
		fi
		count=$((count+1))
	done
	echo "### LPAR $vsi_name was removed from bluxscrt file!"
	exit 0
fi
if [[ $flag == "-addlpar" ]]
then
	echo ""
	echo "   ####  Welcome to your bluexport secrets file configuration helper version $Version"
	echo ""
	echo "So, you want to add an LPAR to the secrets file?!..."
	echo "OK, let's go..."
	echo ""
	bluexscrt=$(cat $HOME/bluexport.conf | grep bluexscrt | awk {'print $2'})
	lpar_number_now=$(tail -n1 $bluexscrt | grep LPAR | awk {'print $5'} | sed -z 's/LPAR//g')
	lpar_number=$((lpar_number_now+1))
	vsi_user=$(cat $bluexscrt | grep VSI_USER | awk {'print $2'})
	ssh_key_path=$(cat $bluexscrt | grep SSHKEYPATH | awk {'print $2'})
	while [[ "$ok" != "y" ]] && [[ "$ok" != "Y" ]]
	do
		read -p "Enter LPAR name " vsi_name
		read -p "Is this name $vsi_name correct? (y/n) " ok
		exists=$(cat $bluexscrt | grep -w $vsi_name | awk {'print $1'})
		if [[ $exists != "" ]]
		then
			echo ""
			echo "### An LPAR with that name $vsi_name already exists!"
			echo ""
			ok="n"
		fi
	done
	ok="n"
	while [[ "$ok" != "y" ]] && [[ "$ok" != "Y" ]]
	do
		read -p "Enter LPAR IP " vsi_ip
		read -p "Is this IP $vsi_ip correct? (y/n) " ok
		exists=$(cat $bluexscrt | grep -w $vsi_ip | awk {'print $1'})
		if [[ $exists != "" ]]
		then
			echo ""
			echo "### An LPAR with that IP $vsi_ip already exists!"
			echo ""
			ok="n"
		fi
	done
	ok="n"
	while [[ "$ok" != "y" ]] && [[ "$ok" != "Y" ]]
	do
		read -p "Enter LPAR ID " vsi_id
		read -p "Is this ID $vsi_id correct? (y/n) " ok
		exists=$(cat $bluexscrt | grep -w $vsi_id | awk {'print $1'})
		if [[ $exists != "" ]]
		then
			echo ""
			echo "### An LPAR with that ID $vsi_id already exists!"
			echo ""
			ok="n"
		fi
	done
	wsshort=$(cat $bluexscrt | grep "crn:" | awk {'print $1'})
	ok="n"
	while [[ "$ok" != "y" ]] && [[ "$ok" != "Y" ]]
	do
		echo "Enter LPAR Workspace shortname (Copt/paste from the list below)"
		echo "$wsshort"
		read -p "> " vsi_ws
		read -p "Is this Workspace $vsi_ws correct? (y/n) " ok
	done
	echo $vsi_name" "$vsi_ip" "$vsi_id" "$vsi_ws" "LPAR$lpar_number >> $bluexscrt
	create_vsi_user
	exit 0
fi

if [[ $flag == "-updlpars" ]]
then
	echo ""
	echo "   ####  Welcome to your bluexport secrets file configuration helper version $Version"
	echo ""
	echo "So, you want to update the LPARs to the secrets file?!..."
	echo "OK, let's go..."
	echo ""
	/usr/local/bin/ibmcloud login --apikey $apikey -r $region -g $resource_grp
	bluexscrt=$(cat $HOME/bluexport.conf | grep bluexscrt | awk {'print $2'})
	echo "Getting updated PowerVS VSI from Account..."
	vsi=$(/usr/local/bin/ibmcloud resources | grep -B3 pvm-instance | grep "Name:" | awk {'print $2'}) ############ Get VMs
	echo "Getting VM IDs..."
	vsi_id=$(/usr/local/bin/ibmcloud resources | grep -B3 pvm-instance | grep "CRN:" | awk {'print $2'} | sed -E 's/.*?pvm-instance://' ) #### Get VMs ID
	echo "Generating file..."
	awk 'FNR==NR { map[FNR]=$0;next } { print map[FNR]" "$0} ' <(echo "$vsi") <(echo "$vsi_id") > updlpars.tmp ##### Combine VMs with VMs ID
	updlpars=$(cat updlpars.tmp)
	upd=0
	for line in $updlpars
	do
		count=$(echo $line | wc -c)
		if [ $count -lt 12 ]
		then
			vm=$line
			vmid=$(cat $bluexscrt | grep -i $line | awk {'print $3'})
		else
			upd=1
			new_vmid=$line
			if [[ "$line" != "$vmid" ]] && [[ "$vmid" != "" ]]
			then
				echo ""
				echo "New ID detected for VSI $vm, updating secret file with new ID: $line"
				sed -i 's/'$vmid'/'$new_vmid'/g' $bluexscrt
				echo ""
			fi
		fi
	done
	if [ $upd -eq 1 ]
	then
		echo "Secret file $bluexscrt updated!"
	else
		echo "No updates needed to Secret file $bluexscrt"
	fi
	rm -f updlpars.tmp
	exit 0
fi

echo ""
echo "   ####  Welcome to your bluexport secrets file configuration helper version $Version"
echo ""
echo "Let's start with the basics for this to work..."
echo ""

while true
do
	while true
	do
		read -p "File Name (Full /path/to/file) : " file_name
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
	while [[ "$apikey" == "" ]]
	do
		read -s -p "APIKEY: " apikey
		echo ""
	done
	read -p "Resource Group: " resource_grp
	while [[ "$acckey" == "" ]]
	do
		read -s -p "COS Access Key: " acckey
		echo""
	done
	echo ""
	while [[ "$scrtkey" == "" ]]
	do
		read -s -p "COS Secret Key: " scrtkey
		echo ""
	done
	read -p "Region: " region
	read -p "Bucket Name: " bucket

	while true
	do
		read -p "LPAR User: " vsi_user
		read -p "LPAR User $vsi_user, is this correct? (Y/N) " continue
		if [[ $continue == "Y" ]] || [[ $continue == "y" ]]
		then
			if [ ${#vsi_user} -gt 8 ]
			then
				echo "   ### Important: LPAR User $vsi_user has more than 8 caracters. You have to enable that on the LPARs with command \"ADDENVVAR ENVVAR(PASE_USRGRP_LIMITED) VALUE(N) LEVEL(*SYS)\" and then \"ENDTCPSVR *SSHD\" followed by \"STRTCPSVR *SSHD\""
			fi
			break
		fi
	done
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
				read -p "Do you want to create $ssh_key_path key now ? " createnow
				if [[ $createnow == "Y" ]] || [[ $createnow == "y" ]]
				then
					ssh-keygen -N "" -t rsa -f $ssh_key_path
					break
				else
					echo "Don't forget to create ssh key named $ssh_key_path !"
					sleep 3
					echo ""
					break
				fi
			fi
		else
			break
		fi
	done

	apikey_count=$(echo -n "$apikey" | wc -c)
	count=$((apikey_count-6))
	echo "APIKEY: "$apikey | sed -E "s/(.{11})(.{$count})/\1***********************/"
	echo "Resource Group: "$resource_grp
	echo "Region: "$region
	acckey_count=$(echo -n "$acckey" | wc -c)
	count=$((acckey_count-6))
	echo "COS Access Key: "$acckey | sed -E "s/(.{19})(.{$count})/\1***********************/"
	scrtkey_count=$(echo -n "$scrtkey" | wc -c)
	count=$((scrtkey_count-6))
	echo "COS Secret Key: "$scrtkey | sed -E "s/(.{19})(.{$count})/\1***********************/"
	echo "Bucket Name: "$bucket
	echo "LPAR User: "$vsi_user
	echo "SSH Key Full Path: "$ssh_key_path
	echo ""
	read -p "Are this data correct? (Y/N) " continue
	if [[ $continue == "Y" ]] || [[ $continue == "y" ]]
	then
		break
	fi
done
echo ""
echo "   #### Checking IBM Cloud credentials and getting Workspaces, please wait..."
echo ""

/usr/local/bin/ibmcloud login --apikey $apikey -r $region -g $resource_grp
/usr/local/bin/ibmcloud pi ws ls
ret=$?
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

echo ""
IFS=':' read -r -a wsnames_array <<< "$wsnames"
IFS='@' read -r -a crns_array <<< "$crns"
IFS='@' read -r -a wsids_array <<< "$wsids"
index=0
echo ""
echo "   ####  Let's give the Workspaces a short name..."
echo ""
echo "Important: I'm not checking, so don't give the same short name to more than 1 Workspace, different from any LPAR name, and without spaces."
echo ""
for i in "${wsnames_array[@]}"
do
	full_ws_name=$i # Get the full workspace name from the map
	ok="n"
	while [[ "$ok" != "y" ]] && [[ "$ok" != "Y" ]]
	do
		ws_short_name=""
		while [[ "$ws_short_name" == "" ]] 
		do
			read -p "Enter short name for Workspace $i : " ws_short_name
			if [[ "$ws_short_name" == "" ]]
			then
				echo "short name cannot be <blank>...!"
			fi
		done
		read -p "Are you OK with this short name $ws_short_name (y/n) " ok
	done
	allws=${allws}" "$ws_short_name
	crn[$index]=$ws_short_name" "${crns_array[$index]}
	wsid[$index]=$ws_short_name"ID "${wsids_array[$index]}
#	echo "ALLWS:   "$allws
#	echo "CRN:   "${crn[$index]}
#	echo "WSID:   "${wsid[$index]}
	echo ""
	index=$((index + 1))
	ws_short_name=""
done

### Building $file_name file

echo "APYKEY $apikey" > $file_name
for crn_print in "${crn[@]}"
do
	echo $crn_print >> $file_name
done
echo "" >> $file_name
echo "ACCESSKEY $acckey" >> $file_name
echo "SECRETKEY $scrtkey" >> $file_name

echo "BUCKETNAME $bucket" >> $file_name
echo "REGION $region" >> $file_name
echo "" >> $file_name
echo "ALLWS$allws" >> $file_name
echo "WSNAMES $wsnames" >> $file_name
echo "" >> $file_name
echo "VSI_USER $vsi_user" >> $file_name
echo "" >> $file_name
echo "SSHKEYPATH $ssh_key_path" >> $file_name
echo "" >> $file_name
for wsid_print in "${wsid[@]}"
do
	echo $wsid_print >> $file_name
done
echo "" >> $file_name
echo "RESOURCE_GRP $resource_grp" >> $file_name

### Adding LPARs and their IP to the config file

echo ""
echo "   #### Now let's add the LPARs and their IP to the config file..."
echo ""
indexvsi=0
for ws in $allws
do
	echo "Targetting Workspace $ws and checking existent LPARs, please wait..."
	echo ""
	wscrn=$(cat $file_name | grep -m 1 $ws | awk {'print $2'})
	/usr/local/bin/ibmcloud pi ws tg $wscrn
	/usr/local/bin/ibmcloud pi ins ls | tail -n +2 | awk {'print $2" "$1'} > $vsi_name_id_tmp_file
	vsis=$(cat $vsi_name_id_tmp_file)
	if [[ "$vsis" == "" ]]
	then
		echo ""
		echo "None LPARs in Workspace $ws, moving on..."
		echo ""
	fi
	while IFS= read -r -u 3 line
	do
		vsi_name[$indexvsi]=$(echo $line|awk {'print $1'})
		vsi_id[$indexvsi]=$(echo $line|awk {'print $2'})
		vsi_ws[$indexvsi]=$ws
		echo ""
		echo "Checking if LPAR ${vsi_name[$indexvsi]} is an IBMi LPAR, please wait..."
		ibmi=$(/usr/local/bin/ibmcloud pi ins get ${vsi_id[$indexvsi]} --json | grep '"osType": "ibmi"')
		if [[ $ibmi != ""  ]]
		then
			rm='"ip": '
			echo "Yes it is! Getting LPAR ${vsi_name[$indexvsi]} IPs, please wait..."
			vsi_ips=$(/usr/local/bin/ibmcloud pi ins get ${vsi_id[$indexvsi]} --json | grep '"ip":' | awk 'BEGIN{RS=ORS=" "}{ if (a[$0] == 0){ a[$0] += 1; print $0}}'| sed s/"$rm"//| sed s/\"// | sed s/\",//)
			ok="n"
			while [[ "$ok" != "y" ]] && [[ "$ok" != "Y" ]]
			do
				echo "IPs available for LPAR ${vsi_name[$indexvsi]} (Copy/paste one of them) :"
				echo $vsi_ips
				read -p "Enter IP for LPAR ${vsi_name[$indexvsi]}: " vsi_ip[$indexvsi]
				read -p "Is this IP ${vsi_ip[$indexvsi]} correct? (y/n) " ok
			done
			indexvsi=$((indexvsi + 1))
		else
			echo "LPAR ${vsi_name[$indexvsi]} is not an IBMi LPAR, moving on..."
		fi
	done 3< "$vsi_name_id_tmp_file"
	echo ""
done

echo "" >> $file_name
len=${#vsi_name[@]}
for (( i=0; i<$len; i++ ))
do
	echo ${vsi_name[$i]}" "${vsi_ip[$i]}" "${vsi_id[$i]}" "${vsi_ws[$i]}" "LPAR$i >> $file_name
done

### Updating bluexport.conf file

oldbluexscrt=$(cat $HOME/bluexport.conf | grep bluexscrt | awk {'print $2'})
newbluexscrt=$file_name
read -p "Do you want to update bluexport.conf with $file_name (Y/N) " use_file
if [[ "$use_file" == "Y" ]] || [[ "$use_file" == "y" ]]
then
	echo "Updating file $HOME/bluexport.conf ..."
	sed -i "s|$oldbluexscrt|$newbluexscrt|g" $HOME/bluexport.conf
	echo "Done!"
else
	echo "## If you want to use this file $file_name as your bluexscrt file, don't forget to update $HOME/bluexport.conf file"
fi

create_vsi_user

chmod 600 $file_name

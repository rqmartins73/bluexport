# bluexport
Capture IBM Cloud PowerVS IBM i VSI and Export to COS or/and Image Catalog.  
Version 3.x now supports the creation, update, delete and list Snapshots, and also Volume Clones.  

###### This script was made in GNU bash, version 5.2.21(1)-release.  
  
> [!IMPORTANT]
> ###### For this script to work you need to have IBM Cloud CLI installed and updated, including the plug-ins.
> ###### IBM Cloud CLI plug-ins needed:
> * <sub>`power-iaas[pi]` *- Version 1.3.0 or higher</sub>*  
> * <sub>`cloud-object-storage` *- Version 1.9.1 or higher</sub>*

> [!IMPORTANT]
> ###### Before running the script `bluexport.sh`:
> * First you must configure the file `bluexscrt` with your IBM Cloud Data.  
> <sub>You can and should use `bluexscrt_config.sh` helper script, to help you create and customize your `bluexscrt` file.</sub>  
> * You must fill in or change the paths in file `bluexport.conf`.  
> * File `bluexport.conf` must reside in your $HOME folder.

> [!TIP]  
> <sub> [IBM Cloud CLI install instructions](https://cloud.ibm.com/docs/cli?topic=cli-install-ibmcloud-cli)</sub>
***
  
## Usage:
`./bluexport.sh [ -a | -x volumes_name_to_exclude ] [VSI_Name_to_Capture] [Capture_Image_Name] [both|image-catalog|cloud-storage] [hourly | daily | weekly | monthly | single]`  
  
`./bluexport.sh -snapcr VSI_NAME SNAPSHOT_NAME 0|["DESCRIPTION"] 0|[VOLUMES(Comma separated list)]`  
  
`./bluexport.sh -snapupd SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|["DESCRIPTION"]`  
  
`./bluexport.sh -snapdel SNAPSHOT_NAME`  
  
`./bluexport.sh -snaplsall`  
  
`./bluexport.sh -imglsall`  
  
`./bluexport.sh -vclone VOLUME_CLONE_NAME BASE_NAME LPAR_NAME True|False(replication-enabled) True|False(rollback-prepare) STORAGE_TIER ALL|(Comma seperated rated Volumes name list to clone)`  
  
`./bluexport.sh -vclonedel VOLUME_CLONE_NAME`  
  
`./bluexport.sh -vclonelsall`  
  
`./bluexport.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO`  
<br>

**Examples:**

- `./bluexport.sh -a vsi_name capture_img_name image-catalog daily` ---- Includes all Volumes and exports to image catalog, and deletes yesterday image if exists.
 
- `./bluexport.sh -x ASP2_ vsi_name capture_img_name both monthly`  ---- Excludes Volumes with ASP2_ in the name and exports to image catalog and COS, and deletes last month images if exists.  

- `./bluexport.sh -snapcr IBMi75 IBMi75_snap "Description of the snap shot" 0`   ---- Makes a Snapshot of LPAR IBMi75 with snap name IBMi75_snap with description "Description of the snap shot" and all volumes.

- `./bluexport.sh -snapupd IBMi75_snap2 0 "SNAP TEST"`    ---- Updates the description to "SNAP TEST" of snapshot IBMi75_snap2.

- `./bluexport.sh -snapdel IBMi75_snap`   ---- Deletes the snapshot named IBMi75_snap.

- `./bluexport.sh -snaplsall`   ---- It will list to terminal and log file all existent snapshots in all Workspaces.  

- `./bluexport.sh -imglsall`   ---- It will list to terminal and log file all existent Captured Images in all Workspaces.  

- `./bluexport.sh -vchtier VSI_NAME VOLUMES_NAME TIER_TO_CHANGE_TO`   ---- It will change the tier of the volumes of the instance with VSI_NAME that have in their names the name "VOLUMES_NAME" to tier TIER_TO_CHANGE_TO(0 or 1 or 3)
<br>

> [!NOTE]
> ###### `[hourly | daily | weekly | monthly | single]` - This parameter allows the script to delete the image from the previous capture.
> ###### i.e. If weekly is selected it will try to delete the image from the week before.

> [!NOTE]
> ###### Reocurrence `hourly` and `daily` only permits captures to image-catalog
<br>
<br>

**Content of file bluexscrt before edit:**
```
APYKEY REPLACE-ALL-THIS-WITH-YOUR-API-KEY  
WSFRADR REPLACE-ALL-THIS-WITH-YOUR-POWER-VIRTUAL-SERVER-CRN  i.e.   crn:v1:bluemix:public:power-iaas:blablablablabla::  
POWERVSPRD REPLACE-ALL-THIS-WITH-YOUR-POWER-VIRTUAL-SERVER-CRN  i.e.  crn:v1:bluemix:public:power-iaas:blablablablabla::  
WSFRAPRD REPLACE-ALL-THIS-WITH-YOUR-POWER-VIRTUAL-SERVER-CRN  i.e.  crn:v1:bluemix:public:power-iaas:blablablablabla::  
  
ACCESSKEY REPLACE-ALL-THIS-WITH-YOUR-ACCES-KEY  
SECRETKEY REPLACE-ALL-THIS-WITH-YOUR-SECRET-KEY  
BUCKETNAME REPLACE-ALL-THIS-WITH-YOUR-BUCKET-NAME  
REGION REPLACE-ALL-THIS-WITH-YOUR-REGION  
  
WSFRADRID REPLACE-ALL-THIS-WITH-YOUR-POWER-VIRTUAL-SERVER-ID     - If you use bluexscrt_config.sh helper these IDs will be automatically filled in...  
POWERVSPRDID REPLACE-ALL-THIS-WITH-YOUR-POWER-VIRTUAL-SERVER-ID  - ...if you do it manually it has to be the workspace short name plus the word "ID" all together  
WSFRAPRDID REPLACE-ALL-THIS-WITH-YOUR-POWER-VIRTUAL-SERVER-ID  
  
ALLWS WSFRADR POWERVSPRD WSFRAPRD                                                                                                   - The shortnames in this line...
WSNAMES Power VS Workspace Name of the WSFRADR:Power VS Workspace Name of the POWERVSPRD:Power VS Workspace Name of the WSFRAPRD  - ...and the long names in this line must be in the same order

VSI_USER vsi_user

SSHKEYPATH /sshkeypath/.ssh/key

RESOURCE_GRP Default # The resource group you want to use when logging in, in this case Default

SERVER1 XXX.XXX.XXX.XXX SERVER1_VSI_ID WSFRADR LPAR0
SERVER2 XXX.XXX.XXX.XXX SERVER2_VSI_ID POWERVSPRD LPAR1
SERVER3 XXX.XXX.XXX.XXX SERVER3_VSI_ID POWERVSPRD LPAR2
.
.
SERVERn XXX.XXX.XXX.XXX SERVERN_VSI_ID WSSHORTNAME LPARn

```

bluexscrt example:
```
APYKEY bla123BLA321bla345BLA  
WSMADDR crn:v1:bluemix:public:power-iaas:bla123bla321bla345bla123bla::  
WSMADPRD crn:v1:bluemix:public:power-iaas:bla123bla312bla345bla123bla::
WSFRADR crn:v1:bluemix:public:power-iaas:bla123bla312bla543bla123bla::
ACCESSKEY bla123BLAblaBLA  
SECRETKEY bla123BLAblaBLAbla  
BUCKETNAME mybucket  
REGION eu-de  
  
WSMADDRID abcdefgh-1234-1a2b-1234-abcd-123abc5def4  
WSMADPRDID abxptogh-1234-1a2b-1234-abcd-123xptodef6  
WSFRADRID abxptigh-1234-1a2b-1234-abcd-123xptidef6  

ALLWS WSMADDR WSMADPRD WSFRADR  
WSNAMES Power VS Workspace Mad DR:Power VS Workspace Mad PRD:Power VS Workspace Fra DR  
  
VSI_USER bluexport  
  
SSHKEYPATH /home/<USER>/.ssh/bluexport_rsa  
  
RESOURCE_GRP powervs  

SERVER1 192.168.111.111 abcdefgh-1234-1a2b-1234-abc123def123 WSMADPRD LPAR0
SERVER2 192.168.111.112 abcdefgh-1234-1a2b-1234-abc123def123 WSMADDR LPAR1
  
```
  
<br>
  
> [!NOTE]
> ######  *This script can be run in crontab, in background or interactively. Depending of the run mode it will produce output to screen or not, but will always make log in the file specified in parameter log_file of the bluexport.conf.*

***

 <sub>Ricardo Martins - [Blue Chip Portugal](http://www.bluechip.pt) - 2024</sub>  

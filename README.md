# bluexport
Capture IBM Cloud POWERVS VSI and Export to COS or/and Image Catalog.  
Version 2.x now supports the creation, update and delete Snapshots.  

###### This script was made in GNU bash, version 5.2.21(1)-release.  

## Usage:
`./bluexport.sh [ -a | -x volumes_name_to_exclude ] [VSI_Name_to_Capture] [Capture_Image_Name] [both|image-catalog|cloud-storage] [hourly | daily | weekly | monthly | single]`  
  
`./bluexport.sh -snapcr VSI_NAME SNAPSHOT_NAME 0|["DESCRIPTION"] 0|[VOLUMES(Comma separated list)]`  
  
`./bluexport.sh -snapupd SNAPSHOT_NAME 0|[NEW_SNAPSHOT_NAME] 0|["DESCRIPTION"]`  
  
`./bluexport.sh -snapdel SNAPSHOT_NAME`  

**Examples:**

- `./bluexport.sh -a vsi_name capture_img_name image-catalog daily` ---- Includes all Volumes and exports to image catalog, and deletes yesterday image if exists.
 
- `./bluexport.sh -x ASP2_ vsi_name capture_img_name both monthly`  ---- Excludes Volumes with ASP2_ in the name and exports to image catalog and COS, and deletes last month images if exists.  

- `./bluexport.sh -snapcr IBMi75 IBMi75_snap "Description of the snap shot" 0`   ---- Makes a Snapshot of LPAR IBMi75 with snap name IBMi75_snap with description "Description of the snap shot" and all volumes.

- `./bluexport.sh -snapupd IBMi75_snap2 0 "SNAP TEST"`    ---- Updates the description to "SNAP TEST" of snapshot IBMi75_snap2.

- `./bluexport.sh -snapdel IBMi75_snap`   ---- Deletes the snapshot named IBMi75_snap.

Flag `t` before `a` or `x` makes it a test and do not makes the capture.

**Example:** 
- `./bluexport.sh -tx "ASP2_ IASP" vsi_name capture_img_name both single` ---- Does not makes the export, and makes log in a different log file.
 
- `[hourly | daily | weekly | monthly | single]` - This parameter allows the script to delete the image from the previous capture. 
i.e. If weekly is selected it will try to delete the image from the week before.
  
 **Note:** Reocurrence "hourly" only permits captures to image-catalog

 <br>
  
 *This file is to be run in crontab or in background, it will produce little or no output to screen, it will log in a file.*  
  
Before running `bluexport.sh`, first you must configure the file **bluexscrt** with your IBM Cloud Data.

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
  
SERVER1 XXX.XXX.XXX.XXX SERVER1_VSI_ID
SERVER2 XXX.XXX.XXX.XXX SERVER2_VSI_ID
SERVER3 XXX.XXX.XXX.XXX SERVER3_VSI_ID
.  
.  
SERVERN XXX.XXX.XXX.XXX SERVERN_VSI_ID

ALLWS WSFRADR POWERVSPRD WSFRAPRD                                                                                                   - The shortnames in this line...
WSNAMES Power VS Workspace Name of the WSFRADR:Power VS Workspace Name of the POWERVSPRD:Power VS Workspace Name of the WSFRAPRD  - ...and the long names in this line must be in the same order

VSI_USER vsi_user

SSHKEYPATH /sshkeypath/.ssh/key

RESOURCE_GRP Default # The resource group you want to use when logging in, in this case Default

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
  
SERVER1 192.168.111.111 abcdefgh-1234-1a2b-1234-abc123def123
SERVER2 192.168.111.112 abcdefgh-1234-1a2b-1234-abc123def123

ALLWS WSMADDR WSMADPRD WSFRADR
WSNAMES Power VS Workspace Mad DR:Power VS Workspace Mad PRD:Power VS Workspace Fra DR

VSI_USER bluexport

SSHKEYPATH /home/<USER>/.ssh/bluexport_rsa

RESOURCE_GRP powervs

```

***

###### For this script to work you need to have IBM Cloud CLI installed.
[IBM Cloud CLI install instructions](https://cloud.ibm.com/docs/cli?topic=cli-install-ibmcloud-cli){:target="_blank"}

 <sub>Ricardo Martins - [Blue Chip Portugal](http://www.bluechip.pt) © 2024</sub>  

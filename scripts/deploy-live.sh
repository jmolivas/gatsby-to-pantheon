#!/bin/bash
# Deploy to Live
# Note: This script uses CircleCI environment variables https://circleci.com/docs/environment-variables

#=====================================================#
# Build prod env and create backup dirs on Circle     #
#=====================================================#



#===============================================================#
# Authenticate Terminus  and create json dump of help output    #
#===============================================================#
terminus auth:login --machine-token $PANTHEON_TOKEN
#terminus list --format=json > ~/gatsby/public/assets/terminus/commands.json
#curl -v -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/pantheon-systems/terminus/releases > ~/build/output_prod/docs/assets/terminus/releases.json

#===============================================================#
# Deploy modified files to production                           #
#===============================================================#
touch ./deployment-log.txt
rsync --delete-delay -chrltzv --ipv4 --info=BACKUP,DEL -e 'ssh -p 2222 -oStrictHostKeyChecking=no' gatsby/public/ --temp-dir=../../tmp/ live.$PROD_UUID@appserver.live.$PROD_UUID.drush.in:files/docs/ | tee deployment-log.txt;
if [ "$?" -eq "0" ]
then
    echo "Success: Deployed to https://pantheon.io/docs"
else
    # If rsync returns an error code the build will fail and send notifications for review
    echo "Error: Deploy failed, review rsync status"
    exit 1
fi


#=====================================================#
# Delete Multidev environment from $STATIC_DOCS_UUID site   #
#=====================================================#
# Identify existing environments for the $STATIC_DOCS_UUID site
terminus env:list --format list --field=ID $STATIC_DOCS_UUID > ./env_list.txt
echo "Existing environments:" && cat env_list.txt
# Create array of existing environments on Static Docs
getExistingTerminusEnvs() {
    existing_terminus_envs=() # Clear array
    while read -r env # Read a line
    do
        existing_terminus_envs+=( "$env" ) # Append line to the array
    done < "$1"
}
getExistingTerminusEnvs "env_list.txt"

# Update vm with current remote branches
git remote update origin --prune
# Identify merged remote branches, ignoring Pantheon defaults and master
git branch -r --merged master | awk -F'/' '/^ *origin/{if(!match($0, /(>|master)/) && (!match($0, /(>|dev)/)) && (!match($0, /(>|test)/)) && (!match($0, /(>|live)/))){print $2}}' | xargs -0 > merged-branches.txt
# Delete empty line at the end of txt file produced by awk
sed '/^$/d' merged-branches.txt > merged-branches-clean.txt
# Create an array of remote branches merged into master
getMergedBranchMultidevName() {
    merged_branch_multidev_names=() # Clear array
    while read -r branch # Read a line
    do
        # Save the first 11 chars, then remove -'s to follow multidev naming strategy
        multidev_name="${branch:0:11}"
        multidev_name="${multidev_name//-}"
        merged_branch_multidev_names+=( "$multidev_name" ) # Append to the array
    done < "$1"
}
getMergedBranchMultidevName "merged-branches-clean.txt"

# Compare existing environments and merged branches, delete only if the environment exists
merged_branch=" ${merged_branch_multidev_names[*]} "
for env in ${existing_terminus_envs[@]}; do
  if [[ $merged_branch =~ " $env " ]] && [ "$env" != "sculpin" ] ; then
    terminus multidev:delete $STATIC_DOCS_UUID.$env --delete-branch --yes
  fi
done

getMergedBranch() {
    merged_branch_array=() # Clear array
    while read -r branch # Read a line
    do
        # Save the first 11 chars, then remove -'s to follow multidev naming strategy
        merged_branch_array+=( "$branch" ) # Append to the array
    done < "$1"
}
getMergedBranch "merged-branches-clean.txt"

# Delete merged branches from GH Repo
# Commenting out for prototype work to avoid one more permissions set up.

exit 0;
  for branch in ${merged_branch_array[@]}; do
    if [ "$branch" != "sculpin" ] ; then
      git push origin --delete "$branch"
    fi
  done

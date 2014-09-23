#!/bin/bash
# Program to build and sign debian packages, and upload those to a public reprepro repository.
# Copyright (c) 2014 Santiago Bassett <santiago.bassett@gmail.com>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation,
# Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

# Usage:
# -u updates chroot environments
# -b builds and signs debian packages
# -s synchronizes uploading new packages to the public repository

packages=(ossec-hids ossec-hids-agent) # only options available
codenames=(sid jessie wheezy) # only options available
architectures=(amd64 i386) # only options available
ossec_version='2.8'
signing_key='XXX'
signing_pass='XXX'
main_path=/root/ # path to ossec-hids and ossec-hids-agent directories
logfile=/var/log/generate_ossec.log

# Function to write to LOG_FILE
write_log() 
{
  while read text
  do 
      local logtime=`date "+%Y-%m-%d %H:%M:%S"`
      echo $logtime": $text" | tee -a $logfile;
  done
}

# Show help function
show_help()
{
  echo "USAGE: Command line arguments available:"
  echo "-h | --help Displays this help."
  echo "-u | --update Updates chroot environments."
  echo "-b | --build Builds debian packages."
  echo "-s | --sync Synchronizes with the debian repository."
}

# Reads latest package version from changelog file
# Argument: changelog_file
read_package_version()
{
  local regex="^ossec-hids[A-Za-z-]* \([0-9]+.*[0-9]*.*[0-9]*-([0-9]+)[A-Za-z]*\)"
  while read line
  do
    if [[ $line =~ $regex ]]; then
      package_version="${BASH_REMATCH[1]}"
      break
    fi
  done < $1
}

# Updates changelog file with new codename, date and debdist.
# Arguments: changelog_file codename
update_changelog()
{
  local changelog_file=$1
  local changelog_file_tmp="${changelog_file}.tmp"
  local codename=$2

  if [ $codename = "sid" ]; then
    local debdist="unstable"
  elif [ $codename = "jessie" ]; then
    local debdist="testing"
  elif [ $codename = "wheezy" ]; then
    local debdist="stable"
  fi

  local changelogtime=$(date -R)
  local last_date_changed=0

  local regex1="^(ossec-hids[A-Za-z-]* \([0-9]+.*[0-9]*.*[0-9]*-[0-9]+)[A-Za-z]*\)"
  local regex2="( -- [[:alnum:]]*[^>]*>  )[[:alnum:]]*,"

  if [ -f ${changelog_file_tmp} ]; then
    rm -f ${changelog_file_tmp}
  fi
  touch ${changelog_file_tmp}

  IFS='' #To preserve line leading whitespaces
  while read line
  do
    if [[ $line =~ $regex1 ]]; then
      line="${BASH_REMATCH[1]}$codename) $debdist; urgency=low"
    fi
    if [[ $line =~ $regex2 ]] && [ $last_date_changed -eq 0 ]; then
      line="${BASH_REMATCH[1]}$changelogtime"
      last_date_changed=1
    fi
    echo "$line" >> ${changelog_file_tmp}
  done < ${changelog_file}

  mv ${changelog_file_tmp} ${changelog_file}
}

# Update chroot environments
update_chroots()
{
  for codename in ${codenames[@]}
  do
    for arch in ${architectures[@]}
    do
      echo "Updating chroot environment: ${codename}-${arch}" | write_log
      DIST=$codename ARCH=$arch pbuilder update
      echo "Successfully updated chroot environment: ${codename}-${arch}" | write_log   
    done
  done
}

# Build packages
build_packages()
{
for package in ${packages[@]}
do 
  for codename in ${codenames[@]}
  do
    for arch in ${architectures[@]}
    do
      source_path="${main_path}/${package}/${package}-${ossec_version}"
      changelog_path="${source_path}/debian/changelog"
      
      # Updating changelog file with new codename, date and debdist.
      update_changelog ${changelog_path} ${codename}

      # Setting up global variable package_version, used for deb_file and changes_file.
      read_package_version ${changelog_path}      
      deb_file="${package}_${ossec_version}-${package_version}${codename}_${arch}.deb"
      changes_file="${package}_${ossec_version}-${package_version}${codename}_${arch}.changes"

      # Building the Debian package.
      echo "Building Debian package ${package} for ${codename}-${arch}" | write_log
      cd ${source_path}
      /usr/bin/pdebuild --use-pdebuild-internal --architecture ${arch} --buildresult /var/cache/pbuilder/${codename}-${arch}/result/ \
      -- --basetgz /var/cache/pbuilder/${codename}-${arch}-base.tgz --distribution ${codename} --architecture ${arch} --aptcache \
      /var/cache/pbuilder/${codename}-${arch}/aptcache/ --override-config
      echo "Successfully built Debian package ${package} for ${codename}-${arch}" | write_log

      #Checking that package has at least 50 files to confirm it has been built correctly
      echo "Checking package ${deb_file} for ${codename}" | write_log
      cd /var/cache/pbuilder/${codename}-${arch}/result/
      files=$(/usr/bin/dpkg --contents ${deb_file} | wc -l)
      echo "Package ${deb_file} for ${codename} has ${files} files" | write_log
      if [ "${files}" -lt "50" ]; then
        echo "Error: Package ${package} for distribution ${codename}-${arch} has ${files} files" | write_log
        echo "Error: Aborting package creation and exiting script" | write_log
        exit 1;
      fi
      echo "Successfully checked package ${deb_file} for ${codename}" | write_log

      # Signing Debian package
      echo "Signing Debian package ${changes_file} for ${codename}" | write_log
      /usr/bin/expect -c "
        spawn debsign --re-sign -k${signing_key} ${changes_file}
        expect -re \".*passphrase.*\"
        send \"${signing_pass}\r\"
        expect -re \".*passphrase.*\"
        send \"${signing_pass}\r\"
        expect -re \".*Successfully.*\"
      "
      echo "Successfully signed Debian package ${changes_file} for ${codename}" | write_log   
 
    done
  done
done
}

# Synchronizes with the external repository, uploading new packages and ubstituting old ones.
sync_repository()
{
for package in ${packages[@]}
do
  for codename in ${codenames[@]}
  do
    for arch in ${architectures[@]}
    do
      source_path="${main_path}/${package}/${package}-${ossec_version}"
      changelog_path="${source_path}/debian/changelog"

      # Setting up global variable package_version, used for deb_file and changes_file.
      read_package_version ${changelog_path}
      deb_file="${package}_${ossec_version}-${package_version}${codename}_${arch}.deb"
      changes_file="${package}_${ossec_version}-${package_version}${codename}_${arch}.changes"

      # Uploading package to repository
      cd /var/cache/pbuilder/${codename}-${arch}/result/
      echo "Uploading package ${changes_file} for ${codename} to OSSEC repository" | write_log
      /usr/bin/dupload -f --to ossec ${changes_file}
      echo "Successfully uploaded package ${changes_file} for ${codename} to OSSEC repository" | write_log

      # Moving package to the right directory at the OSSEC apt repository server
      echo "Adding package /opt/incoming/${deb_file} to server repository for ${codename} distribution" | write_log
      remove_package="cd /var/www/repos/apt/debian; reprepro -A ${arch} remove ${codename} ${package}"
      /usr/bin/expect -c "
        spawn ssh root@ossec \"${remove_package}\"
        expect -re \"Not removed as not found.*\" { exit 1 }
        expect -re \".*passphrase.*\" { send \"${signing_pass}\r\" }
        expect -re \".*passphrase.*\" { send \"${signing_pass}\r\" }
        expect -re \".*deleting.*\"
      "
      include_package="cd /var/www/repos/apt/debian; reprepro includedeb ${codename} /opt/incoming/${deb_file}"
      /usr/bin/expect -c "
        spawn ssh root@ossec \"${include_package}\"
        expect -re \"Skipping inclusion.*\" { exit 1 }
        expect -re \".*passphrase.*\"
        send \"${signing_pass}\r\"
        expect -re \".*passphrase.*\"
        send \"${signing_pass}\r\"
        expect -re \".*Exporting.*\"
      "
      echo "Successfully added package ${deb_file} to server repository for ${codename} distribution" | write_log
    done
  done
done
}

# Reading command line arguments
while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
  -h|--help)
    show_help
    exit 0
    ;;
  -u|--update)
    update_chroots
    shift
    ;;
  -b|--build)
    build_packages
    shift
    ;;
  -s|--sync)
    sync_repository
    shift
    ;;
  *)
    echo "Unknown command line argument."
    show_help
    exit 0
    ;;
  esac
done

# vim: tabstop=2 expandtab shiftwidth=2 softtabstop=2

#!/bin/bash
# Author: Santiago Bassett 06/19/2014
# Creates Debian packages using Pbuilder and uploads those to Reprepro 
# Feel free use and modify this code, but do it at your own risk.

logfile=/var/log/generate_ossec.log

# Function to write to LOG_FILE
write_log() 
{
  while read text
  do 
      logtime=`date "+%Y-%m-%d %H:%M:%S"`
      echo $logtime": $text" | tee -a $logfile;
  done
}

packages=(ossec-hids ossec-hids-agent)
codenames=(sid jessie wheezy)
architectures=(amd64 i386)
ossec_version='2.8'
signing_key='XXX'
signing_pass='XXX'

for package in ${packages[@]}
do 
  for codename in ${codenames[@]}
  do
    for arch in ${architectures[@]}
      do

      #Updating chroot environment
      echo "Updating chroot environment: ${codename}-${arch}" | write_log
      DIST=$codename ARCH=$arch pbuilder update
      echo "Successfully updated chroot environment: ${codename}-${arch}" | write_log

      #Setting package_path variable
      if [ $package = "ossec-hids" ]; then
        package_path="/root/ossec-hids/ossec-hids-${ossec_version}"
      elif [ $package = "ossec-hids-agent" ]; then 
        package_path="/root/ossec-hids-agent/ossec-hids-agent-${ossec_version}"
      fi

      #Updating changelog before building package and cleaning files
      if [ $codename = "sid" ]; then
        debdist="unstable"
      elif [ $codename = "jessie" ]; then
        debdist="testing"
      elif [ $codename = "wheezy" ]; then
        debdist="stable"
      fi
      changelogtime=$(date -R)
      cd ${package_path}
      sed -i "s/^ossec-hids.*/${package} (${ossec_version}-1${codename}) ${debdist}\; urgency\=low/" debian/changelog
      sed -i "s/ -- Santiago Bassett <.*/ -- Santiago Bassett <santiago.bassett@gmail.com>  ${changelogtime}/" debian/changelog
      rm -f debian/files

      #Building the Debian package
      echo "Building Debian package ${package} for ${codename}-${arch}" | write_log
      /usr/bin/pdebuild --use-pdebuild-internal --architecture ${arch} --buildresult /var/cache/pbuilder/${codename}-${arch}/result/ \
      -- --basetgz /var/cache/pbuilder/${codename}-${arch}-base.tgz --distribution ${codename} --architecture ${arch} --aptcache \
      /var/cache/pbuilder/${codename}-${arch}/aptcache/ --override-config
      echo "Successfully built Debian package ${package} for ${codename}-${arch}" | write_log

      #Checking that package has at least 50 files to confirm it has been built correctly
      echo "Checking package ${package}_${ossec_version}-1${codename}_${arch}.deb for ${codename}" | write_log
      cd /var/cache/pbuilder/${codename}-${arch}/result/
      files=$(/usr/bin/dpkg --contents ${package}_${ossec_version}-1${codename}_${arch}.deb | wc -l)
      echo "Package ${package}_${ossec_version}-1${codename}_${arch}.deb for ${codename} has ${files} files" | write_log
      if [ "${files}" -lt "50" ]; then
        echo "Error: Package ${package} for distribution ${codename}-${arch} has ${files} files" | write_log
        echo "Error: Aborting package creation and exiting script" | write_log
        exit 1;
      fi
      echo "Successfully checked package ${package}_${ossec_version}-1${codename}_${arch}.deb for ${codename}" | write_log

      # Signing Debian package
      echo "Signing Debian package ${package}_${ossec_version}-1${codename}_${arch}.changes for ${codename}" | write_log
      /usr/bin/expect -c "
        spawn debsign --re-sign -k${signing_key} ${package}_${ossec_version}-1${codename}_${arch}.changes
        expect -re \".*passphrase.*\"
        send \"${signing_pass}\r\"
        expect -re \".*passphrase.*\"
        send \"${signing_pass}\r\"
        expect -re \".*Successfully.*\"
      "
      echo "Successfully signed Debian package ${package}_${ossec_version}-1${codename}_${arch}.changes for ${codename}" | write_log

      # Uploading package to repository
      echo "Uploading package ${package}_${ossec_version}-1${codename}_${arch}.changes for ${codename} to OSSEC repository" | write_log
      /usr/bin/dupload -f --to ossec ${package}_${ossec_version}-1${codename}_${arch}.changes
      echo "Successfully uploaded package ${package}_${ossec_version}-1${codename}_${arch}.changes for ${codename} to OSSEC repository" | write_log

      # Moving package to the right directory at the OSSEC apt repository server
      echo "Adding package /opt/incoming/${package}_${ossec_version}-1${codename}_${arch}.deb to server repository for ${codename} distribution" | write_log
      remove_package="cd /var/www/repos/apt/debian; reprepro -A ${arch} remove ${codename} ${package}"
      /usr/bin/expect -c "
        spawn ssh root@ossec \"${remove_package}\"
        expect -re \"Not removed as not found.*\" { exit 1 }
        expect -re \".*passphrase.*\" { send \"${signing_pass}\r\" }
        expect -re \".*passphrase.*\" { send \"${signing_pass}\r\" }
        expect -re \".*deleting.*\"
      "
      include_package="cd /var/www/repos/apt/debian; reprepro includedeb ${codename} /opt/incoming/${package}_${ossec_version}-1${codename}_${arch}.deb"
      /usr/bin/expect -c "
        spawn ssh root@ossec \"${include_package}\"
        expect -re \"Skipping inclusion.*\" { exit 1 }
        expect -re \".*passphrase.*\"
        send \"${signing_pass}\r\"
        expect -re \".*passphrase.*\"
        send \"${signing_pass}\r\"
        expect -re \".*Exporting.*\"
      "
      echo "Successfully added package ${package}_${ossec_version}-1${codename}_${arch}.deb to server repository for ${codename} distribution" | write_log

	  done
  done
done

# vim: tabstop=2 expandtab shiftwidth=2 softtabstop=2

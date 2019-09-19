#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

set -e

export PERL5LIB=/home/tdr/lib:/home/tdr/CIHM-Swift/lib
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/tdr/bin:/home/tdr/CIHM-Swift/bin

# This seems to be owned by wrong user from time to time.
mkdir -p /var/lock/tdr/
chown tdr.tdr /var/lock/tdr/
mkdir -p /var/log/tdr/
chown tdr.tdr /var/log/tdr/

echo "export PATH=$PATH" >> /root/.profile
echo "export PERL5LIB=$PERL5LIB" >> /root/.profile

echo "export PATH=$PATH" >> /home/tdr/.profile
echo "export PERL5LIB=$PERL5LIB" >> /home/tdr/.profile
chown tdr.tdr /home/tdr/.profile

exec sudo -u tdr -i "$@"

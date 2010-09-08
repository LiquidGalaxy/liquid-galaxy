<?php
# Copyright 2010 Google Inc.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if (isset($_REQUEST['planet']) and ($_REQUEST['planet'] != '')) { 
  $handle = @fopen("/tmp/query.txt", "w");
  if ($handle) {
    fwrite($handle, "planet=" . $_REQUEST['planet']);
  }
  exec('/lg/chown_tmp_query');
  echo "Going to " . ucwords($_REQUEST['planet']);
} elseif (isset($_REQUEST['query']) and ($_REQUEST['query'] != '') and isset($_REQUEST['name']) and ($_REQUEST['name'] != '')) {
  $handle = @fopen("/tmp/query.txt", "w");
  if ($handle) {
    fwrite($handle, $_REQUEST['query']);
  }
  exec('/lg/chown_tmp_query');
  echo "Going to " . $_REQUEST['name'];
}
?>

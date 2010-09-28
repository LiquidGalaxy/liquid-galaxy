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

$queries = array('earth' => array(), 'moon' => array(), 'mars' => array());
$delimiter = "@";
$handle = @fopen("queries.txt", "r");
if ($handle) {
  while (!feof($handle)) {
    $buffer = fgets($handle);
    if (substr_count($buffer, $delimiter) == 2) {
      list($planet, $name, $query) = explode($delimiter, $buffer);
      $queries[$planet][] = array(trim($name), trim($query));
    }
  }
  fclose($handle);
}
?>
<html>
  <head>
    <link rel="stylesheet" type="text/css" href="style.css" />
    <script type="text/javascript" src="javascript.js"></script>
    <title>Liquid Galaxy</title>
  </head>
  <body>
    <div class="touchscreen">
      <div id="status"></div>
      <div class="earth">
        <div class="title" onclick="changePlanet('earth');">Earth</div>
        <img onclick="changePlanet('earth');" src="earth.png" />
        <div class="expand">
          <?php foreach (array_values($queries['earth']) as $query) { ?>
            <div class="location" onclick="changeQuery('<?php echo $query[1]; ?>', '<?php echo $query[0]; ?>');"><?php echo $query[0]; ?></div>
          <? } ?>
        </div>
      </div>
      <div class="moon">
        <div class="title" onclick="changePlanet('moon');">Moon</div>
        <img onclick="changePlanet('moon');" src="moon.png" />
        <div class="expand">
          <?php foreach (array_values($queries['moon']) as $query) { ?>
            <div class="location" onclick="changeQuery('<?php echo $query[1]; ?>', '<?php echo $query[0]; ?>');"><?php echo $query[0]; ?></div>
          <? } ?>
        </div>
      </div>
      <div class="mars">
        <div class="title" onclick="changePlanet('mars');">Mars</div>
        <img onclick="changePlanet('mars');" src="mars.png" />
        <div class="expand">
          <?php foreach (array_values($queries['mars']) as $query) { ?>
            <div class="location" onclick="changeQuery('<?php echo $query[1]; ?>', '<?php echo $query[0]; ?>');"><?php echo $query[0]; ?></div>
          <? } ?>
        </div>
      </div>
      <div class="keyboard">
        <div class="title">&nbsp;</div>
        <img src="keyboard.png" />
        <div class="expand">
          <div class="keyboardRow1">
            <input class="keyboardEntry" id="keyboardEntry" name="keyboardEntry" type="text" value=""/>
            <div class="keyboardKey keyboardKeyClear" onclick='clearKey();'>Clear</div>
            <div class="keyboardKey keyboardKeySearch" onclick='searchKey();'>Search</div>
          </div>
          <div class="keyboardRow2">
            <?php foreach (array('1','2','3','4','5','6','7','8','9','0') as $key) { ?>
              <div class="keyboardKey" onclick="keyEntry('<?php echo $key; ?>');"><?php echo $key; ?></div>
            <?php } ?>
            <div class="keyboardKey keyboardKeyBackspace" onclick='backspaceKey();'>Bksp</div>
          </div>
          <div class="keyboardRow3">
            <?php foreach (array('Q','W','E','R','T','Y','U','I','O','P') as $key) { ?>
              <div class="keyboardKey" onclick="keyEntry('<?php echo $key; ?>');"><?php echo $key; ?></div>
            <?php } ?>
          </div>
          <div class="keyboardRow4">
            <?php foreach (array('A','S','D','F','G','H','J','K','L') as $key) { ?>
              <div class="keyboardKey" onclick="keyEntry('<?php echo $key; ?>');"><?php echo $key; ?></div>
            <?php } ?>
          </div>
          <div class="keyboardRow5">
            <?php foreach (array('Z','X','C','V','B','N','M',',','.') as $key) { ?>
              <div class="keyboardKey" onclick="keyEntry('<?php echo $key; ?>');"><?php echo $key; ?></div>
            <?php } ?>
          </div>
          <div class="keyboardRow6">
            <div class="keyboardKey keyboardKeySpace" onclick='keyEntry(" ");'></div>
          </div>
        </div>
      </div>
      <div class="welcome">
        Welcome to the Liquid Galaxy by Google
      </div>
      <div class="relaunch">
        <div class="location" onclick="changeQuery('relaunch', 'Relaunch');">Relaunch</div>
      </div>
    </div>
  </body>
</html>

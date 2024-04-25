<?php
// from adamone-setup.php
// Configure cron job for automatic updates
function adamone_configure_autoupdates() {
    global $config;
    $cmd = '/usr/local/bin/adamone-upgrade';
    $a_cron = &$config['cron']['item'];
    $add = true;
    $i = 0;
    if (count($a_cron) > 0) {
        foreach ($a_cron as $ent) {
            if (strpos($ent['command'], $cmd) !== false) {
                $add = false;
            }
            $i++;
        }
    }

    if ($add) {
        // Add the cron job
        $ent = array();
        $ent['minute'] = date('i');
        $ent['hour'] = date('H');
        $ent['mday'] = '*';
        $ent['month'] = '*';
        $ent['wday'] = '*';
        $ent['who'] = 'root';
        $ent['command'] = $cmd;
        $a_cron[] = $ent;
        write_config("Adding adam:ONE automatic upgrade task");
        configure_cron();
    }
}

// Get current backup cron job status
function adamone_autobackups_enabled() {
    global $config;
    $cmd = '/usr/local/bin/adamone-backup';
    $a_cron = &$config['cron']['item'];
    if (count($a_cron) > 0) {
        foreach ($a_cron as $ent) {
            if (strpos($ent['command'], $cmd) !== false) {
                return true;
            }
        }
    }
    return false;
}

// Configure cron job for automatic backups
function adamone_autobackups_configure($enabled) {
    global $config;
    $cmd = '/usr/local/bin/adamone-backup';
    $a_cron = &$config['cron']['item'];
    $add = $enabled;
    $remove = false;
    $i = 0;
    if (count($a_cron) > 0) {
        foreach ($a_cron as $ent) {
            if (strpos($ent['command'], $cmd) !== false) {
                $add = false;
                if (!$enabled) {
                    $remove = true;
                }
                break;
            }
            $i++;
        }
    }

    if ($remove) {
        unset($a_cron[$i]);
        write_config("Removing adam:ONE automatic cloud backup task");
        configure_cron();
    }

    if ($add) {
        // Add the cron job

        $dayOfWeek = date('w');

        $ent = array();
        $ent['minute'] = date('i');
        $ent['hour'] = date('H');
        $ent['mday'] = '*';
        $ent['month'] = '*';
        $ent['wday'] = $dayOfWeek;
        $ent['who'] = 'root';
        $ent['command'] = $cmd;
        $a_cron[] = $ent;
        write_config("Adding adam:ONE automatic cloud backup task");
        configure_cron();
    }
}

<?php

/*
 * Copyright (c) 2026 Jon Wedell <jon@jonwedell.com>
 * All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

namespace ThreatPatrols\Autossh\Migrations;

use OPNsense\Base\BaseModelMigration;

/**
 * Repair rekey_limit values left behind by the 0.3.0 migration.
 *
 * That migration converted stored algorithm names back to option keys for
 * ciphers, host_key_algorithms, kex_algorithms, macs and
 * pubkey_accepted_key_types using array_search (value => key, correct). For
 * rekey_limit it instead indexed the same key => value map *by* the stored
 * value, which never matches, so the field was left holding a raw value such
 * as "default none" rather than "rekey_limit_01".
 *
 * A raw value is not a valid option, so the dialog cannot preselect it and the
 * config generator has to guess. Map it back to its key, conservatively:
 * anything already valid is left alone, and anything unrecognizable falls back
 * to the no-op setting rather than being dropped (the field is required, so
 * leaving it invalid would block future saves).
 */
class M1_0_0 extends BaseModelMigration
{
    private const REKEY_LIMITS = [
        'rekey_limit_01' => 'default none',
        'rekey_limit_02' => '1G 1h',
        'rekey_limit_03' => '1G 4h',
        'rekey_limit_04' => '1G 8h',
        'rekey_limit_05' => '2G 1h',
        'rekey_limit_06' => '2G 4h',
        'rekey_limit_07' => '2G 8h',
        'rekey_limit_08' => '4G 1h',
        'rekey_limit_09' => '4G 4h',
        'rekey_limit_10' => '4G 8h',
    ];

    public function run($model)
    {
        /*
         * Registering a migration for this version replaces the default one,
         * so the base behaviour -- applying defaults to required fields that
         * are not set yet, which is what gives existing tunnels the new
         * algorithm options -- has to be invoked explicitly.
         */
        parent::run($model);

        foreach ($model->tunnels->tunnel->iterateItems() as $tunnel) {
            $current = (string)$tunnel->rekey_limit;

            if ($current === '' || isset(self::REKEY_LIMITS[$current])) {
                continue; // unset, or already an option key
            }

            $key = array_search($current, self::REKEY_LIMITS, true);
            $tunnel->rekey_limit->setValue($key === false ? 'rekey_limit_01' : $key);
        }
    }
}

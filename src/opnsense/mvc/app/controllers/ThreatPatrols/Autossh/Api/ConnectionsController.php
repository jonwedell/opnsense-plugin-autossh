<?php

/*
 * Copyright (c) 2022 Threat Patrols Pty Ltd <contact@threatpatrols.com>
 * Copyright (c) 2026 Jon Wedell <jon@jonwedell.com>
 * All rights reserved.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

namespace ThreatPatrols\Autossh\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;
use ThreatPatrols\Autossh\Autossh;

class ConnectionsController extends ApiControllerBase
{
    /**
     * Live per tunnel status, shaped for a bootgrid.
     */
    public function searchAction()
    {
        $response = json_decode(trim((new Backend())->configdRun('autossh connection_status')), true);
        $rows = (is_array($response) && isset($response['rows'])) ? $response['rows'] : [];

        $search_phrase = (string)$this->request->get('searchPhrase', 'string', '');
        if ($search_phrase !== '') {
            $needle = strtolower($search_phrase);
            $rows = array_values(array_filter($rows, function ($row) use ($needle) {
                foreach (['description', 'connection', 'ssh_key', 'forwards', 'status'] as $field) {
                    if (str_contains(strtolower((string)($row[$field] ?? '')), $needle)) {
                        return true;
                    }
                }
                return false;
            }));
        }

        return [
            'rows' => $rows,
            'total' => count($rows),
            'rowCount' => count($rows),
            'current' => 1,
        ];
    }

    private function tunnelAction($action)
    {
        if (!$this->request->isPost() || !$this->request->hasPost('uuid')) {
            return ['status' => 'failed', 'message' => gettext('No tunnel specified.')];
        }

        // only hand configd the id of a tunnel that exists; it ends up as an
        // argument to autossh, where anything starting with "-" is an option
        $uuid = (string)$this->request->getPost('uuid');
        if (!Autossh::isTunnelUuid($uuid)) {
            return ['status' => 'failed', 'message' => gettext('Unknown tunnel.')];
        }

        $output = trim((new Backend())->configdpRun("autossh {$action}_tunnel", [$uuid]));

        // the rc script prefixes failures with "Fail:"
        if (stripos($output, 'fail') !== false) {
            return ['status' => 'failed', 'message' => $output];
        }

        return ['status' => 'ok', 'message' => $output];
    }

    public function startAction()
    {
        return $this->tunnelAction('start');
    }

    public function stopAction()
    {
        return $this->tunnelAction('stop');
    }

    public function restartAction()
    {
        return $this->tunnelAction('restart');
    }
}

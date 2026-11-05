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

/**
 * Autossh runs one process per tunnel rather than a single daemon, so service
 * control is implemented directly instead of via ApiMutableServiceControllerBase.
 */
class ServiceController extends ApiControllerBase
{
    private function backendJson($action, array $parameters = [])
    {
        $raw = trim((new Backend())->configdpRun($action, $parameters));
        $decoded = json_decode($raw, true);

        if (!is_array($decoded) || !isset($decoded['status'])) {
            return [
                'status' => 'failed',
                'message' => gettext('Unexpected backend response, review the configd log.'),
                'raw' => $raw,
            ];
        }

        return $decoded;
    }

    /**
     * Regenerate the ssh client configuration and apply it. Only tunnels whose
     * rendered configuration actually changed are restarted.
     */
    public function reconfigureAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed', 'message' => gettext('Only POST requests are allowed.')];
        }

        $backend = new Backend();

        // /etc/rc.conf.d/autossh is template rendered; refresh it first so the
        // rc script picks up any packaged changes
        $template = trim($backend->configdRun('template reload ThreatPatrols/Autossh'));
        if (strtoupper($template) !== 'OK') {
            return [
                'status' => 'failed',
                'message' => gettext('Template reload failed, review the configd log.'),
            ];
        }

        $result = $this->backendJson('autossh reconfigure');

        return [
            // the configuration may still have been written when individual
            // tunnels failed to (re)start; the message says which
            'status' => $result['status'] === 'success' ? 'ok' : 'failed',
            'message' => $result['message'],
            'actions' => $result['data']['actions'] ?? [],
            'skipped' => $result['data']['skipped'] ?? [],
        ];
    }

    public function statusAction()
    {
        $output = trim((new Backend())->configdRun('autossh status'));
        $running = substr_count($output, ': running');
        $stopped = substr_count($output, ': not running');

        if ($running === 0 && $stopped === 0) {
            return ['status' => 'none', 'message' => gettext('No tunnels configured.')];
        }

        return [
            'status' => $stopped === 0 ? 'running' : ($running === 0 ? 'stopped' : 'degraded'),
            'running' => $running,
            'stopped' => $stopped,
            'message' => $output,
        ];
    }

    public function startAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed'];
        }
        return ['status' => 'ok', 'message' => trim((new Backend())->configdRun('autossh start'))];
    }

    public function stopAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed'];
        }
        return ['status' => 'ok', 'message' => trim((new Backend())->configdRun('autossh stop'))];
    }

    public function restartAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed'];
        }
        return ['status' => 'ok', 'message' => trim((new Backend())->configdRun('autossh restart'))];
    }
}

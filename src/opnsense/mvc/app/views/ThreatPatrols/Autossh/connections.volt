{#
 # Copyright (c) 2026 Jon Wedell <jon@jonwedell.com>
 # All rights reserved.
 #
 # SPDX-License-Identifier: BSD-2-Clause
 #}

<script>
    $(document).ready(function () {
        const endpoint = '/api/autossh/connections/';

        function tunnelCommand(action, event) {
            const uuid = $(event.currentTarget).data('row-id');
            const $icon = $(event.currentTarget).find('span');
            const restore = $icon.attr('class');

            $icon.attr('class', 'fa fa-fw fa-spinner fa-pulse');
            ajaxCall(endpoint + action, { 'uuid': uuid }, function (data, status) {
                $icon.attr('class', restore);
                if (status !== 'success' || (data && data['status'] === 'failed')) {
                    stdDialogInform(
                        "{{ lang._('Autossh') }}",
                        (data && data['message']) ? data['message'] : "{{ lang._('The request failed.') }}",
                        "{{ lang._('Close') }}", undefined, "warning"
                    );
                }
                $('#grid-connections').bootgrid('reload');
            });
        }

        $("#grid-connections").UIBootgrid({
            search: endpoint + 'search/',
            options: {
                selection: false,
                multiSelect: false,
                rowCount: [-1, 10, 25, 50],
                formatters: {
                    status: function (column, row) {
                        if (row.status === 'running') {
                            return '<span class="label label-success">' + "{{ lang._('running') }}" + '</span>';
                        }
                        if (row.enabled !== '1') {
                            return '<span class="label label-default">' + "{{ lang._('disabled') }}" + '</span>';
                        }
                        return '<span class="label label-danger">' + "{{ lang._('stopped') }}" + '</span>';
                    },
                    nullable: function (column, row) {
                        return row[column.id] ? row[column.id] : '-';
                    }
                }
            },
            commands: {
                start: {
                    title: "{{ lang._('Start') }}",
                    classname: 'fa fa-fw fa-play',
                    sequence: 10,
                    method: function (event) {
                        tunnelCommand('start', event);
                    }
                },
                restart: {
                    title: "{{ lang._('Restart') }}",
                    classname: 'fa fa-fw fa-refresh',
                    sequence: 20,
                    method: function (event) {
                        tunnelCommand('restart', event);
                    }
                },
                stop: {
                    title: "{{ lang._('Stop') }}",
                    classname: 'fa fa-fw fa-stop',
                    sequence: 30,
                    method: function (event) {
                        tunnelCommand('stop', event);
                    }
                }
            }
        });

        // a status page is only useful if it stays current
        setInterval(function () {
            $('#grid-connections').bootgrid('reload');
        }, 15000);
    });
</script>

<div class="content-box">
    <table id="grid-connections" class="table table-condensed table-hover table-striped">
        <thead>
            <tr>
                <th data-column-id="uuid" data-type="string" data-identifier="true" data-visible="false">{{ lang._('ID') }}</th>
                <th data-column-id="status" data-formatter="status" data-width="7em" data-sortable="true">{{ lang._('Status') }}</th>
                <th data-column-id="description" data-type="string" data-sortable="true">{{ lang._('Description') }}</th>
                <th data-column-id="connection" data-type="string" data-sortable="true">{{ lang._('Connection') }}</th>
                <th data-column-id="ssh_key" data-type="string" data-sortable="true">{{ lang._('Key') }}</th>
                <th data-column-id="forwards" data-type="string" data-sortable="false">{{ lang._('Forwarding') }}</th>
                <th data-column-id="pid" data-formatter="nullable" data-width="6em" data-sortable="false">{{ lang._('PID') }}</th>
                <th data-column-id="started" data-formatter="nullable" data-sortable="false">{{ lang._('Started') }}</th>
                <th data-column-id="last_ok" data-formatter="nullable" data-sortable="false">{{ lang._('Last check') }}</th>
                <th data-column-id="commands" data-formatter="commands" data-width="9em" data-sortable="false">{{ lang._('Commands') }}</th>
            </tr>
        </thead>
        <tbody></tbody>
    </table>
</div>

<div class="col-md-12">
    <div class="alert alert-info" role="alert">
        {{ lang._('Last check is the most recent successful autossh monitor poll found in the log. Tunnels reconnect by themselves; starting one by hand is only needed after it has been stopped.') }}
    </div>
</div>

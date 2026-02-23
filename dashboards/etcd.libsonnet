local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local prometheus = g.query.prometheus;
local stat = g.panel.stat;
local timeSeries = g.panel.timeSeries;
local var = g.dashboard.variable;

{
  local statPanel(title, unit, query) =
    stat.new(title)
    + stat.options.withColorMode('none')
    + stat.options.withGraphMode('none')
    + stat.options.reduceOptions.withCalcs(['lastNotNull'])
    + stat.standardOptions.withUnit(unit)
    + stat.queryOptions.withInterval($._config.grafanaK8s.minimumTimeInterval)
    + stat.queryOptions.withTargets([
      prometheus.new('${datasource}', query)
      + prometheus.withInstant(true),
    ]),

  local tsPanel =
    timeSeries {
      new(title):
        timeSeries.new(title)
        + timeSeries.options.legend.withShowLegend()
        + timeSeries.options.legend.withAsTable()
        + timeSeries.options.legend.withDisplayMode('table')
        + timeSeries.options.legend.withPlacement('right')
        + timeSeries.options.legend.withCalcs(['lastNotNull'])
        + timeSeries.options.tooltip.withMode('single')
        + timeSeries.fieldConfig.defaults.custom.withShowPoints('never')
        + timeSeries.fieldConfig.defaults.custom.withFillOpacity(10)
        + timeSeries.fieldConfig.defaults.custom.withSpanNulls(true)
        + timeSeries.queryOptions.withInterval($._config.grafanaK8s.minimumTimeInterval),
    },

  grafanaDashboards+:: {
    'etcd.json':

      local variables = {
        datasource:
          var.datasource.new('datasource', 'prometheus')
          + var.datasource.withRegex($._config.datasourceFilterRegex)
          + var.datasource.generalOptions.showOnDashboard.withLabelAndValue()
          + var.datasource.generalOptions.withLabel('Data source')
          + {
            current: {
              selected: true,
              text: $._config.datasourceName,
              value: $._config.datasourceName,
            },
          },

        cluster:
          var.query.new('cluster')
          + var.query.withDatasourceFromVariable(self.datasource)
          + var.query.queryTypes.withLabelValues(
            $._config.clusterLabel,
            'up{%(etcdSelector)s}' % $._config
          )
          + var.query.generalOptions.withLabel('cluster')
          + var.query.refresh.onTime()
          + (
            if $._config.showMultiCluster
            then var.query.generalOptions.showOnDashboard.withLabelAndValue()
            else var.query.generalOptions.showOnDashboard.withNothing()
          )
          + var.query.withSort(type='alphabetical'),

        instance:
          var.query.new('instance')
          + var.query.withDatasourceFromVariable(self.datasource)
          + var.query.queryTypes.withLabelValues(
            'instance',
            'up{%(etcdSelector)s, %(clusterLabel)s="$cluster"}' % $._config,
          )
          + var.query.generalOptions.withLabel('instance')
          + var.query.refresh.onTime()
          + var.query.generalOptions.showOnDashboard.withLabelAndValue()
          + var.query.selectionOptions.withIncludeAll(true, '.+'),
      };

      local panels = [
        statPanel('Up', 'none', 'sum(up{%(clusterLabel)s="$cluster", %(etcdSelector)s})' % $._config)
        + stat.gridPos.withW(4),

        tsPanel.new('RPC rate')
        + tsPanel.gridPos.withW(10)
        + tsPanel.standardOptions.withUnit('ops')
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'sum(rate(grpc_server_started_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance", grpc_type="unary"}[%(grafanaIntervalVar)s]))' % $._config)
          + prometheus.withLegendFormat('RPC rate'),

          prometheus.new('${datasource}', 'sum(rate(grpc_server_handled_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance", grpc_type="unary", grpc_code=~"Unknown|FailedPrecondition|ResourceExhausted|Internal|Unavailable|DataLoss|DeadlineExceeded"}[%(grafanaIntervalVar)s]))' % $._config)
          + prometheus.withLegendFormat('RPC failed rate'),
        ]),

        tsPanel.new('Active streams')
        + tsPanel.gridPos.withW(10)
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'sum(grpc_server_started_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance", grpc_service="etcdserverpb.Watch", grpc_type="bidi_stream"}) - sum(grpc_server_handled_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance", grpc_service="etcdserverpb.Watch", grpc_type="bidi_stream"})' % $._config)
          + prometheus.withLegendFormat('Watch streams'),

          prometheus.new('${datasource}', 'sum(grpc_server_started_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance", grpc_service="etcdserverpb.Lease", grpc_type="bidi_stream"}) - sum(grpc_server_handled_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance", grpc_service="etcdserverpb.Lease", grpc_type="bidi_stream"})' % $._config)
          + prometheus.withLegendFormat('Lease streams'),
        ]),

        tsPanel.new('DB size')
        + tsPanel.gridPos.withW(8)
        + tsPanel.standardOptions.withUnit('bytes')
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'etcd_mvcc_db_total_size_in_bytes{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}' % $._config)
          + prometheus.withLegendFormat('{{instance}} DB size'),
        ]),

        tsPanel.new('Disk sync duration')
        + tsPanel.gridPos.withW(8)
        + tsPanel.standardOptions.withUnit('s')
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'histogram_quantile(0.99, sum(rate(etcd_disk_wal_fsync_duration_seconds_bucket{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}[%(grafanaIntervalVar)s])) by (instance, le))' % $._config)
          + prometheus.withLegendFormat('{{instance}} WAL fsync'),

          prometheus.new('${datasource}', 'histogram_quantile(0.99, sum(rate(etcd_disk_backend_commit_duration_seconds_bucket{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}[%(grafanaIntervalVar)s])) by (instance, le))' % $._config)
          + prometheus.withLegendFormat('{{instance}} DB fsync'),
        ]),

        tsPanel.new('Memory')
        + tsPanel.gridPos.withW(8)
        + tsPanel.standardOptions.withUnit('bytes')
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'process_resident_memory_bytes{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}' % $._config)
          + prometheus.withLegendFormat('{{instance}} resident memory'),
        ]),

        tsPanel.new('Client traffic in')
        + tsPanel.gridPos.withW(6)
        + tsPanel.standardOptions.withUnit('Bps')
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'rate(etcd_network_client_grpc_received_bytes_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}[%(grafanaIntervalVar)s])' % $._config)
          + prometheus.withLegendFormat('{{instance}} client traffic in'),
        ]),

        tsPanel.new('Client traffic out')
        + tsPanel.gridPos.withW(6)
        + tsPanel.standardOptions.withUnit('Bps')
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'rate(etcd_network_client_grpc_sent_bytes_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}[%(grafanaIntervalVar)s])' % $._config)
          + prometheus.withLegendFormat('{{instance}} client traffic out'),
        ]),

        tsPanel.new('Peer traffic in')
        + tsPanel.gridPos.withW(6)
        + tsPanel.standardOptions.withUnit('Bps')
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'sum(rate(etcd_network_peer_received_bytes_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}[%(grafanaIntervalVar)s])) by (instance)' % $._config)
          + prometheus.withLegendFormat('{{instance}} peer traffic in'),
        ]),

        tsPanel.new('Peer traffic out')
        + tsPanel.gridPos.withW(6)
        + tsPanel.standardOptions.withUnit('Bps')
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'sum(rate(etcd_network_peer_sent_bytes_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}[%(grafanaIntervalVar)s])) by (instance)' % $._config)
          + prometheus.withLegendFormat('{{instance}} peer traffic out'),
        ]),

        tsPanel.new('Raft proposals')
        + tsPanel.gridPos.withW(8)
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'changes(etcd_server_leader_changes_seen_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}[1d])' % $._config)
          + prometheus.withLegendFormat('{{instance}} total leader elections per day'),
        ]),

        tsPanel.new('Total leader elections per day')
        + tsPanel.gridPos.withW(8)
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'changes(etcd_server_leader_changes_seen_total{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}[1d])' % $._config)
          + prometheus.withLegendFormat('{{instance}} total leader elections per day'),
        ]),

        tsPanel.new('Peer round trip time')
        + tsPanel.gridPos.withW(8)
        + tsPanel.standardOptions.withUnit('s')
        + tsPanel.queryOptions.withTargets([
          prometheus.new('${datasource}', 'histogram_quantile(0.99, sum by (instance, le) (rate(etcd_network_peer_round_trip_time_seconds_bucket{%(clusterLabel)s="$cluster", %(etcdSelector)s, instance=~"$instance"}[%(grafanaIntervalVar)s])))' % $._config)
          + prometheus.withLegendFormat('{{instance}} peer round trip time'),
        ]),
      ];

      g.dashboard.new('%(dashboardNamePrefix)setcd' % $._config.grafanaK8s)
      + g.dashboard.withUid($._config.grafanaDashboardIDs['etcd.json'])
      + g.dashboard.withTags($._config.grafanaK8s.dashboardTags)
      + g.dashboard.withEditable(false)
      + g.dashboard.time.withFrom('now-1h')
      + g.dashboard.time.withTo('now')
      + g.dashboard.withRefresh($._config.grafanaK8s.refresh)
      + g.dashboard.withVariables([variables.datasource, variables.cluster, variables.instance])
      + g.dashboard.withPanels(g.util.grid.wrapPanels(panels, panelWidth=12, panelHeight=7)),
  },
}

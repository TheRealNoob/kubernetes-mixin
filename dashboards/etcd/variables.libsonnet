// variables.libsonnet
local g = import './g.libsonnet';
local var = g.dashboard.variable;


function(config) {
  datasource:
    var.datasource.new('datasource', 'prometheus')
    + var.datasource.generalOptions.withLabel('Data Source'),

  cluster:
    if config.clusterLabel != '' then
      var.query.new('cluster')
      + var.query.generalOptions.withLabel('cluster')
      + var.query.withDatasourceFromVariable(self.datasource)
      + { refresh: config.dashboard_var_refresh }
      + var.query.queryTypes.withLabelValues(
        config.clusterLabel,
        'etcd_server_has_leader'
      )
    else {},

  job:
    var.query.new('job')
    + var.query.generalOptions.withLabel('job')
    + var.query.withDatasourceFromVariable(self.datasource)
    + { refresh: config.dashboard_var_refresh }
    + var.query.queryTypes.withLabelValues(
      'job',
      if config.clusterLabel != '' then
        'etcd_server_has_leader{%s="$cluster", %s}' % [config.clusterLabel, config.etcd_selector]
      else
        'etcd_server_has_leader{%s}' % [config.etcd_selector]
    ),

}

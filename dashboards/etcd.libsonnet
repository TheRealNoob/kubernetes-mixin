{
  _config+:: {
    grafana7x: false,
    etcd_selector: 'job=~".*etcd.*"',
    clusterLabel: 'cluster',
    dashboard_var_refresh: 2,
  },
} + (import 'etcd/etcd.libsonnet')

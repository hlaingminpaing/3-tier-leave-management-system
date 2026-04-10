terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Create monitoring namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      name = "monitoring"
    }
  }
}

# ============================================================
# Prometheus & Grafana Stack via Helm
# ============================================================

resource "helm_repository" "prometheus_community" {
  name             = "prometheus-community"
  url              = "https://prometheus-community.github.io/helm-charts"
  repository_cafile = ""
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = helm_repository.prometheus_community.name
  chart            = "kube-prometheus-stack"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  version          = "60.0.0"
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      # Prometheus Configuration
      prometheus = {
        prometheusSpec = {
          # Service Monitor Configuration
          serviceMonitorSelectorNilUsesHelmValues = false
          serviceMonitorSelector = {
            matchLabels = {
              prometheus = "enabled"
            }
          }

          # Storage Configuration
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }

          # Retention
          retention = "30d"

          # Resources
          resources = {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        # Ingress
        ingress = {
          enabled = true
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"  = "ip"
          }
          hosts = ["prometheus.example.com"]
          paths = ["/"]
        }
      }

      # Grafana Configuration
      grafana = {
        # Enable Grafana
        enabled = true

        # Admin Password
        adminPassword = var.grafana_admin_password

        # Persistence
        persistence = {
          enabled       = true
          storageClassName = "gp3"
          size          = "10Gi"
        }

        # Datasources - Pre-configured
        datasources = {
          datasources.yaml = {
            apiVersion = 1
            datasources = [
              {
                name      = "Prometheus"
                type      = "prometheus"
                url       = "http://kube-prometheus-stack-prometheus:9090"
                access    = "proxy"
                isDefault = true
              },
              {
                name   = "Loki"
                type   = "loki"
                url    = "http://loki:3100"
                access = "proxy"
              },
              {
                name   = "Tempo"
                type   = "tempo"
                url    = "http://tempo:3100"
                access = "proxy"
              }
            ]
          }
        }

        # Dashboards
        dashboardProviders = {
          dashboardproviders.yaml = {
            apiVersion = 1
            providers = [
              {
                name            = "default"
                orgId           = 1
                folder          = ""
                type            = "file"
                disableDeletion = false
                updateIntervalSeconds = 10
                allowUiUpdates  = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }

        # Resources
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }

        # Ingress
        ingress = {
          enabled = true
          ingressClassName = "alb"
          annotations = {
            "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"  = "ip"
          }
          path  = "/"
          hosts = ["grafana.example.com"]
        }
      }

      # Alertmanager (optional, for alerting)
      alertmanager = {
        enabled = var.enable_alerting
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
      }

      # Prometheus Node Exporter
      prometheus-node-exporter = {
        enabled = true
      }

      # Kube State Metrics
      kube-state-metrics = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

# ============================================================
# Loki - Log Aggregation
# ============================================================

resource "helm_repository" "grafana" {
  name             = "grafana"
  url              = "https://grafana.github.io/helm-charts"
  repository_cafile = ""
}

resource "helm_release" "loki" {
  name             = "loki"
  repository       = helm_repository.grafana.name
  chart            = "loki"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  version          = "5.47.0"
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      # Loki Configuration
      loki = {
        auth_enabled = false

        # Ingester Configuration
        ingester = {
          chunk_idle_period = "3m"
          max_chunk_age    = "1h"
          max_streams_per_user = 0
          lifecycler = {
            ring = {
              kvstore = {
                store = "inmemory"
              }
              replication_factor = 1
            }
          }
        }

        # Limits Configuration
        limits_config = {
          enforce_metric_name  = false
          reject_old_samples   = true
          reject_old_samples_max_age = "168h"
        }

        # Schema Configuration
        schema_config = {
          configs = [
            {
              from         = "2020-10-24"
              store        = "boltdb-shipper"
              object_store = "filesystem"
              schema       = "v11"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }

        # Storage Configuration (Local by default)
        storage_config = {
          boltdb_shipper = {
            active_index_directory = "/loki/boltdb-shipper-active"
            shared_store           = "filesystem"
            cache_location         = "/loki/boltdb-shipper-cache"
          }
          filesystem = {
            directory = "/loki/chunks"
          }
        }

        # Server Configuration
        server = {
          http_listen_port = 3100
        }

        # Table Manager (retention)
        table_manager = {
          retention_deletes_enabled = true
          retention_period          = "720h" # 30 days
        }
      }

      # Persistence
      persistence = {
        enabled = true
        size    = "10Gi"
        storageClassName = "gp3"
      }

      # Resources
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }

      # Service Configuration
      service = {
        type = "ClusterIP"
      }

      # Promtail for log collection
      promtail = {
        enabled = true
        config = {
          clients = [
            {
              url = "http://loki:3100/loki/api/v1/push"
            }
          ]
          scrape_configs = [
            {
              job_name = "kubernetes-pods"
              kubernetes_sd_configs = [
                {
                  role = "pod"
                }
              ]
              relabel_configs = [
                {
                  source_labels = ["__meta_kubernetes_pod_label_app"]
                  target_label  = "app"
                },
                {
                  source_labels = ["__meta_kubernetes_namespace"]
                  target_label  = "namespace"
                },
                {
                  source_labels = ["__meta_kubernetes_pod_name"]
                  target_label  = "pod"
                }
              ]
            }
          ]
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

# ============================================================
# Tempo - Distributed Tracing
# ============================================================

resource "helm_release" "tempo" {
  name             = "tempo"
  repository       = helm_repository.grafana.name
  chart            = "tempo"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  version          = "1.6.0"
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      # Tempo Configuration
      tempo = {
        # Receiver Configuration (OTLP)
        receivers = {
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
              http = {
                endpoint = "0.0.0.0:4318"
              }
            }
          }
          jaeger = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:14250"
              }
            }
          }
          zipkin = {
            endpoint = "0.0.0.0:9411"
          }
        }

        # Attributes Processor
        attributes = {
          actions = [
            {
              key    = "service.name"
              value  = "leave-backend"
              action = "insert"
            }
          ]
        }

        # Sampler Configuration (100% sampling for demo)
        sampling = {
          static = {
            overall_strategy = "always_on"
          }
        }

        # Storage Configuration
        storage = {
          trace = {
            backend = "local"
            local = {
              path = "/var/tempo/traces"
            }
          }
        }

        # Ingester Configuration
        ingester = {
          trace_idle_period   = "10s"
          max_block_duration  = "5m"
        }

        # Distributor Configuration
        distributor = {
          rate_limiting_enabled = false
        }

        # Query Frontend
        query_frontend = {
          cache_control = "max-age=100"
        }
      }

      # Persistence
      persistence = {
        enabled = true
        size    = "10Gi"
        storageClassName = "gp3"
      }

      # Resources
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }

      # Service Configuration
      service = {
        type = "ClusterIP"
        # Expose OTLP HTTP port
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "3100"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

# ============================================================
# Service Monitor for Backend Metrics
# ============================================================

resource "kubernetes_manifest" "backend_service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "leave-backend-monitor"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
      labels = {
        prometheus = "enabled"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "leave-backend"
        }
      }
      namespaceSelector = {
        matchNames = ["default"]
      }
      endpoints = [
        {
          port     = "9464"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# ============================================================
# ConfigMap for Grafana Dashboards
# ============================================================

resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "backend-dashboard.json" = file("${path.module}/dashboards/backend.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

# ============================================================
# Service for Tempo Ingestion
# ============================================================

resource "kubernetes_service" "tempo_otlp" {
  metadata {
    name      = "tempo-otlp-http"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    selector = {
      app = "tempo"
    }

    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }

  depends_on = [helm_release.tempo]
}

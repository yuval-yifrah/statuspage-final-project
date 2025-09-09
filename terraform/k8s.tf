resource "kubernetes_config_map" "statuspage_db_meta" {
  metadata {
    name      = "statuspage-db-meta"
    namespace = "default"
  }

  data = {
    DATABASE_HOST = aws_db_instance.ly_rds.address
    DATABASE_PORT = aws_db_instance.ly_rds.port
    DATABASE_NAME = aws_db_instance.ly_rds.db_name
  }
}


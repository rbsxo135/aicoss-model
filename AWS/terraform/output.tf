output "bucket_name" {
  value = aws_s3_bucket.input.bucket
}

output "sqs_clinical_url" {
  value = aws_sqs_queue.clinical.id
}

output "sqs_gene_url" {
  value = aws_sqs_queue.gene.id
}

output "sqs_image_url" {
  value = aws_sqs_queue.image.id
}

output "sftp_secret_arn" {
  value = aws_secretsmanager_secret.sftp.arn
}

output "image_worker_instance_id" {
  value = aws_instance.image_worker.id
}

